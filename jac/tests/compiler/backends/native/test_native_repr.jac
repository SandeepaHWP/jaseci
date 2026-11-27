"""End-to-end tests for native container repr (#7593 item 5).

`str(container)`, `f"{container}"`, and `print(container)` must produce
CPython-exact repr text, recursing through nested containers and
dispatching obj elements to `__repr__` (not `__str__`).
"""

import ctypes;
import os;
import from tests.support {
    TESTS_DIR,
    compile_native,
    get_func,
    native_force_opts,
    run_cases
}

glob FIXTURES = os.path.join(
         TESTS_DIR, "compiler", "backends", "native", "fixtures"
     );

"""Run a void JIT function and capture what it writes to fd 1 (C stdout)."""
def capture_stdout(fn: any) -> bytes {
    libc = ctypes.CDLL(None);
    # Drain anything (e.g. the launcher's first-run banner) still sitting in
    # libc's stdout buffer, or the JIT's own fflush dumps it into the capture.
    libc.fflush(None);
    (r, w) = os.pipe();
    saved = os.dup(1);
    os.dup2(w, 1);
    try {
        fn();
        libc.fflush(None);
    } finally {
        os.dup2(saved, 1);
        os.close(saved);
        os.close(w);
        data = os.read(r, 65536);
        os.close(r);
    }
    return data;
}

test "container_repr.jac cases" {
    def check_str_list_int_is_cpython_repr {
        (eng, _) = compile_native("container_repr.jac");

        f = get_func(eng, "list_int_str", ctypes.c_char_p);
        assert f() == b"[1, 2, 3]";
    }

    def check_str_of_empty_list {
        (eng, _) = compile_native("container_repr.jac");

        f = get_func(eng, "list_empty_str", ctypes.c_char_p);
        assert f() == b"[]";
    }

    def check_nested_list_repr {
        (eng, _) = compile_native("container_repr.jac");

        f = get_func(eng, "nested_list_str", ctypes.c_char_p);
        assert f() == b"[[1, 2], [3]]";
    }

    def check_str_elements_get_cpython_quote_choice {
        (eng, _) = compile_native("container_repr.jac");

        f = get_func(eng, "list_str_quoting", ctypes.c_char_p);
        assert f() == b"['a', \"b'c\", 'd\"e']";
    }

    def check_dict_repr {
        (eng, _) = compile_native("container_repr.jac");

        f = get_func(eng, "dict_str", ctypes.c_char_p);
        assert f() == b"{'a': 1, 'b': 2}";
    }

    def check_set_repr {
        (eng, _) = compile_native("container_repr.jac");

        f = get_func(eng, "set_str", ctypes.c_char_p);
        assert f() == b"{1, 2, 3}";
    }

    def check_tuple_repr {
        (eng, _) = compile_native("container_repr.jac");

        f = get_func(eng, "tuple_str", ctypes.c_char_p);
        assert f() == b"(1, 'x')";
    }

    def check_one_tuple_trailing_comma {
        (eng, _) = compile_native("container_repr.jac");

        f = get_func(eng, "one_tuple_str", ctypes.c_char_p);
        assert f() == b"(1,)";
    }

    def check_bool_elements_repr_as_true_false {
        (eng, _) = compile_native("container_repr.jac");

        f = get_func(eng, "bool_list_str", ctypes.c_char_p);
        assert f() == b"[True, False]";
    }

    def check_none_element_in_optional_str_list {
        (eng, _) = compile_native("container_repr.jac");

        f = get_func(eng, "opt_str_list", ctypes.c_char_p);
        assert f() == b"['a', None]";
    }

    def check_float_elements_use_repr_formatting {
        (eng, _) = compile_native("container_repr.jac");

        f = get_func(eng, "float_list_str", ctypes.c_char_p);
        assert f() == b"[1.0, 2.5, 1e+300]";
    }

    def check_f_string_container_interpolation {
        (eng, _) = compile_native("container_repr.jac");

        f = get_func(eng, "fstr_container", ctypes.c_char_p);
        assert f() == b"v=[1, 2]";
    }

    def check_obj_element_uses_repr {
        (eng, _) = compile_native("container_repr.jac");

        f = get_func(eng, "obj_elem_repr", ctypes.c_char_p);
        assert f() == b"[P(1)]";
    }

    def check_obj_element_default_repr {
        (eng, _) = compile_native("container_repr.jac");

        f = get_func(eng, "obj_elem_default", ctypes.c_char_p);
        out = f();
        assert out == b"[Plain(n=1)]" , f"got {out!r}";
    }

    def check_print_list_and_print_tuple_to_stdout {
        (eng, _) = compile_native("container_repr.jac");

        `entry = get_func(eng, "jac_entry", None);
        out = capture_stdout(`entry);
        assert out == b"[1, 2, 3]\n(1, 2)\n" , f"got {out!r}";
    }

    def check_str_of_sized_integers_preserves_unsigned_range_a {
        (eng, _) = compile_native("container_repr.jac");

        f = get_func(eng, "sized_integer_str", ctypes.c_bool);
        assert f();
    }
    run_cases(
        [
            ("str(list[int]) is CPython repr", check_str_list_int_is_cpython_repr),
            ("str of empty list", check_str_of_empty_list),
            ("nested list repr", check_nested_list_repr),
            (
                "str elements get CPython quote choice",
                check_str_elements_get_cpython_quote_choice
            ),
            ("dict repr", check_dict_repr),
            ("set repr", check_set_repr),
            ("tuple repr", check_tuple_repr),
            ("one-tuple trailing comma", check_one_tuple_trailing_comma),
            (
                "bool elements repr as True/False",
                check_bool_elements_repr_as_true_false
            ),
            (
                "None element in optional-str list",
                check_none_element_in_optional_str_list
            ),
            (
                "float elements use repr formatting",
                check_float_elements_use_repr_formatting
            ),
            (
                "f-string container interpolation",
                check_f_string_container_interpolation
            ),
            ("obj element uses __repr__", check_obj_element_uses_repr),
            ("obj element default repr", check_obj_element_default_repr),
            (
                "print(list) and print(tuple) to stdout",
                check_print_list_and_print_tuple_to_stdout
            ),
            (
                "str of sized integers preserves unsigned range and vararg width",
                check_str_of_sized_integers_preserves_unsigned_range_a
            )
        ]
    );
}
