"""Congruence tests for flow-sensitive optional narrowing in jac native.

The sv/bytecode backend already narrows: after a test that proves an optional
is non-None, uses of that value on the proven path see the narrowed type. The
native backend saw the JacOpt/JacVal box instead, so idiomatic guarded code
either failed to lower or forced the author to launder the value through a
typed rebind.

Every behavioral test here compares the native result against the sv result
for the same fixture, so the assertions are a real congruence gate rather than
hardcoded constants. `narrowing removes the tag check` pins the payoff: with
narrowing disabled the same fixture emits checked unwraps, and with it on the
proven uses emit none.
"""

import ctypes;
import os;
import from tests.support {
    TESTS_DIR,
    compile_native,
    names_function,
    native_address,
    compile_native_ir,
    native_force_opts,
    run_cases
}
import jaclang;

import from jaclang.runtime.runtime { JacRuntime }

import from jaclang.compiler.backends.native.na_ir_gen_pass { NaIRGenPass }

glob FIXTURES = os.path.join(
         TESTS_DIR, "compiler", "backends", "native", "fixtures"
     ),
     FIXTURE = "optional_narrowing.jac";

"""Import the same fixture on the sv/bytecode path for congruence."""
def sv_module -> any {
    return JacRuntime.jac_import(target=FIXTURE[:-4], base_path=FIXTURES)[0];
}

"""Get a ctypes-callable int -> int function from the JIT engine."""
def get_func(eng: any, name: str) -> any {
    addr = native_address(eng, name);
    assert addr != 0 , f"Function '{name}' not found in JIT engine";
    return ctypes.CFUNCTYPE(ctypes.c_int64, ctypes.c_int64)(addr);
}

"""Assert native and sv agree on `name` over `inputs`, and return the values."""
def congruent(eng: any, sv: object, name: str, inputs: list[int]) -> list[int] {
    native_fn = get_func(eng, name);
    sv_fn = getattr(sv, name);
    out: list[int] = [];
    for n in inputs {
        got = native_fn(n);
        want = sv_fn(n);
        assert got == want , (
            f"{name}({n}): native returned {got}, sv returned {want}"
        );
        out.append(got);
    }
    return out;
}

"""Slice one function's body out of a printed LLVM module."""
def func_ir(llvm_ir: str, name: str) -> str {
    out: list[str] = [];
    inside = False;
    for line in str(llvm_ir).split("\n") {
        if not inside and line.startswith("define ") and names_function(line, name) {
            inside = True;
        }
        if inside {
            out.append(line);
            if line.startswith("}") {
                break;
            }
        }
    }
    assert out , f"function '{name}' not found in the emitted module";
    return "\n".join(out);
}

"""Stand-in for `_narrowed_flow_type` that disables narrowing (baseline)."""
def _no_narrowing(pass_self: any, nd: any) -> any {
    return None;
}

test "pointer optional: `is None` early-return guard narrows the fall-through, and related cases" {
    def check_pointer_optional_is_none_early_return_guard_narr {
        (eng, _) = compile_native(FIXTURE);
        sv = sv_module();

        vals = congruent(eng, sv, "ptr_guard_is_none", [0, 1, 3]);
        assert vals == [-1, 1, 3] , f"unexpected ptr_guard_is_none results: {vals}";
    }

    def check_pointer_optional_is_not_none_positive_branch_nar {
        (eng, _) = compile_native(FIXTURE);
        sv = sv_module();

        vals = congruent(eng, sv, "ptr_is_not_none", [0, 1, 3]);
        assert vals == [-1, 1, 3] , f"unexpected ptr_is_not_none results: {vals}";
    }

    def check_pointer_optional_if_else_narrows_both_branches {
        (eng, _) = compile_native(FIXTURE);
        sv = sv_module();

        vals = congruent(eng, sv, "ptr_if_else", [0, 2, 5]);
        assert vals == [-1, 20, 50] , f"unexpected ptr_if_else results: {vals}";
    }

    def check_pointer_optional_plain_truthiness_narrows_the_tr {
        (eng, _) = compile_native(FIXTURE);
        sv = sv_module();

        vals = congruent(eng, sv, "ptr_truthy", [0, 2, 4]);
        assert vals == [-1, 102, 104] , f"unexpected ptr_truthy results: {vals}";
    }

    def check_pointer_optional_none_narrows_like_is_not_none {
        (eng, _) = compile_native(FIXTURE);
        sv = sv_module();

        vals = congruent(eng, sv, "ptr_ne_none", [0, 2, 4]);
        assert vals == [-1, 202, 204] , f"unexpected ptr_ne_none results: {vals}";
    }

    def check_scalar_optional_is_none_early_return_guard_narro {
        (eng, _) = compile_native(FIXTURE);
        sv = sv_module();

        vals = congruent(eng, sv, "scalar_guard", [0, 1, 4]);
        assert vals == [-1, 4, 13] , f"unexpected scalar_guard results: {vals}";
    }

    def check_scalar_optional_early_continue_narrows_the_rest {
        (eng, _) = compile_native(FIXTURE);
        sv = sv_module();

        vals = congruent(eng, sv, "scalar_continue_guard", [0, 3, 5]);
        assert vals == [0, 3, 18] , f"unexpected scalar_continue_guard results: {vals}";
    }

    def check_scalar_optional_early_raise_narrows_the_fall_thr {
        (eng, _) = compile_native(FIXTURE);
        sv = sv_module();

        vals = congruent(eng, sv, "scalar_raise_guard", [1, 3]);
        assert vals == [5, 11] , f"unexpected scalar_raise_guard results: {vals}";
    }

    def check_isinstance_narrows_a_boxed_union_to_the_tested_m {
        (eng, _) = compile_native(FIXTURE);
        sv = sv_module();

        vals = congruent(eng, sv, "iso_any", [0, 2, 5]);
        assert vals == [-1, 9, 21] , f"unexpected iso_any results: {vals}";
    }

    def check_a_redundant_is_none_on_a_proven_value_still_read {
        (eng, _) = compile_native(FIXTURE);
        sv = sv_module();

        vals = congruent(eng, sv, "redundant_guard", [0, 1, 2]);
        assert vals == [-1, 6, 9] , f"unexpected redundant_guard results: {vals}";
    }

    def check_a_redundant_is_none_on_a_proven_zero_payload_is {
        (eng, _) = compile_native(FIXTURE);
        sv = sv_module();

        vals = congruent(eng, sv, "zero_payload_redundant_guard", [0, 1, 5]);
        assert vals == [-1, 7, 7] , (
            f"unexpected zero_payload_redundant_guard results: {vals}"
        );
    }

    def check_is_none_as_a_value_never_compares_against_a_narr {
        (eng, _) = compile_native(FIXTURE);
        sv = sv_module();

        vals = congruent(eng, sv, "zero_payload_none_test_value", [0, 1, 5]);
        assert vals == [-1, 9, 9] , (
            f"unexpected zero_payload_none_test_value results: {vals}"
        );
        # a float payload is the case that actually miscompiles if the operand of
        # a None test is narrowed: `x is None` becomes `fcmp une x, 0.0`
        fvals = congruent(eng, sv, "float_none_test_value", [0, 2, 4]);
        assert fvals == [-1, 11, 13] , (
            f"unexpected float_none_test_value results: {fvals}"
        );
    }

    def check_truthiness_of_a_proven_container_stays_len_0 {
        (eng, _) = compile_native(FIXTURE);
        sv = sv_module();

        vals = congruent(eng, sv, "truthy_after_guard", [0, 1, 3]);
        assert vals == [-1, 1, 3] , f"unexpected truthy_after_guard results: {vals}";
    }

    def check_a_rebind_re_widens_the_tag_is_still_read_after_r {
        (eng, _) = compile_native(FIXTURE);
        sv = sv_module();

        vals = congruent(eng, sv, "rebind_widens", [0, 2, 6]);
        assert vals == [-1, 6, 21] , f"unexpected rebind_widens results: {vals}";
    }

    def check_a_loop_that_rebinds_before_the_use_still_narrows {
        (eng, _) = compile_native(FIXTURE);
        sv = sv_module();

        vals = congruent(eng, sv, "loop_fresh_each_iter", [0, 2, 6]);
        assert vals == [-4, 7, 54] , f"unexpected loop_fresh_each_iter results: {vals}";
    }

    def check_a_subscript_store_inside_a_loop_keeps_the_narrow {
        (eng, _) = compile_native(FIXTURE);
        sv = sv_module();

        vals = congruent(eng, sv, "loop_element_store", [0, 3]);
        assert vals == [-1, 9] , f"unexpected loop_element_store results: {vals}";
    }

    def check_case_none_over_a_narrowed_subject_folds_instead {
        (eng, _) = compile_native(FIXTURE);
        sv = sv_module();

        vals = congruent(eng, sv, "match_narrowed_subject", [0, 2, 4]);
        assert vals == [-1, 5, 5] , f"unexpected match_narrowed_subject results: {vals}";
    }
    run_cases(
        [
            (
                "pointer optional: `is None` early-return guard narrows the fall-through",
                check_pointer_optional_is_none_early_return_guard_narr
            ),
            (
                "pointer optional: `is not None` positive branch narrows the body",
                check_pointer_optional_is_not_none_positive_branch_nar
            ),
            (
                "pointer optional: if/else narrows both branches",
                check_pointer_optional_if_else_narrows_both_branches
            ),
            (
                "pointer optional: plain truthiness narrows the true branch",
                check_pointer_optional_plain_truthiness_narrows_the_tr
            ),
            (
                "pointer optional: `!= None` narrows like `is not None`",
                check_pointer_optional_none_narrows_like_is_not_none
            ),
            (
                "scalar optional: `is None` early-return guard narrows the fall-through",
                check_scalar_optional_is_none_early_return_guard_narro
            ),
            (
                "scalar optional: early `continue` narrows the rest of the loop body",
                check_scalar_optional_early_continue_narrows_the_rest
            ),
            (
                "scalar optional: early `raise` narrows the fall-through",
                check_scalar_optional_early_raise_narrows_the_fall_thr
            ),
            (
                "isinstance narrows a boxed union to the tested member",
                check_isinstance_narrows_a_boxed_union_to_the_tested_m
            ),
            (
                "a redundant `is None` on a proven value still reads the tag",
                check_a_redundant_is_none_on_a_proven_value_still_read
            ),
            (
                "a redundant `is None` on a proven zero payload is still False",
                check_a_redundant_is_none_on_a_proven_zero_payload_is
            ),
            (
                "`is None` as a value never compares against a narrowed payload",
                check_is_none_as_a_value_never_compares_against_a_narr
            ),
            (
                "truthiness of a proven container stays len > 0",
                check_truthiness_of_a_proven_container_stays_len_0
            ),
            (
                "a rebind re-widens: the tag is still read after reassignment",
                check_a_rebind_re_widens_the_tag_is_still_read_after_r
            ),
            (
                "a loop that rebinds before the use still narrows",
                check_a_loop_that_rebinds_before_the_use_still_narrows
            ),
            (
                "a subscript store inside a loop keeps the narrow at the loop head",
                check_a_subscript_store_inside_a_loop_keeps_the_narrow
            ),
            (
                "`case None` over a narrowed subject folds instead of comparing to null",
                check_case_none_over_a_narrowed_subject_folds_instead
            )
        ]
    );
}


test "a callee that rebinds the attribute keeps the checked unwrap, and related cases" {
    def check_a_callee_that_rebinds_the_attribute_keeps_the_ch {
        (eng, _) = compile_native(FIXTURE);
        ir = compile_native_ir(FIXTURE);
        sv = sv_module();

        vals = congruent(eng, sv, "callee_rebinds_attr", [0]);
        assert vals == [1] , f"unexpected callee_rebinds_attr results: {vals}";
        body = func_ir(str(ir.gen.llvm_ir), "callee_rebinds_attr");
        assert "opt.isnone" in body , (
            "an attribute a callee can rebind must keep its checked unwrap"
        );
    }

    def check_a_value_live_across_a_loop_back_edge_keeps_the_c {
        (eng, _) = compile_native(FIXTURE);
        ir = compile_native_ir(FIXTURE);
        sv = sv_module();

        vals = congruent(eng, sv, "back_edge_rewiden", [0, 6]);
        assert vals == [-1, 21] , f"unexpected back_edge_rewiden results: {vals}";
        body = func_ir(str(ir.gen.llvm_ir), "back_edge_rewiden");
        assert "opt.isnone" in body , (
            "a use the loop body rebinds after must keep its checked unwrap"
        );
    }

    def check_a_tuple_target_rebind_inside_a_loop_keeps_the_ch {
        (eng, _) = compile_native(FIXTURE);
        ir = compile_native_ir(FIXTURE);
        sv = sv_module();

        vals = congruent(eng, sv, "loop_unpack_rebind", [0, 6]);
        assert vals == [-1, 21] , f"unexpected loop_unpack_rebind results: {vals}";
        body = func_ir(str(ir.gen.llvm_ir), "loop_unpack_rebind");
        assert "opt.isnone" in body , (
            "a use the loop body rebinds through a tuple target must keep its checked unwrap"
        );
    }
    run_cases(
        [
            (
                "a callee that rebinds the attribute keeps the checked unwrap",
                check_a_callee_that_rebinds_the_attribute_keeps_the_ch
            ),
            (
                "a value live across a loop back edge keeps the checked unwrap",
                check_a_value_live_across_a_loop_back_edge_keeps_the_c
            ),
            (
                "a tuple-target rebind inside a loop keeps the checked unwrap",
                check_a_tuple_target_rebind_inside_a_loop_keeps_the_ch
            )
        ]
    );
}


test "the narrowed in-loop use keeps its tag check elided" {
    # `scalar_continue_guard` assigns at the top of the body, so the guard's
    # proof is fresh every iteration and the loop rule must still allow it.
    ir = compile_native_ir(FIXTURE);
    body = func_ir(str(ir.gen.llvm_ir), "scalar_continue_guard");
    assert "opt.isnone" not in body , (
        "assign-then-guard inside a loop must still narrow"
    );
}

test "narrowing removes the tag check from the proven use" {
    # optional_scalar.jac lowers with and without narrowing, so the checked
    # unwrap the guard makes unnecessary is directly measurable as an A/B.
    orig = NaIRGenPass._narrowed_flow_type;
    _napatch: any = NaIRGenPass;
    _napatch._narrowed_flow_type = _no_narrowing;
    try {
        base_ir = compile_native_ir("optional_scalar.jac");
        base = str(base_ir.gen.llvm_ir);
    } finally {
        NaIRGenPass._narrowed_flow_type = orig;
    }
    narrowed_ir = compile_native_ir("optional_scalar.jac");
    narrowed = str(narrowed_ir.gen.llvm_ir);

    for name in ["use_pick", "opt_local", "opt_param"] {
        assert "opt.isnone" in func_ir(base, name) , (
            f"baseline {name} should pay a checked unwrap without narrowing"
        );
        assert "opt.isnone" not in func_ir(narrowed, name) , (
            f"narrowed {name} must read the payload with no tag check"
        );
    }
}

test "a proven pointer-optional use emits no unwrap branch" {
    narrowed_ir = compile_native_ir(FIXTURE);
    body = func_ir(str(narrowed_ir.gen.llvm_ir), "ptr_guard_is_none");
    assert "opt.isnone" not in body , (
        "the guarded len(ids) must read the payload with no tag check"
    );
    assert "raise.TypeError" not in body , (
        "the guarded len(ids) must not branch to a runtime raise"
    );
}
