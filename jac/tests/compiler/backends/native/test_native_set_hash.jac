"""Hash-table set semantics under mutation, across GC modes (#7871 C).

`set` shares the dict's hash core (FNV-1a str hash, ctrl fingerprints with
tombstone-aware probing, used-counting 75% rehash, insertion-order array), so
this mirrors the dict matrix: the JIT tests exercise each set operation
in-process, pinpointing the failing operation via per-function sentinels; the
GC-matrix tests AOT-compile the same fixture with `--memory rc`, `--memory managed`,
and `--memory nogc`, run the binary, and expect a clean exit (the fixture asserts
internally and prints OK).
"""

import ctypes;
import os;
import subprocess;
import tempfile;
import from tests.support {
    jac_command,
    TESTS_DIR,
    compile_native,
    get_func,
    native_force_opts,
    run_cases
}

glob FIXTURES = os.path.join(
         TESTS_DIR, "compiler", "backends", "native", "fixtures"
     ),
     PROG = "set_hash_ops.jac";

test "set int add remove contains, and related cases" {
    def check_set_int_add_remove_contains {
        (eng, _) = compile_native(PROG);

        f = get_func(eng, "add_remove_contains_int", ctypes.c_int64);
        assert f() == 2;
    }

    def check_set_str_add_remove_contains {
        (eng, _) = compile_native(PROG);

        f = get_func(eng, "add_remove_contains_str", ctypes.c_int64);
        assert f() == 2;
    }

    def check_set_tombstone_reuse_after_remove {
        (eng, _) = compile_native(PROG);

        f = get_func(eng, "tombstone_reuse", ctypes.c_int64);
        assert f() == 2;
    }

    def check_set_rehash_cycle_with_removes_mixed_in {
        (eng, _) = compile_native(PROG);

        f = get_func(eng, "rehash_with_deletes", ctypes.c_int64);
        assert f() == 1;
    }

    def check_set_clear_then_contains_and_re_add {
        (eng, _) = compile_native(PROG);

        f = get_func(eng, "clear_then_reuse", ctypes.c_int64);
        assert f() == 1;
    }

    def check_set_iteration_order_preserved_after_removes {
        (eng, _) = compile_native(PROG);

        f = get_func(eng, "order_after_deletes", ctypes.c_char_p);
        assert f().decode("utf-8") == "one;three;four;five;";
    }

    def check_set_pop_drains_in_lifo_order {
        (eng, _) = compile_native(PROG);

        f = get_func(eng, "pop_lifo", ctypes.c_int64);
        assert f() == 0;
    }

    def check_set_algebra_correctness {
        (eng, _) = compile_native(PROG);

        f = get_func(eng, "algebra", ctypes.c_int64);
        assert f() == 1;
    }

    def check_set_in_place_ops_correctness {
        (eng, _) = compile_native(PROG);

        f = get_func(eng, "inplace_ops", ctypes.c_int64);
        assert f() == 1;
    }

    def check_set_f64_elements_hash_and_compare {
        (eng, _) = compile_native(PROG);

        f = get_func(eng, "f64_elems", ctypes.c_int64);
        assert f() == 1;
    }
    run_cases(
        [
            ("set int add remove contains", check_set_int_add_remove_contains),
            ("set str add remove contains", check_set_str_add_remove_contains),
            (
                "set tombstone reuse after remove",
                check_set_tombstone_reuse_after_remove
            ),
            (
                "set rehash cycle with removes mixed in",
                check_set_rehash_cycle_with_removes_mixed_in
            ),
            (
                "set clear then contains and re-add",
                check_set_clear_then_contains_and_re_add
            ),
            (
                "set iteration order preserved after removes",
                check_set_iteration_order_preserved_after_removes
            ),
            ("set pop drains in LIFO order", check_set_pop_drains_in_lifo_order),
            ("set algebra correctness", check_set_algebra_correctness),
            ("set in-place ops correctness", check_set_in_place_ops_correctness),
            (
                "set f64 elements hash and compare",
                check_set_f64_elements_hash_and_compare
            )
        ]
    );
}


def _run_fixture_with_gc(extra_flags: list[str], tag: str) {
    src = os.path.join(FIXTURES, PROG);
    out_bin = os.path.join(tempfile.mkdtemp(), f"set_hash_ops_{tag}.bin");
    cmd = jac_command("build", "--native", src);
    cmd += extra_flags;
    cmd += ["-o", out_bin];
    comp = subprocess.run(cmd, capture_output=True, text=True, timeout=300);
    combined = (comp.stdout or "") + (comp.stderr or "");
    assert comp.returncode == 0 , f"nacompile ({tag}) failed: {combined[-900:]}";
    proc = subprocess.run([out_bin], capture_output=True, text=True, timeout=120);
    assert proc.returncode == 0 , f"set ops failed under {tag}: {(
        proc.stderr or proc.stdout or '(empty)'
    )[-600:]}";
    assert proc.stdout.strip() == "OK set_hash_ops" , f"unexpected output under {tag}: {proc.stdout.strip()!r}";
}

test "set ops pass under --memory cases" {
    def check_set_ops_pass_under_memory_rc {
        _run_fixture_with_gc(["--memory", "rc"], "rc");
    }

    def check_set_ops_pass_under_memory_managed {
        _run_fixture_with_gc(["--memory", "managed"], "cycles");
    }

    def check_set_ops_pass_under_memory_nogc {
        _run_fixture_with_gc(["--memory", "nogc"], "none");
    }
    run_cases(
        [
            ("set ops pass under --memory rc", check_set_ops_pass_under_memory_rc),
            (
                "set ops pass under --memory managed",
                check_set_ops_pass_under_memory_managed
            ),
            ("set ops pass under --memory nogc", check_set_ops_pass_under_memory_nogc)
        ]
    );
}
