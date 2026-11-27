"""Bound methods preserve Self across union receivers."""
import from jaclang.compiler.driver.program { JacProgram }
import from jaclang.compiler.driver.compile_options { CompileOptions }
import from tests.support { run_cases }


def check_receiver(source: str) -> list[str] {
    program = JacProgram();
    program.compile(
        file_path="self_union_receiver.jac",
        use_str=source,
        options=CompileOptions(no_cgen=True, no_ir_cache=True, force_codespace="server")
    );
    return [str(error) for error in program.errors_had];
}

test "paths retain their receiver type when iterating a tuple, and related cases" {
    def check_paths_retain_their_receiver_type_when_iterating {
        errors = check_receiver(
            "import from pathlib { Path }\ndef probe(root_dir: Path, rel: str) -> Path | None {\n for candidate in (root_dir / rel, root_dir / 'fallback') {\n  resolved = candidate.resolve();\n  if root_dir.resolve() not in resolved.parents { continue; }\n  return candidate;\n }\n return None;\n}"
        );
        assert not errors , str(errors);
    }

    def check_self_returns_every_possible_bound_receiver {
        errors = check_receiver(
            "import from typing { Self }\nobj First { has number: int = 0; def copy -> Self { return self; } }\nobj Second { has number: int = 1; def copy -> Self { return self; } }\ndef probe(value: First | Second) -> int { return value.copy().number; }"
        );
        assert not errors , str(errors);
    }
    run_cases(
        [
            (
                "paths retain their receiver type when iterating a tuple",
                check_paths_retain_their_receiver_type_when_iterating
            ),
            (
                "Self returns every possible bound receiver",
                check_self_returns_every_possible_bound_receiver
            )
        ]
    );
}


test "a Self union retains incompatible member types" {
    errors = check_receiver(
        "import from typing { Self }\nobj First { has number: int = 0; def copy -> Self { return self; } }\nobj Second { has number: str = ''; def copy -> Self { return self; } }\ndef probe(value: First | Second) -> int { return value.copy().number; }"
    );
    assert any("Cannot return" in error for error in errors) , str(errors);
}
