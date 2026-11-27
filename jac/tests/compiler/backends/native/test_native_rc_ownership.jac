"""Refcount/ownership regression tests for the native pathway (issue #7320,
Cluster 1).

Two ownership invariants of the na calling convention are exercised end to
end through the JIT:

  - every def returns a +1 reference: returning a module glob (heap string
    or list cache) must retain it, or the caller's release frees the glob
    (items 1d/1e);
  - named locals own what they hold: for-loop tuple unpack must retain the
    borrowed tuple fields it binds, or scope exit / early return releases
    strings still owned by the list (items 1a/1b/1c residue);
  - containers own what they hold: a comprehension's result must carry +1
    per element, so the elements outlive the source and the locals the
    comprehension was built from (issue #8088).

Fixtures encode first-use/second-use results into a single i64 so a wrong
value (freed glob, corrupted list) fails the assert rather than relying on
what freed memory happens to contain.
"""

import ctypes;
import os;
import from tests.support {
    TESTS_DIR,
    get_func,
    names_function,
    native_address,
    compile_native_ir,
    source_spelled,
    run_cases
}
import jaclang;
import from jaclang.compiler.driver.compile_options { CompileOptions }
import from jaclang.compiler.driver.program { JacProgram }

import jaclang.compiler.frontend.unitree as uni;
import from jaclang.compiler.backends.native.llvm.binding { ExecutionEngine }

glob FIXTURES = os.path.join(
         TESTS_DIR, "compiler", "backends", "native", "fixtures"
     );

"""Slice one function's textual IR out of the module dump."""
def fn_ir(ir: uni.Module, name: str) -> str {
    out: list[str] = [];
    inside = False;
    for ln in source_spelled(str(ir.gen.llvm_ir)).split("\n") {
        if not inside and ln.startswith("define") and names_function(ln, name) {
            inside = True;
        }
        if inside {
            out.append(ln);
            if ln == "}" {
                break;
            }
        }
    }
    assert out , f"No IR found for function '{name}'";
    return "\n".join(out);
}

# --- Returning module globs must hand the caller a +1 reference (1d/1e) ---
"""Compile a .jac fixture and return the JIT engine."""
def compile_native(
    fixture: str, gc_mode: str | None = None
) -> tuple[ExecutionEngine, uni.Module] {
    prog = JacProgram();
    opts = CompileOptions(
        force_codespace='native',
        na_gc_mode=(gc_mode if gc_mode is not None else "cycles")
    );
    ir = prog.compile(file_path=str(os.path.join(FIXTURES, fixture)), options=opts);
    errors = [str(e) for e in prog.errors_had] if prog.errors_had else [];
    assert not prog.errors_had , f"Compilation errors in {fixture}: {errors}";
    eng = ir.gen.native_engine;
    assert isinstance(eng, ExecutionEngine) , f"No native engine produced for {fixture}";
    return (eng, ir);
}

test "glob return: cases on rc_glob_return.jac" {
    def check_glob_return_list_cache_survives_a_for_loop_over {
        (eng, _) = compile_native("rc_glob_return.jac");

        get_func(eng, "jac_entry", None)();
        scan_twice = get_func(eng, "scan_twice", ctypes.c_int64);
        result = scan_twice();
        assert result == 13013 , f"Expected 13013 (13 per scan), got {result}";
    }

    def check_glob_return_heap_glob_string_survives_repeated_a {
        (eng, _) = compile_native("rc_glob_return.jac");

        get_func(eng, "jac_entry", None)();
        name_len_twice = get_func(eng, "name_len_twice", ctypes.c_int64);
        result = name_len_twice();
        assert result == 6006 , f"Expected 6006 (len('jactui') per read), got {result}";
    }

    def check_glob_return_accessor_called_inline_inside_len_tw {
        (eng, _) = compile_native("rc_glob_return.jac");

        get_func(eng, "jac_entry", None)();
        defs_len_inline = get_func(eng, "defs_len_inline", ctypes.c_int64);
        result = defs_len_inline();
        assert result == 3003 , f"Expected 3003 (3 cmds per len), got {result}";
    }
    run_cases(
        [
            (
                "glob return: list cache survives a for-loop over the accessor call",
                check_glob_return_list_cache_survives_a_for_loop_over
            ),
            (
                "glob return: heap glob string survives repeated accessor calls",
                check_glob_return_heap_glob_string_survives_repeated_a
            ),
            (
                "glob return: accessor called inline inside len() twice",
                check_glob_return_accessor_called_inline_inside_len_tw
            )
        ]
    );
}


test "tuple unpack: cases on rc_tuple_unpack.jac" {
    # --- Tuple unpack must retain the borrowed fields it binds (1a/1b/1c) ---
    def check_tuple_unpack_second_join_over_the_same_list_is_i {
        (eng, _) = compile_native("rc_tuple_unpack.jac");

        get_func(eng, "jac_entry", None)();
        join_twice = get_func(eng, "join_twice", ctypes.c_int64);
        result = join_twice();
        assert result == 11 , f"Expected 11 (both joins match), got {result}";
    }

    def check_tuple_unpack_early_return_of_an_unpack_bound_loc {
        (eng, _) = compile_native("rc_tuple_unpack.jac");

        get_func(eng, "jac_entry", None)();
        early_ret = get_func(eng, "early_return_keeps_list", ctypes.c_int64);
        result = early_ret();
        assert result == 11 , f"Expected 11 (value and rejoin both ok), got {result}";
    }
    run_cases(
        [
            (
                "tuple unpack: second join over the same list is intact",
                check_tuple_unpack_second_join_over_the_same_list_is_i
            ),
            (
                "tuple unpack: early return of an unpack-bound local keeps the list",
                check_tuple_unpack_early_return_of_an_unpack_bound_loc
            )
        ]
    );
}


# --- Param names must stay per-function codegen state (issue #7466, 1/2) ---
test "param shadow: other fn's param names add no retain-on-return" {
    # `push(s, v)` is never called; its param `v` must not make `make_vec`'s
    # `return v` path treat the fresh local as a borrowed param and retain it
    # (rc=2 at the caller -> every returned Vec leaks).
    (eng, _) = compile_native("rc_param_shadow_return.jac");
    ir = compile_native_ir("rc_param_shadow_return.jac");
    body = fn_ir(ir, "make_vec");
    n = body.count('call void @"__rc_retain"');
    assert n == 0 , f"make_vec should return its owned local with no retain, found {n}";
    sum_first = get_func(eng, "sum_first", ctypes.c_int64, ctypes.c_int64);
    result = sum_first(3);
    assert result == 3 , f"Expected 3 (0.5 * 2 per round), got {result}";
}

test "param shadow: loop-exit cleanup still releases same-named locals" {
    # `use2(a: &Box, b: &Box)`'s param names match `churn`'s two fresh loop
    # locals; the loop-exit (iter_end) cleanup must still release both or the
    # final iteration's Boxes are never freed.
    (eng, _) = compile_native("rc_param_shadow_looptail.jac");
    ir = compile_native_ir("rc_param_shadow_looptail.jac");
    body = fn_ir(ir, "churn");
    assert "iter.cleanup.a" in body , "loop-exit cleanup for local 'a' was suppressed";
    assert "iter.cleanup.b" in body , "loop-exit cleanup for local 'b' was suppressed";
    churn = get_func(eng, "churn", ctypes.c_int64, ctypes.c_int64);
    result = churn(10);
    assert result == 100 , f"Expected 100, got {result}";
}

test "heap-element container compiles and runs under cases" {
    # --- Heap-element containers under non-default gc modes (issue #7466, 3) ---
    def check_heap_element_container_compiles_and_runs_under_m {
        # The list[str] element-release helper used to re-enter _emit_rc_helpers
        # (its guard checked a cycles-only global) and redefine __rc_debug:
        # DuplicatedNameError ICE under rc, fine under the default cycles mode.
        (eng, _) = compile_native("rc_heap_container.jac", gc_mode="rc");
        count_strs = get_func(eng, "count_strs", ctypes.c_int64);
        result = count_strs();
        assert result == 2 , f"Expected 2, got {result}";
    }

    def check_heap_element_container_compiles_and_runs_under_p {
        (eng, _) = compile_native("rc_heap_container.jac", gc_mode="none");
        count_strs = get_func(eng, "count_strs", ctypes.c_int64);
        result = count_strs();
        assert result == 2 , f"Expected 2, got {result}";
    }
    run_cases(
        [
            (
                "heap-element container compiles and runs under --memory rc",
                check_heap_element_container_compiles_and_runs_under_m
            ),
            (
                "heap-element container compiles and runs under plain --memory nogc",
                check_heap_element_container_compiles_and_runs_under_p
            )
        ]
    );
}


test "import sys compiles under --memory rc (argv list is a heap container)" {
    (eng, _) = compile_native("rc_import_sys.jac", gc_mode="rc");
    addr = native_address(eng, "argc_minus_one");
    assert addr != 0 , "argc_minus_one not emitted";
}

# --- def drop parity across gc modes (issue #7466, 4) ---
"""Run the drop fixture and assert the hook fired once per destroyed Res."""
def check_drop_parity(gc_mode: str | None) {
    (eng, _) = compile_native("rc_drop_hook.jac", gc_mode=gc_mode);
    ir = compile_native_ir(
        "rc_drop_hook.jac",
        options=CompileOptions(force_codespace="native", na_gc_mode=gc_mode or "cycles")
    );
    body = fn_ir(ir, "__rc_release_Res");
    assert 'call' in body and 'Res.drop' in body , "managed release fn does not invoke the drop hook";
    run_drops = get_func(eng, "run_drops", ctypes.c_int64);
    drop_count = get_func(eng, "drop_count", ctypes.c_int64);
    last_dropped = get_func(eng, "last_dropped", ctypes.c_int64);
    before = drop_count();
    total = run_drops();
    assert total == 18 , f"Expected 18 (5+6+7), got {total}";
    fired = drop_count() - before;
    assert fired == 3 , f"drop should fire once per Res (3), fired {fired}";
    last = last_dropped();
    assert last == 7 , f"last drop should see tag=7, got {last}";
}

test "drop hook fires on rc release (--memory rc)" {
    check_drop_parity("rc");
}

test "drop hook fires under the default cycles collector" {
    check_drop_parity(None);
}

# --- Tuple unpack across an optional store (PR #7982) ---
"""Call one fixture fn and return (result, drops it caused)."""
def call_counting_drops(eng: any, name: str, a: int, b: int) -> tuple[int, int] {
    fn = get_func(eng, name, ctypes.c_int64, ctypes.c_int64, ctypes.c_int64);
    drops = get_func(eng, "drop_count", ctypes.c_int64);
    before = drops();
    value = fn(a, b);
    return (value, drops() - before);
}

test "tuple unpack cases on rc_tuple_unpack_optional.jac" {
    def check_tuple_unpack_into_an_optional_slot_destroys_each {
        (eng, _) = compile_native("rc_tuple_unpack_optional.jac");

        (value, drops) = call_counting_drops(eng, "unpack_into_optional", 3, 4);
        assert value == 34 , f"Expected 34, got {value}";
        assert drops == 2 , (
            f"2 allocations must produce 2 drops, got {drops} "
            f"(0 means the box abandoned its fields, more than 2 that the bind "
            f"skipped its retain and each payload was released twice)"
        );
    }

    def check_tuple_unpack_from_an_optional_element_costs_no_m {
        (eng, _) = compile_native("rc_tuple_unpack_optional.jac");

        (opt_value, opt_drops) = call_counting_drops(
            eng, "unpack_optional_into_plain", 3, 4
        );
        (plain_value, plain_drops) = call_counting_drops(
            eng, "unpack_plain_into_plain", 3, 4
        );
        assert opt_value == 34 , f"Expected 34 from the optional unpack, got {opt_value}";
        assert plain_value == 34 , f"Expected 34 from the plain unpack, got {plain_value}";
        assert opt_drops == plain_drops , (
            f"optional-element unpack dropped {opt_drops} but the identical "
            f"non-optional shape dropped {plain_drops}; the optional coercion "
            f"must not change ownership accounting"
        );
    }
    run_cases(
        [
            (
                "tuple unpack into an optional slot destroys each object exactly once",
                check_tuple_unpack_into_an_optional_slot_destroys_each
            ),
            (
                "tuple unpack from an optional element costs no more than the plain one",
                check_tuple_unpack_from_an_optional_element_costs_no_m
            )
        ]
    );
}


# --- Comprehension elements are owned by their container (issue #8088) ---
"""Call one fixture builder+reader and return the i64 it encodes."""
def call_elem_fn(eng: any, name: str, n: int) -> int {
    fn = get_func(eng, name, ctypes.c_int64, ctypes.c_int64);
    return fn(n);
}

test "rc_container_elem_ownership.jac cases" {
    def check_list_comprehension_owns_elements_a_borrow_return {
        (eng, _) = compile_native("rc_container_elem_ownership.jac");

        assert call_elem_fn(eng, "borrow_elem_sum", 4) == 10 , (
            "elements of the returned comprehension did not survive their source"
        );
        assert call_elem_fn(eng, "borrow_elem_parent_sum", 4) == 400 , (
            "the owner each element points at did not survive the builder"
        );
        # mid * 1000000 + after * 1000 + total: nothing may be destroyed while the
        # list is alive, and releasing it must destroy the 4 nodes plus the owner.
        assert call_elem_fn(eng, "borrow_elem_drops", 4) == 5010 , (
            "expected 0 destructions during the build, 5 on release and a tag sum "
            "of 10"
        );
    }

    def check_list_comprehension_does_not_double_own_a_fresh_e {
        (eng, _) = compile_native("rc_container_elem_ownership.jac");

        assert call_elem_fn(eng, "fresh_elem_sum", 4) == 50;
        assert call_elem_fn(eng, "fresh_elem_drops", 4) == 4008050 , (
            "a fresh element expression must net exactly one reference"
        );
    }

    def check_list_comprehension_owns_a_bare_loop_variable_ele {
        (eng, _) = compile_native("rc_container_elem_ownership.jac");

        assert call_elem_fn(eng, "alias_elem_sum", 4) == 10;
        assert call_elem_fn(eng, "alias_elem_drops", 4) == 4010 , (
            "aliasing the source's elements must still take a reference each"
        );
    }

    def check_list_comprehension_owns_heap_string_elements {
        (eng, _) = compile_native("rc_container_elem_ownership.jac");

        assert call_elem_fn(eng, "label_match_count", 4) == 4 , (
            "string elements did not survive the source they were borrowed from"
        );
    }

    def check_dict_comprehension_owns_values_a_borrow_returnin {
        (eng, _) = compile_native("rc_container_elem_ownership.jac");

        assert call_elem_fn(eng, "dict_elem_sum", 4) == 10;
        assert call_elem_fn(eng, "dict_elem_drops", 4) == 5010 , (
            "dict values must gain a reference of the dict's own"
        );
    }

    def check_set_comprehension_owns_elements_a_borrow_returni {
        (eng, _) = compile_native("rc_container_elem_ownership.jac");

        assert call_elem_fn(eng, "set_elem_drops", 4) == 4 , (
            "set elements were destroyed while the set still held them"
        );
    }

    def check_nested_comprehension_inner_lists_own_their_eleme {
        (eng, _) = compile_native("rc_container_elem_ownership.jac");

        assert call_elem_fn(eng, "nested_elem_drops", 4) == 40 , (
            "expected no destructions during the build and a tag sum of 40"
        );
    }

    def check_comprehension_over_a_borrowed_collection_leaves {
        (eng, _) = compile_native("rc_container_elem_ownership.jac");

        assert call_elem_fn(eng, "param_elem_sum", 4) == 20;
        assert call_elem_fn(eng, "param_elem_drops", 4) == 10 , (
            "releasing the built list destroyed elements the borrowed source held"
        );
    }

    def check_returning_the_receiver_hands_the_caller_a_refere {
        (eng, _) = compile_native("rc_container_elem_ownership.jac");

        assert call_elem_fn(eng, "self_ref_direct", 4) == 1100 , (
            "the returned receiver did not outlive the list that held it"
        );
    }

    def check_returning_an_element_indexed_through_the_receive {
        (eng, _) = compile_native("rc_container_elem_ownership.jac");

        assert call_elem_fn(eng, "kid_elem_return", 4) == 1 , (
            "an object element returned out of a field slot was released early"
        );
        assert call_elem_fn(eng, "kid_label_return", 4) == 2 , (
            "a string element returned out of a field slot was released early"
        );
    }
    run_cases(
        [
            (
                "list comprehension owns elements a borrow-returning call produced",
                check_list_comprehension_owns_elements_a_borrow_return
            ),
            (
                "list comprehension does not double-own a fresh element",
                check_list_comprehension_does_not_double_own_a_fresh_e
            ),
            (
                "list comprehension owns a bare loop variable element",
                check_list_comprehension_owns_a_bare_loop_variable_ele
            ),
            (
                "list comprehension owns heap string elements",
                check_list_comprehension_owns_heap_string_elements
            ),
            (
                "dict comprehension owns values a borrow-returning call produced",
                check_dict_comprehension_owns_values_a_borrow_returnin
            ),
            (
                "set comprehension owns elements a borrow-returning call produced",
                check_set_comprehension_owns_elements_a_borrow_returni
            ),
            (
                "nested comprehension: inner lists own their elements too",
                check_nested_comprehension_inner_lists_own_their_eleme
            ),
            (
                "comprehension over a borrowed collection leaves it intact",
                check_comprehension_over_a_borrowed_collection_leaves
            ),
            (
                "returning the receiver hands the caller a reference of its own",
                check_returning_the_receiver_hands_the_caller_a_refere
            ),
            (
                "returning an element indexed through the receiver still retains it",
                check_returning_an_element_indexed_through_the_receive
            )
        ]
    );
}
