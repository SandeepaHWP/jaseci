"""Programs the native tier ran and answered differently from the Python tier.

Each case here was found by the tier census (`tests/tier_census.jac`): an
ordinary program, not written for the native tier, that lowered, ran to the
end and printed something else. A refusal is loud; these were not."""
import from pathlib { Path }
import from tests.support { assert_native_identity, run_cases }

def fixture(name: str) -> str {
    return str(Path(__file__).resolve().parent / "fixtures" / name);
}

test "a switch falls through to the next case until a break, and related cases" {
    # A `switch` falls through: once a case matches, every later case runs until
    # a `break`, the default included, and a default that is reached before any
    # match runs too. The native lowering ran one case and left, skipped a case
    # with no body, and dropped a case that names several values.
    def check_a_switch_falls_through_to_the_next_case_until_a {
        out = assert_native_identity(
            fixture("switch_fallthrough.jac"), profiles=["rc", "managed"]
        );
        assert "banana ['banana-or-orange', 'grape']" in out , out;
        assert "kiwi ['kiwi-or-lime', 'default:kiwi']" in out , out;
        assert "3 many nine" in out , out;
        assert "5109" in out , out;
    }

    # `(a, b) = pair` inside a function, where `a` and `b` are module globals,
    # assigns the globals, as `a = x` does. The native lowering bound two locals
    # and the globals kept their old values.
    def check_a_tuple_assignment_to_module_globals_writes_the {
        out = assert_native_identity(
            fixture("unpack_into_globals.jac"), profiles=["rc", "managed"]
        );
        assert "World Hello 1" in out , out;
        assert "y1 y2 3" in out , out;
        assert "['p', 'q'] q lr" in out , out;
    }

    # `3 == 3.0` and `True == 1` hold whatever the static types are. Two untyped
    # values were equal on the native tier only when they were the same kind of
    # number, so `x as int as float == 3.0` was false for `x: any = 3`.
    def check_untyped_numbers_of_different_kinds_compare_by_va {
        out = assert_native_identity(
            fixture("any_number_equality.jac"), profiles=["rc", "managed"]
        );
        assert "True True True True True" in out , out;
        assert "False False False False True" in out , out;
        assert "True True True False" in out , out;
    }

    # An archetype is a dataclass on the Python tier, so printing one writes
    # `Name(field=value, ...)`. The native tier wrote `<Name object at 0x...>`,
    # which is different text and a different one every run.
    def check_an_object_without_its_own_repr_prints_its_fields {
        out = assert_native_identity(
            fixture("default_object_text.jac"), profiles=["rc", "managed"]
        );
        assert "Named(x=1, y=2.0, label=\"it's\", tags=['a', 'b'])" in out , out;
        assert "Holder(inner=Point(x=3, y=1.5), maybe=None, flag=True)" in out , out;
        assert "Link(name='a', nxt=Link(name='b', nxt=None))" in out , out;
        assert "Bag(counts={'x': 1}, seen={1}, pair=(1, 'a'), anything='q', ratio=0.1)"
            in out , out;
        assert "Tour(depth=2) Road(km=9)" in out , out;
    }

    # The text follows the object, not the type it is held as: a subclass
    # instance held as its base prints the subclass's name and fields, or runs the
    # subclass's own `__repr__`.
    def check_default_object_text_follows_the_runtime_class {
        out = assert_native_identity(
            fixture("default_object_text_subclass.jac"), profiles=["rc", "managed"]
        );
        assert "Shape(sides=0) Square(sides=4, width=2) Named<q>" in out , out;
        assert "[Square(sides=4, width=2), Shape(sides=0), Named<q>]" in out , out;
    }

    # An ability triggered by `Root` runs at the root node only. The native
    # tier has no root node of its own and read the name as "any location", so
    # `with Root | Stop entry` ran at every node, and twice at a `Stop`. An
    # ability whose trigger names a base and its subclass does run twice at the
    # subclass, on both tiers.
    def check_a_root_trigger_does_not_match_every_node {
        out = assert_native_identity(
            fixture("union_trigger_abilities.jac"), profiles=["rc", "managed"]
        );
        assert "['ab', 'a'] ['ab'] ['root-or-c']" in out , out;
        assert "['either', 'either', 'leaving', 'leaving'] ['either', 'leaving']"
            in out , out;
    }

    # `print(f())` writes `None` when `f` returns nothing. The native tier
    # refused the program instead, which made this the most common reason a
    # program was not native in the first census.
    def check_printing_the_result_of_a_call_that_returns_nothi {
        out = assert_native_identity(
            fixture("print_none_result.jac"), profiles=["rc", "managed"]
        );
        assert "a None b None" in out , out;
        assert "None 1 2" in out , out;
    }

    # `hub ++> [a, b]` connects `hub` to each node, and `[a, b] ++> sink` each
    # node to `sink`, with a fresh edge per connection.
    def check_a_connect_with_a_list_of_nodes_on_one_side_conne {
        out = assert_native_identity(
            fixture("connect_through_list.jac"), profiles=["rc", "managed"]
        );
        assert "fan out [1, 2, 3]" in out , out;
        assert "fan in [5, 9] [6, 9]" in out , out;
        assert "typed [10, 11, 12]" in out , out;
        assert "single and empty [20, 21]" in out , out;
    }

    # An object reached again while its own text is being written prints as
    # `...`, as a dataclass does on the Python tier, so a tree with parent links
    # or two objects that hold each other still print and still terminate.
    def check_default_object_text_stops_at_an_object_it_is_alr {
        out = assert_native_identity(
            fixture("default_object_text_cycle.jac"), profiles=["rc", "managed"]
        );
        assert "Tree(name='top', parent=None, kids=[Tree(name='kid', parent=..., kids=[])])"
            in out , out;
        assert "Pair(left=Pair(left=..., label='b'), label='a')" in out , out;
    }

    # The native tier has no root node. A plain `root ++> node` in a module
    # that only follows edges forward is an anchor nothing native can observe, so
    # it is accepted and the rest of the statement still happens: `root ++> a ++>
    # b` used to drop the whole statement and leave `a` and `b` unconnected. A
    # root connect that names an edge, or sits beside a backward traversal, would
    # be missed, and is refused.
    def check_a_connect_from_root_keeps_the_rest_of_the_chain {
        out = assert_native_identity(
            fixture("connect_from_root.jac"), profiles=["rc", "managed"]
        );
        assert "chain [1, 2, 3]" in out , out;
        assert "reversed [4, 5]" in out , out;
    }

    # An integer and a float are equal when they are the same number, not when
    # they round to the same float. `9007199254740993 == 9007199254740992.0` is
    # false, and so is `9223372036854775807 == 9223372036854775808.0`; comparing
    # both sides as floats made each of them true.
    def check_untyped_numbers_compare_exactly_past_the_range_a {
        out = assert_native_identity(
            fixture("any_number_equality_wide.jac"), profiles=["rc", "managed"]
        );
        assert "False True" in out , out;
        assert "True True False False" in out , out;
    }

    # `sinks <++ src` yields `sinks` and `hub <++ feeders` yields `hub`: the
    # side the edges arrive at, as written, whichever side is the list.
    def check_a_connect_written_toward_its_source_yields_the_d {
        out = assert_native_identity(
            fixture("connect_reverse_result.jac"), profiles=["rc", "managed"]
        );
        assert "reverse list dest 2" in out , out;
        assert "reverse node dest 10" in out , out;
        assert "[1, 2, 3]" in out , out;
    }

    # A `continue` inside a switch belongs to the loop around the switch. The
    # native tier jumped to that loop without running the `finally` blocks it left
    # on the way. The Python tier runs a switch as a loop of its own and restarted
    # it, so the same program never finished there.
    def check_a_continue_inside_a_switch_moves_the_enclosing_l {
        out = assert_native_identity(
            fixture("switch_continue.jac"), profiles=["rc", "managed"]
        );
        assert "zero\nfinally 0\none\nafter switch 1\nfinally 1\n" in out , out;
        assert "inner finally 00\ninner 01\ninner finally 01\nouter finally 0\n"
            in out , out;
        assert "skip 0\nodd 1\nend 1\neven 2\nafter inner 2\n" in out , out;
        assert "counted 0\nk 1\nk 3\ncounted 2\n" in out , out;
        assert "two done\ntail 2\nn 4\ntail 4\n" in out , out;
    }

    # The objects being written out are tracked without a limit. With room for
    # 64, a chain of 80 objects that closes on itself past the 64th was followed
    # round the cycle until the stack ran out.
    def check_default_object_text_nests_past_any_fixed_depth_a {
        out = assert_native_identity(
            fixture("default_object_text_deep.jac"), profiles=["rc", "managed"]
        );
        assert "1754 80 0\n1753 80 1\n" in out , out;
        assert "True 1754" in out , out;
    }

    # An object whose field holds its own type is written out by one helper,
    # whichever is printed first: the object, or a list or dict that holds it.
    # Printing the container first built the object's helper twice and stopped
    # the compile.
    def check_a_self_referential_object_prints_from_inside_a_c {
        out = assert_native_identity(
            fixture("default_object_text_recursive.jac"), profiles=["rc", "managed"]
        );
        assert "[Link(name='a', after=Link(name='b', after=None))]\n" in out , out;
        assert "[Tree(label='r', kids=[Tree(label='x', kids=[])])]\n" in out , out;
        assert "{'h': Hub(name='p', spokes={'q': Hub(name='q', spokes={})})}\n"
            in out , out;
    }
    run_cases(
        [
            (
                "a switch falls through to the next case until a break",
                check_a_switch_falls_through_to_the_next_case_until_a
            ),
            (
                "a tuple assignment to module globals writes the globals",
                check_a_tuple_assignment_to_module_globals_writes_the
            ),
            (
                "untyped numbers of different kinds compare by value",
                check_untyped_numbers_of_different_kinds_compare_by_va
            ),
            (
                "an object without its own repr prints its fields",
                check_an_object_without_its_own_repr_prints_its_fields
            ),
            (
                "default object text follows the runtime class",
                check_default_object_text_follows_the_runtime_class
            ),
            (
                "a Root trigger does not match every node",
                check_a_root_trigger_does_not_match_every_node
            ),
            (
                "printing the result of a call that returns nothing writes None",
                check_printing_the_result_of_a_call_that_returns_nothi
            ),
            (
                "a connect with a list of nodes on one side connects each node",
                check_a_connect_with_a_list_of_nodes_on_one_side_conne
            ),
            (
                "default object text stops at an object it is already writing",
                check_default_object_text_stops_at_an_object_it_is_alr
            ),
            (
                "a connect from root keeps the rest of the chain",
                check_a_connect_from_root_keeps_the_rest_of_the_chain
            ),
            (
                "untyped numbers compare exactly past the range a float holds",
                check_untyped_numbers_compare_exactly_past_the_range_a
            ),
            (
                "a connect written toward its source yields the destination",
                check_a_connect_written_toward_its_source_yields_the_d
            ),
            (
                "a continue inside a switch moves the enclosing loop on",
                check_a_continue_inside_a_switch_moves_the_enclosing_l
            ),
            (
                "default object text nests past any fixed depth and still stops at a cycle",
                check_default_object_text_nests_past_any_fixed_depth_a
            ),
            (
                "a self-referential object prints from inside a container first",
                check_a_self_referential_object_prints_from_inside_a_c
            )
        ]
    );
}


"""Two graph forms were accepted by the native tier and did nothing: a
statement naming `root` was dropped whole, and a connect with a list as an
operand connected to the list object. A walker then stopped early and the
program printed less than the Python tier, with no error. What is still not
lowered (`root` as a value, and a list on both sides of a connect) is
refused by name."""
test "graph forms the native tier cannot lower are refused, not dropped" {
    import from jaclang.compiler.driver.program { JacProgram }
    import from tests.support { native_force_opts }
    options = native_force_opts();
    options.skip_native_engine = True;
    options.no_ir_cache = True;
    program = JacProgram();
    program.compile(file_path=fixture("graph_forms_not_lowered.jac"), options=options);
    refusals = [str(e) for e in program.errors_had];
    assert any("expression 'root'" in r for r in refusals) , refusals;
    assert any("connect operand 'root'" in r for r in refusals) , refusals;
    assert any("connect operand 'list'" in r for r in refusals) , refusals;
}

"""A function that cannot be lowered is left to the Python tier and every
native caller of it is refused. A walker's ability has no caller in the
source: the graph engine runs it. So a walker with an ability that could not
be lowered compiled, and the program stopped on the stub when the engine
reached it. The module is now refused when that happens."""
test "a walker ability that cannot be lowered refuses the module" {
    import from jaclang.compiler.driver.program { JacProgram }
    import from tests.support { native_force_opts }
    options = native_force_opts();
    options.skip_native_engine = True;
    options.no_ir_cache = True;
    program = JacProgram();
    program.compile(file_path=fixture("ability_not_lowered.jac"), options=options);
    refusals = [str(e) for e in program.errors_had];
    assert any("event ability" in r and "look" in r for r in refusals) , refusals;
}


test "swapping two module globals that hold objects keeps both, and related cases" {
    # `(a, b) = (b, a)` on two module globals reads both before it writes
    # either. Releasing the value a global held as soon as it was overwritten freed
    # an object the second assignment was still about to store.
    def check_swapping_two_module_globals_that_hold_objects_ke {
        out = assert_native_identity(
            fixture("unpack_swaps_object_globals.jac"), profiles=["rc", "managed"]
        );
        assert out == "R L 2\nL R 2\nR L 2\n" , out;
    }

    # The values a tuple assignment replaces outlive the whole assignment, at
    # any nesting depth. In `((a, n), b) = ((b, 1), a)` the value `a` held is
    # stored into `b` after the inner tuple is done; releasing it when the inner
    # tuple finished freed it first, for locals and for module globals.
    def check_a_swap_through_a_nested_tuple_keeps_every_object {
        out = assert_native_identity(
            fixture("unpack_nested_swap.jac"), profiles=["rc", "managed"]
        );
        assert out == "R L 1 2\nL R 2 2\nR L 3 2\nba3\n" , out;
    }

    # A connect with a list of nodes on one side evaluates its edge and its
    # attribute values once, as the Python tier does, not once per node: with no
    # nodes they are still evaluated, and every edge gets the same values.
    def check_a_connect_through_a_list_evaluates_its_edge_once {
        out = assert_native_identity(
            fixture("connect_through_list_once.jac"), profiles=["rc", "managed"]
        );
        assert out == "assigned 1 3\nassigned to none 2\nbuilt 3 2\n" , out;
    }

    # A field a subclass declares again keeps the place its base gave it, as on
    # the Python tier: `Child(x=3, y=2)`, not `Child(y=2, x=3)`. An optional field
    # whose type has no native text still leaves a program that compiles.
    def check_default_object_text_keeps_the_base_s_field_order {
        out = assert_native_identity(
            fixture("default_object_text_fields.jac"), profiles=["rc", "managed"]
        );
        assert out == "Child(x=3, y=2)\nBase(x=1, y=2) Child(x=5, y=6)\nb\n" , out;
    }
    run_cases(
        [
            (
                "swapping two module globals that hold objects keeps both",
                check_swapping_two_module_globals_that_hold_objects_ke
            ),
            (
                "a swap through a nested tuple keeps every object",
                check_a_swap_through_a_nested_tuple_keeps_every_object
            ),
            (
                "a connect through a list evaluates its edge once",
                check_a_connect_through_a_list_evaluates_its_edge_once
            ),
            (
                "default object text keeps the base's field order",
                check_default_object_text_keeps_the_base_s_field_order
            )
        ]
    );
}


"""Only an edge that leaves root is an anchor nothing native can observe.
One that arrives at root, or runs both ways, gives the node an outgoing edge
a forward traversal would follow, so it is refused like any other use of
root."""
test "a connect that puts an edge into root is refused" {
    import from jaclang.compiler.driver.program { JacProgram }
    import from tests.support { native_force_opts }
    options = native_force_opts();
    options.skip_native_engine = True;
    options.no_ir_cache = True;
    program = JacProgram();
    program.compile(file_path=fixture("connect_into_root.jac"), options=options);
    refusals = [
        str(e)
        for e in program.errors_had
        if "connect operand 'root'" in str(e)
    ];
    assert len(refusals) == 4 , [str(e) for e in program.errors_had];
}


test "an error raised while an object is written out leaves it printable, and related cases" {
    # A field whose own text raises ends the write of the object holding it.
    # The object is no longer being written, so printing it again writes it in
    # full rather than `...`.
    def check_an_error_raised_while_an_object_is_written_out_l {
        out = assert_native_identity(
            fixture("default_object_text_raise.jac"), profiles=["rc", "managed"]
        );
        assert out
            == (
                "Holder(name='h', inner=calm)\n"
                "refused: not now\n"
                "Holder(name='h', inner=calm)\n"
                "Holder(name='h', inner=calm)\n"
            ) , out;
    }

    # A `break` in a `finally` replaces a `continue` that was on its way out of
    # a switch. The Python tier kept the `continue` pending and moved the loop on,
    # skipping the statements after the switch. The native tier ran the `finally`
    # where the `continue` or `return` was, so its `break` left the innermost loop
    # or switch there instead of the one around the `try`, and the program
    # crashed.
    def check_a_break_in_a_finally_cancels_a_continue_leaving {
        out = assert_native_identity(
            fixture("switch_finally_break.jac"), profiles=["rc", "managed"]
        );
        assert out
            == (
                "case 0 after 0 finally 1 after 1 case 2 after 2\n"
                "even 0 after 0 after 1 even 2 after 2 inner 3 after inner 3 after 3\n"
                "j 00 j 01 broke\n"
            ) , out;
    }
    run_cases(
        [
            (
                "an error raised while an object is written out leaves it printable",
                check_an_error_raised_while_an_object_is_written_out_l
            ),
            (
                "a break in a finally cancels a continue leaving a switch",
                check_a_break_in_a_finally_cancels_a_continue_leaving
            )
        ]
    );
}

"""Each thread tracks the objects it is writing out on its own. Sharing one
record let a `flow for` body see another thread's objects as its own and
print `...` for an object it had not met."""
test "threads writing out cyclic objects do not see each other's progress" {
    out = assert_native_identity(
        fixture("default_object_text_threads.jac"), profiles=["rc", "managed"]
    );
    assert "Pair(label=7, other=Pair(label=107, other=...))\nwrong 0\n" in out , out;
}

"""Each switch passes on only a `continue` that leaves through it. With one
flag shared by every switch, a switch holding a loop saw the `continue` that
loop had already taken and moved its own loop on too, and a switch that ran
in a `finally` cleared the flag of a `continue` on its way out."""
test "a continue reaches the loop it belongs to and no other" {
    out = assert_native_identity(
        fixture("switch_continue_nested.jac"), profiles=["rc", "managed"]
    );
    assert "after inner loop 0\nafter outer switch 0\nodd 1\n" in out , out;
    assert "after inner loop 2\nafter outer switch 2\n" in out , out;
    assert "cleanup tail 1\nother 1\ntail 1\n" in out , out;
    assert "\ntail 0\n" not in out , out;
}
