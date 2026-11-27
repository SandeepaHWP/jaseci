"""Destruction counts for every tuple-bind shape the native backend lowers.

A heap tuple box owns one strong reference per managed field: it retains what
it does not already own when the box is built, and its destructor releases
each field when the box dies. Every binding out of a box is therefore a
borrow that owes a retain, and every binding into a slot that already holds
something owes a release of what it overwrites.

`fixtures/rc_tuple_unpack_ownership.jac` allocates a statically known number
of `Res` per shape and counts destructions in a module glob through
`def drop`, so each test compares allocations against destructions instead
of reasoning about which retain the codegen happened to emit.
"""

import ctypes;
import os;
import from tests.support { TESTS_DIR, native_address, compile_native_ir, run_cases }
import jaclang;
import from jaclang.compiler.driver.program { JacProgram }
import from jaclang.compiler.driver.compile_options { CompileOptions }
import jaclang.compiler.frontend.unitree as uni;
import from jaclang.compiler.backends.native.llvm.binding { ExecutionEngine }

glob FIXTURES = os.path.join(
         TESTS_DIR, "compiler", "backends", "native", "fixtures"
     ),
     FIXTURE = "rc_tuple_unpack_ownership.jac";

"""Compile the ownership fixture natively and return the JIT engine."""
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

"""Call one fixture fn with (3, 4) and return (result, destructions it caused)."""
def run_shape(eng: any, name: str) -> tuple[int, int] {
    fn = get_func(eng, name, ctypes.c_int64, ctypes.c_int64, ctypes.c_int64);
    drops = get_func(eng, "drop_count", ctypes.c_int64);
    before = drops();
    value = fn(3, 4);
    return (value, drops() - before);
}

"""Assert a shape returns `want` and destroys exactly `allocs` objects."""
def check(eng: any, name: str, want: int, allocs: int) {
    (value, drops) = run_shape(eng, name);
    assert value == want , f"{name} returned {value}, expected {want}";
    assert drops == allocs , (
        f"{name} allocated {allocs} Res but destroyed {drops}; "
        f"fewer means a leak, more an over-release"
    );
}

test "value-tuple unpack destroys what each target slot held, and related cases" {
    # --- Value tuples: the target's previous contents must be released ---
    def check_value_tuple_unpack_destroys_what_each_target_slo {
        (eng, _) = compile_fixture();

        check(eng, "unpack_plain_into_plain", 34, 4);
    }

    def check_value_tuple_unpack_moves_elements_it_already_own {
        (eng, _) = compile_fixture();

        check(eng, "unpack_fresh_into_plain", 34, 4);
    }

    def check_optional_elements_unpacked_into_plain_slots_cost {
        (eng, _) = compile_fixture();

        check(eng, "unpack_optional_into_plain", 34, 4);
    }

    # --- Boxed tuples: fields are borrowed from a box that owns them ---
    def check_boxed_tuple_unpacked_into_optional_slots_destroy {
        (eng, _) = compile_fixture();

        check(eng, "unpack_boxed_into_optional", 34, 2);
    }

    def check_boxed_tuple_unpacked_into_plain_slots_destroys_t {
        (eng, _) = compile_fixture();

        check(eng, "unpack_boxed_into_plain", 34, 4);
    }

    def check_boxed_tuple_unpacked_into_fresh_names_destroys_b {
        (eng, _) = compile_fixture();

        check(eng, "unpack_boxed_into_fresh", 34, 2);
    }

    # --- Single field binds: a box outliving the read is a borrow, not a move ---
    def check_one_field_bound_into_an_optional_local_leaves_no {
        (eng, _) = compile_fixture();

        check(eng, "index_into_optional", 34, 2);
    }

    def check_one_field_bound_into_a_plain_local_releases_what {
        (eng, _) = compile_fixture();

        check(eng, "index_into_plain", 34, 3);
    }

    def check_the_same_field_bound_twice_is_destroyed_exactly {
        (eng, _) = compile_fixture();

        check(eng, "index_twice_into_optional", 33, 2);
    }
    run_cases(
        [
            (
                "value-tuple unpack destroys what each target slot held",
                check_value_tuple_unpack_destroys_what_each_target_slo
            ),
            (
                "value-tuple unpack moves elements it already owns",
                check_value_tuple_unpack_moves_elements_it_already_own
            ),
            (
                "optional elements unpacked into plain slots cost no extra reference",
                check_optional_elements_unpacked_into_plain_slots_cost
            ),
            (
                "boxed tuple unpacked into optional slots destroys each payload once",
                check_boxed_tuple_unpacked_into_optional_slots_destroy
            ),
            (
                "boxed tuple unpacked into plain slots destroys targets and fields",
                check_boxed_tuple_unpacked_into_plain_slots_destroys_t
            ),
            (
                "boxed tuple unpacked into fresh names destroys both fields",
                check_boxed_tuple_unpacked_into_fresh_names_destroys_b
            ),
            (
                "one field bound into an optional local leaves nothing alive",
                check_one_field_bound_into_an_optional_local_leaves_no
            ),
            (
                "one field bound into a plain local releases what the slot held",
                check_one_field_bound_into_a_plain_local_releases_what
            ),
            (
                "the same field bound twice is destroyed exactly once",
                check_the_same_field_bound_twice_is_destroyed_exactly
            )
        ]
    );
}


# --- The box destructor is what makes the borrows balance ---
test "a boxed tuple carries a destructor that releases its fields" {
    ir = compile_native_ir(FIXTURE);
    text = str(ir.gen.llvm_ir);
    assert '__rc_release_tuple0' in text , (
        "no tuple-box destructor was emitted; boxed tuple fields would be "
        "abandoned when the box dies"
    );
    body: list[str] = [];
    inside = False;
    for ln in text.split("\n") {
        if not inside
            and ln.startswith("define")
            and ('@"__rc_release_tuple0"' in ln) {
            inside = True;
        }
        if inside {
            body.append(ln);
            if ln == "}" {
                break;
            }
        }
    }
    joined = "\n".join(body);
    assert joined.count('call void @"__rc_release_simple"') == 2 , (
        f"tuple destructor should release both fields, IR was:\n{joined}"
    );
}
