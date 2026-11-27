"""Tests for the `new` ambient builtin.

`new(Cls, ...args)` is a portable, codespace-aware constructor:
  * In server/Python target code it lowers to `Cls(*args)`.
  * In `cl` (client / JavaScript) blocks it lowers to
    `Reflect.construct(Cls, [args])`.

This replaces the previous client-only `Reflect.construct(...)` idiom and
lets the same source compile cleanly in both backends.
"""

import from jaclang.compiler.backends.py.codegen_shim { generated_python }
import os;
import tempfile;
import from pathlib { Path }
import from tempfile { NamedTemporaryFile }
import jaclang;
import from jaclang.compiler.frontend.parser.frontend { parse }
import from jaclang.compiler.passes.ast_validation_pass { ASTValidationPass }
import from jaclang.compiler.driver.program { JacProgram }
import from jaclang.compiler.driver.pass_driver { run_pass }
import from tests.support { run_cases }


glob _test_tmp_dir: str = tempfile.mkdtemp(prefix="jac_test_new_builtin_"),
     _client_tmp_dir: str = os.path.join(_test_tmp_dir, "client");

with entry {
    os.makedirs(_client_tmp_dir, exist_ok=True);
    with open(os.path.join(_client_tmp_dir, "jac.toml"), "w") as config {
        config.write('[project]\nkind = "js-package"\n');
    }
}

"""Compile inline Jac source through a fresh JacProgram and return module."""
def compile_inline(
    code: str, prog: JacProgram | None = None, client: bool = False
) -> any {
    with NamedTemporaryFile(
        mode="w",
        suffix=".jac",
        delete=False,
        dir=_client_tmp_dir if client else _test_tmp_dir
    ) as f {
        f.write(code);
        f.flush();
        if prog is None {
            prog = JacProgram();
        }
        mod = prog.compile(f.name);
        os.unlink(f.name);
        return mod;
    }
}

"""Parse + validate, returning the JacProgram so we can inspect diagnostics."""
def parse_and_validate(source: str) -> JacProgram {
    prog = JacProgram();
    (module, _) = parse(source, "/tmp/test_new_builtin.jac", prog=prog);
    if module is not None {
        run_pass(ASTValidationPass, module, prog);
    }
    return prog;
}

"""Check whether a specific diagnostic code was emitted."""
def has_code(prog: JacProgram, code: str) -> bool {
    for d in prog.errors_had {
        if d.code is not None and d.code.code == code {
            return True;
        }
    }
    return False;
}


# ─────────────────────────────────────────────────────────────────────
#  Validation: `new(...)` must NOT trigger the legacy E0010 rejection
# ─────────────────────────────────────────────────────────────────────
test "new() as a call is not flagged by ast_validation_pass" {
    prog = parse_and_validate("with entry { x = new(list, [1, 2, 3]); }");
    assert not has_code(prog, "E0010") , (
        "new(...) used as a function call must be allowed (E0010 should not fire)"
    );
}

test "new as a bare identifier (function reference) is allowed, and related cases" {
    def check_new_as_a_bare_identifier_function_reference_is_a {
        prog = parse_and_validate("with entry { f = new; }");

        assert not has_code(prog, "E0010") , (
            "Passing `new` as a first-class function reference must be allowed"
        );
    }

    def check_f_new_first_class_reference_does_not_emit_e0012 {
        prog = parse_and_validate("with entry { f = new; }");

        assert not has_code(prog, "E0012") , (
            "Legitimate `f = new;` must not trip the JS-pattern detector"
        );
        assert not has_code(prog, "E0002");
    }
    run_cases(
        [
            (
                "new as a bare identifier (function reference) is allowed",
                check_new_as_a_bare_identifier_function_reference_is_a
            ),
            (
                "`f = new;` (first-class reference) does NOT emit E0012",
                check_f_new_first_class_reference_does_not_emit_e0012
            )
        ]
    );
}

test "JS-style `new cases" {
    def check_js_style_new_foo_keyword_usage_still_errors {
        prog = parse_and_validate("with entry { x = new Foo(1, 2); }");

        assert len(prog.errors_had) > 0 , (
            "JS-style `new Foo()` must continue to be rejected"
        );
    }

    def check_js_style_new_foo_emits_e0012_not_a_generic_parse {
        prog = parse_and_validate("with entry { x = new Foo(1, 2); }");

        assert has_code(prog, "E0012") , (
            "Assignment-style `x = new Foo(...)` must emit E0012"
        );
        assert not has_code(prog, "E0002") , (
            "Should not also emit E0002 when E0012 fired for the same offense"
        );
    }
    run_cases(
        [
            (
                "JS-style `new Foo()` keyword usage still errors",
                check_js_style_new_foo_keyword_usage_still_errors
            ),
            (
                "JS-style `new Foo(...)` emits E0012, not a generic parse error",
                check_js_style_new_foo_emits_e0012_not_a_generic_parse
            )
        ]
    );
}


test "JS-style bare `new Foo();` emits E0012" {
    prog = parse_and_validate("with entry { new Foo(1, 2); }");
    assert has_code(prog, "E0012") , ("Bare statement `new Foo(...)` must emit E0012");
    assert not has_code(prog, "E0002");
}


# ─────────────────────────────────────────────────────────────────────
#  Client (cl) backend: `new(...)` → `Reflect.construct(...)`
# ─────────────────────────────────────────────────────────────────────
test "cl: new(Cls, args) lowers to Reflect.construct in JS output" {
    code = "def make_date(s: str) -> Any {\n" + "    return new(Date, s);\n" + "}\n";
    mod = compile_inline(code, client=True);
    js = mod.gen.js;
    assert js.strip() , "Expected JavaScript output for cl code";
    assert "Reflect.construct(Date, [s])" in js , (
        "new(Date, s) must lower to Reflect.construct(Date, [s]); got:\n" + js
    );
    assert "new(" not in js , (
        "Raw `new(` call must not leak into JS output; emitter should rewrite it"
    );
}

test "cl: new(Cls) with no args lowers to Reflect.construct(Cls, []), and related cases" {
    def check_cl_new_cls_with_no_args_lowers_to_reflect_constr {
        code = "def make_set() -> Any {\n" + "    return new(Set);\n" + "}\n";
        mod = compile_inline(code, client=True);
        js = mod.gen.js;
        assert "Reflect.construct(Set, [])" in js , (
            "new(Set) with no args must lower to Reflect.construct(Set, []); got:\n"
            + js
        );
    }

    def check_cl_new_with_multiple_args_produces_a_js_array_of {
        code = "def mk(a: int, b: int) -> Any {\n"
            + "    return new(Map, a, b);\n"
            + "}\n";
        mod = compile_inline(code, client=True);
        js = mod.gen.js;
        assert "Reflect.construct(Map, [a, b])" in js , (
            "new(Map, a, b) must lower to Reflect.construct(Map, [a, b]); got:\n" + js
        );
    }
    run_cases(
        [
            (
                "cl: new(Cls) with no args lowers to Reflect.construct(Cls, [])",
                check_cl_new_cls_with_no_args_lowers_to_reflect_constr
            ),
            (
                "cl: new with multiple args produces a JS array of args",
                check_cl_new_with_multiple_args_produces_a_js_array_of
            )
        ]
    );
}


# ─────────────────────────────────────────────────────────────────────
#  Server (Python) backend: `new(...)` works as an ambient builtin
# ─────────────────────────────────────────────────────────────────────
test "server: new is auto-imported from runtime.builtin" {
    code = "with entry { x = new(list, [1, 2, 3]); print(x); }\n";
    mod = compile_inline(code);
    py = generated_python(mod.gen);
    assert "from jaclang.runtime.builtin import" in py , (
        "Expected builtin import preamble; got:\n" + py
    );
    assert "new" in py , "Expected `new` to appear in generated Python";
}

test "server: new(Cls, *args) returns Cls(*args) at runtime" {
    import from jaclang.runtime.builtin { new }
    class Box {
        def init(self: Box, x: int, y: int) {
            self.x = x;
            self.y = y;
        }
    }
    b = new(Box, 3, 4);
    assert isinstance(b, Box);
    assert b.x == 3 and b.y == 4;
}

test "server: new with builtin types works end-to-end" {
    import from jaclang.runtime.builtin { new }
    assert new(list, [1, 2, 3]) == [1, 2, 3];
    assert new(dict, {"a": 1}) == {"a": 1};
    assert new(set, [1, 2, 2, 3]) == {1, 2, 3};
}


# ─────────────────────────────────────────────────────────────────────
#  Diagnostic: E0012 should now point at `new(...)`, not `Reflect.construct`
# ─────────────────────────────────────────────────────────────────────
test "E0012 message mentions new(...) idiom" {
    import from jaclang.compiler.frontend.diagnostics { E0012 }
    msg = E0012.message_template;
    assert "new(" in msg , (
        "E0012 should recommend `new(target, ...args)`; current template: " + msg
    );
}
