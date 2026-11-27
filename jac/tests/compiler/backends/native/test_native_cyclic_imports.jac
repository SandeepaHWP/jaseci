import ctypes;
import os;
import from tests.support { TESTS_DIR, compile_native, get_func, run_cases }

glob FIXTURES = os.path.join(
         TESTS_DIR, "compiler", "backends", "native", "fixtures"
     );

test "cyclic import: cases on cycle_ping.jac" {
    def check_cyclic_import_mandated_two_file_cycle_compiles {
        (eng, _) = compile_native("cycle_ping.jac");

        assert eng is not None;
    }

    def check_cyclic_import_mutual_recursion_computes_across_m {
        (eng, _) = compile_native("cycle_ping.jac");

        get_func(eng, "jac_entry", None)();
        f = get_func(eng, "ping", ctypes.c_int64, ctypes.c_int64);
        assert f(7) == 7 , f"ping(7) expected 7, got {f(7)}";
        assert f(0) == 0 , f"ping(0) expected 0, got {f(0)}";
    }
    run_cases(
        [
            (
                "cyclic import: mandated two-file cycle compiles",
                check_cyclic_import_mandated_two_file_cycle_compiles
            ),
            (
                "cyclic import: mutual recursion computes across modules",
                check_cyclic_import_mutual_recursion_computes_across_m
            )
        ]
    );
}


test "glob init: transitive runtime initializer runs dependencies first" {
    (eng, _) = compile_native("glob_chain_entry.jac");
    get_func(eng, "jac_entry", None)();
    got = get_func(eng, "get_b", ctypes.c_int64)();
    assert got == 7 , f"get_b() expected 7 (leaf inits before mid), got {got}";
}

test "glob init: cyclic modules init once without crashing" {
    (eng, _) = compile_native("cycle_glob_a.jac");
    get_func(eng, "jac_entry", None)();
    av = get_func(eng, "get_av", ctypes.c_int64)();
    bv = get_func(eng, "get_bv", ctypes.c_int64)();
    assert av == 11 , f"get_av() expected 11, got {av}";
    assert bv == 22 , f"get_bv() expected 22, got {bv}";
    cross_a = get_func(eng, "read_bv", ctypes.c_int64)();
    cross_b = get_func(eng, "read_av", ctypes.c_int64)();
    assert cross_a == 22 , f"read_bv() expected 22, got {cross_a}";
    assert cross_b == 11 , f"read_av() expected 11, got {cross_b}";
}
