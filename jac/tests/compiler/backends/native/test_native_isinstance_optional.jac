"""`isinstance` lowers when the operand is optional.

Native represents an optional as `{i8 tag, payload}` with tag 0 meaning
None. `_emit_isinstance` boxed the operand directly, which does not work for
that layout, so every `isinstance` on a `T | None` value hit E5092 -- and
`unitree.jac` is full of them, since most tree navigation returns optionals.

The fix guards the check: `None` is an instance of nothing, so the payload
is only inspected on the some-branch and the none-branch yields False
through a phi. The guard matters beyond tidiness -- the user-archetype path
reads a vtable pointer off the object, so an unguarded unwrap would
dereference an undefined payload.

`_opt_unwrap_attr` deliberately is not reused here: it raises AttributeError
on None, which is right for attribute access and wrong for `isinstance`.

Refs #8039
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
import jaclang;

import from jaclang.compiler.driver.program { JacProgram }

glob FIXTURES = os.path.join(
         TESTS_DIR, "compiler", "backends", "native", "fixtures"
     );

test "isinstance_optional.jac cases" {
    def check_isinstance_on_an_optional_none_is_an_instance_of {
        (eng, _) = compile_native("isinstance_optional.jac");

        f = get_func(eng, "opt_single", ctypes.c_bool, ctypes.c_int64);
        assert f(1) is True , "Leaf should match";
        assert f(2) is False , "Twig should not match Leaf";
        assert f(0) is False , "None must be False, not a crash";
    }

    def check_isinstance_on_an_optional_against_a_class_tuple {
        (eng, _) = compile_native("isinstance_optional.jac");

        f = get_func(eng, "opt_tuple", ctypes.c_bool, ctypes.c_int64);
        assert f(1) is True;
        assert f(2) is True;
        assert f(0) is False;
    }

    def check_the_none_branch_never_inspects_the_payload {
        (eng, _) = compile_native("isinstance_optional.jac");

        f = get_func(eng, "opt_negative", ctypes.c_bool, ctypes.c_int64);
        # pick=0 leaves the option empty; an unguarded unwrap would read a vtable
        # off an undefined payload here.
        assert f(0) is False;
        assert f(1) is False;
    }

    def check_an_optional_crosses_into_a_static_method_and_sti {
        (eng, _) = compile_native("isinstance_optional.jac");

        f = get_func(eng, "opt_through_static", ctypes.c_bool, ctypes.c_int64);
        assert f(1) is True;
        assert f(0) is False;
    }
    run_cases(
        [
            (
                "isinstance on an optional: None is an instance of nothing",
                check_isinstance_on_an_optional_none_is_an_instance_of
            ),
            (
                "isinstance on an optional against a class tuple",
                check_isinstance_on_an_optional_against_a_class_tuple
            ),
            (
                "the none-branch never inspects the payload",
                check_the_none_branch_never_inspects_the_payload
            ),
            (
                "an optional crosses into a static method and still narrows",
                check_an_optional_crosses_into_a_static_method_and_sti
            )
        ]
    );
}


test "the optional-isinstance fixture compiles with no native diagnostics" {
    prog = JacProgram();
    prog.compile(
        file_path=str(os.path.join(FIXTURES, "isinstance_optional.jac")),
        options=native_force_opts()
    );
    assert not prog.errors_had , str([str(e) for e in prog.errors_had]);
}
