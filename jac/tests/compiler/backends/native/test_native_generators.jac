"""Behavioral tests for generator functions (yield) on native.

Graduated from the YieldExpr hard reject in the capability gate: a `def`
containing `yield` lowers to a JacIter creation function plus a private
resume state machine. Consumers exercise the existing iterator surface:
for-loops, first-class next(), independent instances, early break (frame
drop), and composition through the lazy adapters.
"""

import ctypes;
import os;
import from tests.support {
    TESTS_DIR,
    compile_native,
    get_func,
    has_error_code,
    native_address,
    native_force_opts,
    run_cases
}
import jaclang;

import from jaclang.compiler.driver.program { JacProgram }
import from jaclang.compiler.frontend.codeinfo { HDR_RC_OFF }

glob FIXTURES = os.path.join(
         TESTS_DIR, "compiler", "backends", "native", "fixtures"
     );

class JacStrABI(ctypes.Structure) {
    # Register view of a by-value JacStr {root, data, len} return. LLVM
    # lowers the aggregate return into scalar return registers; a 16-byte
    # two-pointer struct restype makes libffi read the first two of them,
    # which yields root and data. len rides in the third return register,
    # unreachable through libffi, but Jac string payloads are always
    # NUL-terminated at len so a bounded read is recovered from data.
    has _fields_: list[tuple[str, type]] = [
        ("root", ctypes.c_void_p),
        ("data", ctypes.c_void_p)
    ];
}

def get_sfunc(eng: any, name: str, restype: type | None, *argtypes: type) -> any {
    # descriptor-ABI variant of get_func: a c_char_p spelling here means a
    # Jac `str` (the by-value {root, data, len} descriptor at the native
    # ABI). LLVM decomposes a by-value descriptor param into three scalar
    # slots, so each str param is declared as (root, data, len) scalars and
    # bytes/str args build their backing storage via jac_str_new; str
    # returns come back as the full bytes of the result string, so existing
    # comparisons keep working.
    addr = native_address(eng, name);
    assert addr != 0 , f"Function '{name}' not found in JIT engine";
    real_res: any = JacStrABI if restype == ctypes.c_char_p else restype;
    str_slots: list[bool] = [];
    real_args: list[any] = [];
    for a in argtypes {
        if a == ctypes.c_char_p {
            str_slots.append(True);
            real_args.append(ctypes.c_void_p);
            real_args.append(ctypes.c_void_p);
            real_args.append(ctypes.c_int64);
        } else {
            str_slots.append(False);
            real_args.append(a);
        }
    }
    raw = ctypes.CFUNCTYPE(real_res, *real_args)(addr);
    sn_addr = 0;
    for sn in ("jac_str_new", "__jac_str_new") {
        try {
            sn_addr = native_address(eng, sn);
        } except Exception {
            sn_addr = 0;
        }
        if sn_addr {
            break;
        }
    }
    mkstr = (
        ctypes.CFUNCTYPE(ctypes.c_void_p, ctypes.c_char_p, ctypes.c_int64)(sn_addr)
            if sn_addr
            else None
    );
    keepalive: list[any] = [];
    def _call(*args: any) -> any {
        c_args: list[any] = [];
        for (a, is_str) in zip(args, str_slots) {
            if is_str {
                b = a.encode("utf-8") if isinstance(a, str) else a;
                if mkstr is not None {
                    p = mkstr(b, len(b));
                } else {
                    # modules that never build strings natively (this one only
                    # measures len over a str param) emit no jac_str_new; back
                    # the descriptor with a NUL-terminated ctypes buffer, the
                    # same fallback native_marshal uses. Safe: rc ops verify
                    # the header magic and skip foreign allocations.
                    buf = ctypes.create_string_buffer(b);
                    keepalive.append(buf);
                    p = ctypes.cast(buf, ctypes.c_void_p).value;
                }
                c_args.append(p);
                c_args.append(p);
                c_args.append(len(b));
            } else {
                c_args.append(a);
            }
        }
        r = raw(*c_args);
        if real_res is JacStrABI {
            if not r.data {
                return b"";
            }
            return ctypes.string_at(r.data);
        }
        return r;
    }
    return _call;
}

"""Compile a snippet through the native pipeline and return the program."""
def compile_na_inline(label: str, code: str) -> JacProgram {
    path = os.path.join(FIXTURES, f"_gen_{label}.jac");
    prog = JacProgram();
    prog.compile(file_path=path, use_str=code, options=native_force_opts());
    return prog;
}

test "generators.jac cases" {
    def check_generator_for_loop_drives_a_while_yield_state_ma {
        (eng, _) = compile_native("generators.jac");

        f = get_func(eng, "total_of", ctypes.c_int64, ctypes.c_int64);
        assert f(5) == 10 , "0+1+2+3+4";
        assert f(0) == 0 , "empty generator yields nothing";
        assert f(1) == 0 , "single yield of 0";
    }

    def check_generator_early_break_abandons_the_stream_safely {
        (eng, _) = compile_native("generators.jac");

        f = get_func(
            eng, "early_break", ctypes.c_int64, ctypes.c_int64, ctypes.c_int64
        );
        assert f(10, 3) == 3 , "sees 0,1,2 then breaks";
    }

    def check_generator_first_class_next_advances_a_stored_ins {
        (eng, _) = compile_native("generators.jac");

        f = get_func(eng, "manual_next", ctypes.c_int64, ctypes.c_int64);
        assert f(5) == 1 , "a=0, b=1 -> 0*10+1";
    }

    def check_generator_independent_instances_do_not_share_fra {
        (eng, _) = compile_native("generators.jac");

        f = get_func(eng, "two_streams", ctypes.c_int64, ctypes.c_int64);
        # sum over a,b in [0..2]^2 of a*b = (0+1+2)^2 = 9.
        assert f(3) == 9;
    }

    def check_generator_yield_inside_a_for_over_range_resumes {
        (eng, _) = compile_native("generators.jac");

        f = get_func(eng, "total_for_yield", ctypes.c_int64, ctypes.c_int64);
        assert f(4) == 12 , "0+2+4+6";
    }

    def check_generator_plain_return_stops_iteration_early {
        (eng, _) = compile_native("generators.jac");

        f = get_func(
            eng, "total_stop_early", ctypes.c_int64, ctypes.c_int64, ctypes.c_int64
        );
        assert f(10, 4) == 6 , "0+1+2+3 then return";
    }

    def check_generator_str_parameter_is_retained_by_the_frame {
        (eng, _) = compile_native("generators.jac");

        f = get_sfunc(eng, "echo_len", ctypes.c_int64, ctypes.c_char_p);
        assert f(b"abcd") == 12 , "len('abcd') * 3";
    }

    def check_generator_composes_under_the_lazy_map_adapter {
        (eng, _) = compile_native("generators.jac");

        f = get_func(eng, "doubled_total", ctypes.c_int64, ctypes.c_int64);
        assert f(4) == 12 , "2*(0+1+2+3)";
    }
    run_cases(
        [
            (
                "generator: for-loop drives a while/yield state machine",
                check_generator_for_loop_drives_a_while_yield_state_ma
            ),
            (
                "generator: early break abandons the stream safely",
                check_generator_early_break_abandons_the_stream_safely
            ),
            (
                "generator: first-class next() advances a stored instance",
                check_generator_first_class_next_advances_a_stored_ins
            ),
            (
                "generator: independent instances do not share frames",
                check_generator_independent_instances_do_not_share_fra
            ),
            (
                "generator: yield inside a for-over-range resumes mid-loop",
                check_generator_yield_inside_a_for_over_range_resumes
            ),
            (
                "generator: plain return stops iteration early",
                check_generator_plain_return_stops_iteration_early
            ),
            (
                "generator: str parameter is retained by the frame across yields",
                check_generator_str_parameter_is_retained_by_the_frame
            ),
            (
                "generator: composes under the lazy map adapter",
                check_generator_composes_under_the_lazy_map_adapter
            )
        ]
    );
}


test "generators_residual.jac cases" {
    def check_generator_yield_from_chains_generators_lists_and {
        (eng, _) = compile_native("generators_residual.jac");

        f = get_func(eng, "total_chain", ctypes.c_int64, ctypes.c_int64);
        assert f(3) == 1302 , "0+1+2 + 100+200 + 999";
        assert f(0) == 1299 , "empty inner generator, then 100+200+999";
    }

    def check_generator_yield_from_a_string_yields_its_charact {
        (eng, _) = compile_native("generators_residual.jac");

        f = get_sfunc(eng, "count_chars", ctypes.c_int64, ctypes.c_char_p);
        assert f(b"abcd") == 4;
        assert f(b"") == 0;
    }

    def check_generator_bare_yield_paces_iteration {
        (eng, _) = compile_native("generators_residual.jac");

        f = get_func(eng, "count_pacer", ctypes.c_int64, ctypes.c_int64);
        assert f(5) == 5;
        assert f(0) == 0;
    }

    def check_generator_return_value_stops_iteration_value_dis {
        (eng, _) = compile_native("generators_residual.jac");

        f = get_func(eng, "total_upto_return", ctypes.c_int64, ctypes.c_int64);
        assert f(7) == 3 , "1+2, the returned 70 has no JacIter consumer";
    }

    def check_generator_yield_inside_a_for_over_a_list_resumes {
        (eng, _) = compile_native("generators_residual.jac");

        f = get_func(eng, "total_doubles", ctypes.c_int64);
        assert f() == 12 , "2+4+6";
    }

    def check_generator_yield_inside_a_for_over_dict_keys_resu {
        (eng, _) = compile_native("generators_residual.jac");

        f = get_func(eng, "count_keys", ctypes.c_int64);
        assert f() == 3 , "len('a') + len('bb')";
    }

    def check_generator_yield_inside_a_for_over_a_string_resum {
        (eng, _) = compile_native("generators_residual.jac");

        f = get_sfunc(eng, "count_per_char", ctypes.c_int64, ctypes.c_char_p);
        assert f(b"xyz") == 3;
    }

    def check_generator_yield_inside_try_exception_raised_and {
        (eng, _) = compile_native("generators_residual.jac");

        f = get_func(eng, "total_resilient", ctypes.c_int64, ctypes.c_int64);
        assert f(0) == 7 , "1+2+4, no exception";
        assert f(1) == 8 , "1, boom caught, 3, 4";
    }
    run_cases(
        [
            (
                "generator: yield from chains generators, lists, and plain yields",
                check_generator_yield_from_chains_generators_lists_and
            ),
            (
                "generator: yield from a string yields its characters",
                check_generator_yield_from_a_string_yields_its_charact
            ),
            (
                "generator: bare yield paces iteration",
                check_generator_bare_yield_paces_iteration
            ),
            (
                "generator: return <value> stops iteration, value discarded on JacIter",
                check_generator_return_value_stops_iteration_value_dis
            ),
            (
                "generator: yield inside a for over a list resumes mid-loop",
                check_generator_yield_inside_a_for_over_a_list_resumes
            ),
            (
                "generator: yield inside a for over dict keys resumes mid-loop",
                check_generator_yield_inside_a_for_over_dict_keys_resu
            ),
            (
                "generator: yield inside a for over a string resumes mid-loop",
                check_generator_yield_inside_a_for_over_a_string_resum
            ),
            (
                "generator: yield inside try, exception raised and caught across resumes",
                check_generator_yield_inside_try_exception_raised_and
            )
        ]
    );
}


test "generators_finally.jac cases" {
    def check_generator_yield_inside_finally_resumes_through_b {
        (eng, _) = compile_native("generators_finally.jac");

        f = get_func(eng, "sum_yf", ctypes.c_int64, ctypes.c_int64);
        assert f(5) == 11 , "yields 5 then 6";
        assert f(10) == 21 , "yields 10 then 11";
    }

    def check_generator_abandoning_a_yield_in_finally_stream_d {
        (eng, _) = compile_native("generators_finally.jac");

        f = get_func(eng, "first_yf", ctypes.c_int64, ctypes.c_int64);
        assert f(10) == 10 , "early return abandons the stream without crashing";
    }
    run_cases(
        [
            (
                "generator: yield inside finally resumes through both continuations",
                check_generator_yield_inside_finally_resumes_through_b
            ),
            (
                "generator: abandoning a yield-in-finally stream drops the frame safely",
                check_generator_abandoning_a_yield_in_finally_stream_d
            )
        ]
    );
}


test "generators_closures.jac cases" {
    def check_generator_capturing_lambda_escaping_inside_a_gen {
        (eng, _) = compile_native("generators_closures.jac");

        f = get_func(eng, "sum_gen_scaled", ctypes.c_int64, ctypes.c_int64);
        assert f(3) == 9 , "g(1)+g(2) with k=3: 3+6";
        assert f(0) == 0;
    }

    def check_generator_plain_param_after_a_captured_param_kee {
        (eng, _) = compile_native("generators_closures.jac");

        f = get_func(
            eng, "sum_gen_mixed", ctypes.c_int64, ctypes.c_int64, ctypes.c_int64
        );
        assert f(3, 10) == 63 , "g(10)+g(11) with k=3: 30+33";
        assert f(0, 5) == 0;
    }

    def check_generator_capturing_lambda_as_a_map_callback_ins {
        (eng, _) = compile_native("generators_closures.jac");

        f = get_func(eng, "sum_gen_mapped", ctypes.c_int64, ctypes.c_int64);
        assert f(10) == 36 , "11+12+13";
    }
    run_cases(
        [
            (
                "generator: capturing lambda escaping inside a generator frame",
                check_generator_capturing_lambda_escaping_inside_a_gen
            ),
            (
                "generator: plain param after a captured param keeps its own value",
                check_generator_plain_param_after_a_captured_param_kee
            ),
            (
                "generator: capturing lambda as a map callback inside a generator",
                check_generator_capturing_lambda_as_a_map_callback_ins
            )
        ]
    );
}


test "generators_iter_ownership.jac cases" {
    def check_generator_enumerate_inside_a_generator_body_surv {
        (eng, _) = compile_native("generators_iter_ownership.jac");

        f = get_func(eng, "total_picked", ctypes.c_int64, ctypes.c_int64);
        assert f(200) == 200 * (20 + 30);
    }

    def check_generator_a_for_loop_iterator_in_a_frame_slot_is {
        (eng, _) = compile_native("generators_iter_ownership.jac");

        make = get_func(eng, "make_counter", ctypes.c_void_p, ctypes.c_int64);
        alias = get_func(eng, "alias", ctypes.c_void_p, ctypes.c_void_p);
        drain_owned = get_func(eng, "drain_owned", ctypes.c_int64, ctypes.c_void_p);
        drain_borrowed = get_func(
            eng, "drain_borrowed", ctypes.c_int64, ctypes.c_void_p
        );
        first_borrowed = get_func(
            eng, "first_borrowed", ctypes.c_int64, ctypes.c_void_p
        );
        for (label, run, expected) in [
            ("owned", drain_owned, 6),
            ("borrowed", drain_borrowed, 6),
            ("abandoned", first_borrowed, 0)
        ] {
            it = make(4);
            assert alias(it) == it;
            before = iter_refs(it);
            assert before == 2 , f"{label}: caller holds two references";
            assert run(it) == expected , label;
            assert iter_refs(it) == before , f"{label}: iterator reference count drifted";
        }
    }
    run_cases(
        [
            (
                "generator: enumerate inside a generator body survives frame drop",
                check_generator_enumerate_inside_a_generator_body_surv
            ),
            (
                "generator: a for-loop iterator in a frame slot is released exactly once",
                check_generator_a_for_loop_iterator_in_a_frame_slot_is
            )
        ]
    );
}

def iter_refs(it: int) -> int {
    return ctypes.c_int64.from_address(it + HDR_RC_OFF).value;
}
