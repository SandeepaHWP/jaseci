"""A call to a module's own function named like a fixed-width type (`u16`) or
a wrapping builtin calls that function natively, as it does interpreted,
instead of lowering as the cast. Fixture: fixtures/sized_name_shadowed.jac."""

import ctypes;
import os;
import from tests.support { TESTS_DIR, native_address, native_force_opts, run_cases }
import from jaclang.compiler.driver.program { JacProgram }
import from jaclang.compiler.backends.native.llvm.binding { ExecutionEngine }

glob FIXTURE = os.path.join(
         TESTS_DIR,
         "compiler",
         "backends",
         "native",
         "fixtures",
         "sized_name_shadowed.jac"
     );

def probe(name: str) -> int {
    prog = JacProgram();
    ir = prog.compile(file_path=str(FIXTURE), options=native_force_opts());
    errors = [str(e) for e in prog.errors_had] if prog.errors_had else [];
    assert not prog.errors_had , f"Compilation errors: {errors}";
    eng = ir.gen.native_engine;
    assert isinstance(eng, ExecutionEngine) , "No native engine produced";
    addr = native_address(eng, name);
    assert addr != 0 , f"Function '{name}' not found in JIT engine";
    return ctypes.CFUNCTYPE(ctypes.c_int64)(addr)();
}

test "a module function named cases" {
    def check_a_module_function_named_u16_is_called_not_taken {
        assert probe("shadowed_u16_reads_bytes") == 513;
    }

    def check_a_module_function_named_like_a_wrapping_builtin {
        assert probe("shadowed_wrapping_is_the_module_function") == 1003;
    }
    run_cases(
        [
            (
                "a module function named u16 is called, not taken for the cast",
                check_a_module_function_named_u16_is_called_not_taken
            ),
            (
                "a module function named like a wrapping builtin is called",
                check_a_module_function_named_like_a_wrapping_builtin
            )
        ]
    );
}


test "fixed-width casts the module does not shadow still lower as casts" {
    assert probe("unshadowed_cast_still_casts") == 7 + 44;
}
