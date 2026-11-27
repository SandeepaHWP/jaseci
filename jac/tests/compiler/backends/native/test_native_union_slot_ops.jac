"""Read, compare and select over a union-typed slot, checked by value.

A union whose members do not share a lowering is stored as a boxed
`jacval`; a union of pointers keeps the first member's pointer layout. The
object-building parser traffics in both, and three expression forms over
those slots have to be right: `is`/`is not None` (a tag test, not a null
test), a bare read in condition position (truthiness, which `0`, `""` and
`[]` answer differently from "is the slot set"), and a ternary select whose
arms are an option against `None` or two distinct class pointers.

Optional-payload loss at the use site is the silent-miscompile hazard here:
a select or unbox that drops the payload still yields a well-typed value
and still compiles. So every assertion reads the payload back -- a field
off the object, the member value, or the negated length of a container --
and every function is additionally checked against the sv/bytecode result
of the same fixture -- the parity idiom the native lowering tests here
share.

Refs #8062
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
     FIXTURE = "union_slot_ops.jac",
     ALL_FNS = [
         "is_none_union",
         "is_not_none_union",
         "truthy_union",
         "not_truthy_union",
         "opt_ternary",
         "cls_ternary",
         "union_opt_ternary",
         "multi_cls_none",
         "multi_cls_truthy",
         "use_narrow_ternary",
         "pass_through_opt",
         "bool_join"
     ],
     FLAGS = [0, 1, 2, 3, 4, 5, 6];


"""Compile the fixture natively and return the JIT engine."""
def _compile -> object {
    prog = JacProgram();
    ir = prog.compile(
        file_path=str(os.path.join(FIXTURES, FIXTURE)), options=native_force_opts()
    );
    errors = [str(e) for e in prog.errors_had] if prog.errors_had else [];
    assert not prog.errors_had , f"Compilation errors in {FIXTURE}: {errors}";
    eng = ir.gen.native_engine;
    assert eng is not None , f"No native engine produced for {FIXTURE}";
    return eng;
}


"""ctypes handle for an (int) -> int function in the JIT engine."""
def _get(eng: any, name: str) -> object {
    addr = native_address(eng, name);
    assert addr != 0 , f"Function '{name}' not found in JIT engine";
    return ctypes.CFUNCTYPE(ctypes.c_int64, ctypes.c_int64)(addr);
}


"""Import the same fixture through the sv/bytecode pathway."""
def _sv_module -> object {
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
    return mods[0];
}


test "is None over a boxed union is a tag test, not a null test, and related cases" {
    def check_is_none_over_a_boxed_union_is_a_tag_test_not_a_n {
        f = _get(_compile(), "is_none_union");
        assert f(0) == 0 , "the int member 7 is present; a null test would call it None";
        assert f(1) == 0 , "the str member is present";
        assert f(2) == 1 , "None is None";
    }

    def check_a_two_class_pointer_ternary_keeps_each_arm_s_own {
        f = _get(_compile(), "cls_ternary");
        assert f(1) == 3 , "the Alpha arm's field";
        assert f(0) == 9 , "the Beta arm's field";
    }

    def check_a_boxed_bool_join_reads_back_as_a_condition {
        f = _get(_compile(), "bool_join");
        assert f(2) == 1 , "a set option with a non-empty list";
        assert f(1) == 1 , "a set option with an empty list, via the `or` arm";
        assert f(0) == 0 , "an unset option with an empty list";
    }
    run_cases(
        [
            (
                "is None over a boxed union is a tag test, not a null test",
                check_is_none_over_a_boxed_union_is_a_tag_test_not_a_n
            ),
            (
                "a two-class-pointer ternary keeps each arm's own payload",
                check_a_two_class_pointer_ternary_keeps_each_arm_s_own
            ),
            (
                "a boxed bool join reads back as a condition",
                check_a_boxed_bool_join_reads_back_as_a_condition
            )
        ]
    );
}


test "is not None over a boxed union keeps the payload on the some arm, and related cases" {
    def check_is_not_none_over_a_boxed_union_keeps_the_payload {
        f = _get(_compile(), "is_not_none_union");
        assert f(0) == 7 , "the int member must arrive as itself";
        assert f(1) == -4 , "the str member must arrive as its negated length";
        assert f(2) == -9 , "None must take the else arm";
    }

    def check_a_ternary_between_a_boxed_union_and_none_round_t {
        f = _get(_compile(), "union_opt_ternary");
        assert f(0) == 7 , "the int member through the boxed arm";
        assert f(1) == -4 , "the str member through the boxed arm";
        assert f(2) == -1 , "the None arm";
    }
    run_cases(
        [
            (
                "is not None over a boxed union keeps the payload on the some arm",
                check_is_not_none_over_a_boxed_union_keeps_the_payload
            ),
            (
                "a ternary between a boxed union and None round-trips every member",
                check_a_ternary_between_a_boxed_union_and_none_round_t
            )
        ]
    );
}


test "truthiness of a boxed union is not conflated with being set, and related cases" {
    def check_truthiness_of_a_boxed_union_is_not_conflated_wit {
        eng = _compile();

        f = _get(eng, "truthy_union");
        n = _get(eng, "not_truthy_union");
        expect = {0: 1, 1: 0, 2: 1, 3: 0, 4: 1, 5: 0, 6: 0};
        labels = {0: "5", 1: "0", 2: "'hi'", 3: "''", 4: "[1, 2]", 5: "[]", 6: "None"};
        for (flag, want) in expect.items() {
            assert f(flag) == want , (
                f"truthiness of the {labels[flag]} member: got {f(flag)}, want {want}"
            );
            assert n(flag) == 1 - want , (
                f"`not` over the {labels[flag]} member disagrees with the `if`"
            );
        }
    }

    def check_an_all_pointer_union_answers_is_none_and_truthin {
        eng = _compile();

        f = _get(eng, "multi_cls_none");
        t = _get(eng, "multi_cls_truthy");
        assert f(1) == 11 , "the Alpha member's field";
        assert f(2) == 22 , "the Beta member's field";
        assert f(0) == -1 , "the unset slot is None";
        assert t(1) == 1 , "a set all-pointer slot is truthy";
        assert t(2) == 1 , "a set all-pointer slot is truthy";
        assert t(0) == 0 , "an unset all-pointer slot is falsy";
    }

    def check_a_narrowing_ternary_round_trips_an_option_throug {
        eng = _compile();

        f = _get(eng, "use_narrow_ternary");
        p = _get(eng, "pass_through_opt");
        assert f(1) == 17 , (
            "the narrowed arm must reach the far-side field read with its payload"
        );
        assert f(2) == -1 , "an Alpha that is not a Sub takes the None arm";
        assert f(0) == -1 , "a None source takes the None arm";
        assert p(1) == 4 , "the same option without a select in the way";
        assert p(2) == 5 , "the base member's field";
        assert p(0) == -1 , "the unset option";
    }
    def check_every_union_slot_form_agrees_with_the_sv_result {
        eng = _compile();

        sv = _sv_module();
        for name in ALL_FNS {
            na_fn = _get(eng, name);
            sv_fn = getattr(sv, name);
            for flag in FLAGS {
                assert na_fn(flag) == sv_fn(flag) , (
                    f"{name}({flag}): native {na_fn(flag)} != sv {sv_fn(flag)}"
                );
            }
        }
    }
    run_cases(
        [
            (
                "truthiness of a boxed union is not conflated with being set",
                check_truthiness_of_a_boxed_union_is_not_conflated_wit
            ),
            (
                "an all-pointer union answers is-None and truthiness on the same slot",
                check_an_all_pointer_union_answers_is_none_and_truthin
            ),
            (
                "a narrowing ternary round-trips an option through the select",
                check_a_narrowing_ternary_round_trips_an_option_throug
            ),
            (
                "every union-slot form agrees with the sv result",
                check_every_union_slot_form_agrees_with_the_sv_result
            )
        ]
    );
}


test "a T | None ternary carries its payload to the field read" {
    f = _get(_compile(), "opt_ternary");
    assert f(1) == 42 , "the object arm must reach the field read intact";
    assert f(0) == -1 , "the None arm must be None";
}
