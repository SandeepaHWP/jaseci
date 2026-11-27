"""Differential identity over the everyday owned-code shapes of #8984.

Each fixture is an ordinary program written against the ownership surface. It
is built headerless (`nogc`), under plain reference counting, under the cycle
collector, and run on the Python backend, and every output must agree byte
for byte with the Python backend's. That agreement is the erasure contract of
the design: annotations never change behavior, and a zero-RC build behaves
exactly like a managed one. Drop hooks in the fixtures make lifetimes part of
the output, so a leak, a double drop, or a read of freed memory shows up as a
diff rather than luck.

ownbench's kernels are the other differential surface; these fixtures cover
the shapes those kernels do not: optional own-field moves, owned-parameter
drops, `pop()` on owned lists, subclass elements, borrow returns, generics.
"""

import os;
import from tests.support { TESTS_DIR, assert_native_identity, run_cases }

glob FIXTURES = os.path.join(
         TESTS_DIR, "compiler", "backends", "native", "fixtures", "nogc_identity"
     );

def _fixture(name: str) -> str {
    return os.path.join(FIXTURES, name);
}

test "cleanup tolerates an owned local whose branch was not entered" {
    out = assert_native_identity(_fixture("branch_cleanup.jac"));
    assert out.splitlines() == ["1", "drop 1", "2", "drop 2", "1", "drop 1"];
}

test "runtime errors propagate through Jac calls without an unwinder" {
    out = assert_native_identity(_fixture("runtime_errors.jac"));
    assert out.splitlines()
        == ["bounds caught", "bounds finalized", "assertion caught"];
}

test "finalizers run on returns, breaks and continues" {
    out = assert_native_identity(_fixture("finally_exits.jac"));
    assert out.splitlines()
        == ["inner", "outer", "7", "0", "1", "after loop", "after try"];
}

test "error propagation preserves pending errors and finalizes handlers" {
    out = assert_native_identity(_fixture("error_nested.jac"));
    assert out.splitlines()
        == [
            "temporary handled",
            "inner finally",
            "original handled",
            "handler finally",
            "replacement handled",
            "reraised"
        ];
}

test "a named own local moved into an optional own field is owned by the field, and related cases" {
    def check_a_named_own_local_moved_into_an_optional_own_fie {
        out = assert_native_identity(_fixture("optfield_move.jac"));
        assert out.splitlines()
            == [
                "a.next.v=2",
                "h.slot.v=3",
                "drop node 3",
                "drop node 1",
                "drop node 2",
                "done"
            ] , out;
    }

    def check_views_over_a_borrowed_list_never_own_its_element {
        out = assert_native_identity(_fixture("view_cursor.jac"));
        assert out.splitlines()
            == [
                "drop item 4",
                "drop item 3",
                "drop item 2",
                "drop item 1",
                "123406",
                "done"
            ] , out;
    }
    run_cases(
        [
            (
                "a named own local moved into an optional own field is owned by the field",
                check_a_named_own_local_moved_into_an_optional_own_fie
            ),
            (
                "views over a borrowed list never own its elements",
                check_views_over_a_borrowed_list_never_own_its_element
            )
        ]
    );
}

test "a named own local moved into an inline-flattened own field drops once, and related cases" {
    def check_a_named_own_local_moved_into_an_inline_flattened {
        out = assert_native_identity(_fixture("inline_field_move.jac"));
        assert out.splitlines()
            == ["drop node 0", "h.slot.v=2", "drop node 2", "done"] , out;
    }

    def check_own_parameters_are_dropped_by_the_callee_and_own {
        out = assert_native_identity(_fixture("own_param_drop.jac"));
        assert out.splitlines() == ["drop job 1", "drop job 7", "8", "done"] , out;
    }

    def check_optional_owned_local_moves_drop_overwritten_valu {
        out = assert_native_identity(_fixture("optional_local_move.jac"));
        assert out.splitlines() == ["drop 1", "2", "drop 2", "done"] , out;
    }
    run_cases(
        [
            (
                "a named own local moved into an inline-flattened own field drops once",
                check_a_named_own_local_moved_into_an_inline_flattened
            ),
            (
                "own parameters are dropped by the callee and own returns by the receiver",
                check_own_parameters_are_dropped_by_the_callee_and_own
            ),
            (
                "optional owned local moves drop overwritten values and clear the source",
                check_optional_owned_local_moves_drop_overwritten_valu
            )
        ]
    );
}

test "str() of a string returns a value its consumer owns" {
    out = assert_native_identity(_fixture("str_builtin_ownership.jac"));
    assert out.splitlines() == ["caught: out of range", "literal item3 580"] , out;
}

"""Build `name` headerless and require the macOS `leaks` tool to find nothing."""
def _assert_nogc_leak_free(name: str) {
    import shutil;
    import subprocess;
    import tempfile;
    import from tests.support { native_build }
    if not shutil.which("leaks") {
        testskip("the macOS leaks tool is not available");
    }
    binary = os.path.join(tempfile.mkdtemp(), name.replace(".jac", ".nogc"));
    native_build(_fixture(name), binary, memory="nogc");
    lk = subprocess.run(
        ["leaks", "--atExit", "--", binary], capture_output=True, text=True, timeout=300
    );
    assert "0 leaks for 0 total leaked bytes" in lk.stdout , lk.stdout[-1500:];
}

test "str() copies and len() temporaries leave nothing behind, and related cases" {
    def check_str_copies_and_len_temporaries_leave_nothing_beh {
        out = assert_native_identity(_fixture("str_builtin_leaks.jac"));
        assert out.strip() == "literal 870" , out;
        _assert_nogc_leak_free("str_builtin_leaks.jac");
    }

    def check_rebound_and_freshly_built_string_locals_leave_no {
        out = assert_native_identity(_fixture("rebind_leaks.jac"));
        assert out.strip() == "item49 1350" , out;
        _assert_nogc_leak_free("rebind_leaks.jac");
    }

    def check_objects_own_their_str_and_bytes_fields_and_conta {
        out = assert_native_identity(_fixture("str_field_leaks.jac"));
        assert out.strip() == "1280" , out;
        _assert_nogc_leak_free("str_field_leaks.jac");
    }

    def check_a_method_handing_back_its_receiver_returns_a_bor {
        out = assert_native_identity(_fixture("receiver_borrow.jac"));
        assert out.strip() == "530" , out;
        _assert_nogc_leak_free("receiver_borrow.jac");
    }

    def check_a_conditional_expression_copies_its_borrowed_arm {
        out = assert_native_identity(_fixture("ternary_arm_owners.jac"));
        assert out.strip() == "350" , out;
        _assert_nogc_leak_free("ternary_arm_owners.jac");
    }

    def check_caught_exceptions_are_freed_when_their_handler_e {
        out = assert_native_identity(_fixture("caught_exception_leaks.jac"));
        assert out.strip() == "1770" , out;
        _assert_nogc_leak_free("caught_exception_leaks.jac");
    }
    run_cases(
        [
            (
                "str() copies and len() temporaries leave nothing behind",
                check_str_copies_and_len_temporaries_leave_nothing_beh
            ),
            (
                "rebound and freshly built string locals leave nothing behind",
                check_rebound_and_freshly_built_string_locals_leave_no
            ),
            (
                "objects own their str and bytes fields and containers their strings",
                check_objects_own_their_str_and_bytes_fields_and_conta
            ),
            (
                "a method handing back its receiver returns a borrow",
                check_a_method_handing_back_its_receiver_returns_a_bor
            ),
            (
                "a conditional expression copies its borrowed arm when the other arm is owned",
                check_a_conditional_expression_copies_its_borrowed_arm
            ),
            (
                "caught exceptions are freed when their handler ends",
                check_caught_exceptions_are_freed_when_their_handler_e
            )
        ]
    );
}


test "static text a builtin returns reaches its owner as a copy" {
    out = assert_native_identity(_fixture("static_text_owners.jac"));
    assert out.splitlines() == ["ABC", "744"] , out;
    _assert_nogc_leak_free("static_text_owners.jac");
}


test "an own field held by pointer drops the object each store replaces" {
    out = assert_native_identity(_fixture("pointer_field_move.jac"));
    assert out.splitlines()
        == [
            "before=0",
            "drop node 0",
            "h.slot.v=2",
            "drop node 2",
            "h.slot.v=3",
            "drop node 3",
            "done"
        ] , out;
}

test "an owned singly linked list with take() and swap() behaves identically, and related cases" {
    def check_an_owned_singly_linked_list_with_take_and_swap_b {
        out = assert_native_identity(_fixture("linked_list.jac"));
        assert out.strip() == "10409" , out;
    }

    def check_subclass_instances_in_a_list_own_base_keep_their {
        out = assert_native_identity(_fixture("subclass_owned_list.jac"));
        assert out.strip() == "1010" , out;
    }

    def check_a_borrow_of_a_list_element_returned_under_t_read {
        out = assert_native_identity(_fixture("elem_borrow_return.jac"));
        assert out.strip() == "9" , out;
    }

    def check_a_generic_over_a_borrowed_list_returns_a_borrow {
        out = assert_native_identity(_fixture("generic_elem.jac"));
        assert out.strip() == "77" , out;
    }
    run_cases(
        [
            (
                "an owned singly linked list with take() and swap() behaves identically",
                check_an_owned_singly_linked_list_with_take_and_swap_b
            ),
            (
                "subclass instances in a list[own Base] keep their layout and dispatch",
                check_subclass_instances_in_a_list_own_base_keep_their
            ),
            (
                "a borrow of a list element returned under -> &T reads the element",
                check_a_borrow_of_a_list_element_returned_under_t_read
            ),
            (
                "a generic over a borrowed list returns a borrow of the element",
                check_a_generic_over_a_borrowed_list_returns_a_borrow
            )
        ]
    );
}

test "an owned local moved after it was borrowed is dropped once, by the new owner" {
    out = assert_native_identity(_fixture("borrow_then_move.jac"));
    assert out.splitlines()
        == [
            "mut m.n=1",
            "drop 1",
            "--",
            "peek 5",
            "shared m.n=5",
            "drop 2",
            "--",
            "loop peek 3",
            "loop peek 3",
            "loop m.n=3",
            "drop 3",
            "--",
            "field peek 1",
            "field g.inner.n=1",
            "drop 4",
            "--",
            "first m.tag=5",
            "drop 5",
            "existing m.tag=6 m.n=1",
            "drop 6",
            "--",
            "opt a.n=9",
            "opt m.n=9",
            "drop 7",
            "--",
            "param m.n=1",
            "drop 8",
            "done"
        ] , out;
}


test "pop() on a list[own T] hands the element to the receiver, and related cases" {
    def check_pop_on_a_list_own_t_hands_the_element_to_the_rec {
        out = assert_native_identity(_fixture("pop_owned.jac"));
        assert out.splitlines() == ["drop 3", "drop 2", "drop 1", "6", "done"] , out;
    }

    def check_a_lin_binding_lowers_exactly_like_own_in_every_m {
        out = assert_native_identity(_fixture("lin_handle.jac"));
        assert out.splitlines() == ["using 7", "close 7", "drop 7", "1", "done"] , out;
    }
    run_cases(
        [
            (
                "pop() on a list[own T] hands the element to the receiver",
                check_pop_on_a_list_own_t_hands_the_element_to_the_rec
            ),
            (
                "a lin binding lowers exactly like own in every memory mode",
                check_a_lin_binding_lowers_exactly_like_own_in_every_m
            )
        ]
    );
}


test "pop, insert, del, index-assign and extend on a list of owned elements" {
    out = assert_native_identity(_fixture("owned_list_ops.jac"));
    assert out.splitlines()
        == [
            "popped 1 -> 0,2,3,4",
            "drop 1",
            "inserted -> 9,0,2,3,4",
            "drop 2",
            "deleted -> 9,0,3,4",
            "drop 9",
            "assigned -> 7,0,3,4",
            "extended -> 7,0,3,4,11,12",
            "drop 12",
            "drop 11",
            "drop 4",
            "drop 3",
            "drop 0",
            "drop 7",
            "6",
            "done"
        ] , out;
}

test "a self: own method consumes and drops its receiver exactly once, and related cases" {
    def check_a_self_own_method_consumes_and_drops_its_receive {
        out = assert_native_identity(_fixture("own_self_method.jac"));
        assert out.splitlines() == ["drop counter 2", "22", "done"] , out;
    }

    def check_a_string_returned_from_a_local_container_preserv {
        out = assert_native_identity(_fixture("borrowed_string_return.jac"));
        assert out.splitlines() == ["3", "98", "c"] , out;
    }
    run_cases(
        [
            (
                "a self: own method consumes and drops its receiver exactly once",
                check_a_self_own_method_consumes_and_drops_its_receive
            ),
            (
                "a string returned from a local container preserves its bytes after cleanup",
                check_a_string_returned_from_a_local_container_preserv
            )
        ]
    );
}


test "owned archetype values in a dict: overwrite, pop, del and the dict drop" {
    out = assert_native_identity(_fixture("owned_dict_values.jac"));
    assert out.splitlines()
        == [
            "drop 1",
            "a=10",
            "popped=2",
            "drop 10",
            "sink 2",
            "drop 2",
            "drop 3",
            "1",
            "done"
        ] , out;
}

test "named own archetypes move into append, insert, a dict store and a list literal" {
    out = assert_native_identity(_fixture("named_move_containers.jac"));
    assert out.splitlines()
        == [
            "xs=21",
            "m=34",
            "ys=5",
            "sink 1",
            "drop 1",
            "sink 4",
            "drop 4",
            "drop 3",
            "sink 5",
            "drop 5",
            "drop 2",
            "2",
            "done"
        ] , out;
}


test "raise propagates through the hidden error slot with static drops and finally" {
    out = assert_native_identity(_fixture("error_slot.jac"));
    assert out.splitlines()
        == ["drop 1", "81", "drop 1", "8080", "caught", "finally", "done"] , out;
}

test "inferred local states never change behavior" {
    out = assert_native_identity(_fixture("local_inference.jac"));
    assert out.splitlines()
        == [
            "a,b,c a1 yes svc 2",
            "15",
            "drop cfg",
            "a!",
            "b",
            "x,X,y,Y",
            "4",
            "012",
            "drop item 2",
            "drop item 1"
        ];
}


test "super.init owns each argument before it replaces a field a later one reads" {
    out = assert_native_identity(_fixture("super_init_borrowed_text.jac"));
    assert out.splitlines()
        == [
            "seed0-new seed0-old seed0!",
            "seed1-new seed1-old seed1!",
            "seed2-new seed2-old seed2!",
            "1050"
        ] , out;
    _assert_nogc_leak_free("super_init_borrowed_text.jac");
}

test "a character indexed from a string reaches each owner as a copy" {
    out = assert_native_identity(_fixture("str_index_owners.jac"));
    assert out.splitlines() == ["a b ['c']", "a b ['c']", "900"] , out;
    _assert_nogc_leak_free("str_index_owners.jac");
}
