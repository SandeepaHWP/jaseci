"""A walker event ability named `drop` is not a destructor hook."""

import ctypes;
import from tests.support { compile_native, get_func, run_cases }

test "walker_drop_ability.jac cases" {
    def check_event_ability_named_drop_lowers_and_runs_nativel {
        (engine, _) = compile_native("walker_drop_ability.jac");

        fly_over = get_func(engine, "fly_over", ctypes.c_int64);
        assert fly_over() == 7;
        load_things = get_func(engine, "load_things", ctypes.c_int64, ctypes.c_int64);
        assert load_things(5) == 10;
    }

    def check_def_drop_beside_an_event_ability_named_drop_stil {
        (engine, _) = compile_native("walker_drop_ability.jac");

        release = get_func(engine, "release_crate", None);
        count = get_func(engine, "drop_count", ctypes.c_int64);
        before = count();
        release();
        assert count() == before + 5;
    }
    run_cases(
        [
            (
                "event ability named drop lowers and runs natively",
                check_event_ability_named_drop_lowers_and_runs_nativel
            ),
            (
                "def drop beside an event ability named drop still runs as a destructor",
                check_def_drop_beside_an_event_ability_named_drop_stil
            )
        ]
    );
}
