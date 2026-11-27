"""Behavioral tests for isinstance over mixed builtin + archetype tuples.

Graduated from the E5092 guardrail (`isinstance mixed tuple unsupported type
errors` in test_native_gen_pass.jac): the mixed form now lowers as a guarded
disjunction — JacVal tag compares for the builtin arms, and a vtable identity
compare (behind an object-tag branch, so it never dereferences a non-pointer
payload) for the archetype arms.
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

test "isinstance_mixed.jac cases" {
    def check_isinstance_recognizes_native_string_fields_local {
        (eng, _) = compile_native("isinstance_mixed.jac");

        assert get_func(eng, "chk_string_representations", ctypes.c_int64)() == 127;
    }

    def check_isinstance_mixed_builtin_arm_matches_int_and_boo {
        (eng, _) = compile_native("isinstance_mixed.jac");

        f = get_func(eng, "chk_int_foo", ctypes.c_int64, ctypes.c_int64);
        assert f(0) == 1 , "int must match the int arm";
        assert f(1) == 0 , "str must not match (int, Foo)";
        assert f(5) == 1 , "bool must match the int arm (Python semantics)";
        assert f(6) == 0 , "None must not match (int, Foo)";
    }

    def check_isinstance_mixed_archetype_arm_matches_exact_typ {
        (eng, _) = compile_native("isinstance_mixed.jac");

        f = get_func(eng, "chk_int_foo", ctypes.c_int64, ctypes.c_int64);
        assert f(2) == 1 , "Foo instance must match the Foo arm";
        assert f(3) == 1 , "Sub(Foo) instance must match the Foo arm via MRO";
        assert f(4) == 0 , "unrelated archetype must not match (int, Foo)";
    }

    def check_isinstance_mixed_str_archetype_tuple {
        (eng, _) = compile_native("isinstance_mixed.jac");

        f = get_func(eng, "chk_str_other", ctypes.c_int64, ctypes.c_int64);
        assert f(0) == 1 , "str must match the str arm";
        assert f(1) == 1 , "Other instance must match the Other arm";
        assert f(2) == 0 , "Foo must not match (str, Other)";
    }

    def check_isinstance_mixed_hierarchy_less_target_forces_vt {
        (eng, _) = compile_native("isinstance_mixed.jac");

        f = get_func(eng, "chk_lone", ctypes.c_int64, ctypes.c_int64);
        assert f(0) == 1 , "Lone instance must match its own arm";
        assert f(1) == 1 , "float must match the float arm";
    }

    def check_isinstance_mixed_statically_typed_struct_operand {
        (eng, _) = compile_native("isinstance_mixed.jac");

        f = get_func(eng, "chk_typed_operand", ctypes.c_int64);
        assert f() == 1 , "Sub-typed operand must match the Foo arm";
    }
    run_cases(
        [
            (
                "isinstance recognizes native string fields locals parameters and optionals",
                check_isinstance_recognizes_native_string_fields_local
            ),
            (
                "isinstance mixed: builtin arm matches int and bool, rejects str/None",
                check_isinstance_mixed_builtin_arm_matches_int_and_boo
            ),
            (
                "isinstance mixed: archetype arm matches exact type and subtype",
                check_isinstance_mixed_archetype_arm_matches_exact_typ
            ),
            (
                "isinstance mixed: str + archetype tuple",
                check_isinstance_mixed_str_archetype_tuple
            ),
            (
                "isinstance mixed: hierarchy-less target forces vtable materialization",
                check_isinstance_mixed_hierarchy_less_target_forces_vt
            ),
            (
                "isinstance mixed: statically typed struct operand",
                check_isinstance_mixed_statically_typed_struct_operand
            )
        ]
    );
}
