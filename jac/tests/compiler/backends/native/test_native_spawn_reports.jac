"""A spawn's report list is handed to the walker, not pinned for the life of
the program: each spawn used to leak its list and everything reported."""

import ctypes;
import from tests.support { compile_native, get_func, run_cases }

test "spawn_reports_reclaim.jac cases" {
    def check_reports_from_every_spawn_are_reclaimed_with_the {
        (engine, _) = compile_native("spawn_reports_reclaim.jac");

        run = get_func(engine, "run", ctypes.c_int64, ctypes.c_int64);
        assert run(6) == 6;
        dropped = get_func(engine, "read_dropped", ctypes.c_int64);
        assert dropped() == 6;
    }

    def check_a_walker_spawned_again_keeps_the_earlier_list_re {
        (engine, _) = compile_native("spawn_reports_reclaim.jac");

        respawn = get_func(engine, "respawn", ctypes.c_int64);
        assert respawn() == 11;
        dropped = get_func(engine, "read_dropped", ctypes.c_int64);
        assert dropped() == 2;
    }

    def check_nested_spawn_reports_still_reach_the_outer_walke {
        (engine, _) = compile_native("spawn_reports_reclaim.jac");

        nested = get_func(engine, "nested", ctypes.c_int64);
        assert nested() == 1;
    }
    run_cases(
        [
            (
                "reports from every spawn are reclaimed with the walker",
                check_reports_from_every_spawn_are_reclaimed_with_the
            ),
            (
                "a walker spawned again keeps the earlier list readable",
                check_a_walker_spawned_again_keeps_the_earlier_list_re
            ),
            (
                "nested spawn reports still reach the outer walker",
                check_nested_spawn_reports_still_reach_the_outer_walke
            )
        ]
    );
}
