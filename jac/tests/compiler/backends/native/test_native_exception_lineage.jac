"""`except Base` catches a user-defined subclass of `Base` natively.

Handler type ids came from a static descendant table that holds only the
builtin hierarchy, so `except AppError` matched `AppError` itself and never
a raised `StoreError(AppError)`: the exception escaped the handler and the
process aborted. Raises of user exception classes now record their ancestors
in a process-wide lineage table that handlers consult, which also covers a
subclass defined in a module the handler never imports.
"""

import ctypes;
import from tests.support { compile_native, get_func, run_cases }

def call(eng: any, name: str) -> int {
    return get_func(eng, name, ctypes.c_int64)();
}

test "exc_lineage_main.jac cases" {
    def check_a_subclass_raised_in_the_same_frame_is_caught_by {
        (eng, _) = compile_native("exc_lineage_main.jac");

        assert call(eng, "same_frame") == 1;
    }

    def check_a_two_level_subclass_raised_in_a_callee_is_caugh {
        (eng, _) = compile_native("exc_lineage_main.jac");

        assert call(eng, "two_levels") == 2;
    }

    def check_a_subclass_of_a_builtin_exception_is_caught_by_t {
        (eng, _) = compile_native("exc_lineage_main.jac");

        assert call(eng, "builtin_base") == 3;
    }

    def check_a_from_imported_exception_class_is_caught_by_nam {
        (eng, _) = compile_native("exc_lineage_main.jac");

        assert call(eng, "imported_name") == 4;
    }

    def check_an_imported_subclass_is_caught_by_its_imported_b {
        (eng, _) = compile_native("exc_lineage_main.jac");

        assert call(eng, "imported_base") == 4;
    }

    def check_a_handler_catches_a_subclass_from_a_module_it_ne {
        (eng, _) = compile_native("exc_lineage_main.jac");

        assert call(eng, "unseen_subclass") == -1;
    }

    def check_an_unrelated_handler_lets_the_subclass_through_t {
        (eng, _) = compile_native("exc_lineage_main.jac");

        assert call(eng, "falls_through") == 6;
    }
    run_cases(
        [
            (
                "a subclass raised in the same frame is caught by its base",
                check_a_subclass_raised_in_the_same_frame_is_caught_by
            ),
            (
                "a two-level subclass raised in a callee is caught by its base",
                check_a_two_level_subclass_raised_in_a_callee_is_caugh
            ),
            (
                "a subclass of a builtin exception is caught by the builtin",
                check_a_subclass_of_a_builtin_exception_is_caught_by_t
            ),
            (
                "a from-imported exception class is caught by name",
                check_a_from_imported_exception_class_is_caught_by_nam
            ),
            (
                "an imported subclass is caught by its imported base",
                check_an_imported_subclass_is_caught_by_its_imported_b
            ),
            (
                "a handler catches a subclass from a module it never imports",
                check_a_handler_catches_a_subclass_from_a_module_it_ne
            ),
            (
                "an unrelated handler lets the subclass through to the next clause",
                check_an_unrelated_handler_lets_the_subclass_through_t
            )
        ]
    );
}
