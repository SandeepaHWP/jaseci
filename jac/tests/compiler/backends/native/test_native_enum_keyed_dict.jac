"""Congruence tests for `dict[<enum>, V]` in the native backend.

Every case JIT-compiles `fixtures/enum_keyed_dict.jac` natively and compares
the result against the same function run through the sv pathway, so the
assertion is native-equals-bytecode rather than a hardcoded constant.

The gap these pin: a native dict stores an enum key as the enum's native int
representation, which is the member ordinal for a string-valued enum but the
declared value for an int-valued one. Hashing and equality were already on
that i64 and worked. Reading a key back out was not: `.name`/`.value` on a
runtime enum-typed value indexed the per-enum ordinal arrays with the raw
key, so an int-valued enum landed on the wrong member (LOW's value 2 is
HIGH's ordinal) or past the end of the array (25, 40) -- a segfault -- and
`.value` had no array at all, which demoted the whole module. That made
`dict[Level, str]` unusable: its keys could not be iterated or inspected.
"""

import ctypes;
import os;
import from tests.support {
    TESTS_DIR,
    native_address,
    native_force_opts,
    native_str_func,
    run_cases
}
import from jaclang.compiler.driver.program { JacProgram }
import from jaclang.runtime.runtime { JacRuntime }
import from jaclang.compiler.backends.native.llvm.binding { ExecutionEngine }

glob FIXTURES = os.path.join(
         TESTS_DIR, "compiler", "backends", "native", "fixtures"
     ),
     PROG = "enum_keyed_dict.jac",
     _SV_MOD: list[any] = [],
     _ENG: list[any] = [];

"""Compile the fixture natively, run module init, return its JIT engine."""
def compile_native(fixture: str) -> ExecutionEngine {
    if _ENG {
        return _ENG[0];
    }
    prog = JacProgram();
    ir = prog.compile(
        file_path=str(os.path.join(FIXTURES, fixture)), options=native_force_opts()
    );
    errors = [str(e) for e in prog.errors_had] if prog.errors_had else [];
    assert not prog.errors_had , f"Compilation errors in {fixture}: {errors}";
    eng = ir.gen.native_engine;
    assert isinstance(eng, ExecutionEngine) , f"No native engine produced for {fixture}";
    # The glob tables live in module globals; without jac_entry they are null
    # and every table read segfaults the JIT.
    entry_addr = native_address(eng, "jac_entry");
    assert entry_addr != 0 , "no jac_entry to initialize module globals";
    ctypes.CFUNCTYPE(None)(entry_addr)();
    _ENG.append(eng);
    return eng;
}

"""Import the same fixture through the sv pathway (the congruence oracle)."""
def sv_module -> object {
    if not _SV_MOD {
        _SV_MOD.append(
            JacRuntime.jac_import(target="enum_keyed_dict", base_path=FIXTURES)[0]
        );
    }
    return _SV_MOD[0];
}

"""Assert the native str-returning function matches the sv one."""
def same_str(eng: any, name: str) {
    native = native_str_func(eng, name, ctypes.c_char_p)().decode("utf-8");
    sv = getattr(sv_module(), name)();
    assert native == sv , f"{name}: native {native!r} != sv {sv!r}";
}

"""Assert the native int-returning function matches the sv one."""
def same_int(eng: any, name: str) {
    addr = native_address(eng, name);
    assert addr != 0 , f"Function '{name}' not found in JIT engine";
    native = ctypes.CFUNCTYPE(ctypes.c_int64)(addr)();
    sv = getattr(sv_module(), name)();
    assert native == sv , f"{name}: native {native!r} != sv {sv!r}";
}

test "string-valued enum keys: lookup by member and by runtime key, and related cases" {
    def check_string_valued_enum_keys_lookup_by_member_and_by {
        eng = compile_native(PROG);

        same_str(eng, "str_by_member");
        same_str(eng, "str_by_runtime_key");
    }

    def check_string_valued_enum_keys_membership_get_with_and {
        eng = compile_native(PROG);

        same_int(eng, "str_contains");
        same_str(eng, "str_get_default");
        same_str(eng, "str_get_no_default");
    }

    def check_string_valued_enum_keys_iteration_yields_keys_th {
        eng = compile_native(PROG);

        same_str(eng, "str_iter_keys");
        same_str(eng, "str_iter_names");
    }

    def check_string_valued_enum_keys_incremental_build_overwr {
        eng = compile_native(PROG);

        same_str(eng, "str_incremental");
        same_int(eng, "str_incremental_len");
    }

    def check_int_valued_enum_keys_lookup_by_member_and_by_run {
        eng = compile_native(PROG);

        same_str(eng, "int_by_member");
        same_str(eng, "int_by_runtime_key");
    }

    def check_int_valued_enum_keys_membership_and_get_with_a_d {
        eng = compile_native(PROG);

        same_int(eng, "int_contains");
        same_str(eng, "int_get_default");
    }

    def check_int_valued_enum_keys_iteration_yields_keys_that {
        eng = compile_native(PROG);

        same_int(eng, "int_iter_values");
        same_str(eng, "int_iter_names");
    }

    def check_int_valued_enum_keys_incremental_build {
        eng = compile_native(PROG);

        same_str(eng, "int_incremental");
    }

    def check_enum_keys_distinct_members_never_collide {
        eng = compile_native(PROG);

        same_str(eng, "distinct_members");
        same_int(eng, "distinct_members_len");
        same_str(eng, "mixed_no_collision");
    }
    run_cases(
        [
            (
                "string-valued enum keys: lookup by member and by runtime key",
                check_string_valued_enum_keys_lookup_by_member_and_by
            ),
            (
                "string-valued enum keys: membership, get with and without a default",
                check_string_valued_enum_keys_membership_get_with_and
            ),
            (
                "string-valued enum keys: iteration yields keys that read back",
                check_string_valued_enum_keys_iteration_yields_keys_th
            ),
            (
                "string-valued enum keys: incremental build overwrites in place",
                check_string_valued_enum_keys_incremental_build_overwr
            ),
            (
                "int-valued enum keys: lookup by member and by runtime key",
                check_int_valued_enum_keys_lookup_by_member_and_by_run
            ),
            (
                "int-valued enum keys: membership and get with a default",
                check_int_valued_enum_keys_membership_and_get_with_a_d
            ),
            (
                "int-valued enum keys: iteration yields keys that read back",
                check_int_valued_enum_keys_iteration_yields_keys_that
            ),
            (
                "int-valued enum keys: incremental build",
                check_int_valued_enum_keys_incremental_build
            ),
            (
                "enum keys: distinct members never collide",
                check_enum_keys_distinct_members_never_collide
            )
        ]
    );
}
