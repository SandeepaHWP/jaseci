"""End-to-end tests for native object stringification (#7003).

`str(obj)`, `f"{obj}"`, and `print(obj)` must dispatch to a user object's
`__str__` method (resolving the runtime subclass through the vtable), and fall
back to a `<TypeName object at 0x...>` default -- not a garbage pointer -- when
no `__str__` is defined. All assertions hold the native (`na`) result to the
shape it would take on the `sv` pathway.
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

"""Run a void JIT function and capture what it writes to fd 1 (C stdout).

`contextlib.redirect_stdout` only sees Python writes; the JIT's printf goes
straight to the C runtime, so we redirect the OS-level file descriptor and
flush libc's stdio buffer before restoring it."""
def capture_stdout(fn: object) -> bytes {
    libc = ctypes.CDLL(None);
    # Drain anything (e.g. the launcher's first-run banner) still sitting in
    # libc's stdout buffer, or the JIT's own fflush dumps it into the capture.
    # Same guard `test_native_repr.jac` carries for the same reason.
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
        # Close the write-end to signal EOF, then drain and close the read-end.
        # Kept in `finally` so a raising fn() never leaks the pipe fds.
        os.close(w);
        data = os.read(r, 65536);
        os.close(r);
    }
    return data;
}

test "obj_str.jac cases" {
    # --- str(obj) ---
    def check_str_obj_dispatches_to_str {
        (eng, _) = compile_native("obj_str.jac");

        f = get_func(eng, "obj_str", ctypes.c_char_p);
        assert f() == b"hello";
    }

    def check_str_obj_with_a_computed_f_string_str {
        (eng, _) = compile_native("obj_str.jac");

        f = get_func(eng, "obj_str_computed", ctypes.c_char_p);
        assert f() == b"Q(42)";
    }

    # --- f"{obj}" ---
    def check_f_string_interpolates_obj_via_str {
        (eng, _) = compile_native("obj_str.jac");

        f = get_func(eng, "obj_in_fstring", ctypes.c_char_p);
        assert f() == b"[world]";
    }

    # --- default repr fallback (no __str__) ---
    def check_str_obj_without_str_writes_the_object_s_fields_a {
        (eng, _) = compile_native("obj_str.jac");

        f = get_func(eng, "obj_default_repr", ctypes.c_char_p);
        got = f();
        assert got == b"Plain(x=7)" , f"got: {got!r}";
    }

    # --- polymorphism (vtable dispatch through a base-typed receiver) ---
    def check_str_obj_resolves_the_runtime_subclass_str {
        (eng, _) = compile_native("obj_str.jac");

        f = get_func(eng, "poly_str", ctypes.c_char_p);
        assert f() == b"Dog:rex";
    }

    def check_str_obj_on_a_base_instance_uses_the_base_str {
        (eng, _) = compile_native("obj_str.jac");

        f = get_func(eng, "base_str", ctypes.c_char_p);
        assert f() == b"Animal:generic";
    }

    # --- null receiver (T | None) ---
    def check_str_obj_on_a_null_none_struct_pointer_renders_no {
        (eng, _) = compile_native("obj_str.jac");

        f = get_func(eng, "maybe_str", ctypes.c_char_p, ctypes.c_int64);
        assert f(1) == b"set";
        assert f(0) == b"None";
    }

    # --- print(obj) ---
    def check_print_obj_writes_str_to_stdout {
        (eng, _) = compile_native("obj_str.jac");

        `entry = get_func(eng, "jac_entry", None);
        got = capture_stdout(`entry);
        assert got == b"printed\n" , got;
    }
    run_cases(
        [
            ("str(obj) dispatches to __str__", check_str_obj_dispatches_to_str),
            (
                "str(obj) with a computed (f-string) __str__",
                check_str_obj_with_a_computed_f_string_str
            ),
            (
                "f-string interpolates obj via __str__",
                check_f_string_interpolates_obj_via_str
            ),
            (
                "str(obj) without __str__ writes the object's fields, as the Python tier does",
                check_str_obj_without_str_writes_the_object_s_fields_a
            ),
            (
                "str(obj) resolves the runtime subclass __str__",
                check_str_obj_resolves_the_runtime_subclass_str
            ),
            (
                "str(obj) on a base instance uses the base __str__",
                check_str_obj_on_a_base_instance_uses_the_base_str
            ),
            (
                "str(obj) on a null (None) struct pointer renders \"None\", not a crash",
                check_str_obj_on_a_null_none_struct_pointer_renders_no
            ),
            (
                "print(obj) writes __str__ to stdout",
                check_print_obj_writes_str_to_stdout
            )
        ]
    );
}
