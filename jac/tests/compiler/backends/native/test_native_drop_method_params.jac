"""A `def drop` that takes arguments is a method, not a destructor hook.

Both backends recognised a destructor hook as any `def` named `drop`. The
native release function then called `Shelf.drop(self, name)` with one
argument: building that call raised `IndexError: list index out of range`
inside the compiler, which `jac check` reported as an internal error and a
build answered by sending the whole module to the server codespace.
"""

import ctypes;
import from tests.support { compile_native, get_func, run_cases }

glob FIXTURE = "drop_method_params.jac";

test "a def drop that takes arguments lowers natively and is called as written, and related cases" {
    def check_a_def_drop_that_takes_arguments_lowers_natively {
        (engine, _) = compile_native(FIXTURE);

        assert get_func(engine, "shelf_probe", ctypes.c_int64)() == 1;
    }

    def check_a_def_drop_without_parameters_beside_it_still_ru {
        (engine, _) = compile_native(FIXTURE);

        release = get_func(engine, "release_crate", None);
        count = get_func(engine, "drop_count", ctypes.c_int64);
        before = count();
        release();
        assert count() == before + 5;
    }

    def check_a_def_drop_that_takes_arguments_hides_an_inherit {
        (engine, _) = compile_native(FIXTURE);

        release = get_func(engine, "release_tray", None);
        count = get_func(engine, "drop_count", ctypes.c_int64);
        before = count();
        release();
        assert count() == before;
        assert get_func(engine, "tray_probe", ctypes.c_int64)() == before + 300;
    }

    def check_a_static_def_drop_is_not_a_destructor_hook {
        (engine, _) = compile_native(FIXTURE);

        release = get_func(engine, "release_bin", None);
        count = get_func(engine, "drop_count", ctypes.c_int64);
        before = count();
        release();
        assert count() == before;
    }
    run_cases(
        [
            (
                "a def drop that takes arguments lowers natively and is called as written",
                check_a_def_drop_that_takes_arguments_lowers_natively
            ),
            (
                "a def drop without parameters beside it still runs as a destructor",
                check_a_def_drop_without_parameters_beside_it_still_ru
            ),
            (
                "a def drop that takes arguments hides an inherited destructor hook",
                check_a_def_drop_that_takes_arguments_hides_an_inherit
            ),
            (
                "a static def drop is not a destructor hook",
                check_a_static_def_drop_is_not_a_destructor_hook
            )
        ]
    );
}
