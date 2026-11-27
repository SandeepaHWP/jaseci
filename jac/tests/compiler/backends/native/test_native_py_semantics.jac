"""CPython-parity value-semantics tests for the native pathway (issue
#7320, Cluster 2 silent-wrong-value family).

Each fixture exercises an idiom that previously compiled clean on na but
returned a different value than CPython/sv, with results encoded into a
single i64 so a silent divergence fails an equality assert.
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

glob FIXTURES = os.path.join(
         TESTS_DIR, "compiler", "backends", "native", "fixtures"
     );

test "chained comparison: cases on py_chain_cmp.jac" {
    # --- 2a: chained comparisons lower every link, not just the first ---
    def check_chained_comparison_every_link_is_evaluated_and_a {
        (eng, _) = compile_native("py_chain_cmp.jac");

        get_func(eng, "jac_entry", None)();
        cases = get_func(eng, "chain_cases", ctypes.c_int64);
        result = cases();
        # a=0 (2<3<1), b=1, c=1, d=1, e=0, f=1, g=1
        assert result == 111011 , f"Expected 111011, got {result}";
    }

    def check_chained_comparison_middle_operand_evaluated_exac {
        (eng, _) = compile_native("py_chain_cmp.jac");

        get_func(eng, "jac_entry", None)();
        once = get_func(eng, "middle_evaluated_once", ctypes.c_int64);
        result = once();
        assert result == 11 , f"Expected 11 (true, one bump), got {result}";
    }

    def check_chained_comparison_three_link_chain_with_mixed_d {
        (eng, _) = compile_native("py_chain_cmp.jac");

        get_func(eng, "jac_entry", None)();
        chain = get_func(eng, "long_chain", ctypes.c_int64);
        result = chain();
        assert result == 1 , f"Expected 1 (1<2<3>2), got {result}";
    }
    run_cases(
        [
            (
                "chained comparison: every link is evaluated and ANDed",
                check_chained_comparison_every_link_is_evaluated_and_a
            ),
            (
                "chained comparison: middle operand evaluated exactly once",
                check_chained_comparison_middle_operand_evaluated_exac
            ),
            (
                "chained comparison: three-link chain with mixed directions",
                check_chained_comparison_three_link_chain_with_mixed_d
            )
        ]
    );
}


test "chained comparison: cases on py_chain_cmp_mixed.jac" {
    # --- #7593 item 2: membership/identity links in chains ---
    def check_chained_comparison_membership_links_lower_like_s {
        (eng, _) = compile_native("py_chain_cmp_mixed.jac");

        get_func(eng, "jac_entry", None)();
        cases = get_func(eng, "chain_in_cases", ctypes.c_int64);
        result = cases();
        assert result == 10111 , f"Expected 10111, got {result}";
    }

    def check_chained_comparison_identity_links_lower_like_sin {
        (eng, _) = compile_native("py_chain_cmp_mixed.jac");

        get_func(eng, "jac_entry", None)();
        cases = get_func(eng, "chain_is_cases", ctypes.c_int64);
        result = cases();
        assert result == 1001 , f"Expected 1001, got {result}";
    }

    def check_chained_comparison_membership_middle_operand_eva {
        (eng, _) = compile_native("py_chain_cmp_mixed.jac");

        get_func(eng, "jac_entry", None)();
        once = get_func(eng, "chain_middle_once", ctypes.c_int64);
        result = once();
        assert result == 11 , f"Expected 11 (true, one bump), got {result}";
    }
    run_cases(
        [
            (
                "chained comparison: membership links lower like single 'in'",
                check_chained_comparison_membership_links_lower_like_s
            ),
            (
                "chained comparison: identity links lower like single 'is'",
                check_chained_comparison_identity_links_lower_like_sin
            ),
            (
                "chained comparison: membership middle operand evaluated once",
                check_chained_comparison_membership_middle_operand_eva
            )
        ]
    );
}


test "bool ops: cases on py_bool_ops.jac" {
    # --- 2b: or/and yield the deciding operand value, not a truth bit ---
    def check_bool_ops_int_or_and_return_the_operand_value {
        (eng, _) = compile_native("py_bool_ops.jac");

        get_func(eng, "jac_entry", None)();
        ops = get_func(eng, "bool_ops_int", ctypes.c_int64);
        result = ops();
        # 5 or 7 = 5; 0 or 7 = 7; 3 and 9 = 9; 0 and 9 = 0
        assert result == 5790 , f"Expected 5790, got {result}";
    }

    def check_bool_ops_str_or_picks_the_fallback_for_empty_str {
        (eng, _) = compile_native("py_bool_ops.jac");

        get_func(eng, "jac_entry", None)();
        ops = get_func(eng, "bool_ops_str", ctypes.c_int64);
        result = ops();
        assert result == 1111 , f"Expected 1111 (all four str cases), got {result}";
    }

    def check_bool_ops_rhs_is_not_evaluated_when_lhs_decides {
        (eng, _) = compile_native("py_bool_ops.jac");

        get_func(eng, "jac_entry", None)();
        ops = get_func(eng, "bool_ops_short_circuit", ctypes.c_int64);
        result = ops();
        # v=5, w=0, zero bump() calls
        assert result == 500 , f"Expected 500, got {result}";
    }
    run_cases(
        [
            (
                "bool ops: int or/and return the operand value",
                check_bool_ops_int_or_and_return_the_operand_value
            ),
            (
                "bool ops: str or picks the fallback for empty strings",
                check_bool_ops_str_or_picks_the_fallback_for_empty_str
            ),
            (
                "bool ops: rhs is not evaluated when lhs decides",
                check_bool_ops_rhs_is_not_evaluated_when_lhs_decides
            )
        ]
    );
}


test "membership: str cases on py_membership.jac" {
    # --- 2c: membership compares string values, not pointer identity ---
    def check_membership_str_in_list_str_compares_values {
        (eng, _) = compile_native("py_membership.jac");

        get_func(eng, "jac_entry", None)();
        mem = get_func(eng, "str_list_membership", ctypes.c_int64);
        result = mem();
        # beta found, heap needle found, delta absent, not-in true, 2 in nums
        assert result == 11011 , f"Expected 11011, got {result}";
    }

    def check_membership_str_in_d_keys_compares_values {
        (eng, _) = compile_native("py_membership.jac");

        get_func(eng, "jac_entry", None)();
        mem = get_func(eng, "dict_keys_membership", ctypes.c_int64);
        result = mem();
        assert result == 110 , f"Expected 110, got {result}";
    }
    run_cases(
        [
            (
                "membership: str in list[str] compares values",
                check_membership_str_in_list_str_compares_values
            ),
            (
                "membership: str in d.keys() compares values",
                check_membership_str_in_d_keys_compares_values
            )
        ]
    );
}


test "sort kwargs: cases on py_sort_kwargs.jac" {
    # --- 2d: sort()/sorted() honor reverse= and key= ---
    def check_sort_kwargs_reverse_true_sorts_descending_in_pla {
        (eng, _) = compile_native("py_sort_kwargs.jac");

        get_func(eng, "jac_entry", None)();
        srt = get_func(eng, "sort_reverse", ctypes.c_int64);
        result = srt();
        assert result == 321 , f"Expected 321, got {result}";
    }

    def check_sort_kwargs_sorted_reverse_true_returns_a_descen {
        (eng, _) = compile_native("py_sort_kwargs.jac");

        get_func(eng, "jac_entry", None)();
        srt = get_func(eng, "sorted_reverse_copies", ctypes.c_int64);
        result = srt();
        # b untouched (3xxx), c descending 321
        assert result == 3321 , f"Expected 3321, got {result}";
    }

    def check_sort_kwargs_key_len_orders_by_key_not_by_element {
        (eng, _) = compile_native("py_sort_kwargs.jac");

        get_func(eng, "jac_entry", None)();
        srt = get_func(eng, "sort_key_len", ctypes.c_int64);
        result = srt();
        assert result == 111 , f"Expected 111 (a, dd, ccc), got {result}";
    }

    def check_sort_kwargs_key_and_reverse_compose {
        (eng, _) = compile_native("py_sort_kwargs.jac");

        get_func(eng, "jac_entry", None)();
        srt = get_func(eng, "sort_key_and_reverse", ctypes.c_int64);
        result = srt();
        # keys mod 10: 5->5, 12->2, 3->3; descending keys: 5, 3, 12
        assert result == 50312 , f"Expected 50312, got {result}";
    }
    run_cases(
        [
            (
                "sort kwargs: reverse=True sorts descending in place",
                check_sort_kwargs_reverse_true_sorts_descending_in_pla
            ),
            (
                "sort kwargs: sorted(reverse=True) returns a descending copy",
                check_sort_kwargs_sorted_reverse_true_returns_a_descen
            ),
            (
                "sort kwargs: key=len orders by key not by element",
                check_sort_kwargs_key_len_orders_by_key_not_by_element
            ),
            (
                "sort kwargs: key= and reverse= compose",
                check_sort_kwargs_key_and_reverse_compose
            )
        ]
    );
}


test "py_dropped_args.jac cases" {
    # --- dropped-argument family: range step, find start, pow modulus ---
    def check_range_honors_a_positive_and_negative_step_in_for {
        (eng, _) = compile_native("py_dropped_args.jac");

        get_func(eng, "jac_entry", None)();
        fn = get_func(eng, "range_step_sum", ctypes.c_int64);
        result = fn();
        # 0,3,6,9 -> 369; 5,3,1 -> 531
        assert result == 369531 , f"Expected 369531, got {result}";
    }

    def check_str_search_methods_honor_start_and_end {
        (eng, _) = compile_native("py_dropped_args.jac");

        get_func(eng, "jac_entry", None)();
        s = "ab/> cd <img x />";
        cases = [
            # find('b', 2)=4, find('b')=1, find('z', 1)=-1
            ("find_with_start", 411),
            ("find_bounds_index_from", s.index("/>", 5)),
            ("find_bounds_find_end", s.find("/>", 0, 3)),
            ("find_bounds_rfind_window", s.rfind("/>", 0, 6)),
            ("find_bounds_rindex_window", s.rindex("/>", 0, 6)),
            ("find_bounds_rfind_from", s.rfind("/>", 5)),
            ("find_bounds_count_from", s.count("/>", 5)),
            ("find_bounds_count_window", s.count("/>", 0, 6)),
            ("find_bounds_negative", s.find("img", -9, -2)),
            ("find_bounds_empty_past_end", s.find("", 50)),
            ("find_bounds_empty_start_after_end", s.find("", 6, 2)),
            ("find_bounds_rfind_empty_window", s.rfind("", 0, 4)),
            ("find_bounds_count_empty_window", s.count("", 0, 4)),
            # s.index("/>", 0, 3) raises ValueError; the fixture maps that to -7
            ("find_bounds_index_miss", -7)
        ];
        for (name, expected) in cases {
            got = get_func(eng, name, ctypes.c_int64)();
            assert got == expected , f"{name}: native {got}, CPython {expected}";
        }
    }

    def check_pow_honors_the_modulus_argument {
        (eng, _) = compile_native("py_dropped_args.jac");

        get_func(eng, "jac_entry", None)();
        fn = get_func(eng, "pow_with_mod", ctypes.c_int64);
        result = fn();
        # pow(3,4,5)=1, pow(2,10,1000)=24
        assert result == 1024 , f"Expected 1024, got {result}";
    }

    def check_range_with_zero_step_raises_valueerror_instead_o {
        (eng, _) = compile_native("py_dropped_args.jac");

        get_func(eng, "jac_entry", None)();
        fn = get_func(eng, "range_zero_step_raises", ctypes.c_int64);
        result = fn();
        assert result == 1 , f"Expected 1 (caught ValueError), got {result}";
    }

    def check_pow_with_zero_modulus_raises_valueerror_instead {
        (eng, _) = compile_native("py_dropped_args.jac");

        get_func(eng, "jac_entry", None)();
        fn = get_func(eng, "pow_zero_mod_raises", ctypes.c_int64);
        result = fn();
        assert result == 1 , f"Expected 1 (caught ValueError), got {result}";
    }
    run_cases(
        [
            (
                "range honors a positive and negative step in for headers",
                check_range_honors_a_positive_and_negative_step_in_for
            ),
            (
                "str search methods honor start and end",
                check_str_search_methods_honor_start_and_end
            ),
            ("pow honors the modulus argument", check_pow_honors_the_modulus_argument),
            (
                "range with zero step raises ValueError instead of looping",
                check_range_with_zero_step_raises_valueerror_instead_o
            ),
            (
                "pow with zero modulus raises ValueError instead of trapping",
                check_pow_with_zero_modulus_raises_valueerror_instead
            )
        ]
    );
}


test "py_fstring.jac cases" {
    # --- 2f: f-strings size their buffer and honor format specs ---
    def check_fstring_output_larger_than_1024_bytes_is_not_tru {
        (eng, _) = compile_native("py_fstring.jac");

        get_func(eng, "jac_entry", None)();
        fn = get_func(eng, "fstring_long", ctypes.c_int64);
        result = fn();
        assert result == 1204 , f"Expected 1204, got {result}";
    }

    def check_fstring_numeric_and_string_format_specs_render_l {
        (eng, _) = compile_native("py_fstring.jac");

        get_func(eng, "jac_entry", None)();
        fn = get_func(eng, "fstring_specs", ctypes.c_int64);
        result = fn();
        # .2f, 04d, x, and >4/<4 alignment all correct
        assert result == 1111 , f"Expected 1111, got {result}";
    }

    def check_fstring_r_conversion_matches_cpython_repr {
        (eng, _) = compile_native("py_fstring.jac");

        get_func(eng, "jac_entry", None)();
        fn = get_func(eng, "fstring_repr", ctypes.c_int64);
        result = fn();
        # int, float, bool, quote-switching str repr, and repr-then-pad ordering
        assert result == 11111 , f"Expected 11111, got {result}";
    }

    def check_fstring_dynamic_format_specs_render_like_cpython {
        (eng, _) = compile_native("py_fstring.jac");

        get_func(eng, "jac_entry", None)();
        fn = get_func(eng, "fstring_dynspec", ctypes.c_int64);
        result = fn();
        # {w}.{p}f, {w}x, 0{w}d, and *^{w} all correct
        assert result == 1111 , f"Expected 1111, got {result}";
    }

    def check_fstring_invalid_dynamic_spec_raises_valueerror {
        (eng, _) = compile_native("py_fstring.jac");

        get_func(eng, "jac_entry", None)();
        fn = get_func(eng, "fstring_dynspec_invalid", ctypes.c_int64);
        result = fn();
        assert result == 1 , f"Expected 1 (ValueError raised), got {result}";
    }
    run_cases(
        [
            (
                "fstring: output larger than 1024 bytes is not truncated",
                check_fstring_output_larger_than_1024_bytes_is_not_tru
            ),
            (
                "fstring: numeric and string format specs render like CPython",
                check_fstring_numeric_and_string_format_specs_render_l
            ),
            (
                "fstring: !r conversion matches CPython repr",
                check_fstring_r_conversion_matches_cpython_repr
            ),
            (
                "fstring: dynamic format specs render like CPython",
                check_fstring_dynamic_format_specs_render_like_cpython
            ),
            (
                "fstring: invalid dynamic spec raises ValueError",
                check_fstring_invalid_dynamic_spec_raises_valueerror
            )
        ]
    );
}


test "py_subscript_aug.jac cases" {
    # --- subscript aug-assign lowers read-modify-write, not an RHS store ---
    def check_subscript_aug_list_int_arithmetic_ops_read_modif {
        (eng, _) = compile_native("py_subscript_aug.jac");

        get_func(eng, "jac_entry", None)();
        fn = get_func(eng, "list_int_ops", ctypes.c_int64);
        result = fn();
        # 7 +=3 ->10, -=2 ->8, *=3 ->24, //=5 ->4, %=3 ->1
        assert result == 100824041 , f"Expected 100824041, got {result}";
    }

    def check_subscript_aug_list_int_bitwise_shift_pow_ops_app {
        (eng, _) = compile_native("py_subscript_aug.jac");

        get_func(eng, "jac_entry", None)();
        fn = get_func(eng, "list_int_bitops", ctypes.c_int64);
        result = fn();
        # 17 <<=3 ->136, >>=1 ->68, |=3 ->71, ^=5 ->66, &=31 ->2, **=5 ->32
        assert result == 136068071066002032 , f"Expected 136068071066002032, got {result}";
    }

    def check_subscript_aug_list_float_ops_apply_incl_floored {
        (eng, _) = compile_native("py_subscript_aug.jac");

        get_func(eng, "jac_entry", None)();
        fn = get_func(eng, "list_float_ops", ctypes.c_int64);
        result = fn();
        # 8.0 +=1.5 ->9.5, -=0.25 ->9.25, *=2 ->18.5, //=4 ->4.0 (floored), /=5 ->0.8
        assert result == 95092501850408 , f"Expected 95092501850408, got {result}";
    }

    def check_subscript_aug_dict_int_and_float_values_read_mod {
        (eng, _) = compile_native("py_subscript_aug.jac");

        get_func(eng, "jac_entry", None)();
        fn = get_func(eng, "dict_ops", ctypes.c_int64);
        result = fn();
        # d[3]: 10 +=5 ->15, -=7 ->8, *=4 ->32; s["k"]: 1.5 *=4 ->6.0
        assert result == 15083206 , f"Expected 15083206, got {result}";
    }

    def check_field_aug_float_floors_and_int_applies {
        (eng, _) = compile_native("py_subscript_aug.jac");

        get_func(eng, "jac_entry", None)();
        fn = get_func(eng, "field_scalar_ops", ctypes.c_int64);
        result = fn();
        # h.f: 7.0 //=2 ->3.0, *=2.5 ->7.5; h.n: 20 %=6 ->2
        assert result == 307502 , f"Expected 307502, got {result}";
    }

    def check_subscript_aug_index_expression_evaluated_exactly {
        (eng, _) = compile_native("py_subscript_aug.jac");

        get_func(eng, "jac_entry", None)();
        fn = get_func(eng, "index_evaluated_once", ctypes.c_int64);
        result = fn();
        # m[bump_idx(1)] += 7 -> m[1]==27 with one bump
        assert result == 271 , f"Expected 271, got {result}";
    }
    run_cases(
        [
            (
                "subscript aug: list int arithmetic ops read-modify-write",
                check_subscript_aug_list_int_arithmetic_ops_read_modif
            ),
            (
                "subscript aug: list int bitwise/shift/pow ops apply",
                check_subscript_aug_list_int_bitwise_shift_pow_ops_app
            ),
            (
                "subscript aug: list float ops apply incl. floored //=",
                check_subscript_aug_list_float_ops_apply_incl_floored
            ),
            (
                "subscript aug: dict int and float values read-modify-write",
                check_subscript_aug_dict_int_and_float_values_read_mod
            ),
            (
                "field aug: float //= floors and int %= applies",
                check_field_aug_float_floors_and_int_applies
            ),
            (
                "subscript aug: index expression evaluated exactly once",
                check_subscript_aug_index_expression_evaluated_exactly
            )
        ]
    );
}


test "py_str_identity_index.jac cases" {
    # --- str() identity ownership and negative string indexing ---
    def check_str_of_an_owned_temp_keeps_the_value_alive {
        (eng, _) = compile_native("py_str_identity_index.jac");

        get_func(eng, "jac_entry", None)();
        fn = get_func(eng, "str_of_owned_temp", ctypes.c_int64);
        result = fn();
        assert result == 2 , f"Expected 2, got {result}";
    }

    def check_test_slug_shape_str_of_joined_chars_survives_the {
        (eng, _) = compile_native("py_str_identity_index.jac");

        get_func(eng, "jac_entry", None)();
        fn = get_func(eng, "slug_of_desc", ctypes.c_int64);
        result = fn();
        # ok=1 (slug == "canary_t"), len=8
        assert result == 18 , f"Expected 18, got {result}";
    }

    def check_string_subscript_wraps_negative_indices {
        (eng, _) = compile_native("py_str_identity_index.jac");

        get_func(eng, "jac_entry", None)();
        fn = get_func(eng, "neg_index_reads", ctypes.c_int64);
        result = fn();
        # v[-1]==v[0], v[-1]=='"', v[-2]=='t', "abc"[-3]=='a'
        assert result == 1111 , f"Expected 1111, got {result}";
    }

    def check_string_subscript_raises_indexerror_below_range {
        (eng, _) = compile_native("py_str_identity_index.jac");

        get_func(eng, "jac_entry", None)();
        fn = get_func(eng, "neg_index_oob", ctypes.c_int64);
        result = fn();
        assert result == 1 , f"Expected 1, got {result}";
    }

    def check_string_subscript_raises_indexerror_above_range {
        (eng, _) = compile_native("py_str_identity_index.jac");

        get_func(eng, "jac_entry", None)();
        fn = get_func(eng, "pos_index_oob", ctypes.c_int64);
        result = fn();
        assert result == 1 , f"Expected 1, got {result}";
    }
    run_cases(
        [
            (
                "str() of an owned temp keeps the value alive",
                check_str_of_an_owned_temp_keeps_the_value_alive
            ),
            (
                "test-slug shape: str of joined chars survives the arg release",
                check_test_slug_shape_str_of_joined_chars_survives_the
            ),
            (
                "string subscript wraps negative indices",
                check_string_subscript_wraps_negative_indices
            ),
            (
                "string subscript raises IndexError below range",
                check_string_subscript_raises_indexerror_below_range
            ),
            (
                "string subscript raises IndexError above range",
                check_string_subscript_raises_indexerror_above_range
            )
        ]
    );
}
