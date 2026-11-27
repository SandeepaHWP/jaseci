"""End-to-end tests for loop `else` clauses on the native backend (#8629).

The else body of a for/while loop must run exactly when the loop
exhausts normally; a `break` bypasses it (loop-else semantics). The
probes return whether the else body ran, so each lowering path in the
native backend -- while, C-style iter-for, the indexed range path and
the iter-protocol list/string paths -- is checked for both edges.
"""

import ctypes;
import from tests.support { compile_native, get_func, run_cases }

test "loop_else.jac cases" {
    def check_while_else_runs_on_exhaustion_and_is_skipped_by {
        (_eng, _ir) = compile_native("loop_else.jac");

        f = get_func(_eng, "while_else_ran", ctypes.c_bool, ctypes.c_int64);
        assert f(3) is True , "else must run when while exhausts normally";
        assert f(0) is True , "else must run for a zero-iteration while";
        g = get_func(_eng, "while_else_break_skips", ctypes.c_bool, ctypes.c_int64);
        assert g(5) is False , "break must bypass the while else body";
        assert g(0) is True , "no break taken means the else still runs";
    }

    def check_iter_for_else_runs_on_exhaustion_and_is_skipped {
        (_eng, _ir) = compile_native("loop_else.jac");

        f = get_func(_eng, "iter_for_else_ran", ctypes.c_bool, ctypes.c_int64);
        assert f(3) is True , "else must run when iter-for exhausts normally";
        assert f(0) is True , "else must run for a zero-iteration iter-for";
        g = get_func(_eng, "iter_for_else_break_skips", ctypes.c_bool, ctypes.c_int64);
        assert g(5) is False , "break must bypass the iter-for else body";
        assert g(1) is True , "no break taken means the else still runs";
    }

    def check_range_for_else_runs_on_exhaustion_and_is_skipped {
        (_eng, _ir) = compile_native("loop_else.jac");

        f = get_func(_eng, "range_for_else_ran", ctypes.c_bool);
        assert f() is True , "else must run when a range for exhausts";
        g = get_func(_eng, "range_for_else_break_skips", ctypes.c_bool);
        assert g() is False , "break must bypass the range-for else body";
        h = get_func(_eng, "range_for_else_contributes", ctypes.c_int64);
        assert h() == 1006 , "6 + 1000: exhaustion falls into the else block";
    }

    def check_iter_protocol_for_else_covers_lists_and_strings {
        (_eng, _ir) = compile_native("loop_else.jac");

        f = get_func(_eng, "list_for_else_ran", ctypes.c_bool);
        assert f() is True , "else must run when a list for exhausts";
        g = get_func(_eng, "list_for_else_break_skips", ctypes.c_bool);
        assert g() is True , "break must bypass the list-for else body";
        h = get_func(_eng, "str_for_else_ran", ctypes.c_bool);
        assert h() is True , "string for exhaustion must fall into the else block";
    }

    def check_break_and_continue_in_a_nested_loop_s_else_belon {
        (_eng, _ir) = compile_native("loop_else.jac");

        f = get_func(_eng, "inner_else_break_leaves_outer", ctypes.c_bool);
        assert f() is True , (
            "break in the inner else must leave the outer loop and skip its else"
        );
        g = get_func(_eng, "inner_else_continue_skips_rest", ctypes.c_int64);
        assert g() == 4 , "continue in the inner else skips the rest of that pass: 1 + 3";
        h = get_func(_eng, "iter_for_else_continue_steps", ctypes.c_int64);
        assert h() == 3 , "continue in the inner else still runs the iter-for step";
    }

    def check_flow_for_else_runs_with_sequential_lowering {
        (_eng, _ir) = compile_native("loop_else.jac");

        f = get_func(_eng, "flow_for_else_ran", ctypes.c_bool);
        assert f() is True , "else must run when a flow for exhausts";
    }
    run_cases(
        [
            (
                "while else runs on exhaustion and is skipped by break",
                check_while_else_runs_on_exhaustion_and_is_skipped_by
            ),
            (
                "iter-for else runs on exhaustion and is skipped by break",
                check_iter_for_else_runs_on_exhaustion_and_is_skipped
            ),
            (
                "range for else runs on exhaustion and is skipped by break",
                check_range_for_else_runs_on_exhaustion_and_is_skipped
            ),
            (
                "iter-protocol for else covers lists and strings",
                check_iter_protocol_for_else_covers_lists_and_strings
            ),
            (
                "break and continue in a nested loop's else belong to the outer loop",
                check_break_and_continue_in_a_nested_loop_s_else_belon
            ),
            (
                "flow-for else runs with sequential lowering",
                check_flow_for_else_runs_with_sequential_lowering
            )
        ]
    );
}
