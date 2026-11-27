"""`except T as e` binds what the raise produced, local or imported.

A raise of a field-less exception class (`raise ProgrammingError("msg")`)
carries the message as its payload, but the handler bound any class it could
resolve to a struct as that struct, reinterpreting the message string as the
object: `str(e)` printed `<ProgrammingError object at 0x...>`. Module-scoped
archetype identities (#9472) made imported classes resolve too, which broke
every error message of the bundled native `sqlite3`. A `raise e` of such a
binding rebuilt the raise from it and lost the raised subclass and message.
"""

import ctypes;
import from tests.support { compile_native, get_func, run_cases }

def call_str(eng: any, name: str) -> bytes {
    return get_func(eng, name, ctypes.c_char_p)();
}

def call_int(eng: any, name: str) -> int {
    return get_func(eng, name, ctypes.c_int64)();
}

test "exc_binding_main.jac cases" {
    def check_a_field_less_local_exception_binds_its_message {
        (eng, _) = compile_native("exc_binding_main.jac");

        assert call_str(eng, "local_message") == b"local 3";
    }

    def check_a_field_less_imported_exception_binds_its_messag {
        (eng, _) = compile_native("exc_binding_main.jac");

        assert call_str(eng, "imported_message") == b"cannot bind 0";
    }

    def check_an_exception_class_with_fields_binds_its_struct {
        (eng, _) = compile_native("exc_binding_main.jac");

        assert call_int(eng, "struct_code") == 404;
    }

    def check_raise_of_a_bound_exception_re_raises_the_caught {
        (eng, _) = compile_native("exc_binding_main.jac");

        assert call_str(eng, "reraised_message") == b"cannot bind 0";
        assert call_int(eng, "reraised_code") == 404;
    }
    run_cases(
        [
            (
                "a field-less local exception binds its message",
                check_a_field_less_local_exception_binds_its_message
            ),
            (
                "a field-less imported exception binds its message",
                check_a_field_less_imported_exception_binds_its_messag
            ),
            (
                "an exception class with fields binds its struct",
                check_an_exception_class_with_fields_binds_its_struct
            ),
            (
                "raise of a bound exception re-raises the caught one",
                check_raise_of_a_bound_exception_re_raises_the_caught
            )
        ]
    );
}
