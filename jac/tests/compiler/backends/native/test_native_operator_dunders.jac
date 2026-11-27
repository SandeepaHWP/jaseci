"""Behavioral tests for operator-overload dispatch on archetypes (#7626 B3).

Binary operators on archetype operands lower as static dunder calls:
the left operand's magic method resolves through the MRO (the same walk
class patterns use); when the left type has no matching dunder, the
right operand's reflected form dispatches with swapped operands.
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

test "operator dunder: cases on operator_dunders.jac" {
    def check_operator_dunder_a_b_dispatches_add {
        (eng, _) = compile_native("operator_dunders.jac");

        f = get_func(eng, "add_vecs", ctypes.c_int64);
        assert f() == 3142 , "Vec(1,2) + Vec(30,40) == Vec(31,42)";
    }

    def check_operator_dunder_a_k_dispatches_mul {
        (eng, _) = compile_native("operator_dunders.jac");

        f = get_func(eng, "mul_vec", ctypes.c_int64);
        assert f() == 1520 , "Vec(3,4) * 5 == Vec(15,20)";
    }

    def check_operator_dunder_reflected_radd_dispatches_with_s {
        (eng, _) = compile_native("operator_dunders.jac");

        f = get_func(eng, "radd_vec", ctypes.c_int64);
        assert f() == 1314 , "Tag(10) + Vec(3,4) == Vec(13,14) via Vec.__radd__";
    }

    def check_operator_dunder_inherited_add_resolves_through_t {
        (eng, _) = compile_native("operator_dunders.jac");

        f = get_func(eng, "inherited_add", ctypes.c_int64);
        assert f() == 809 , "Vec3(7,8) + Vec(1,1) == Vec(8,9)";
    }
    run_cases(
        [
            (
                "operator dunder: a + b dispatches __add__",
                check_operator_dunder_a_b_dispatches_add
            ),
            (
                "operator dunder: a * k dispatches __mul__",
                check_operator_dunder_a_k_dispatches_mul
            ),
            (
                "operator dunder: reflected __radd__ dispatches with swapped operands",
                check_operator_dunder_reflected_radd_dispatches_with_s
            ),
            (
                "operator dunder: inherited __add__ resolves through the MRO",
                check_operator_dunder_inherited_add_resolves_through_t
            )
        ]
    );
}
