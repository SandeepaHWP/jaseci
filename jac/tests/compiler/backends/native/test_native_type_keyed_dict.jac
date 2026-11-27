"""Congruence tests for `dict[type, V]` in the native backend (#8068).

A `type` had no native representation at all, so a dict keyed by one had no
layout: the layout pass reported the field as not layout-compatible and the
codegen pass refused the type outright, demoting every method that touched it.
`UniNode.__sub_node_tab` is exactly that dict, which is why the seal shipped
`_construct_sub_node_tab` and `FuncSignature.is_in_py_class` as `abort()`
stubs and why two more methods were hand-rewritten to dodge it.

Each case JIT-compiles `fixtures/type_keyed_dict.jac` and compares the answer
against the same source run through the sv pathway, so the assertion is
native-equals-bytecode rather than a hardcoded constant. The identity the keys
are checked for is the one the sub-node index needs: the *runtime* class of a
base-typed receiver, distinct per subclass, and stable across the module
boundary that `type_keyed_dict_lib` puts between two of the key classes.
"""

import ctypes;
import os;
import from tests.support { TESTS_DIR, native_address, native_force_opts, run_cases }
import from jaclang.compiler.driver.program { JacProgram }
import from jaclang.runtime.runtime { JacRuntime }
import from jaclang.compiler.frontend.codeinfo {
    get_effective_default_codespace_override,
    set_effective_default_codespace
}

glob FIXTURES = os.path.join(
         TESTS_DIR, "compiler", "backends", "native", "fixtures"
     ),
     FIXTURE = "type_keyed_dict.jac",
     _ENG: list[any] = [],
     _SV_MOD: list[any] = [];

"""Compile the fixture natively, run module init, return its JIT engine."""
def _engine -> any {
    if _ENG {
        return _ENG[0];
    }
    prog = JacProgram();
    ir = prog.compile(
        file_path=str(os.path.join(FIXTURES, FIXTURE)), options=native_force_opts()
    );
    errors = [str(e) for e in prog.errors_had] if prog.errors_had else [];
    assert not prog.errors_had , f"Compilation errors in {FIXTURE}: {errors}";
    eng = ir.gen.native_engine;
    assert eng is not None , f"No native engine produced for {FIXTURE}";
    entry_addr = native_address(eng, "jac_entry");
    assert entry_addr != 0 , "no jac_entry to initialize module globals";
    ctypes.CFUNCTYPE(None)(entry_addr)();
    _ENG.append(eng);
    return eng;
}

"""Warnings the native compile of the fixture emitted."""
def _warnings -> list[str] {
    prog = JacProgram();
    prog.compile(
        file_path=str(os.path.join(FIXTURES, FIXTURE)), options=native_force_opts()
    );
    return [str(w) for w in (prog.warnings_had or [])];
}

"""Import the same fixture through the sv/bytecode pathway (the oracle)."""
def _sv_module -> any {
    if _SV_MOD {
        return _SV_MOD[0];
    }
    prev = get_effective_default_codespace_override();
    set_effective_default_codespace("server");
    try {
        mods = JacRuntime.jac_import(
            target=FIXTURE[:-4], base_path=FIXTURES, reload_module=True
        );
    } finally {
        set_effective_default_codespace(prev);
    }
    assert mods , "sv import of the fixture produced no module";
    _SV_MOD.append(mods[0]);
    return mods[0];
}

"""Assert the native int-returning function matches the sv one."""
def _same_int(name: str) -> int {
    addr = native_address(_engine(), name);
    assert addr != 0 , f"Function '{name}' not found in JIT engine";
    native = ctypes.CFUNCTYPE(ctypes.c_int64)(addr)();
    sv = getattr(_sv_module(), name)();
    assert native == sv , f"{name}: native {native!r} != sv {sv!r}";
    return native;
}


test "a dict keyed by type lowers at all" {
    eng = _engine();
    assert native_address(eng, "key_count") != 0 , (
        "the fixture produced no `key_count`: a `type` key made the whole "
        "module refuse to lower"
    );
}


test "an obj field of type dict[type, V] is layout-compatible" {
    offenders = [
        w
        for w in _warnings()
        if "layout-compatible" in w
    ];
    assert not offenders , (f"W5032 on a `type`-keyed field: {offenders}");
}


test "one bucket per runtime class, keyed off a base-typed receiver, and related cases" {
    def check_one_bucket_per_runtime_class_keyed_off_a_base_ty {
        assert _same_int("key_count") == 4 , (
            "six nodes over four classes must produce four buckets"
        );
    }

    def check_isinstance_against_a_class_value_keeps_subclass {
        assert _same_int("runtime_isinstance") == 111001 , (
            "a runtime class value must answer isinstance by the hierarchy, not "
            "by class identity"
        );
    }
    run_cases(
        [
            (
                "one bucket per runtime class, keyed off a base-typed receiver",
                check_one_bucket_per_runtime_class_keyed_off_a_base_ty
            ),
            (
                "isinstance against a class value keeps subclass semantics",
                check_isinstance_against_a_class_value_keeps_subclass
            )
        ]
    );
}


test "class literals probe the buckets `type(x)` built, and related cases" {
    def check_class_literals_probe_the_buckets_type_x_built {
        _same_int("literal_key_sums");
    }

    def check_a_key_computed_at_runtime_finds_the_bucket_a_lit {
        _same_int("runtime_key_sums");
    }

    def check_a_subclass_key_does_not_collapse_into_its_parent {
        _same_int("subclass_keys_distinct");
    }

    def check_a_type_held_in_a_local_is_still_a_usable_key {
        _same_int("key_in_local");
    }

    def check_class_literals_work_as_the_keys_of_a_dict_litera {
        _same_int("dict_literal_keys");
    }

    def check_the_table_survives_as_an_object_field {
        _same_int("registry_field");
    }

    def check_a_class_that_was_never_inserted_misses_and_alias {
        _same_int("absent_key");
    }

    def check_a_type_t_parameter_carries_a_class_through_a_gen {
        _same_int("generic_collect");
    }
    run_cases(
        [
            (
                "class literals probe the buckets `type(x)` built",
                check_class_literals_probe_the_buckets_type_x_built
            ),
            (
                "a key computed at runtime finds the bucket a literal key names",
                check_a_key_computed_at_runtime_finds_the_bucket_a_lit
            ),
            (
                "a subclass key does not collapse into its parent's bucket",
                check_a_subclass_key_does_not_collapse_into_its_parent
            ),
            (
                "a type held in a local is still a usable key",
                check_a_type_held_in_a_local_is_still_a_usable_key
            ),
            (
                "class literals work as the keys of a dict literal",
                check_class_literals_work_as_the_keys_of_a_dict_litera
            ),
            (
                "the table survives as an object field",
                check_the_table_survives_as_an_object_field
            ),
            (
                "a class that was never inserted misses, and aliases nothing",
                check_a_class_that_was_never_inserted_misses_and_alias
            ),
            (
                "a `type[T]` parameter carries a class through a generic call",
                check_a_type_t_parameter_carries_a_class_through_a_gen
            )
        ]
    );
}


test "a key minted in another module matches a literal written here, and related cases" {
    def check_a_key_minted_in_another_module_matches_a_literal {
        _same_int("cross_module_key");
        _same_int("cross_module_key_reverse");
    }

    def check_keys_read_out_of_one_table_re_key_another_the_su {
        _same_int("merge_tables");
        _same_int("key_roundtrip");
    }
    run_cases(
        [
            (
                "a key minted in another module matches a literal written here",
                check_a_key_minted_in_another_module_matches_a_literal
            ),
            (
                "keys read out of one table re-key another (the sub-node-tab merge)",
                check_keys_read_out_of_one_table_re_key_another_the_su
            )
        ]
    );
}
