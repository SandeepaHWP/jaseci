"""Tuple values meeting variadic slots and range subscripts natively.

A fixed-arity tuple stored into a `tuple[Any, ...]` slot is boxed element by
element into the slot's sequence instead of being bitcast into it, and a range
subscript the native backend cannot slice is refused instead of being lowered
as an index read at the range's start.
"""

import ctypes;
import os;
import from tests.support { TESTS_DIR, compile_native, get_func, run_cases }
import from jaclang.compiler.driver.compile_options { CompileOptions }
import from jaclang.compiler.driver.na_coverage { na_coverage_begin, na_coverage_end }
import from jaclang.compiler.driver.program { JacProgram }

glob FIXTURES = os.path.join(
         TESTS_DIR, "compiler", "backends", "native", "fixtures"
     ),
     _ENG: list[any] = [];

def _engine -> any {
    if not _ENG {
        (eng, _) = compile_native("struct_unpack_variadic.jac");
        get_func(eng, "jac_entry", None)();
        _ENG.append(eng);
    }
    return _ENG[0];
}

test "an unpacked tuple in an entry global keeps its length and elements, and related cases" {
    def check_an_unpacked_tuple_in_an_entry_global_keeps_its_l {
        eng = _engine();
        assert get_func(eng, "entry_len", ctypes.c_int64)() == 2;
        assert get_func(eng, "entry_second", ctypes.c_double)() == 2.5;
    }

    def check_a_slice_of_an_unpacked_tuple_in_an_entry_global {
        eng = _engine();
        assert get_func(eng, "entry_head_len", ctypes.c_int64)() == 1;
        assert get_func(eng, "entry_head", ctypes.c_double)() == 1.5;
        assert get_func(eng, "zeros_head_len", ctypes.c_int64)() == 1;
    }
    run_cases(
        [
            (
                "an unpacked tuple in an entry global keeps its length and elements",
                check_an_unpacked_tuple_in_an_entry_global_keeps_its_l
            ),
            (
                "a slice of an unpacked tuple in an entry global is not empty",
                check_a_slice_of_an_unpacked_tuple_in_an_entry_global
            )
        ]
    );
}


test "mixed int and float fields box into the variadic slot" {
    eng = _engine();
    assert get_func(eng, "mixed_sum", ctypes.c_double)() == 11.5;
}

test "an annotated variadic local holds every unpacked field, and related cases" {
    def check_an_annotated_variadic_local_holds_every_unpacked {
        eng = _engine();
        assert get_func(eng, "local_tail_len", ctypes.c_int64)() == 2;
    }

    def check_a_slice_of_a_none_narrowed_optional_string_still {
        eng = _engine();
        assert get_func(eng, "narrowed_str_tail", ctypes.c_int64)() == 3;
    }
    run_cases(
        [
            (
                "an annotated variadic local holds every unpacked field",
                check_an_annotated_variadic_local_holds_every_unpacked
            ),
            (
                "a slice of a None-narrowed optional string still lowers",
                check_a_slice_of_a_none_narrowed_optional_string_still
            )
        ]
    );
}


test "a fixed tuple slice is refused rather than read as an index" {
    path = os.path.join(FIXTURES, "tuple_slice_refusal.jac");
    prog = JacProgram();
    na_coverage_begin();
    try {
        prog.compile(file_path=path, options=CompileOptions(force_codespace='native'));
    } finally {
        coverage = na_coverage_end();
    }
    rec = coverage.get(os.path.realpath(path));
    seams = [str(s) for s in ((rec.get("seams") or []) if rec is not None else [])];
    owned = [
        s
        for s in seams
        if s.startswith("tail_of_three: ")
    ];
    assert len(owned) == 1 , str(seams);
    assert "slice" in owned[0] , owned[0];
}
