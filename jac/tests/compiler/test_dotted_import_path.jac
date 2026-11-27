"""`import a.b` binds `a`, and `a.b.C` resolves through it.

Python's AST gives `import a.b` as a single alias whose name is the dotted
string "a.b". Wrapping that string in one Name produced a module path with a
single segment literally spelled "a.b" -- a name no expression can reference --
so `a` was never bound and every `a.b.C` in that module went unresolved.

Base classes suffered worst: typeshed writes `class TextTestResult(
unittest.result.TestResult, ...)`, so the base resolved to nothing and every
inherited member vanished. E1030 then asserted a definite negative --
"has no attribute" -- for members that plainly exist.
"""

import from jaclang.compiler.driver.program { JacProgram }
import from jaclang.compiler.driver.compile_options { CompileOptions }
import from tests.support { run_cases }


def check_src(src: str) -> list[str] {
    prog = JacProgram();
    prog.compile(
        file_path="dotted.jac", use_str=src, options=CompileOptions(no_cgen=True)
    );
    return [str(e) for e in prog.errors_had];
}

test "members inherited through a dotted base class stay visible, and related cases" {
    def check_members_inherited_through_a_dotted_base_class_st {
        src = "import unittest;\n"
            + "def probe(r: unittest.TextTestResult) -> bool {\n"
            + "    return r.wasSuccessful();\n"
            + "}\n";
        errs = check_src(src);
        assert not errs , f"dotted base class lost its members: {errs}";
    }

    def check_a_dotted_submodule_reference_resolves_inside_a_l {
        src = "import unittest;\n"
            + "def probe(r: unittest.TextTestResult) -> int {\n"
            + "    return len(r.failures);\n"
            + "}\n";
        errs = check_src(src);
        assert not errs , f"dotted submodule reference unresolved: {errs}";
    }
    run_cases(
        [
            (
                "members inherited through a dotted base class stay visible",
                check_members_inherited_through_a_dotted_base_class_st
            ),
            (
                "a dotted submodule reference resolves inside a loaded module",
                check_a_dotted_submodule_reference_resolves_inside_a_l
            )
        ]
    );
}
