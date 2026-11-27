"""Loud seals (#7857 Phase F): W1312 when an owned binding silently crosses.

Passing an owned binding to a resolved callee's unannotated parameter is
the membrane acting silently -- the callee receives a managed value and
the caller's binding is consumed at a distance. W1312 makes that crossing
loud; wrapping the argument in managed() or annotating the parameter own
keeps it quiet.
"""

import os;
import from tests.support { JAC_ROOT, run_cases }
import from jaclang.compiler.driver.program { JacProgram }

glob FIXTURES = os.path.join(
         JAC_ROOT, "tests", "compiler", "passes", "fixtures", "ownership"
     );

def _codes(name: str) -> list[str] {
    prog = JacProgram();
    prog.compile(os.path.join(FIXTURES, name));
    out = [
        a.code.code
        for a in (list(prog.errors_had) + list(prog.warnings_had))
        if a.code is not None
            and (a.code.code.startswith("E13") or a.code.code == "W1312")
    ];
    out.sort();
    return out;
}

test "owned binding into an unannotated param warns W1312" {
    assert _codes("seal_warn_plain_param.jac") == ["W1312"];
}

test "owned binding into an own param is quiet, and related cases" {
    def check_owned_binding_into_an_own_param_is_quiet {
        assert _codes("seal_warn_own_param_ok.jac") == [];
    }

    def check_managed_at_the_call_site_is_quiet {
        assert _codes("seal_warn_managed_ok.jac") == [];
    }
    run_cases(
        [
            (
                "owned binding into an own param is quiet",
                check_owned_binding_into_an_own_param_is_quiet
            ),
            (
                "managed() at the call site is quiet",
                check_managed_at_the_call_site_is_quiet
            )
        ]
    );
}
