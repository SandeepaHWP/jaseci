"""Value checks for optionals living inside tuple slots (#8091).

A tuple slot declared `T | None` must hold the JacOpt representation the
declared type promises: the constructor stores it, the destructor releases
through it, and the reader decodes it. The failure classes are a segfault
(present payload decoded through the sheared layout) and, worse, silent
payload loss or a truthiness flip when the tag byte lands on the wrong
memory -- so every shape here is checked by value, in both the present and
the None arm, with destruction counts to rule out leaks and over-releases.

`fixtures/opt_tuple_payload.jac` carries the shapes; `(Box | None, bool)`
is `parse_from_path` in the sealed parser, whose `from_loc` kid-append is
how #8091 surfaced.
"""

import ctypes;
import os;
import jaclang;
import from tests.support { TESTS_DIR, native_address, run_cases }
import from jaclang.compiler.driver.program { JacProgram }
import from jaclang.compiler.driver.compile_options { CompileOptions }
import jaclang.compiler.frontend.unitree as uni;
import from jaclang.compiler.backends.native.llvm.binding { ExecutionEngine }

glob FIXTURES = os.path.join(
         TESTS_DIR, "compiler", "backends", "native", "fixtures"
     ),
     FIXTURE = "opt_tuple_payload.jac";

"""Compile the optional-payload fixture natively and return the JIT engine."""
def compile_fixture -> tuple[ExecutionEngine, uni.Module] {
    prog = JacProgram();
    opts = CompileOptions(force_codespace='native', memory_profile="managed");
    ir = prog.compile(file_path=str(os.path.join(FIXTURES, FIXTURE)), options=opts);
    errors = [str(e) for e in prog.errors_had] if prog.errors_had else [];
    assert not prog.errors_had , f"Compilation errors in {FIXTURE}: {errors}";
    eng = ir.gen.native_engine;
    assert isinstance(eng, ExecutionEngine) , f"No native engine produced for {FIXTURE}";
    return (eng, ir);
}

"""Get a ctypes-callable function from the JIT engine."""
def get_func(eng: any, name: str, restype: type | None, *argtypes: type) -> any {
    addr = native_address(eng, name);
    assert addr != 0 , f"Function '{name}' not found in JIT engine";
    functype = ctypes.CFUNCTYPE(restype, *argtypes);
    return functype(addr);
}

"""Call `name` with `args`, assert the value and the destruction count."""
def check(eng: any, name: str, args: list[int], want: int, allocs: int) {
    fn = get_func(eng, name, ctypes.c_int64, *[ctypes.c_int64 for _ in args]);
    drops = get_func(eng, "drop_count", ctypes.c_int64);
    before = drops();
    value = fn(*args);
    freed = drops() - before;
    assert value == want , f"{name}{tuple(args)} returned {value}, expected {want}";
    assert freed == allocs , (
        f"{name}{tuple(args)} allocated {allocs} Box but destroyed {freed}; "
        f"fewer means a leak, more an over-release"
    );
}


test "an optional in a later slot keeps both the prim and the payload, and related cases" {
    def check_an_optional_in_a_later_slot_keeps_both_the_prim {
        (eng, _) = compile_fixture();

        check(eng, "read_last", [7], 77, 1);
        check(eng, "read_last", [-3], -30, 0);
    }

    def check_tuple_unpack_binds_the_optional_payload_without {
        (eng, _) = compile_fixture();

        check(eng, "unpack_first", [6], 6, 1);
        check(eng, "unpack_first", [-1], -1, 0);
    }

    def check_an_optional_payload_flows_through_a_list_append {
        (eng, _) = compile_fixture();

        check(eng, "append_payload", [9], 9, 1);
        check(eng, "append_payload", [-1], -1, 0);
    }
    def check_a_present_optional_payload_in_slot_0_survives_th {
        (eng, _) = compile_fixture();

        check(eng, "read_first", [5], 5, 1);
    }

    def check_a_none_in_slot_0_takes_the_is_none_arm_and_the_f {
        (eng, _) = compile_fixture();

        check(eng, "read_first", [-1], -1, 0);
        check(eng, "read_first_flag", [-1], 0, 0);
        check(eng, "read_first_flag", [5], 1, 1);
    }

    def check_two_optional_slots_keep_independent_payloads_acr {
        (eng, _) = compile_fixture();

        check(eng, "read_pair", [3, 4], 403, 2);
        check(eng, "read_pair", [-1, 4], -600, 1);
        check(eng, "read_pair", [3, -1], -99997, 1);
        check(eng, "read_pair", [-1, -1], -101000, 0);
    }
    run_cases(
        [
            (
                "an optional in a later slot keeps both the prim and the payload",
                check_an_optional_in_a_later_slot_keeps_both_the_prim
            ),
            (
                "tuple unpack binds the optional payload without a truthiness flip",
                check_tuple_unpack_binds_the_optional_payload_without
            ),
            (
                "an optional payload flows through a list append (from_loc shape)",
                check_an_optional_payload_flows_through_a_list_append
            ),
            (
                "a present optional payload in slot 0 survives the subscript read",
                check_a_present_optional_payload_in_slot_0_survives_th
            ),
            (
                "a None in slot 0 takes the is-None arm and the flag stays intact",
                check_a_none_in_slot_0_takes_the_is_none_arm_and_the_f
            ),
            (
                "two optional slots keep independent payloads across mixed arms",
                check_two_optional_slots_keep_independent_payloads_acr
            )
        ]
    );
}
