"""Idioms the compiler's analysis passes use lower natively and agree with Python.

Moving the pre-backend passes into native scope surfaced four general gaps:
a generator of `str(...)` values handed to `str.join` built an integer list
and the join raised in the emitter; `set.update`/`set.union` accepted only a
set argument although Python takes any iterable; an importer typed another
module's unannotated `glob` as a bare integer, so `is` against it either
refused or compared the wrong words; and `==` between an optional container
and a plain one compared list elements as strings, so two different
`list[tuple[int, str]]` values answered equal. The expected values below are
what the Python backend computes for the same fixtures.
"""

import ctypes;
import from tests.support { compile_native, get_func, run_cases }
import from jaclang.compiler.backends.native.lowering { native_lowering_issues }

test "pass idioms lower without seams and match the Python results, and related cases" {
    def check_pass_idioms_lower_without_seams_and_match_the_py {
        (engine, module) = compile_native("compiler_pass_idioms.jac");
        issues = native_lowering_issues(str(module.gen.llvm_ir));
        assert not issues , "\n".join(issue.detail for issue in issues);
        assert get_func(engine, "joined_generator", ctypes.c_int64)() == 1;
        assert get_func(engine, "set_update_from_lists", ctypes.c_int64)() == 56;
        assert get_func(engine, "set_update_from_keys", ctypes.c_int64)() == 8;
        assert get_func(engine, "optional_list_equality", ctypes.c_int64)() == 1010;
    }

    def check_an_importer_sees_an_untyped_glob_with_its_initia {
        (engine, module) = compile_native("glob_identity_main.jac");
        issues = native_lowering_issues(str(module.gen.llvm_ir));
        assert not issues , "\n".join(issue.detail for issue in issues);
        assert get_func(engine, "identity_mask", ctypes.c_int64)() == 100;
        assert get_func(engine, "singleton_name_length", ctypes.c_int64)() == 6;
    }
    run_cases(
        [
            (
                "pass idioms lower without seams and match the Python results",
                check_pass_idioms_lower_without_seams_and_match_the_py
            ),
            (
                "an importer sees an untyped glob with its initializer's type",
                check_an_importer_sees_an_untyped_glob_with_its_initia
            )
        ]
    );
}
