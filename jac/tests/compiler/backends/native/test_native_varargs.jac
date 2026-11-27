"""Behavioral tests for variadic parameters (*args / **kwargs) on native.

Graduated from the guardrail ("star-args def is rejected loudly" in
test_native_crash_guards.jac, #7320). The call site materializes the pack:
`*args: T` is a native List of T (List.jacval for `*args: any`) and
`**kwargs: T` a native str-keyed Dict, each passed as one pointer and
released after the call. Shapes the lowering does not cover demote their
owning callable to a Python-only seam (call-site argument unpacking
`f(*xs)` / `f(**d)`, def:pub variadics, and since #8234 a variadic `init`,
whose construction sites then refuse), while shapes with no demotable
owner at all stay structured errors (unannotated variadics).

Expected values are pinned against CPython (see each fixture wrapper).

The generic cases at the bottom (#8247) run through a subprocess instead of
the JIT: a pack of a generic archetype's erased type parameter used to lower
without diagnostic and then read the pack pointer as a `str`, so the failure
mode is a segfault, which has to fail the test rather than take the runner
down with it.
"""

import ctypes;
import os;
import from tests.support {
    TESTS_DIR,
    by_source_name,
    compile_native,
    get_func,
    has_error_code,
    native_build_fails,
    native_force_opts,
    sv_run,
    na_run,
    same_lines,
    source_spelled,
    unit_symbol,
    run_cases
}
import jaclang;

import from jaclang.compiler.driver.program { JacProgram }

glob FIXTURES = os.path.join(
         TESTS_DIR, "compiler", "backends", "native", "fixtures"
     );

"""Compile a snippet through the native pipeline and return the program."""
def compile_na_inline(label: str, code: str) -> JacProgram {
    path = os.path.join(FIXTURES, f"_varargs_{label}.jac");
    prog = JacProgram();
    prog.compile(file_path=path, use_str=code, options=native_force_opts());
    return prog;
}

"""Like `compile_na_inline`, but also hand back the compiled module so a
granular demotion (epic #8201) is observable through the native layout."""
def compile_na_inline_ir(label: str, code: str) -> tuple[any, ...] {
    path = os.path.join(FIXTURES, f"_varargs_{label}.jac");
    prog = JacProgram();
    options = native_force_opts();
    options.no_ir_cache = True;
    options.skip_native_engine = True;
    ir = prog.compile(file_path=path, use_str=code, options=options);
    return (prog, ir, );
}

test "varargs.jac cases" {
    def check_varargs_args_sums_positional_extras {
        (eng, _) = compile_native("varargs.jac");

        f = get_func(eng, "test_sum_all", ctypes.c_int64);
        assert f() == 6 , f"Expected 6, got {f()}";
    }

    def check_varargs_empty_args_materializes_an_empty_list {
        (eng, _) = compile_native("varargs.jac");

        f = get_func(eng, "test_sum_empty", ctypes.c_int64);
        assert f() == 0 , f"Expected 0, got {f()}";
    }

    def check_varargs_fixed_params_bind_before_the_pack {
        (eng, _) = compile_native("varargs.jac");

        f = get_func(eng, "test_mixed", ctypes.c_int64);
        assert f() == 7003 , f"Expected 7003, got {f()}";
    }

    def check_varargs_defaults_compose_with_args {
        (eng, _) = compile_native("varargs.jac");

        packed = get_func(eng, "test_default_packed", ctypes.c_int64);
        empty = get_func(eng, "test_default_empty", ctypes.c_int64);
        assert packed() == 36 , f"Expected 36, got {packed()}";
        assert empty() == 0 , f"Expected 0, got {empty()}";
    }

    def check_varargs_indexing_and_len_over_the_pack {
        (eng, _) = compile_native("varargs.jac");

        f = get_func(eng, "test_idx_ends", ctypes.c_int64);
        assert f() == 47 , f"Expected 47, got {f()}";
    }

    def check_varargs_str_pack_rc_pointer_elements {
        (eng, _) = compile_native("varargs.jac");

        f = get_func(eng, "test_join_lens", ctypes.c_int64);
        assert f() == 5 , f"Expected 5, got {f()}";
    }

    def check_varargs_args_any_boxes_heterogeneous_values {
        (eng, _) = compile_native("varargs.jac");

        f = get_func(eng, "test_any_pack", ctypes.c_int64);
        assert f() == 3 , f"Expected 3, got {f()}";
    }

    def check_kwargs_kwargs_get_and_contains {
        (eng, _) = compile_native("varargs.jac");

        hit = get_func(eng, "test_kw_hit", ctypes.c_int64);
        miss = get_func(eng, "test_kw_miss", ctypes.c_int64);
        assert hit() == 4 , f"Expected 4, got {hit()}";
        assert miss() == -1 , f"Expected -1, got {miss()}";
    }

    def check_kwargs_kwargs_iteration_sums_values {
        (eng, _) = compile_native("varargs.jac");

        f = get_func(eng, "test_kw_sum", ctypes.c_int64);
        e = get_func(eng, "test_kw_sum_empty", ctypes.c_int64);
        assert f() == 6 , f"Expected 6, got {f()}";
        assert e() == 0 , f"Expected 0, got {e()}";
    }

    def check_varargs_kwonly_kwargs_combined_binding {
        (eng, _) = compile_native("varargs.jac");

        mn = get_func(eng, "test_combo_min", ctypes.c_int64);
        rest = get_func(eng, "test_combo_rest", ctypes.c_int64);
        kwonly = get_func(eng, "test_combo_kwonly", ctypes.c_int64);
        full = get_func(eng, "test_combo_full", ctypes.c_int64);
        assert mn() == 100000 , f"Expected 100000, got {mn()}";
        assert rest() == 207000 , f"Expected 207000, got {rest()}";
        assert kwonly() == 207500 , f"Expected 207500, got {kwonly()}";
        assert full() == 102309 , f"Expected 102309, got {full()}";
    }

    def check_varargs_method_receives_the_pack_after_self {
        (eng, _) = compile_native("varargs.jac");

        f = get_func(eng, "test_method_pack", ctypes.c_int64);
        assert f() == 106 , f"Expected 106, got {f()}";
    }

    def check_varargs_cross_module_callee_receives_the_pack {
        (eng, _) = compile_native("varargs.jac");

        f = get_func(eng, "test_xmod_pack", ctypes.c_int64);
        assert f() == 15 , f"Expected 15, got {f()}";
    }
    run_cases(
        [
            (
                "varargs: *args sums positional extras",
                check_varargs_args_sums_positional_extras
            ),
            (
                "varargs: empty *args materializes an empty list",
                check_varargs_empty_args_materializes_an_empty_list
            ),
            (
                "varargs: fixed params bind before the pack",
                check_varargs_fixed_params_bind_before_the_pack
            ),
            (
                "varargs: defaults compose with *args",
                check_varargs_defaults_compose_with_args
            ),
            (
                "varargs: indexing and len over the pack",
                check_varargs_indexing_and_len_over_the_pack
            ),
            (
                "varargs: str pack (RC pointer elements)",
                check_varargs_str_pack_rc_pointer_elements
            ),
            (
                "varargs: *args: any boxes heterogeneous values",
                check_varargs_args_any_boxes_heterogeneous_values
            ),
            ("kwargs: **kwargs get and contains", check_kwargs_kwargs_get_and_contains),
            (
                "kwargs: **kwargs iteration sums values",
                check_kwargs_kwargs_iteration_sums_values
            ),
            (
                "varargs+kwonly+kwargs combined binding",
                check_varargs_kwonly_kwargs_combined_binding
            ),
            (
                "varargs: method receives the pack after self",
                check_varargs_method_receives_the_pack_after_self
            ),
            (
                "varargs: cross-module callee receives the pack",
                check_varargs_cross_module_callee_receives_the_pack
            )
        ]
    );
}


test "callsite star-unpack of a LIST into a fixed-arity callee demotes the caller, and related cases" {
    def check_callsite_star_unpack_of_a_list_into_a_fixed_arit {
        # A list's arity is not statically known, so this stays refused even now
        # that tuple spreads and variadic-callee list spreads lower (#7626 A6).
        # Before wave 2, two(*xs) compiled CLEAN and returned 0 (the star
        # expression lowered to None and both params default-padded); the
        # refusal now demotes use() to its Python implementation instead of
        # failing the whole module.
        (prog, ir) = compile_na_inline_ir(
            "star_fixed",
            "def two(a: int, b: int) -> int { return a * 10 + b; }\n"
            "def use() -> int { xs = [7, 8]; return two(*xs); }\n"
        );
        assert not prog.errors_had , (
            f"two(*xs) is owned by use(), which must demote to a seam, got: "
            f"{[str(e) for e in prog.errors_had]}"
        );
        layout = ir.gen.native_layout;
        assert layout is not None , "whole-module native compile aborted";
        assert "two" in layout.functions , (
            f"clean sibling function was lost: {list(layout.functions)}"
        );
        assert "use" not in layout.functions , (
            "the unpacking caller must be demoted out of the native layout"
        );
    }

    def check_a_callee_whose_pack_slot_did_not_lay_out_refuses {
        (prog, ir) = compile_na_inline_ir(
            "packslot",
            "obj Cell[T] { has n: int = 0; def take(*xs: dict[T, T]) -> int { return 0; } }\n"
            "def use() -> int { c = Cell[Cell[int]](); return c.take(); }\n"
            "def pure(x: int) -> int { return x + 1; }\n"
        );
        assert not prog.errors_had , (
            f"the caller owns the refusal, so the module must still compile: "
            f"{[str(e) for e in prog.errors_had]}"
        );
        layout = ir.gen.native_layout;
        assert layout is not None , "whole-module native compile aborted";
        assert "pure" in layout.functions , (
            f"clean sibling function was lost: {list(layout.functions)}"
        );
        assert "use" not in layout.functions , (
            "binding the extras into a slot that is not a pack is a silent misread; "
            "the caller must demote instead"
        );
    }
    run_cases(
        [
            (
                "callsite star-unpack of a LIST into a fixed-arity callee demotes the caller",
                check_callsite_star_unpack_of_a_list_into_a_fixed_arit
            ),
            (
                "a callee whose pack slot did not lay out refuses its caller",
                check_a_callee_whose_pack_slot_did_not_lay_out_refuses
            )
        ]
    );
}

test "callsite star-unpack: cases on call_unpack.jac" {
    def check_callsite_star_unpack_tuple_spread_splits_into_de {
        (eng, _) = compile_native("call_unpack.jac");

        f = get_func(eng, "spread_tuple", ctypes.c_int64);
        assert f() == 30201 , "add3(1, 2, 3)";
        g = get_func(eng, "spread_mixed", ctypes.c_int64);
        assert g(1) == 30201 , "add3(1, *(2, 3)) mixes positional and spread";
    }

    def check_callsite_star_unpack_list_spread_routes_through {
        (eng, _) = compile_native("call_unpack.jac");

        f = get_func(eng, "spread_variadic", ctypes.c_int64);
        assert f() == 15 , "vsum(*[4, 5, 6])";
    }
    run_cases(
        [
            (
                "callsite star-unpack: tuple spread splits into declared params",
                check_callsite_star_unpack_tuple_spread_splits_into_de
            ),
            (
                "callsite star-unpack: list spread routes through a variadic callee",
                check_callsite_star_unpack_list_spread_routes_through
            )
        ]
    );
}


test "double-star unpack into fixed parameters stays native" {
    (prog, ir) = compile_na_inline_ir(
        "dstar_fixed",
        "def two(a: int, b: int) -> int { return a * 10 + b; }\n"
        "def use() -> int { d = {'a': 1, 'b': 2}; return two(**d); }\n"
    );
    assert not prog.errors_had , [str(e) for e in prog.errors_had];
    layout = ir.gen.native_layout;
    assert layout is not None , "whole-module native compile aborted";
    assert "two" in layout.functions and "use" in layout.functions , (
        f"a ** spread into fixed parameters binds natively: {list(layout.functions)}"
    );
}

test "unannotated variadic parameter is a loud error" {
    prog = compile_na_inline("unannot", "def f(*args) -> int { return 0; }\n");
    assert prog.errors_had , "Expected a loud error for an unannotated *args";
}

test "def:pub variadic demotes off the native interop surface" {
    (prog, ir) = compile_na_inline_ir(
        "pubvar", "def:pub f(*args: int) -> int { return 0; }\n"
    );
    assert not prog.errors_had , (
        f"the interop bridge cannot marshal a parameter pack, so the pub "
        f"variadic must demote to its Python implementation, got: "
        f"{[str(e) for e in prog.errors_had]}"
    );
    layout = ir.gen.native_layout;
    assert layout is not None , "whole-module native compile aborted";
    assert "f" not in layout.functions , (
        "the pub variadic must be demoted out of the native layout"
    );
}

test "variadic init demotes the constructor and refuses its callers" {
    (prog, ir) = compile_na_inline_ir(
        "initvar",
        "obj P { has n: int = 0; def init(*vals: int) { self.n = 0; } }\n"
        "def mk() -> int { p = P(); return p.n; }\n"
        "def pure(x: int) -> int { return x + 1; }\n"
    );
    assert not prog.errors_had , (
        f"a constructor owns its own capability violation since #8234, so a "
        f"variadic init demotes instead of refusing the module, got: "
        f"{[str(e) for e in prog.errors_had]}"
    );
    layout = ir.gen.native_layout;
    assert layout is not None , "whole-module native compile aborted";
    assert "pure" in layout.functions , (
        f"clean sibling function was lost: {list(layout.functions)}"
    );
    assert "P.init" not in by_source_name(layout.methods) , (
        "the variadic init must be demoted out of the native layout"
    );
    assert "mk" not in layout.functions , (
        "constructing through a demoted initializer must refuse, not build a "
        "half-initialized object"
    );
}

test "a pack of a generic archetype's erased T answers what CPython answers" {
    (sv_out, _sv_err) = sv_run(os.path.join(FIXTURES, "varargs_generic.jac"));
    (na_out, _na_err) = na_run(os.path.join(FIXTURES, "varargs_generic.jac"));
    same_lines(sv_out, na_out, "erased pack");
}

test "a generic pack slot is a native list, not the bare erased pointer" {
    prog = JacProgram();
    options = native_force_opts();
    options.no_ir_cache = True;
    options.skip_native_engine = True;
    ir = prog.compile(os.path.join(FIXTURES, "varargs_generic.jac"), options=options);
    assert not prog.errors_had , str(prog.errors_had);
    layout = ir.gen.native_layout;
    assert layout is not None , "whole-module native compile aborted";
    assert "Cell.get" in by_source_name(layout.methods) , (
        f"the variadic method must reach the native image: {sorted(layout.methods)}"
    );
    assert "Cell.count" in by_source_name(layout.methods) , (
        f"the variadic method must reach the native image: {sorted(layout.methods)}"
    );
    assert "Cell.pick" in by_source_name(layout.methods) , (
        f"a pack after a fixed parameter must lower too: {sorted(layout.methods)}"
    );
    text = source_spelled(str(ir.gen.llvm_ir));
    assert f'define i8* @"{source_spelled(
        unit_symbol(ir, "Cell.get")
    )}"(%"Cell"* %"self", %"List.ptr"* %"fallback")'
        in text , (
        "the pack slot must lay out as the pointer-flavoured native list; a bare "
        "i8* there is the erased element leaking into the pack's own slot"
    );
}

test "a generic pack at a by-value type argument is refused, not lowered" {
    combined = native_build_fails(os.path.join(FIXTURES, "varargs_generic_scalar.jac"));
    assert "Cell[int]" in combined , (
        f"diagnostic does not name the instantiation: {combined[-600:]}"
    );
}
