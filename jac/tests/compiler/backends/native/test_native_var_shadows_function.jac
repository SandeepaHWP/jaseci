"""A variable shadows a function of the same name that it never imported.

Lowering a module declares every public function of the modules it imports
from, under the functions' bare names, whether or not the import names them.
A read of, or a call through, one of the module's own variables of that name
used to bind to the other module's function: `burst = Thing(); burst.value`
read a field out of machine code, and calling a variable holding a lambda
called the other module's function, with no diagnostic either way.
"""
import ctypes;
import os;
import subprocess;
import from tests.support {
    compile_native,
    get_func,
    jac_command,
    TESTS_DIR,
    run_cases
}

glob FIXTURES = os.path.join(
         TESTS_DIR, "compiler", "backends", "native", "fixtures"
     ),
     MAIN = "var_shadows_function_main.jac",
     EXPECTED_LINES: list[str] = ["15", "9 18 10", "101", "364 606 101", "11 15050"];

test "a call through a local named like an unimported function calls the local, and related cases" {
    def check_a_call_through_a_local_named_like_an_unimported {
        (engine, _module) = compile_native(MAIN);

        assert get_func(engine, "local_call_probe", ctypes.c_int64)() == 101;
    }

    def check_locals_parameters_and_imported_functions_bind_as {
        (engine, _module) = compile_native(MAIN);

        assert get_func(engine, "local_read_probe", ctypes.c_int64)() == 606;
        assert get_func(engine, "param_caller_probe", ctypes.c_int64)() == 11;
        assert get_func(engine, "imported_probe", ctypes.c_int64)() == 15050;
    }
    run_cases(
        [
            (
                "a call through a local named like an unimported function calls the local",
                check_a_call_through_a_local_named_like_an_unimported
            ),
            (
                "locals, parameters and imported functions bind as they did",
                check_locals_parameters_and_imported_functions_bind_as
            )
        ]
    );
}

test "a local named like an unimported decorated or generic function is called" {
    (engine, _module) = compile_native("var_shadows_function_kinds.jac");
    assert get_func(engine, "decorated_name_probe", ctypes.c_int64)() == 201;
    assert get_func(engine, "generic_name_probe", ctypes.c_int64)() == 301;
    assert get_func(engine, "imported_probe", ctypes.c_int64)() == 8;
}


test "entry variables and globals named like unimported functions stay variables" {
    # Run as a program: reading a field through a function's address can
    # crash, and that must fail this test, not take the test process down.
    proc = subprocess.run(
        jac_command("run", os.path.join(FIXTURES, MAIN)),
        capture_output=True,
        text=True,
        timeout=900
    );
    assert proc.returncode == 0 , proc.stderr[-800:];
    assert "server codespace" not in proc.stderr , proc.stderr[-800:];
    lines = [
        line
        for line in proc.stdout.splitlines()
        if line.strip()
    ];
    assert lines == EXPECTED_LINES , proc.stdout;
}
