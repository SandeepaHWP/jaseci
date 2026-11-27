"""Regression tests for the headerless nogc container-element fence (E1406).

Under `--memory nogc`, owned containers of *str* elements are
supported: fresh values (f-strings, concats, str slices, call results) move
into the container, while named bindings, string literals, and container-
element reads are copied in at codegen, so the container always owns heap
storage it can free at drop. Borrowed params and obj-field reads would alias
storage the container must not free, so they stay fenced, as do non-str heap
elements (archetypes, nested containers), whose element-drop monomorphization
is still deferred. These tests pin both sides: every unsupported write is
fenced, and the supported shapes (scalar containers, str containers, and a
same-named method on a non-container user type) stay clean. Archetype
elements move into lists and dict values (fresh values and named own
bindings alike); sets of archetypes stay fenced.

Each fixture is compiled through the real type-check schedule with enforcement
enabled via CompileOptions, matching `jac build --native --memory nogc`.
"""

import os;
import from jaclang.compiler.driver.program { JacProgram }
import from jaclang.compiler.driver.compile_options { CompileOptions }
import from tests.support { JAC_ROOT, run_cases }

glob FIXTURES = os.path.join(
         JAC_ROOT, "tests", "compiler", "passes", "fixtures", "nogc_containers"
     );

"""Compile a fixture as a headerless nogc-enforced module; return its coded
alerts in emission order."""
def enforced_alerts(fixture: str) -> list[any] {
    path = os.path.join(FIXTURES, fixture);
    prog = JacProgram();
    opts = CompileOptions(aot_mode=True, memory_profile="nogc");
    prog.compile(file_path=path, options=opts);
    return [
        a
        for a in list(prog.errors_had)
        if a.code is not None
    ];
}

"""Compile a fixture as a headerless nogc-enforced module; return its unique,
sorted diagnostic codes."""
def enforced_codes(fixture: str) -> list[str] {
    path = os.path.join(FIXTURES, fixture);
    prog = JacProgram();
    opts = CompileOptions(aot_mode=True, memory_profile="nogc");
    prog.compile(file_path=path, options=opts);
    codes: set[str] = set();
    for alert in list(prog.errors_had) {
        if alert.code is not None {
            codes.add(alert.code.code);
        }
    }
    return sorted(codes);
}

test "fresh archetypes move into list appends since #7857 Phase B, and related cases" {
    # --- Heap element reaching a container by any write must be fenced (E1406). ----
    def check_fresh_archetypes_move_into_list_appends_since_78 {
        assert enforced_codes("append_obj.jac") == [];
    }

    def check_a_str_method_on_a_borrowed_element_yields_a_fres {
        assert enforced_codes("append_elem_method_ok.jac") == [];
    }

    def check_own_p_copies_a_borrowed_str_element_into_an_owne {
        assert enforced_codes("append_own_copy_ok.jac") == [];
    }

    def check_a_fresh_archetype_index_assigned_as_a_dict_value {
        assert enforced_codes("dict_heap_val.jac") == [];
    }

    def check_a_dict_literal_with_a_fresh_archetype_value_move {
        assert enforced_codes("dict_literal_heap.jac") == [];
    }

    # --- Supported shapes stay clean: no false positives. -------------------------
    def check_appending_freshly_built_strings_into_a_list_is_c {
        assert enforced_codes("append_built_str.jac") == [];
    }

    def check_append_of_f_string_concat_slice_and_call_result {
        assert enforced_codes("append_fresh_str_ok.jac") == [];
    }

    def check_appending_a_named_owned_string_copies_it_in_the {
        assert enforced_codes("append_named_copy_ok.jac") == [];
    }

    def check_adding_freshly_built_strings_to_a_set_is_clean {
        assert enforced_codes("set_add_fresh_str_ok.jac") == [];
    }

    def check_str_keys_and_values_entering_a_dict_are_clean {
        assert enforced_codes("dict_str_val_ok.jac") == [];
    }

    def check_a_list_literal_of_fresh_static_and_named_str_ele {
        assert enforced_codes("list_literal_fresh_ok.jac") == [];
    }

    def check_overwriting_a_list_slot_with_a_fresh_str_is_clea {
        assert enforced_codes("list_set_str_ok.jac") == [];
    }

    def check_scalar_list_dict_set_with_append_add_index_is_cl {
        assert enforced_codes("scalar_containers_ok.jac") == [];
    }

    def check_indexing_a_container_with_a_scalar_returning_cal {
        assert enforced_codes("scalar_call_index_ok.jac") == [];
    }

    def check_a_list_of_string_literals_static_not_owned_heap {
        assert enforced_codes("str_literal_list_ok.jac") == [];
    }

    def check_append_on_a_non_container_user_type_does_not_tri {
        assert enforced_codes("user_append_ok.jac") == [];
    }
    run_cases(
        [
            (
                "fresh archetypes move into list appends since #7857 Phase B",
                check_fresh_archetypes_move_into_list_appends_since_78
            ),
            (
                "a str method on a borrowed element yields a fresh str that moves in",
                check_a_str_method_on_a_borrowed_element_yields_a_fres
            ),
            (
                "`own p` copies a borrowed str element into an owned list",
                check_own_p_copies_a_borrowed_str_element_into_an_owne
            ),
            (
                "a fresh archetype index-assigned as a dict value moves into the dict",
                check_a_fresh_archetype_index_assigned_as_a_dict_value
            ),
            (
                "a dict literal with a fresh archetype value moves it into the dict",
                check_a_dict_literal_with_a_fresh_archetype_value_move
            ),
            (
                "appending freshly-built strings into a list is clean",
                check_appending_freshly_built_strings_into_a_list_is_c
            ),
            (
                "append of f-string, concat, slice, and call-result strings is clean",
                check_append_of_f_string_concat_slice_and_call_result
            ),
            (
                "appending a named owned string copies it in; the source stays live",
                check_appending_a_named_owned_string_copies_it_in_the
            ),
            (
                "adding freshly-built strings to a set is clean",
                check_adding_freshly_built_strings_to_a_set_is_clean
            ),
            (
                "str keys and values entering a dict are clean",
                check_str_keys_and_values_entering_a_dict_are_clean
            ),
            (
                "a list literal of fresh, static, and named str elements is clean",
                check_a_list_literal_of_fresh_static_and_named_str_ele
            ),
            (
                "overwriting a list slot with a fresh str is clean",
                check_overwriting_a_list_slot_with_a_fresh_str_is_clea
            ),
            (
                "scalar list/dict/set with append/add/index is clean",
                check_scalar_list_dict_set_with_append_add_index_is_cl
            ),
            (
                "indexing a container with a scalar-returning call is clean",
                check_indexing_a_container_with_a_scalar_returning_cal
            ),
            (
                "a list of string literals (static, not owned heap) is clean",
                check_a_list_of_string_literals_static_not_owned_heap
            ),
            (
                "`.append` on a non-container user type does not trip the fence",
                check_append_on_a_non_container_user_type_does_not_tri
            )
        ]
    );
}

test "E1406: appending a borrowed str param into a list, and related cases" {
    def check_e1406_appending_a_borrowed_str_param_into_a_list {
        assert enforced_codes("append_borrow_fenced.jac") == ["E1406"];
    }

    def check_e1406_appending_an_obj_field_read_into_a_list {
        assert enforced_codes("append_field_fenced.jac") == ["E1406"];
    }

    def check_e1406_adding_an_owned_heap_object_to_a_set {
        assert enforced_codes("set_add_obj.jac") == ["E1406"];
    }

    def check_e1406_a_set_literal_with_an_owned_heap_element {
        assert enforced_codes("set_literal_heap.jac") == ["E1406"];
    }

    def check_e1406_an_owned_heap_object_used_as_a_dict_key {
        assert enforced_codes("dict_heap_key.jac") == ["E1406"];
    }
    run_cases(
        [
            (
                "E1406: appending a borrowed str param into a list",
                check_e1406_appending_a_borrowed_str_param_into_a_list
            ),
            (
                "E1406: appending an obj field read into a list",
                check_e1406_appending_an_obj_field_read_into_a_list
            ),
            (
                "E1406: adding an owned heap object to a set",
                check_e1406_adding_an_owned_heap_object_to_a_set
            ),
            (
                "E1406: a set literal with an owned heap element",
                check_e1406_a_set_literal_with_an_owned_heap_element
            ),
            (
                "E1406: an owned heap object used as a dict key",
                check_e1406_an_owned_heap_object_used_as_a_dict_key
            )
        ]
    );
}


test "E1406 names the borrow, its owner, the container and the fix" {
    alerts = enforced_alerts("append_loop_borrow_fenced.jac");
    assert [a.code.code for a in alerts] == ["E1406"];
    assert "'p', a borrow of 'parts', cannot enter 'out', which owns its elements"
        in alerts[0].msg;
    assert "out.append(own p)" in (alerts[0].help_text or "");
    assert "for p in parts" in (alerts[0].help_text or "");
}

test "E1406 on an inferred imm local names the copy idiom" {
    alerts = enforced_alerts("append_imm_local_fenced.jac");
    assert [a.code.code for a in alerts] == ["E1406"];
    assert "'lit', an `imm` value, cannot enter 'xs'" in alerts[0].msg;
    assert "xs.append(own lit)" in (alerts[0].help_text or "");
}


test "E1306 + E1406: a borrowed heap object as a dict value" {
    assert enforced_codes("dict_heap_val_borrow.jac") == ["E1306", "E1406"];
}
