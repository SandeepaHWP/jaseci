"""`isinstance` against archetypes owned by an imported module (issue #8061).

Candidate vtables were enumerated from the classes the module being compiled
defines, and every vtable global was module-`private`, so a check against an
imported class found nothing to compare and the whole site demoted (E5092).
The candidate set now comes from the program-wide class hierarchy and an
imported class's vtable is referenced as an external symbol, so these sites
lower natively -- and the answers below are what proves the reference points
at the right vtable rather than merely existing.
"""

import ctypes;
import os;
import from tests.support {
    TESTS_DIR,
    compile_native,
    get_func,
    native_force_opts,
    source_spelled,
    run_cases
}

import from jaclang.compiler.driver.program { JacProgram }

glob FIXTURES = os.path.join(
         TESTS_DIR, "compiler", "backends", "native", "fixtures"
     );

test "isinstance against an imported class lowers natively" {
    prog = JacProgram();
    ir = prog.compile(
        file_path=str(os.path.join(FIXTURES, "xmod_isinstance_main.jac")),
        options=native_force_opts()
    );
    demoted = [
        d.pretty_print()
        for d in (prog.errors_had or [])
        if d.code is not None and d.code.code == "E5092"
    ];
    assert not demoted , f"cross-module isinstance did not lower: {demoted}";
    llvm_ir = source_spelled(str(ir.gen.llvm_ir));
    assert "Circle.__vtable" in llvm_ir , "the imported Circle vtable is not referenced at all";
}

test "xmod_isinstance_main.jac cases" {
    def check_imported_base_class_matches_through_the_imported {
        (eng, _) = compile_native("xmod_isinstance_main.jac");

        f = get_func(eng, "chk_base", ctypes.c_int64, ctypes.c_int64);
        assert f(0) == 1 , "Circle must match its imported base Shape";
        assert f(1) == 1 , "Square must match its imported base Shape";
        assert f(2) == 0 , "an unrelated imported hierarchy must not match Shape";
        assert f(3) == 0 , "an int must not match an imported archetype";
    }

    def check_imported_leaf_class_does_not_match_a_sibling {
        (eng, _) = compile_native("xmod_isinstance_main.jac");

        f = get_func(eng, "chk_leaf", ctypes.c_int64, ctypes.c_int64);
        assert f(0) == 1 , "Circle must match Circle";
        assert f(1) == 0 , "Square must not match its sibling Circle";
    }

    def check_statically_typed_operand_of_an_imported_class_ma {
        (eng, _) = compile_native("xmod_isinstance_main.jac");

        f = get_func(eng, "chk_typed", ctypes.c_int64);
        assert f() == 1 , "a Circle-typed local must match the imported base Shape";
    }

    def check_objects_built_by_the_defining_module_carry_the_s {
        (eng, _) = compile_native("xmod_isinstance_main.jac");

        f = get_func(eng, "chk_lib_built", ctypes.c_int64, ctypes.c_int64);
        assert f(0) == 1 , "a Circle built inside the library must match Circle here";
        assert f(1) == 0 , "a Square built inside the library must not match Circle";
    }
    run_cases(
        [
            (
                "imported base class matches through the imported MRO",
                check_imported_base_class_matches_through_the_imported
            ),
            (
                "imported leaf class does not match a sibling",
                check_imported_leaf_class_does_not_match_a_sibling
            ),
            (
                "statically typed operand of an imported class matches its base",
                check_statically_typed_operand_of_an_imported_class_ma
            ),
            (
                "objects built by the defining module carry the same vtable",
                check_objects_built_by_the_defining_module_carry_the_s
            )
        ]
    );
}


test "isinstance against a module-qualified imported class, and related cases" {
    def check_isinstance_against_a_module_qualified_imported_c {
        (eng, _) = compile_native("xmod_isinstance_qualified_main.jac");
        f = get_func(eng, "chk_qualified", ctypes.c_int64, ctypes.c_int64);
        got = [f(k) for k in range(3)];
        assert got == [1, 1, 0] , f"lib.Circle/lib.Square must match lib.Shape, got {got}";
    }

    def check_class_patterns_match_archetypes_an_imported_modu {
        (eng, _) = compile_native("xmod_match_main.jac");
        f = get_func(eng, "shape_kind", ctypes.c_int64, ctypes.c_int64);
        got = [f(k) for k in range(3)];
        assert got == [1, 2, 0] , f"imported class patterns matched {got}";
    }
    run_cases(
        [
            (
                "isinstance against a module-qualified imported class",
                check_isinstance_against_a_module_qualified_imported_c
            ),
            (
                "class patterns match archetypes an imported module defines",
                check_class_patterns_match_archetypes_an_imported_modu
            )
        ]
    );
}


"""A subclass defined in a module the checking module never imports.

The checking module's candidate vtables and class index only list the classes
it can see, so an object of an unseen subclass compared equal to none of them
and every check answered `False`. Each vtable now points at its class's own
ancestry, emitted by the defining module, and a candidate miss walks it.
"""
test "a subclass from an unimported module matches its imported base" {
    (eng, _) = compile_native("xmod_isinstance_foreign_main.jac");
    checks = [
        ("chk_foreign_isinstance", [1, 0, 1]),
        ("chk_foreign_match", [7, -1, 9]),
        ("chk_foreign_kind", [1, 0, 1]),
        ("chk_foreign_walker", [1, 0, 1])
    ];
    for (name, expected) in checks {
        f = get_func(eng, name, ctypes.c_int64, ctypes.c_int64);
        got = [f(k) for k in range(3)];
        assert got == expected , f"{name}: expected {expected}, got {got}";
    }
}
