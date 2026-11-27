"""End-to-end tests for the native iterator protocol (#6403).

Covers lazy adapters (map/filter/enumerate/zip) driven through for-loops,
composition, break/empty edge cases, and first-class iter()/next() values.
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

test "iter_protocol.jac cases" {
    def check_list_consumes_the_remaining_iterator_values_with {
        (eng, _) = compile_native("iter_protocol.jac");

        f = get_func(eng, "iterator_list_values", ctypes.c_int64);
        assert f() == 25;
    }

    def check_returned_iterators_own_their_local_source_collec {
        (eng, _) = compile_native("iter_protocol.jac");

        f = get_func(eng, "returned_iterator_values", ctypes.c_int64);
        drops = get_func(eng, "iterator_item_drop_count", ctypes.c_int64);
        before = drops();
        assert f() == 268;
        assert drops() - before == 2;
    }

    # --- first-class iter() / next() (#6403 phase 2) ---
    # `it = iter(x); next(it)` and `for x in it` over a stored iterator value, now
    # that the native checker infers `iter(x) -> Iterator[T]` / `next(it) -> T`
    # through the same __iter__/__next__ machinery the for-loop uses.
    def check_iter_next_basic {
        (eng, _) = compile_native("iter_protocol.jac");

        f = get_func(eng, "iter_next_basic", ctypes.c_int64);
        assert f() == 57;
    }

    def check_iter_for_over_stored_iterator {
        (eng, _) = compile_native("iter_protocol.jac");

        f = get_func(eng, "for_over_iter", ctypes.c_int64);
        assert f() == 10;
    }

    def check_iter_str_iter_next {
        (eng, _) = compile_native("iter_protocol.jac");

        f = get_func(eng, "str_iter_next", ctypes.c_int64);
        assert f() == 2;
    }

    # next() past the end raises StopIteration (Python contract), caught here.
    def check_iter_next_exhausted_raises_stopiteration {
        (eng, _) = compile_native("iter_protocol.jac");

        f = get_func(eng, "next_exhausted", ctypes.c_int64);
        assert f() == 99;
    }

    # --- M1: first-class iter() over range / dict / set ---
    def check_iter_over_range {
        (eng, _) = compile_native("iter_protocol.jac");

        f = get_func(eng, "for_over_range_iter", ctypes.c_int64);
        assert f() == 10;
    }

    def check_iter_next_over_stepped_range {
        (eng, _) = compile_native("iter_protocol.jac");

        f = get_func(eng, "next_range", ctypes.c_int64);
        assert f() == 1013;
    }

    def check_iter_over_descending_range {
        (eng, _) = compile_native("iter_protocol.jac");

        f = get_func(eng, "for_over_range_desc", ctypes.c_int64);
        assert f() == 15;
    }

    def check_iter_over_dict_yields_keys {
        (eng, _) = compile_native("iter_protocol.jac");

        f = get_func(eng, "for_over_dict_iter", ctypes.c_int64);
        assert f() == 3;
    }

    def check_iter_over_set {
        (eng, _) = compile_native("iter_protocol.jac");

        f = get_func(eng, "for_over_set_iter", ctypes.c_int64);
        assert f() == 12;
    }

    # --- composition: adapter over a stored iterator ---
    def check_iter_map_over_stored_iterator {
        (eng, _) = compile_native("iter_protocol.jac");

        f = get_func(eng, "map_over_stored", ctypes.c_int64);
        assert f() == 12;
    }

    # --- #6403: iter() of a stored iterator must retain (no double-release UAF) ---
    # `iter(it)` returns the same JacIter the variable owns; the loop's owned
    # reference must carry its own +1 so the source's single +1 is not released
    # twice (loop end + scope exit).
    def check_iter_for_over_iter_of_stored_iterator {
        (eng, _) = compile_native("iter_protocol.jac");

        f = get_func(eng, "for_over_iter_of_stored", ctypes.c_int64);
        assert f() == 10;
    }

    def check_iter_assign_iter_of_stored_iterator {
        (eng, _) = compile_native("iter_protocol.jac");

        f = get_func(eng, "assign_iter_of_stored", ctypes.c_int64);
        assert f() == 10;
    }
    run_cases(
        [
            (
                "list consumes the remaining iterator values with their element types",
                check_list_consumes_the_remaining_iterator_values_with
            ),
            (
                "returned iterators own their local source collections",
                check_returned_iterators_own_their_local_source_collec
            ),
            ("iter next basic", check_iter_next_basic),
            ("iter for over stored iterator", check_iter_for_over_stored_iterator),
            ("iter str iter next", check_iter_str_iter_next),
            (
                "iter next exhausted raises stopiteration",
                check_iter_next_exhausted_raises_stopiteration
            ),
            ("iter over range", check_iter_over_range),
            ("iter next over stepped range", check_iter_next_over_stepped_range),
            ("iter over descending range", check_iter_over_descending_range),
            ("iter over dict yields keys", check_iter_over_dict_yields_keys),
            ("iter over set", check_iter_over_set),
            ("iter map over stored iterator", check_iter_map_over_stored_iterator),
            (
                "iter for over iter of stored iterator",
                check_iter_for_over_iter_of_stored_iterator
            ),
            (
                "iter assign iter of stored iterator",
                check_iter_assign_iter_of_stored_iterator
            )
        ]
    );
}


test "iter_adapters.jac cases" {
    # --- map / filter ---
    def check_iter_map_sum {
        (eng, _) = compile_native("iter_adapters.jac");

        f = get_func(eng, "map_sum", ctypes.c_int64);
        assert f() == 20;
    }

    def check_iter_filter_sum {
        (eng, _) = compile_native("iter_adapters.jac");

        f = get_func(eng, "filter_sum", ctypes.c_int64);
        assert f() == 12;
    }

    def check_iter_filter_empty {
        (eng, _) = compile_native("iter_adapters.jac");

        f = get_func(eng, "filter_empty", ctypes.c_int64);
        assert f() == 0;
    }

    def check_iter_compose_map_over_filter {
        (eng, _) = compile_native("iter_adapters.jac");

        f = get_func(eng, "compose_sum", ctypes.c_int64);
        assert f() == 24;
    }

    def check_iter_map_with_break {
        (eng, _) = compile_native("iter_adapters.jac");

        f = get_func(eng, "map_break", ctypes.c_int64);
        assert f() == 6;
    }

    # --- enumerate / zip (tuple unpack) ---
    def check_iter_enumerate_sum {
        (eng, _) = compile_native("iter_adapters.jac");

        f = get_func(eng, "enum_sum", ctypes.c_int64);
        assert f() == 360;
    }

    def check_iter_zip_sum {
        (eng, _) = compile_native("iter_adapters.jac");

        f = get_func(eng, "zip_sum", ctypes.c_int64);
        assert f() == 140;
    }

    def check_iter_zip_unequal_lengths {
        (eng, _) = compile_native("iter_adapters.jac");

        f = get_func(eng, "zip_unequal", ctypes.c_int64);
        assert f() == 50;
    }
    run_cases(
        [
            ("iter map sum", check_iter_map_sum),
            ("iter filter sum", check_iter_filter_sum),
            ("iter filter empty", check_iter_filter_empty),
            ("iter compose map over filter", check_iter_compose_map_over_filter),
            ("iter map with break", check_iter_map_with_break),
            ("iter enumerate sum", check_iter_enumerate_sum),
            ("iter zip sum", check_iter_zip_sum),
            ("iter zip unequal lengths", check_iter_zip_unequal_lengths)
        ]
    );
}


# --- #6403: iter()/next() are positional-only; the keyword form is rejected ---
# The checker must not type a keyword call (`next(it=...)`) that the backend
# cannot lower — it should fail at the type level like CPython does.
test "iter next keyword arg rejected" {
    prog = JacProgram();
    prog.compile(
        file_path=str(os.path.join(FIXTURES, "iter_kwarg_rejected.jac")),
        options=native_force_opts()
    );
    errs = [str(e) for e in prog.errors_had] if prog.errors_had else [];
    assert errs , "expected a type error for next(it=...)";
    assert any("No matching overload" in e for e in errs) , errs;
}

test "user iter cases on iter_user.jac" {
    # --- #6403 M2: user-defined __iter__/__next__ bridged into the protocol ---
    # A user `obj` implementing the iterator protocol drives for-loops, works with
    # first-class iter()/next(), composes under map/filter/enumerate, and crosses
    # function boundaries — its `__next__`'s StopIteration becomes the protocol's
    # i1-0 exhaustion flag.
    def check_user_iter_self_for_loop {
        (eng, _) = compile_native("iter_user.jac");

        f = get_func(eng, "user_self_for", ctypes.c_int64);
        assert f() == 10;
    }

    def check_user_iter_borrowed_var_for_loop {
        (eng, _) = compile_native("iter_user.jac");

        f = get_func(eng, "user_self_for_var", ctypes.c_int64);
        assert f() == 3;
    }

    def check_user_iter_separate_iterator_for_loop {
        (eng, _) = compile_native("iter_user.jac");

        f = get_func(eng, "user_separate_for", ctypes.c_int64);
        assert f() == 6;
    }

    def check_user_iter_first_class_iter_next {
        (eng, _) = compile_native("iter_user.jac");

        f = get_func(eng, "user_iter_next", ctypes.c_int64);
        assert f() == 1011;
    }

    def check_user_iter_under_map_adapter {
        (eng, _) = compile_native("iter_user.jac");

        f = get_func(eng, "user_map_compose", ctypes.c_int64);
        assert f() == 6;
    }

    def check_user_iter_break_mid_iteration {
        (eng, _) = compile_native("iter_user.jac");

        f = get_func(eng, "user_break", ctypes.c_int64);
        assert f() == 3;
    }

    def check_user_iter_crosses_function_boundary {
        (eng, _) = compile_native("iter_user.jac");

        f = get_func(eng, "user_cross_fn", ctypes.c_int64);
        assert f() == 10;
    }

    # A non-StopIteration error from __next__ must propagate, not end the loop.
    def check_user_iter_next_non_stopiteration_propagates {
        (eng, _) = compile_native("iter_user.jac");

        f = get_func(eng, "user_next_propagates", ctypes.c_int64);
        assert f() == 42;
    }

    # A subclass driving __iter__/__next__ inherited from its base.
    def check_user_iter_inherited_from_base {
        (eng, _) = compile_native("iter_user.jac");

        f = get_func(eng, "user_inherited_iter", ctypes.c_int64);
        assert f() == 6;
    }
    run_cases(
        [
            ("user iter self for-loop", check_user_iter_self_for_loop),
            ("user iter borrowed var for-loop", check_user_iter_borrowed_var_for_loop),
            (
                "user iter separate iterator for-loop",
                check_user_iter_separate_iterator_for_loop
            ),
            ("user iter first-class iter next", check_user_iter_first_class_iter_next),
            ("user iter under map adapter", check_user_iter_under_map_adapter),
            ("user iter break mid-iteration", check_user_iter_break_mid_iteration),
            (
                "user iter crosses function boundary",
                check_user_iter_crosses_function_boundary
            ),
            (
                "user iter next non-stopiteration propagates",
                check_user_iter_next_non_stopiteration_propagates
            ),
            ("user iter inherited from base", check_user_iter_inherited_from_base)
        ]
    );
}


test "iterator bindings retain borrowed objects across cleanup and reassignment" {
    (engine, _) = compile_native("iterator_object_ownership.jac");
    for name in [
        "enumerate_keeps_elements",
        "iter_keeps_elements",
        "zip_keeps_elements"
    ] {
        assert get_func(engine, name, ctypes.c_int64)() == 42;
    }
}
