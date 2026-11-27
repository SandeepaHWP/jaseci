"""Test suite for all missing diagnostics identified in the gap analysis.

Covers 145 new diagnostic codes across 8 categories:
  - Phase 1: Lexer (E0110-E0117)
  - Phase 2: Parser / Syntax (E0052-E0078)
  - Phase 3: Name Resolution / Scope (E/W 2020-2037)
  - Phase 4: Type System (E/W 1100-1183)
  - Phase 5: Semantic Analysis (E/W 2040-2087)
  - Phase 6: Lint (W3020-W3037)
  - Phase 7: Import (E/W 4001-4010)
  - Phase 8: Codegen (E/W 5080-5083)

Diagnostics that are not yet implemented are tracked as unlisted rows in
the IMPLEMENTED_REJECT / IMPLEMENTED_VALIDATE sets below, which gate the two
parametrized reject suites. Tests are organized to match the implementation
milestones in _planning/diagnostics_implementation_progress.md.
"""

import os;
import from tests.support { JAC_ROOT, run_cases }
import jaclang;

import from jaclang.compiler.passes.ast_validation_pass { ASTValidationPass }
import from jaclang.compiler.driver.program { JacProgram }
import from jaclang.compiler.frontend.parser.frontend { parse }
import from jaclang.testing.test { parametrize }
import from jaclang.compiler.driver.pass_driver { run_pass }

glob FIXTURES = os.path.join(JAC_ROOT, "tests", "compiler", "passes", "fixtures"),
     CHECKER_FIXTURES = os.path.join(
         JAC_ROOT, "tests", "compiler", "passes", "fixtures", "checker"
     ),
     NEW_DIAG_FIXTURES = os.path.join(
         JAC_ROOT, "tests", "compiler", "passes", "fixtures", "new_diagnostics"
     );

# ──────────────────────────────────────────────────────────────────
# Helpers
# ──────────────────────────────────────────────────────────────────
"""Compile a fixture with type checking and static analysis. Returns (program, module)."""
def compile_and_check(fixture_name: str) -> tuple[any, ...] {
    import from jaclang.compiler.driver.compile_options { CompileOptions }
    path = os.path.join(NEW_DIAG_FIXTURES, fixture_name);
    program = JacProgram();
    mod = program.compile(path, options=CompileOptions(default_codespace='server'));
    return (program, mod);
}

"""Compile a fixture without type checking. Returns (program, module)."""
def compile_only(fixture_name: str) -> tuple[any, ...] {
    path = os.path.join(NEW_DIAG_FIXTURES, fixture_name);
    program = JacProgram();
    mod = program.compile(path);
    return (program, mod);
}

"""Parse source string with diagnostic capture: returns (program, had_error)."""
def parse_with_prog(source: str) -> tuple[JacProgram, bool] {
    prog = JacProgram();
    try {
        (_, had_error) = parse(source, "/tmp/test.jac", prog=prog);
        return (prog, had_error);
    } except Exception {
        return (prog, True);
    }
}

"""Parse source string, return (has_errors: bool, program: JacProgram)."""
def parse_and_validate(source: str) -> tuple[any, ...] {
    try {
        (module, had_error) = parse(source, "/tmp/test.jac");
        if had_error or module is None {
            return (True, None);
        }
        prog = JacProgram();
        run_pass(ASTValidationPass, module, prog);
        return (len(prog.errors_had) > 0, prog);
    } except Exception {
        return (True, None);
    }
}

"""Check that a diagnostic with a specific code was emitted."""
def has_diagnostic_code(
    program: JacProgram, code: str, in_warnings: bool = False
) -> bool {
    alerts = program.warnings_had if in_warnings else program.errors_had;
    for alert in alerts {
        if alert.code is not None and alert.code.code == code {
            return True;
        }
    }
    return False;
}

"""Count diagnostics with a specific code."""
def count_diagnostic_code(
    program: JacProgram, code: str, in_warnings: bool = False
) -> int {
    alerts = program.warnings_had if in_warnings else program.errors_had;
    count = 0;
    for alert in alerts {
        if alert.code is not None and alert.code.code == code {
            count += 1;
        }
    }
    return count;
}

test "W0100: invalid escape sequence warns" {
    prog = JacProgram();
    prog.compile(use_str='with entry { x = "press \\q now"; }', file_path="test.jac");
    assert has_diagnostic_code(prog, "W0100", in_warnings=True);
}

test "W0100: valid escapes do not warn" {
    prog = JacProgram();
    prog.compile(
        use_str='with entry { x = "tab\\there\\nline\\x41"; }', file_path="test.jac"
    );
    assert not has_diagnostic_code(prog, "W0100", in_warnings=True);
}

test "W0100: raw string keeps backslashes and is exempt" {
    prog = JacProgram();
    prog.compile(use_str='with entry { x = r"press \\q"; }', file_path="test.jac");
    assert not has_diagnostic_code(prog, "W0100", in_warnings=True);
}

test "W0100: each invalid escape warns once" {
    prog = JacProgram();
    prog.compile(use_str='with entry { x = "\\q then \\e"; }', file_path="test.jac");
    assert count_diagnostic_code(prog, "W0100", in_warnings=True) == 2;
}

# ══════════════════════════════════════════════════════════════════
#  PHASE 2: PARSER / SYNTAX DIAGNOSTICS (E0052-E0078)
#  Infrastructure: INFRA-8 for E0055-E0058
#  Milestone: 1 (Context Validity) + 4 (Parser/Lexer Hardening)
# ══════════════════════════════════════════════════════════════════

# ── E0025: JS arrow function syntax (=>) ───────────────────────────
test "E0013: keyword as a field name carries prefix help" {
    (prog, _) = parse_with_prog("obj X { has match: int = 1; }");
    assert has_diagnostic_code(prog, "E0013");
    hlp = [
        a.help_text
        for a in prog.errors_had
        if a.code is not None and a.code.code == "E0013"
    ];
    assert hlp[0] is not None;
    assert "prefix" in hlp[0];
    assert "{" not in hlp[0];
}

test "E0013: message no longer advertises a closing backtick" {
    (prog, _) = parse_with_prog("obj X { has match: int = 1; }");
    msgs = [
        a.msg
        for a in prog.errors_had
        if a.code is not None and a.code.code == "E0013"
    ];
    assert "`match)" not in msgs[0];
}

test "E0014: a backtick on a non-keyword still errors, and related cases" {
    def check_e0014_a_backtick_on_a_non_keyword_still_errors {
        (prog, _) = parse_with_prog("obj X { has `total: int = 1; }");
        assert has_diagnostic_code(prog, "E0014");
    }

    def check_e0025_arrow_in_fstring_slot {
        (prog, _) = parse_with_prog('with entry { s = f"{x => y}"; }');
        assert has_diagnostic_code(prog, "E0025");
    }

    def check_e0025_empty_body_recovers_without_crash {
        (prog, _) = parse_with_prog('with entry { f = x =>; }');
        assert has_diagnostic_code(prog, "E0025");
    }
    run_cases(
        [
            (
                "E0014: a backtick on a non-keyword still errors",
                check_e0014_a_backtick_on_a_non_keyword_still_errors
            ),
            ("E0025: arrow in fstring slot", check_e0025_arrow_in_fstring_slot),
            (
                "E0025: empty body recovers without crash",
                check_e0025_empty_body_recovers_without_crash
            )
        ]
    );
}

test "kwesc: the prefix form parses clean" {
    (prog, had_error) = parse_with_prog("obj X { has `match: int = 1; }");
    assert not had_error;
    assert len(prog.errors_had) == 0;
}


test "E0013: a keyword after a dot is an attribute, no escape needed" {
    # #8982 item 9: `sys.exit(0)` is the idiom every CLI ends with.
    for src in [
        "import sys; with entry { sys.exit(0); }",
        "with entry { m = re.match; x = obj_.entry; y = cfg.default; }",
        "with entry { z = a.b.node.edge.walker; }"
    ] {
        (prog, had_error) = parse_with_prog(src);
        assert not had_error , src;
        assert not has_diagnostic_code(prog, "E0013") , src;
    }
}

test "E0013: a keyword still cannot bind a name, and names the escape" {
    for src in [
        "with entry { exit = 1; }",
        "def f(match: int) {}",
        "obj X { has entry: int = 1; }",
        "def g(own: int, mut: int, imm: int, awaiting: int) {}"
    ] {
        (prog, _) = parse_with_prog(src);
        assert has_diagnostic_code(prog, "E0013") , src;
    }
}

test "E0025: js arrow in jsx cases" {
    def check_e0025_js_arrow_in_jsx_attribute_slot {
        src = 'cl { def:pub Foo() -> JsxElement {'
            + ' return <button onClick={e => doThing(e)}>Click</button>; } }';
        (prog, _) = parse_with_prog(src);
        assert has_diagnostic_code(prog, "E0025");
        assert count_diagnostic_code(prog, "E0025") == 1;
    }

    def check_e0025_js_arrow_in_jsx_child_slot {
        src = 'cl { def:pub Foo() -> JsxElement {'
            + ' return <div>{e => fn(e)}</div>; } }';
        (prog, _) = parse_with_prog(src);
        assert has_diagnostic_code(prog, "E0025");
        assert count_diagnostic_code(prog, "E0025") == 1;
    }
    run_cases(
        [
            (
                "E0025: js arrow in jsx attribute slot",
                check_e0025_js_arrow_in_jsx_attribute_slot
            ),
            (
                "E0025: js arrow in jsx child slot",
                check_e0025_js_arrow_in_jsx_child_slot
            )
        ]
    );
}


test "E0025: js arrow cases" {
    def check_e0025_js_arrow_at_module_level_glob {
        (prog, _) = parse_with_prog('glob f = x => x + 1;');
        assert has_diagnostic_code(prog, "E0025");
        assert count_diagnostic_code(prog, "E0025") == 1;
    }

    def check_e0025_js_arrow_with_block_body {
        (prog, _) = parse_with_prog('with entry { f = x => { print(x); }; }');
        assert has_diagnostic_code(prog, "E0025");
        assert count_diagnostic_code(prog, "E0025") == 1;
    }
    run_cases(
        [
            (
                "E0025: js arrow at module level glob",
                check_e0025_js_arrow_at_module_level_glob
            ),
            ("E0025: js arrow with block body", check_e0025_js_arrow_with_block_body)
        ]
    );
}


test "E0025: chained arrows emit one diagnostic per arrow" {
    (prog, _) = parse_with_prog('with entry { f = a => b => c; }');
    assert count_diagnostic_code(prog, "E0025") == 2;
}

test "E0025: gte (>=) does not fire, and related cases" {
    def check_e0025_gte_does_not_fire {
        (prog, had_err) = parse_with_prog('with entry { x = (a >= b); }');
        assert not had_err;
        assert not has_diagnostic_code(prog, "E0025");
    }

    def check_e0025_lambda_syntax_unaffected {
        (prog, had_err) = parse_with_prog(
            'with entry { f = lambda (x: int) { x + 1; }; }'
        );
        assert not had_err;
        assert not has_diagnostic_code(prog, "E0025");
    }
    run_cases(
        [
            ("E0025: gte (>=) does not fire", check_e0025_gte_does_not_fire),
            ("E0025: lambda syntax unaffected", check_e0025_lambda_syntax_unaffected)
        ]
    );
}


test "E0025: spaced '= >' is not an arrow" {
    # '=' and '>' separated by whitespace should never match the arrow shape;
    # the source is invalid for other reasons, but E0025 must not fire.
    (prog, _) = parse_with_prog('with entry { x = a = > b; }');
    assert not has_diagnostic_code(prog, "E0025");
}


test "E0027: +>: EdgeType without :+> closer emits E0027, and related cases" {
    # ── E0027: forward typed connection missing :+> ──────────────────────
    def check_e0027_edgetype_without_closer_emits_e0027 {
        (prog, _) = compile_only("parser_E0027_forward_missing_close.jac");
        assert has_diagnostic_code(prog, "E0027");
    }

    # ── E0028: backward typed connection missing :<+ ─────────────────────
    def check_e0028_edgetype_without_closer_emits_e0028 {
        (prog, _) = compile_only("parser_E0028_backward_missing_close.jac");
        assert has_diagnostic_code(prog, "E0028");
    }
    run_cases(
        [
            (
                "E0027: +>: EdgeType without :+> closer emits E0027",
                check_e0027_edgetype_without_closer_emits_e0027
            ),
            (
                "E0028: <+: EdgeType without :<+ closer emits E0028",
                check_e0028_edgetype_without_closer_emits_e0028
            )
        ]
    );
}

test "E0027: complete +>: EdgeType :+> does not fire, and related cases" {
    def check_e0027_complete_edgetype_does_not_fire {
        (prog, had_err) = parse_with_prog(
            'node N {} edge F {} with entry { n1=N(); n2=N(); n1 +>: F :+> n2; }'
        );
        assert not had_err;
        assert not has_diagnostic_code(prog, "E0027");
    }

    def check_e0028_complete_edgetype_does_not_fire {
        (prog, had_err) = parse_with_prog(
            'node N {} edge F {} with entry { n1=N(); n2=N(); n1 <+: F :<+ n2; }'
        );
        assert not had_err;
        assert not has_diagnostic_code(prog, "E0028");
    }
    run_cases(
        [
            (
                "E0027: complete +>: EdgeType :+> does not fire",
                check_e0027_complete_edgetype_does_not_fire
            ),
            (
                "E0028: complete <+: EdgeType :<+ does not fire",
                check_e0028_complete_edgetype_does_not_fire
            )
        ]
    );
}


test "E0052: missing type annotation on parameter, and related cases" {
    def check_e0052_missing_type_annotation_on_parameter {
        (has_err, prog) = parse_and_validate('def foo(x) { }');
        assert has_err or (prog is not None and has_diagnostic_code(prog, "E0052"));
    }

    def check_e0055_yield_outside_function {
        (has_err, prog) = parse_and_validate('with entry { yield 5; }');
        assert has_err or (prog is not None and has_diagnostic_code(prog, "E0055"));
    }

    def check_e0058_break_outside_loop {
        (has_err, prog) = parse_and_validate('with entry { break; }');
        assert has_err or (prog is not None and has_diagnostic_code(prog, "E0058"));
    }

    def check_e0058_continue_outside_loop {
        (has_err, prog) = parse_and_validate('with entry { continue; }');
        assert has_err or (prog is not None and has_diagnostic_code(prog, "E0058"));
    }

    def check_e0075_duplicate_base_class {
        (has_err, prog) = parse_and_validate('obj Base { }\nobj Bad(Base, Base) { }');
        assert has_err or (prog is not None and has_diagnostic_code(prog, "E0075"));
    }
    run_cases(
        [
            (
                "E0052: missing type annotation on parameter",
                check_e0052_missing_type_annotation_on_parameter
            ),
            ("E0055: yield outside function", check_e0055_yield_outside_function),
            ("E0058: break outside loop", check_e0058_break_outside_loop),
            ("E0058: continue outside loop", check_e0058_continue_outside_loop),
            ("E0075: duplicate base class", check_e0075_duplicate_base_class)
        ]
    );
}

test "E0052: missing type annotation on multiple params" {
    (has_err, prog) = parse_and_validate('def foo(x, y) { }');
    assert has_err or (prog is not None and count_diagnostic_code(prog, "E0052") == 2);
}

test "E0052: typed parameter is valid, and related cases" {
    def check_e0052_typed_parameter_is_valid {
        (has_err, _) = parse_and_validate('def foo(x: int) -> int { return x; }');
        assert not has_err;
    }

    def check_e0052_lambda_params_do_not_require_annotations {
        (has_err, _) = parse_and_validate('with entry { f = lambda (x) { x + 1; }; }');
        assert not has_err;
    }

    def check_e0058_break_inside_loop_is_valid {
        (has_err, _) = parse_and_validate('with entry { for i in [1,2] { break; } }');
        assert not has_err;
    }

    def check_e0063_glob_at_module_level_is_valid {
        (has_err, _) = parse_and_validate('glob x: int = 5;');
        assert not has_err;
    }

    def check_valid_return_inside_function {
        (has_err, _) = parse_and_validate('def foo() -> int { return 42; }');
        assert not has_err;
    }

    def check_valid_single_base_class {
        (has_err, _) = parse_and_validate('obj Base { }\nobj Child(Base) { }');
        assert not has_err;
    }
    run_cases(
        [
            ("E0052: typed parameter is valid", check_e0052_typed_parameter_is_valid),
            (
                "E0052: lambda params do not require annotations",
                check_e0052_lambda_params_do_not_require_annotations
            ),
            (
                "E0058: break inside loop is valid",
                check_e0058_break_inside_loop_is_valid
            ),
            (
                "E0063: glob at module level is valid",
                check_e0063_glob_at_module_level_is_valid
            ),
            ("valid: return inside function", check_valid_return_inside_function),
            ("valid: single base class", check_valid_single_base_class)
        ]
    );
}


test "E0052: method self param requires annotation, and related cases" {
    def check_e0052_method_self_param_requires_annotation {
        (has_err, _) = parse_and_validate(
            'obj Foo { def bar(self: Foo, x: int) -> int { return x; } }'
        );
        assert not has_err;
    }

    def check_e0058_continue_in_an_inner_loop_s_else_continues {
        (has_err, _) = parse_and_validate(
            'with entry { for r in [1] { for i in [1,2] { } else { continue; } } }'
        );
        assert not has_err;
    }

    def check_e0058_break_in_an_inner_loop_s_else_breaks_the_o {
        (has_err, _) = parse_and_validate(
            'with entry { while True { for i in [1,2] { } else { break; } } }'
        );
        assert not has_err;
    }

    def check_e0058_continue_inside_if_else_inside_loop_is_val {
        (has_err, _) = parse_and_validate(
            'with entry { for i in [1,2] { if i == 1 { } else { continue; } } }'
        );
        assert not has_err;
    }

    # ══════════════════════════════════════════════════════════════════
    #  POSITIVE TESTS (ensure valid code is NOT flagged)
    #  These should pass even before implementation, confirming no
    #  false positives on valid patterns.
    # ══════════════════════════════════════════════════════════════════
    def check_valid_break_inside_loop {
        (has_err, _) = parse_and_validate(
            'with entry { for i in [1,2,3] { if i == 2 { break; } } }'
        );
        assert not has_err;
    }

    def check_valid_continue_inside_loop {
        (has_err, _) = parse_and_validate(
            'with entry { for i in [1,2,3] { if i == 2 { continue; } } }'
        );
        assert not has_err;
    }

    def check_valid_distinct_keyword_args {
        (has_err, _) = parse_and_validate(
            'def foo(a: int, b: int) -> int { return a + b; }\nwith entry { foo(a=1, b=2); }'
        );
        assert not has_err;
    }

    def check_valid_except_with_specific_type {
        (has_err, _) = parse_and_validate(
            'with entry { try { x = 1; } except ValueError as e { print(e); } }'
        );
        assert not has_err;
    }

    def check_valid_non_empty_f_string {
        (has_err, _) = parse_and_validate(
            'with entry { name = "world"; x = f"hello {name}"; }'
        );
        assert not has_err;
    }

    def check_valid_function_with_return_on_all_paths {
        (has_err, _) = parse_and_validate(
            'def foo(x: int) -> int { if x > 0 { return x; } else { return -x; } }'
        );
        assert not has_err;
    }
    run_cases(
        [
            (
                "E0052: method self param requires annotation",
                check_e0052_method_self_param_requires_annotation
            ),
            (
                "E0058: continue in an inner loop's else continues the outer loop",
                check_e0058_continue_in_an_inner_loop_s_else_continues
            ),
            (
                "E0058: break in an inner loop's else breaks the outer loop",
                check_e0058_break_in_an_inner_loop_s_else_breaks_the_o
            ),
            (
                "E0058: continue inside if-else inside loop is valid",
                check_e0058_continue_inside_if_else_inside_loop_is_val
            ),
            ("valid: break inside loop", check_valid_break_inside_loop),
            ("valid: continue inside loop", check_valid_continue_inside_loop),
            ("valid: distinct keyword args", check_valid_distinct_keyword_args),
            ("valid: except with specific type", check_valid_except_with_specific_type),
            ("valid: non-empty f-string", check_valid_non_empty_f_string),
            (
                "valid: function with return on all paths",
                check_valid_function_with_return_on_all_paths
            )
        ]
    );
}


test "E0057: return inside any function body is valid" {
    for src in [
        'def f -> int { return 1; }',
        'obj A { has n: int = 0; def get -> int { return self.n; } }',
        'obj A { has n: int = 0; def get -> int; }\nimpl A.get -> int { return self.n; }',
        'walker W { can go with Root entry { if True { return; } } }',
        'test "early exit" { if True { return; } }',
        'with entry { def g -> int { return 2; } f = lambda -> int { return 3; }; }'
    ] {
        (has_err, prog) = parse_and_validate(src);
        errors = [str(e) for e in prog.errors_had] if prog else ["parse failed"];
        assert not has_err , f"{src!r}: {errors}";
    }
}


test "E0058: continue in a loop's else with no outer loop, and related cases" {
    def check_e0058_continue_in_a_loop_s_else_with_no_outer_lo {
        (has_err, prog) = parse_and_validate(
            'with entry { for i in [1,2] { } else { continue; } }'
        );
        assert has_err and prog is not None and has_diagnostic_code(prog, "E0058");
    }

    def check_e0058_break_in_a_loop_s_else_with_no_outer_loop {
        (has_err, prog) = parse_and_validate(
            'with entry { for i in [1,2] { } else { break; } }'
        );
        assert has_err and prog is not None and has_diagnostic_code(prog, "E0058");
    }
    run_cases(
        [
            (
                "E0058: continue in a loop's else with no outer loop",
                check_e0058_continue_in_a_loop_s_else_with_no_outer_lo
            ),
            (
                "E0058: break in a loop's else with no outer loop",
                check_e0058_break_in_a_loop_s_else_with_no_outer_loop
            )
        ]
    );
}


test "E0065: duplicate keyword argument, and related cases" {
    def check_e0065_duplicate_keyword_argument {
        (prog, _) = compile_and_check("parser_E0065_duplicate_kwarg.jac");
        assert has_diagnostic_code(prog, "E0065");
    }

    def check_e0066_positional_after_keyword_argument {
        (prog, _) = compile_and_check("parser_E0066_pos_after_kw.jac");
        assert has_diagnostic_code(prog, "E0066");
    }

    def check_e0076_duplicate_method_definition {
        (prog, _) = compile_and_check("parser_E0076_duplicate_method.jac");
        assert has_diagnostic_code(prog, "E0076");
    }

    def check_e2055_return_in_finally_block {
        (prog, _) = compile_and_check("context_E2055_return_in_finally.jac");
        assert has_diagnostic_code(prog, "E2055");
    }

    # --- Context Validity (INFRA-8) ---
    def check_e2083_disengage_outside_walker {
        (prog, _) = compile_and_check("context_E2083_disengage_outside_walker.jac");
        assert has_diagnostic_code(prog, "E2083");
    }
    run_cases(
        [
            (
                "E0065: duplicate keyword argument",
                check_e0065_duplicate_keyword_argument
            ),
            (
                "E0066: positional after keyword argument",
                check_e0066_positional_after_keyword_argument
            ),
            (
                "E0076: duplicate method definition",
                check_e0076_duplicate_method_definition
            ),
            ("E2055: return in finally block", check_e2055_return_in_finally_block),
            ("E2083: disengage outside walker", check_e2083_disengage_outside_walker)
        ]
    );
}


test "E0071: bare except not last" {
    (has_err, prog) = parse_and_validate(
        'with entry { try { x=1; } except { y=2; } except ValueError as e { z=3; } }'
    );
    assert has_err or (prog is not None and has_diagnostic_code(prog, "E0071"));
}


test "E0076: Python __init__ and init are distinct methods, and related cases" {
    def check_e0076_python_init_and_init_are_distinct_methods {
        # Issue #6556: a Python class with both `__init__` and a plain `init`
        # method (e.g. Pillow's PIL.ImageFile.PyCodec) is valid Python; raising
        # `__init__` to Jac's `init` constructor must not collide with it.
        (prog, _) = compile_only("parser_E0076_py_init_distinct.py");
        assert not has_diagnostic_code(prog, "E0076");
    }

    def check_e2036_an_impl_overloads_a_self_import_and_a_glob {
        (prog, _) = compile_only("scope_E2036_allowed_redefinitions.jac");
        assert not has_diagnostic_code(prog, "E2036");
    }
    run_cases(
        [
            (
                "E0076: Python __init__ and init are distinct methods",
                check_e0076_python_init_and_init_are_distinct_methods
            ),
            (
                "E2036: an impl, overloads, a self-import and a glob assignment are not duplicates",
                check_e2036_an_impl_overloads_a_self_import_and_a_glob
            )
        ]
    );
}

test "E0078: a method or ability with a field's name is rejected, and related cases" {
    def check_e0078_a_method_or_ability_with_a_field_s_name_is {
        # The later class attribute replaced the field, so `self.rise` read the
        # ability's function and `jac check` passed it silently.
        (prog, _) = compile_and_check("parser_E0078_field_method_clash.jac");
        assert count_diagnostic_code(prog, "E0078") == 3 , "the method 'grow', the ability 'rise' and the impl-block 'grow'";
    }

    def check_e2036_a_second_module_level_definition_of_a_name {
        (prog, _) = compile_and_check("scope_E2036_duplicate_def.jac");
        assert count_diagnostic_code(prog, "E2036") == 2 , "the second 'foo' and the second 'Bar'";
    }
    run_cases(
        [
            (
                "E0078: a method or ability with a field's name is rejected",
                check_e0078_a_method_or_ability_with_a_field_s_name_is
            ),
            (
                "E2036: a second module-level definition of a name is rejected",
                check_e2036_a_second_module_level_definition_of_a_name
            )
        ]
    );
}

test "E0078: distinct names, property accessors and init/postinit beside same-named fields are not clashes" {
    (prog, _) = compile_and_check("parser_E0078_distinct_members.jac");
    assert not has_diagnostic_code(prog, "E0078");
}

test "E0078: a Python class is not checked, and related cases" {
    def check_e0078_a_python_class_is_not_checked {
        prog = JacProgram();
        prog.compile(
            use_str="class Box:\n    grow: int = 3\n\n    def grow(self) -> int:\n        return 7\n",
            file_path="clash.py"
        );
        assert not has_diagnostic_code(prog, "E0078");
    }

    def check_e2036_a_python_module_may_redefine_a_name {
        prog = JacProgram();
        prog.compile(
            use_str="def pick() -> int:\n    return 1\n\n\ndef pick() -> int:\n    return 2\n",
            file_path="redefine.py"
        );
        assert not has_diagnostic_code(prog, "E2036");
    }
    run_cases(
        [
            (
                "E0078: a Python class is not checked",
                check_e0078_a_python_class_is_not_checked
            ),
            (
                "E2036: a Python module may redefine a name",
                check_e2036_a_python_module_may_redefine_a_name
            )
        ]
    );
}


test "E2036: the call the checker passed against the first def is now an error" {
    # The later def wins at run time, so `resolve("edit")` used to check clean
    # and then fail with "takes 0 positional arguments but 1 was given".
    prog = JacProgram();
    prog.compile(
        use_str='def resolve(capability: str = "") -> str { return "first:" + capability; }\n'
            + 'def resolve() -> str { return "second"; }\n'
            + 'with entry { print(resolve("edit")); }',
        file_path="dup.jac"
    );
    assert count_diagnostic_code(prog, "E2036") == 1;
}


test "E2036: a local def, obj or glob that reuses an imported name is rejected" {
    # `def Thing -> int;` used to lose to the imported record: the checker typed
    # `Thing()` as the record and the program constructed it instead of
    # calling the def.
    (prog, _) = compile_and_check("scope_E2036_import_shadow.jac");
    messages = [
        e.msg
        for e in prog.errors_had
        if e.code is not None and e.code.code == "E2036"
    ];
    assert len(messages) == 3 , messages;
    assert "Duplicate definition of 'Thing': the import on line 2 binds it too."
        in messages , messages;
    assert any("'Other'" in m for m in messages) , messages;
    assert any("'Knob'" in m for m in messages) , messages;
}

test "E2036: an import after the local definition still collides, and related cases" {
    def check_e2036_an_import_after_the_local_definition_still {
        (_, prog) = parse_and_validate(
            "def Thing -> int {\n    return 7;\n}\n\nimport from rec { Thing }\n"
        );
        assert count_diagnostic_code(prog, "E2036") == 1;
    }

    def check_e2036_a_module_import_and_an_enum_or_type_alias {
        (_, prog) = parse_and_validate(
            "import os;\nimport from rec { Kind, Alias }\n\n"
                + "enum Kind { A, B }\n\ntype Alias = int;\n\n"
                + "def os -> int {\n    return 0;\n}\n"
        );
        assert count_diagnostic_code(prog, "E2036") == 3;
    }
    run_cases(
        [
            (
                "E2036: an import after the local definition still collides",
                check_e2036_an_import_after_the_local_definition_still
            ),
            (
                "E2036: a module import and an enum or type alias collide too",
                check_e2036_a_module_import_and_an_enum_or_type_alias
            )
        ]
    );
}


test "E2036: an include does not collide with a local definition" {
    # A module's own definition shadows a name an `include` brings in.
    (_, prog) = parse_and_validate(
        "include rec;\nimport from rec { Thing as Widget }\n\n"
            + "obj Thing {}\n\ndef Widget2 -> int {\n    return 1;\n}\n"
    );
    assert not has_diagnostic_code(prog, "E2036");
}

test "removed nonlocal directive is a parse error" {
    (has_err, prog) = parse_and_validate('with entry { nonlocal x; }');
    assert has_err;
}


test "E0063: glob in statement position is always rejected" {
    sources = [
        "with entry { glob a = 90; }",
        "with entry { glob a = 90 }",
        "with entry { glob a = }",
        "with entry { glob a }",
        "with entry { glob }",
        "def foo() -> int { glob a = 1; return a; }",
        "test \"t\" { glob sneaky = 1; assert True; }"
    ];
    for src in sources {
        (has_err, _) = parse_and_validate(src);
        assert has_err , f"Expected error for: {src}";
    }
}

test "removed placement-marker blocks raise the migration error" {
    # cl/sv/na blocks were removed with #7772; the parser points authors at
    # 'jac fix placement' instead of a bare syntax error.
    for src in ["cl { glob counter: int = 0; }", "sv { glob token = \"x\"; }"] {
        (has_err, _) = parse_and_validate(src);
        assert has_err , f"Expected the marker-removal error for: {src}";
    }
}

test "E0063: glob inside a function blocks codegen and points at the rebinding idiom" {
    # Detected by ASTValidationPass (not the parser), and the structural
    # error must block codegen so the invalid module cannot silently execute.
    prog = JacProgram();
    mod = prog.compile(
        file_path="/tmp/test_e0063_gate.jac",
        use_str="def foo() -> int { glob a = 1; return a; }"
    );
    assert has_diagnostic_code(prog, "E0063");
    assert not mod.gen.py_bytecode;
    # Jac has no `global` statement; a function rebinds a module glob by
    # plain assignment, so a hint that says "global" leads to a parse error (#8612).
    alert = [
        a
        for a in prog.errors_had
        if a.code is not None and a.code.code == "E0063"
    ][0];
    assert "global" not in alert.msg;
    assert alert.help_text is not None;
    assert "assignment" in alert.help_text and "no global statement" in alert.help_text;
}

# ══════════════════════════════════════════════════════════════════
#  PHASE 4: TYPE SYSTEM DIAGNOSTICS (E/W 1100-1183)
#  Infrastructure: INFRA-3 (exhaustiveness), INFRA-4 (null safety),
#                  INFRA-9 (generics)
#  Milestones: 7, 8, 11
# ══════════════════════════════════════════════════════════════════

test "E1042: calling an async function without await" {
    # An `async def` call is a coroutine, not its return value. Assigning it
    # without `await` is a type error; the awaited forms must stay clean.
    (prog, _) = compile_and_check("type_E1042_missing_await.jac");
    assert count_diagnostic_code(prog, "E1042") == 2 , f"expected 2 E1042 (the two un-awaited calls), got "
    f"{count_diagnostic_code(prog, 'E1042')}; "
    f"errors={[str(e) for e in prog.errors_had]}";
}

test "E1042: missing await on a bridged server call (issue #6236)" {
    # Server functions imported into client context (a CLIENT_BRIDGE) are
    # async RPC stubs; calling one without `await` assigns a coroutine to a
    # typed field and crashes at runtime. `jac check` must flag it.
    (prog, _) = compile_and_check("type_E1042_sv_missing_await.jac");
    assert has_diagnostic_code(prog, "E1042") , f"expected E1042 for the un-awaited bridged call; "
    f"errors={[str(e) for e in prog.errors_had]}";
}

test "E1042: a same-app server->server call is synchronous, not a coroutine, and related cases" {
    def check_e1042_a_same_app_server_server_call_is_synchrono {
        # A server module importing another server module of the same app is a
        # LOCAL import (no app boundary, no bridge), so binding its result to a
        # concrete type without `await` is correct and must NOT raise E1042.
        # Uses the SAME provider as the client fixture above, which still must
        # raise it -- the check is sensitive to the importing module's context,
        # not to the shape of the import statement. The cross-app server case
        # (SERVICE_BRIDGE, which IS a coroutine) is covered in
        # tests/compiler/test_cross_app_import.jac.
        (prog, _) = compile_and_check("type_E1042_sv_sync_call_server.jac");
        assert count_diagnostic_code(prog, "E1042") == 0 , f"same-app server call must not be flagged as a missing-await coroutine; "
        f"errors={[str(e) for e in prog.errors_had]}";
    }

    def check_e2085_await_outside_async_function_or_ability_is {
        # jac check must catch what only jac run's bytecode compile caught before:
        # a plain `can`/`def` body that awaits is invalid, and the checker had no
        # opinion on it at all -- `await` was never visited by any checking pass.
        (prog, _) = compile_and_check("context_E2085_await_outside_async.jac");
        assert count_diagnostic_code(prog, "E2085") == 1 , f"expected exactly 1 E2085 (the plain 'can', not the 'async can'), got "
        f"{count_diagnostic_code(prog, 'E2085')}; errors={[
            str(e) for e in prog.errors_had
        ]}";
    }
    run_cases(
        [
            (
                "E1042: a same-app server->server call is synchronous, not a coroutine",
                check_e1042_a_same_app_server_server_call_is_synchrono
            ),
            (
                "E2085: await outside async function or ability (issue #8998)",
                check_e2085_await_outside_async_function_or_ability_is
            )
        ]
    );
}

# ══════════════════════════════════════════════════════════════════
#  PHASE 5: SEMANTIC ANALYSIS DIAGNOSTICS (E/W 2040-2087)
#  Infrastructure: INFRA-7 (archetype contracts), INFRA-1 (def-use),
#                  INFRA-2 (dominance), INFRA-8 (context)
#  Milestones: 1, 5, 9, 10
# ══════════════════════════════════════════════════════════════════

test "W2058: None comparison with ==, and related cases" {
    def check_w2058_none_comparison_with {
        (prog, _) = compile_and_check("semantic_W2058_none_eq.jac");
        assert has_diagnostic_code(prog, "W2058", in_warnings=True);
    }

    def check_w2063_self_assignment {
        (prog, _) = compile_and_check("semantic_W2063_self_assignment.jac");
        assert has_diagnostic_code(prog, "W2063", in_warnings=True);
    }

    # --- Data Flow / Values ---
    def check_w2070_division_by_zero {
        (prog, _) = compile_and_check("semantic_W2070_div_by_zero.jac");
        assert has_diagnostic_code(prog, "W2070", in_warnings=True);
    }

    def check_w2074_f_string_with_no_expressions {
        (prog, _) = compile_and_check("semantic_W2074_fstring_no_expr.jac");
        assert has_diagnostic_code(prog, "W2074", in_warnings=True);
    }

    def check_w2075_redundant_boolean_comparison {
        (prog, _) = compile_and_check("semantic_W2075_redundant_bool.jac");
        assert has_diagnostic_code(prog, "W2075", in_warnings=True);
    }
    run_cases(
        [
            ("W2058: None comparison with ==", check_w2058_none_comparison_with),
            ("W2063: self-assignment", check_w2063_self_assignment),
            ("W2070: division by zero", check_w2070_division_by_zero),
            (
                "W2074: f-string with no expressions",
                check_w2074_f_string_with_no_expressions
            ),
            (
                "W2075: redundant boolean comparison",
                check_w2075_redundant_boolean_comparison
            )
        ]
    );
}

test "W2029: python-style property decorators in an obj" {
    (prog, _) = compile_and_check("semantic_W2029_property_decorators.jac");
    # One per decorator: '@property', '@val.getter', '@val.setter', '@val.deleter'.
    # The '@property' inside the Python-compat 'class' is exempt, like W2006/W2007.
    assert count_diagnostic_code(prog, "W2029", in_warnings=True) == 4;
}


test "W2075 silent for boolean-literal tests over non-bool operands" {
    (prog, _) = compile_and_check("semantic_W2075_any_identity_ok.jac");
    assert not has_diagnostic_code(prog, "W2075", in_warnings=True) , "identity/equality against True over any-typed operands is a discriminator, not redundancy";
}


test "W3020: unnecessary pass in non-empty body, and related cases" {
    # ══════════════════════════════════════════════════════════════════
    #  PHASE 6: LINT DIAGNOSTICS (W3020-W3037)
    #  Infrastructure: None required (pure AST patterns)
    #  Milestone: 3 (Lint Pass Extensions)
    # ══════════════════════════════════════════════════════════════════
    def check_w3020_unnecessary_pass_in_non_empty_body {
        path = os.path.join(NEW_DIAG_FIXTURES, "lint_W3020_unnecessary_pass.jac");
        prog = JacProgram.jac_file_formatter(path, auto_lint=True);
        assert has_diagnostic_code(prog, "W3020", in_warnings=True);
    }

    def check_w3021_unnecessary_else_after_return {
        path = os.path.join(NEW_DIAG_FIXTURES, "lint_W3021_unnecessary_else.jac");
        prog = JacProgram.jac_file_formatter(path, auto_lint=True);
        assert has_diagnostic_code(prog, "W3021", in_warnings=True);
    }

    def check_w3022_nested_if_can_be_elif {
        path = os.path.join(NEW_DIAG_FIXTURES, "lint_W3022_nested_if_to_elif.jac");
        prog = JacProgram.jac_file_formatter(path, auto_lint=True);
        assert has_diagnostic_code(prog, "W3022", in_warnings=True);
    }

    def check_w3023_return_true_false_simplification {
        path = os.path.join(NEW_DIAG_FIXTURES, "lint_W3023_return_bool.jac");
        prog = JacProgram.jac_file_formatter(path, auto_lint=True);
        assert has_diagnostic_code(prog, "W3023", in_warnings=True);
    }

    def check_w3024_repeated_condition_in_if_elif {
        path = os.path.join(NEW_DIAG_FIXTURES, "lint_W3024_repeated_condition.jac");
        prog = JacProgram.jac_file_formatter(path, auto_lint=True);
        assert has_diagnostic_code(prog, "W3024", in_warnings=True);
    }

    def check_w3025_identical_if_else_branches {
        path = os.path.join(NEW_DIAG_FIXTURES, "lint_W3025_identical_branches.jac");
        prog = JacProgram.jac_file_formatter(path, auto_lint=True);
        assert has_diagnostic_code(prog, "W3025", in_warnings=True);
    }

    def check_w3030_too_many_parameters {
        path = os.path.join(NEW_DIAG_FIXTURES, "lint_W3030_too_many_params.jac");
        prog = JacProgram.jac_file_formatter(path, auto_lint=True);
        assert has_diagnostic_code(prog, "W3030", in_warnings=True);
    }

    def check_w3035_is_with_literal {
        path = os.path.join(NEW_DIAG_FIXTURES, "lint_W3035_is_with_literal.jac");
        prog = JacProgram.jac_file_formatter(path, auto_lint=True);
        assert has_diagnostic_code(prog, "W3035", in_warnings=True);
    }

    def check_w3036_mutable_default_argument {
        path = os.path.join(NEW_DIAG_FIXTURES, "lint_W3036_mutable_default.jac");
        prog = JacProgram.jac_file_formatter(path, auto_lint=True);
        assert has_diagnostic_code(prog, "W3036", in_warnings=True);
    }

    def check_w3040_filter_comparison_tautology_on_shadowed_na {
        path = os.path.join(NEW_DIAG_FIXTURES, "lint_W3040_filter_tautology.jac");
        prog = JacProgram.jac_file_formatter(path, auto_lint=True);
        assert has_diagnostic_code(prog, "W3040", in_warnings=True);
    }
    run_cases(
        [
            (
                "W3020: unnecessary pass in non-empty body",
                check_w3020_unnecessary_pass_in_non_empty_body
            ),
            (
                "W3021: unnecessary else after return",
                check_w3021_unnecessary_else_after_return
            ),
            ("W3022: nested if can be elif", check_w3022_nested_if_can_be_elif),
            (
                "W3023: return True/False simplification",
                check_w3023_return_true_false_simplification
            ),
            (
                "W3024: repeated condition in if/elif",
                check_w3024_repeated_condition_in_if_elif
            ),
            (
                "W3025: identical if/else branches",
                check_w3025_identical_if_else_branches
            ),
            ("W3030: too many parameters", check_w3030_too_many_parameters),
            ("W3035: is with literal", check_w3035_is_with_literal),
            ("W3036: mutable default argument", check_w3036_mutable_default_argument),
            (
                "W3040: filter comparison tautology on shadowed name",
                check_w3040_filter_comparison_tautology_on_shadowed_na
            )
        ]
    );
}


test "W3025: no false positive on subscript targets and call kwargs" {
    path = os.path.join(
        NEW_DIAG_FIXTURES, "lint_W3025_identical_branches_false_positive.jac"
    );
    prog = JacProgram.jac_file_formatter(path, auto_lint=True);
    # Fixture has 3 if/else pairs: 2 differ (must not warn) + 1 truly matches
    # with a subscript target (must warn). Expect exactly 1 W3025.
    assert count_diagnostic_code(prog, "W3025", in_warnings=True) == 1;
}


# ══════════════════════════════════════════════════════════════════
#  REMOVED PAREN FILTER SYNTAX (E0048)
# ══════════════════════════════════════════════════════════════════
test "E0048: removed paren filter syntax errors" {
    (prog, _) = compile_only("parser_E0048_removed_paren_filter.jac");
    assert has_diagnostic_code(prog, "E0048") , "Removed (?:...) filter syntax should emit E0048 error";
}

test "E0048: bracket filter no error" {
    (prog, _) = compile_only("parser_E0048_bracket_filter_ok.jac");
    assert not has_diagnostic_code(prog, "E0048") , "Bracket filter syntax [?:...] should not emit E0048";
}

test "E0048: multiple removed filters emit multiple errors" {
    prog = JacProgram();
    prog.compile(
        use_str='with entry { x = [1,2](?a<1); y = [3,4](?a>2); }', file_path="test.jac"
    );
    assert count_diagnostic_code(prog, "E0048") == 2 , "Each removed filter occurrence should emit its own E0048";
}

test "E0048: edge ref with removed filter, and related cases" {
    def check_e0048_edge_ref_with_removed_filter {
        prog = JacProgram();
        prog.compile(
            use_str='walker W { can go with entry { visit [-->](?:Foo); } }',
            file_path="test.jac"
        );
        assert has_diagnostic_code(prog, "E0048") , "Removed filter inside edge ref should emit E0048";
    }

    def check_e0048_filter_inside_edge_chain_errors {
        prog = JacProgram();
        prog.compile(
            use_str='walker W { can go with entry { visit [-->(?:Foo)]; } }',
            file_path="test.jac"
        );
        assert has_diagnostic_code(prog, "E0048") , "(?:...) inside edge chain should also emit E0048";
    }
    run_cases(
        [
            (
                "E0048: edge ref with removed filter",
                check_e0048_edge_ref_with_removed_filter
            ),
            (
                "E0048: filter inside edge chain errors",
                check_e0048_filter_inside_edge_chain_errors
            )
        ]
    );
}

test "E0048: edge ref with bracket filter no error, and related cases" {
    def check_e0048_edge_ref_with_bracket_filter_no_error {
        prog = JacProgram();
        prog.compile(
            use_str='walker W { can go with entry { visit [-->][?:Foo]; } }',
            file_path="test.jac"
        );
        assert not has_diagnostic_code(prog, "E0048") , "Bracket filter after edge ref should not emit E0048";
    }

    def check_e0048_bracket_filter_inside_edge_chain_no_error {
        prog = JacProgram();
        prog.compile(
            use_str='walker W { can go with entry { visit [-->[?:Foo]]; } }',
            file_path="test.jac"
        );
        assert not has_diagnostic_code(prog, "E0048") , "Bracket filter [?:...] inside edge chain should not emit E0048";
    }
    run_cases(
        [
            (
                "E0048: edge ref with bracket filter no error",
                check_e0048_edge_ref_with_bracket_filter_no_error
            ),
            (
                "E0048: bracket filter inside edge chain no error",
                check_e0048_bracket_filter_inside_edge_chain_no_error
            )
        ]
    );
}


# ══════════════════════════════════════════════════════════════════
#  INLINE SNIPPET PARAMETRIZED TESTS
#  These test simple patterns that don't need fixture files
# ══════════════════════════════════════════════════════════════════
glob MUST_REJECT_NEW: dict[str, str] = {
         "E0053_double_args": "def foo(*a: int, *b: str) { }",
         "E0053_double_kwargs": "def foo(**a: int, **b: str) { }",
         "E0059_literal_lhs": "with entry { 42 = x; }",
         "E0059_binop_lhs": "with entry { a + b = x; }",
         "E0071_bare_except_first": "with entry { try { x=1; } except { } except ValueError as e { } }",
         "E0075_dup_base": "obj A { }\nobj B(A, A) { }",
         "E0077_empty_fstring": 'with entry { x = f"{}"; }'
     },
     MUST_VALIDATE_NEW: dict[str, str] = {
         "E0055_yield_in_entry": "with entry { yield 5; }",
         "E0057_return_in_entry": "with entry { return; }",
         "E0057_return_in_entry_if": "with entry { x = 1; if x { return; } }",
         "E0057_return_in_entry_loop": "with entry { for i in [1] { return i; } }",
         "E0057_return_in_archetype_entry": "obj Holder { with entry { return; } }",
         "E0058_break_no_loop": "with entry { break; }",
         "E0058_continue_no_loop": "with entry { continue; }"
     };

glob IMPLEMENTED_REJECT: set[str] = {
         "E0063_glob_inside_func",
         "E0071_bare_except_first",
         "E0075_dup_base"
     },
     IMPLEMENTED_VALIDATE: set[str] = {
         "E0055_yield_in_entry",
         "E0057_return_in_entry",
         "E0057_return_in_entry_if",
         "E0057_return_in_entry_loop",
         "E0057_return_in_archetype_entry",
         "E0058_break_no_loop",
         "E0058_continue_no_loop"
     };

def reject_test(name_snippet: tuple[any, ...]) {
    (name, snippet) = name_snippet;
    if name not in IMPLEMENTED_REJECT {
        testskip(f"{name} not yet implemented");
    }
    # For implemented checks, parse then validate — errors come from ASTValidationPass
    (has_errors, _) = parse_and_validate(snippet);
    assert has_errors , f"Validation must reject '{name}': {snippet}";
}

def validate_reject_test(name_snippet: tuple[any, ...]) {
    (name, snippet) = name_snippet;
    if name not in IMPLEMENTED_VALIDATE {
        testskip(f"{name} not yet implemented");
    }
    (has_errors, prog) = parse_and_validate(snippet);
    assert has_errors , f"Validation must reject '{name}': {snippet}";
    code = name.split("_")[0];
    assert prog is not None and count_diagnostic_code(prog, code) == 1 , (
        name,
        [str(e) for e in prog.errors_had] if prog else "parse failed"
    );
}


test "view body check flags cases on view_body_rules.jac" {
    def check_view_body_check_flags_bare_return_in_any_slot_po {
        (program, _) = compile_and_check("view_body_rules.jac");

        # Bare `return;` is now forbidden ANYWHERE inside a slot body — the
        # "use `skip;`" guidance applies in loops, outside loops, and nested
        # under control flow (`match` / `try` / etc.). Fixture has three
        # call sites: ReturnInLoop, ReturnAtTopLevel, ReturnInLoopUnderMatch.
        n = count_diagnostic_code(program, "E2020");
        assert n >= 3 , (
            f"E2020 should fire for each bare `return;` in a slot body (loop, top-level, and nested), got {n}"
        );
    }

    def check_view_body_check_flags_break_inside_a_template_lo {
        (program, _) = compile_and_check("view_body_rules.jac");

        # Shallow `for { break; }` AND nested `for { try { break; } except: ... }`
        # should both fire — verifies `_check_body` recurses through `try`.
        # `skip;` is NO LONGER in E2021 (it's the slot early-exit now).
        n = count_diagnostic_code(program, "E2021");
        assert n >= 2 , (
            f"E2021 should fire for both shallow and nested `break;` in loops, got {n}"
        );
    }
    # ══════════════════════════════════════════════════════════════════
    #  view_body_check — `view` declarator body rules (ViewLowerPass)
    # ══════════════════════════════════════════════════════════════════
    def check_view_body_check_flags_a_value_returning_return_e {
        (program, _) = compile_and_check("view_body_rules.jac");

        assert has_diagnostic_code(program, "E2019") , (
            "a `return <value>;` in a view body should raise E2019"
        );
    }

    def check_redundant_slot_wrapping_inside_slot_body_raises {
        (program, _) = compile_and_check("view_body_rules.jac");

        # `RedundantSlotWrap` has two redundant `{...}` slots inside the
        # outer slot body (`{if ... }}` and `{for ... }}`) — each drives
        # E2023, and no cascade of E0001/E0002 parse errors should fire.
        n = count_diagnostic_code(program, "E2023");
        assert n >= 2 , (
            f"E2023 should fire once per redundant inner `{{...}}` slot, got {n}"
        );
        # Critically, the recovery path must NOT produce a parse-error
        # cascade — the redundant-slot diagnostic replaces it.
        parse_cascade = count_diagnostic_code(program, "E0002");
        assert parse_cascade == 0 , (
            f"E2023 recovery must avoid the E0001/E0002 parse cascade, got {parse_cascade} E0002 errors"
        );
    }

    def check_redundant_expr_slot_wrapping_inside_slot_body_ra {
        (program, _) = compile_and_check("view_body_rules.jac");

        n = count_diagnostic_code(program, "E2028");
        assert n >= 3 , (
            f"E2028 should fire once per redundant single-expression wrap, got {n}"
        );
        # The two statement wraps (`RedundantSlotWrap`) stay the E2023 error; the
        # expression wraps must not inflate that count.
        e2023 = count_diagnostic_code(program, "E2023");
        assert e2023 == 2 , (
            f"only the two control-flow wraps stay E2023 errors, got {e2023}"
        );
        parse_cascade = count_diagnostic_code(program, "E0002");
        assert parse_cascade == 0 , (
            f"E2028 recovery must avoid the E0002 parse cascade, got {parse_cascade} E0002 errors"
        );
    }

    def check_view_body_check_warns_on_a_keyless_while_w2019 {
        (program, _) = compile_and_check("view_body_rules.jac");

        # Shallow `while { <span/> }` AND nested `while { try { <span/> } }` AND
        # `while { switch { case _: <span/> } }` should all fire — verifies
        # `_emits_keyless_jsx` recurses through `try` and `switch`.
        n = count_diagnostic_code(program, "W2019", in_warnings=True);
        assert n >= 3 , (
            f"W2019 should fire for shallow, try-wrapped, and switch-wrapped keyless `while`, got {n}"
        );
    }
    run_cases(
        [
            (
                "view body check flags bare return; in any slot position (E2020)",
                check_view_body_check_flags_bare_return_in_any_slot_po
            ),
            (
                "view body check flags break inside a template loop (E2021)",
                check_view_body_check_flags_break_inside_a_template_lo
            ),
            (
                "view body check flags a value-returning return (E2019)",
                check_view_body_check_flags_a_value_returning_return_e
            ),
            (
                "redundant `{...}` slot wrapping inside slot body raises E2023",
                check_redundant_slot_wrapping_inside_slot_body_raises
            ),
            (
                "redundant `{expr}` slot wrapping inside slot body raises E2028 (issue #6733)",
                check_redundant_expr_slot_wrapping_inside_slot_body_ra
            ),
            (
                "view body check warns on a keyless while (W2019)",
                check_view_body_check_warns_on_a_keyless_while_w2019
            )
        ]
    );
}


test "implicit return outside function tail position raises E2084" {
    (program, _) = compile_and_check("implicit_return_rules.jac");
    # `misplaced_in_if` (tail of an `if` body) and the module-level
    # `with entry` tail should each fire E2084; the function-tail
    # implicit returns must not.
    n = count_diagnostic_code(program, "E2084");
    assert n == 2 , (
        f"E2084 should fire for if-body and module-level tails only, got {n}"
    );
    # The recovery path must not produce an E0002 parse-error cascade —
    # the placement diagnostic replaces it entirely.
    assert count_diagnostic_code(program, "E0002") == 0 , (
        "tail-expression recovery must not cascade into E0002"
    );
}

test "implicit return participates in return-type checking" {
    (program, _) = compile_and_check("implicit_return_rules.jac");
    # `wrong_type_tail` returns a string from `-> int` via implicit return.
    assert has_diagnostic_code(program, "E1002") , (
        "implicit return must be type-checked like an explicit return"
    );
    # `ok_tail`'s implicit return satisfies the all-paths-return analysis.
    assert not has_diagnostic_code(program, "E1004") , (
        "a tail implicit return must count as returning on all paths"
    );
}


test "genuine collection literals in a slot body are not mistaken for slot wraps" {
    # A multi-element set `{1, 2}` and a dict `{a: 1}` are real collection
    # expressions, not redundant single-expression slot wraps — the `,`/`:`
    # disambiguates them, so the parser leaves them as collection literals and
    # must NOT raise E2028. Uses `parse_with_prog` so the parser diagnostics
    # (E2028 is parser-emitted) are captured.
    src = 'def:pub C(a: int) -> JsxElement { '
        + 'return <ul>{for x in [a] { {1, 2}; {a: 1}; }}</ul>; }';
    (prog, _) = parse_with_prog(src);
    n = count_diagnostic_code(prog, "E2028");
    assert n == 0 , f"genuine collection literals must not raise E2028, got {n}";
}


# ══════════════════════════════════════════════════════════════════
#  ENTRY POINT — register parametrized tests
# ══════════════════════════════════════════════════════════════════
with entry {
    parametrize(
        "new reject",
        list(MUST_REJECT_NEW.items()),
        reject_test,
        id_fn=lambda (x: tuple[str, str]) { x[0]; }
    );
    parametrize(
        "new validate reject",
        list(MUST_VALIDATE_NEW.items()),
        validate_reject_test,
        id_fn=lambda (x: tuple[str, str]) { x[0]; }
    );
}


test "E2085 permits async client functions and implicit async client tests" {
    prog = JacProgram();
    prog.compile(
        use_str='import from "@jac/runtime" { jacLogin }\n'
        'async def app -> JsxElement { await jacLogin("a", "b"); return <div/>; }\n'
        'test "login" { await jacLogin("a", "b"); }\n',
        file_path="await_client.jac",
        no_cgen=True
    );
    assert not prog.errors_had , str(prog.errors_had);
}


test "E2085 rejects plain client functions and lambdas inside async tests" {
    prog = JacProgram();
    prog.compile(
        use_str='import from "@jac/runtime" { jacLogin }\n'
        'def app -> JsxElement { await jacLogin("a", "b"); return <div/>; }\n'
        'test "login" { callback = lambda { await jacLogin("a", "b"); }; }\n',
        file_path="invalid_await_client.jac",
        no_cgen=True
    );
    assert count_diagnostic_code(prog, "E2085") == 2;
}
