"""Behavioral tests for bare functions stored in containers (native).

Regression suite for the callable-in-list crash class: `list[Callable]`
lowers its element slots to raw i8*, while the Callable read/call
convention loads a {fn, env} closure pair — so a bare code pointer stored
via a list literal, `append`/`insert`, or `lst[i] = f` was read back as a
closure box, retained through its code bytes, and called through garbage
(SIGSEGV). Stores into list slots now wrap raw functions as owned
{fn, env=null} boxes (`_wrap_fn_as_closure_value`). Dicts were never
affected — their Callable value type lowers to the closure struct, so the
centralized `_coerce_type` wrap already fired — but they are pinned here
so a future lowering change cannot regress them silently.

Every fixture function routes around a decoy (`h_bad` returns -99), so a
wrong-target dispatch can never satisfy the asserts.
"""

import ctypes;
import os;
import tempfile;
import from pathlib { Path }
import from tests.support {
    compile_native,
    get_func,
    native_build,
    native_build_fails,
    native_run,
    run_cases
}

glob FIXTURES = Path(__file__).resolve().parent / "fixtures";

test "callable_in_container.jac cases" {
    def check_callable_in_list_append_then_index_set_then_call {
        (eng, _) = compile_native("callable_in_container.jac");

        f = get_func(eng, "list_append_dispatch", ctypes.c_int64, ctypes.c_int64);
        assert f(7) == 107;
    }

    def check_callable_in_list_list_literal_elements_dispatch {
        (eng, _) = compile_native("callable_in_container.jac");

        f = get_func(eng, "list_literal_dispatch", ctypes.c_int64, ctypes.c_int64);
        # h_one(4) + h_two(4) = 104 + 204.
        assert f(4) == 308;
    }

    def check_callable_in_list_insert_wraps_and_releases_exact {
        (eng, _) = compile_native("callable_in_container.jac");

        f = get_func(eng, "list_insert_dispatch", ctypes.c_int64, ctypes.c_int64);
        assert f(5) == 105;
    }

    def check_callable_in_list_global_list_element_dispatch {
        (eng, _) = compile_native("callable_in_container.jac");

        f = get_func(eng, "global_list_dispatch", ctypes.c_int64, ctypes.c_int64);
        assert f(6) == 206;
    }

    def check_callable_in_list_list_of_funcs_passed_as_a_param {
        (eng, _) = compile_native("callable_in_container.jac");

        f = get_func(eng, "list_as_param", ctypes.c_int64, ctypes.c_int64);
        # h_one(3) + h_two(3) = 103 + 203.
        assert f(3) == 306;
    }

    def check_callable_value_bare_fn_passed_as_a_callable_para {
        (eng, _) = compile_native("callable_in_container.jac");

        f = get_func(eng, "fn_as_param", ctypes.c_int64, ctypes.c_int64);
        assert f(2) == 102;
    }

    def check_callable_in_dict_literal_index_set_values_dispat {
        (eng, _) = compile_native("callable_in_container.jac");

        f = get_func(eng, "dict_dispatch", ctypes.c_int64, ctypes.c_int64);
        # h_one(1) + h_two(1) = 101 + 201.
        assert f(1) == 302;
    }

    def check_callable_in_dict_list_of_dicts_passed_as_a_param {
        (eng, _) = compile_native("callable_in_container.jac");

        f = get_func(eng, "list_of_dicts_dispatch", ctypes.c_int64, ctypes.c_int64);
        assert f(9) == 209;
    }

    def check_callable_in_list_two_rebound_slots_chain_through {
        (eng, _) = compile_native("callable_in_container.jac");

        f = get_func(eng, "chained_dispatch", ctypes.c_int64, ctypes.c_int64);
        # h_two(h_one(1)) = 200 + 101.
        assert f(1) == 301;
    }

    def check_callable_in_any_functions_read_out_of_dict_and_l {
        (eng, _) = compile_native("callable_in_container.jac");

        f = get_func(eng, "any_dispatch", ctypes.c_int64, ctypes.c_int64);
        assert f(3) == 303;
    }
    run_cases(
        [
            (
                "callable-in-list: append then index-set then call",
                check_callable_in_list_append_then_index_set_then_call
            ),
            (
                "callable-in-list: list literal elements dispatch",
                check_callable_in_list_list_literal_elements_dispatch
            ),
            (
                "callable-in-list: insert wraps and releases exactly once",
                check_callable_in_list_insert_wraps_and_releases_exact
            ),
            (
                "callable-in-list: global list element dispatch",
                check_callable_in_list_global_list_element_dispatch
            ),
            (
                "callable-in-list: list of funcs passed as a param",
                check_callable_in_list_list_of_funcs_passed_as_a_param
            ),
            (
                "callable value: bare fn passed as a Callable param",
                check_callable_value_bare_fn_passed_as_a_callable_para
            ),
            (
                "callable-in-dict: literal + index-set values dispatch",
                check_callable_in_dict_literal_index_set_values_dispat
            ),
            (
                "callable-in-dict: list of dicts passed as a param",
                check_callable_in_dict_list_of_dicts_passed_as_a_param
            ),
            (
                "callable-in-list: two rebound slots chain through each other",
                check_callable_in_list_two_rebound_slots_chain_through
            ),
            (
                "callable-in-any: functions read out of dict and list of any dispatch",
                check_callable_in_any_functions_read_out_of_dict_and_l
            )
        ]
    );
}


test "callable-in-any: a call with no native signature is refused with a hint" {
    out = native_build_fails(str(FIXTURES / "call_through_value_refused.jac"));
    for fn_name in ["call_any", "call_bare_keyword", "call_bare_positional"] {
        assert f"demoting {fn_name} to Python-only" in out , out[-1500:];
    }
    assert "E9003" not in out , out[-1500:];
    assert "help: The callee's native type carries no call signature" in out , out[-1500:];
    assert out.count("keywords or extra arguments would be lost") == 2 , out[-1500:];
}

test "callable-in-any: a class or instance raises TypeError, a boxed function keeps its identity, and a boxed closure is released" {
    out_bin = os.path.join(tempfile.mkdtemp(), "any_callable");
    native_build(str(FIXTURES / "any_callable.jac"), out_bin, extra=["--debug"]);
    out = native_run(out_bin);
    err = "TypeError: only a function stored in `any` can be called natively through a Callable\n";
    assert out.startswith(err * 2 + "1275\nTrue False False\n") , out[:400];
    assert "RC LIVE OBJECTS at exit" in out , out[-400:];
    assert "<- LEAK" not in out , out[-1500:];
}
