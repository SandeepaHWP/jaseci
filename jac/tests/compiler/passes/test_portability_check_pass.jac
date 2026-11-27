"""Portability check pass tests."""

import os;
import from tests.support { JAC_ROOT, run_cases }
import jaclang;
import from jaclang.compiler.driver.program { JacProgram }

glob FIXTURES = os.path.join(
         JAC_ROOT, "tests", "compiler", "passes", "fixtures", "portability"
     );

def has_warning_code(prog: JacProgram, code: str) -> bool {
    for alert in prog.warnings_had {
        if alert.code is not None and alert.code.code == code {
            return True;
        }
    }
    return False;
}

def count_warning_code(prog: JacProgram, code: str) -> int {
    count = 0;
    for alert in prog.warnings_had {
        if alert.code is not None and alert.code.code == code {
            count += 1;
        }
    }
    return count;
}

def get_warnings_with_code(prog: JacProgram, code: str) -> list[any] {
    return [
        w
        for w in prog.warnings_had
        if w.code is not None and w.code.code == code
    ];
}

test "console usage produces W6001 warning, and related cases" {
    # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    # W6001: JS-specific globals
    # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    def check_console_usage_produces_w6001_warning {
        file_path = os.path.join(FIXTURES, "js_globals.jac");
        prog = JacProgram();
        prog.compile(file_path);
        warnings = get_warnings_with_code(prog, "W6001");
        warning_msgs = [str(w) for w in warnings];
        assert any("console" in w for w in warning_msgs) , f"Expected W6001 warning for 'console', got: {warning_msgs}";
    }

    def check_math_usage_produces_w6001_warning {
        file_path = os.path.join(FIXTURES, "js_globals.jac");
        prog = JacProgram();
        prog.compile(file_path);
        warnings = get_warnings_with_code(prog, "W6001");
        warning_msgs = [str(w) for w in warnings];
        assert any("Math" in w for w in warning_msgs) , f"Expected W6001 warning for 'Math', got: {warning_msgs}";
    }

    def check_json_usage_produces_w6001_warning {
        file_path = os.path.join(FIXTURES, "js_globals.jac");
        prog = JacProgram();
        prog.compile(file_path);
        warnings = get_warnings_with_code(prog, "W6001");
        warning_msgs = [str(w) for w in warnings];
        assert any("JSON" in w for w in warning_msgs) , f"Expected W6001 warning for 'JSON', got: {warning_msgs}";
    }

    def check_array_object_map_set_constructors_produce_w6001 {
        file_path = os.path.join(FIXTURES, "js_globals.jac");
        prog = JacProgram();
        prog.compile(file_path);
        warnings = get_warnings_with_code(prog, "W6001");
        warning_msgs = [str(w) for w in warnings];
        assert any("Array" in w for w in warning_msgs) , f"Expected W6001 warning for 'Array', got: {warning_msgs}";
        assert any("Object" in w for w in warning_msgs) , f"Expected W6001 warning for 'Object', got: {warning_msgs}";
        assert any("Map" in w for w in warning_msgs) , f"Expected W6001 warning for 'Map', got: {warning_msgs}";
    }

    def check_settimeout_setinterval_produce_w6001_warnings {
        file_path = os.path.join(FIXTURES, "js_globals.jac");
        prog = JacProgram();
        prog.compile(file_path);
        warnings = get_warnings_with_code(prog, "W6001");
        warning_msgs = [str(w) for w in warnings];
        assert any("setTimeout" in w for w in warning_msgs) , f"Expected W6001 warning for 'setTimeout', got: {warning_msgs}";
        assert any("setInterval" in w for w in warning_msgs) , f"Expected W6001 warning for 'setInterval', got: {warning_msgs}";
    }

    def check_multiple_js_globals_produce_correct_count_of_w60 {
        file_path = os.path.join(FIXTURES, "js_globals.jac");
        prog = JacProgram();
        prog.compile(file_path);
        count = count_warning_code(prog, "W6001");
        # console (2: log, warn), Math (2: floor, ceil), JSON (2: parse, stringify),
        # Array, Object, Map, Set (4), setTimeout, setInterval (2) = 12
        assert count >= 10 , f"Expected at least 10 W6001 warnings for JS globals, got: {count}";
    }

    # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    # W6002: JS-idiomatic methods
    # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    def check_push_method_produces_w6002_warning {
        file_path = os.path.join(FIXTURES, "js_methods.jac");
        prog = JacProgram();
        prog.compile(file_path);
        warnings = get_warnings_with_code(prog, "W6002");
        warning_msgs = [str(w) for w in warnings];
        assert any("push" in w for w in warning_msgs) , f"Expected W6002 warning for '.push()', got: {warning_msgs}";
    }

    def check_foreach_method_produces_w6002_warning {
        file_path = os.path.join(FIXTURES, "js_methods.jac");
        prog = JacProgram();
        prog.compile(file_path);
        warnings = get_warnings_with_code(prog, "W6002");
        warning_msgs = [str(w) for w in warnings];
        assert any("forEach" in w for w in warning_msgs) , f"Expected W6002 warning for '.forEach()', got: {warning_msgs}";
    }

    def check_indexof_method_produces_w6002_warning {
        file_path = os.path.join(FIXTURES, "js_methods.jac");
        prog = JacProgram();
        prog.compile(file_path);
        warnings = get_warnings_with_code(prog, "W6002");
        warning_msgs = [str(w) for w in warnings];
        assert any("indexOf" in w for w in warning_msgs) , f"Expected W6002 warning for '.indexOf()', got: {warning_msgs}";
    }

    def check_string_js_methods_produce_w6002_warnings {
        file_path = os.path.join(FIXTURES, "js_methods.jac");
        prog = JacProgram();
        prog.compile(file_path);
        warnings = get_warnings_with_code(prog, "W6002");
        warning_msgs = [str(w) for w in warnings];
        assert any("charAt" in w for w in warning_msgs) , f"Expected W6002 warning for '.charAt()', got: {warning_msgs}";
        assert any("charCodeAt" in w for w in warning_msgs) , f"Expected W6002 warning for '.charCodeAt()', got: {warning_msgs}";
        assert any("substring" in w for w in warning_msgs) , f"Expected W6002 warning for '.substring()', got: {warning_msgs}";
    }

    def check_functional_methods_every_some_find_produce_w6002 {
        file_path = os.path.join(FIXTURES, "js_methods.jac");
        prog = JacProgram();
        prog.compile(file_path);
        warnings = get_warnings_with_code(prog, "W6002");
        warning_msgs = [str(w) for w in warnings];
        assert any("every" in w for w in warning_msgs) , f"Expected W6002 warning for '.every()', got: {warning_msgs}";
        assert any("some" in w for w in warning_msgs) , f"Expected W6002 warning for '.some()', got: {warning_msgs}";
        assert any("find" in w and "findIndex" not in w for w in warning_msgs) , f"Expected W6002 warning for '.find()', got: {warning_msgs}";
    }

    def check_find_with_a_lambda_callback_produces_w6002_warni {
        file_path = os.path.join(FIXTURES, "js_methods.jac");
        prog = JacProgram();
        prog.compile(file_path);
        count = count_warning_code(prog, "W6002");
        warnings = get_warnings_with_code(prog, "W6002");
        warning_msgs = [str(w) for w in warnings];
        find_hits = len(
            [
                w
                for w in warning_msgs
                if ".find(" in w
            ]
        );
        assert find_hits >= 2 , f"Expected find warnings for both function-ref and lambda callbacks, got: {warning_msgs}";
        assert count >= 16 , f"Expected the lambda find call to add a W6002, got count: {count}";
    }

    def check_conversion_methods_tofixed_tostring_produce_w600 {
        file_path = os.path.join(FIXTURES, "js_methods.jac");
        prog = JacProgram();
        prog.compile(file_path);
        warnings = get_warnings_with_code(prog, "W6002");
        warning_msgs = [str(w) for w in warnings];
        assert any("toFixed" in w for w in warning_msgs) , f"Expected W6002 warning for '.toFixed()', got: {warning_msgs}";
        assert any("toString" in w for w in warning_msgs) , f"Expected W6002 warning for '.toString()', got: {warning_msgs}";
    }

    def check_multiple_js_methods_produce_correct_count_of_w60 {
        file_path = os.path.join(FIXTURES, "js_methods.jac");
        prog = JacProgram();
        prog.compile(file_path);
        count = count_warning_code(prog, "W6002");
        # push, forEach, indexOf, splice, unshift, shift, includes (7)
        # charAt, charCodeAt, substring, padStart, trim (5)
        # every, some, find, findIndex (4)
        # hasOwnProperty, entries, keys, values (4)
        # toFixed, toPrecision, toString (3)
        assert count >= 15 , f"Expected at least 15 W6002 warnings for JS methods, got: {count}";
    }

    # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    # W6003: JS-specific keywords
    # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    def check_undefined_keyword_produces_w6003_warning {
        file_path = os.path.join(FIXTURES, "js_keywords.jac");
        prog = JacProgram();
        prog.compile(file_path);
        warnings = get_warnings_with_code(prog, "W6003");
        warning_msgs = [str(w) for w in warnings];
        assert any("undefined" in w for w in warning_msgs) , f"Expected W6003 warning for 'undefined', got: {warning_msgs}";
    }

    def check_typeof_keyword_produces_w6003_warning {
        file_path = os.path.join(FIXTURES, "js_keywords.jac");
        prog = JacProgram();
        prog.compile(file_path);
        warnings = get_warnings_with_code(prog, "W6003");
        warning_msgs = [str(w) for w in warnings];
        assert any("typeof" in w for w in warning_msgs) , f"Expected W6003 warning for 'typeof', got: {warning_msgs}";
    }

    def check_void_keyword_produces_w6003_warning {
        file_path = os.path.join(FIXTURES, "js_keywords.jac");
        prog = JacProgram();
        prog.compile(file_path);
        warnings = get_warnings_with_code(prog, "W6003");
        warning_msgs = [str(w) for w in warnings];
        assert any("void" in w for w in warning_msgs) , f"Expected W6003 warning for 'void', got: {warning_msgs}";
    }

    def check_js_keywords_produce_correct_count_of_w6003_warni {
        file_path = os.path.join(FIXTURES, "js_keywords.jac");
        prog = JacProgram();
        prog.compile(file_path);
        count = count_warning_code(prog, "W6003");
        # undefined, typeof, void = 3
        assert count >= 3 , f"Expected at least 3 W6003 warnings, got: {count}";
    }

    # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    # W6004: JS-specific properties
    # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    def check_length_property_produces_w6004_warning {
        file_path = os.path.join(FIXTURES, "js_properties.jac");
        prog = JacProgram();
        prog.compile(file_path);
        warnings = get_warnings_with_code(prog, "W6004");
        warning_msgs = [str(w) for w in warnings];
        assert any("length" in w for w in warning_msgs) , f"Expected W6004 warning for '.length', got: {warning_msgs}";
    }

    def check_prototype_property_produces_w6004_warning {
        file_path = os.path.join(FIXTURES, "js_properties.jac");
        prog = JacProgram();
        prog.compile(file_path);
        warnings = get_warnings_with_code(prog, "W6004");
        warning_msgs = [str(w) for w in warnings];
        assert any("prototype" in w for w in warning_msgs) , f"Expected W6004 warning for '.prototype', got: {warning_msgs}";
    }

    def check_js_properties_produce_correct_count_of_w6004_war {
        file_path = os.path.join(FIXTURES, "js_properties.jac");
        prog = JacProgram();
        prog.compile(file_path);
        count = count_warning_code(prog, "W6004");
        # items.length, s.length, MyObj.prototype = 3
        assert count >= 3 , f"Expected at least 3 W6004 warnings, got: {count}";
    }
    run_cases(
        [
            (
                "console usage produces W6001 warning",
                check_console_usage_produces_w6001_warning
            ),
            (
                "Math usage produces W6001 warning",
                check_math_usage_produces_w6001_warning
            ),
            (
                "JSON usage produces W6001 warning",
                check_json_usage_produces_w6001_warning
            ),
            (
                "Array/Object/Map/Set constructors produce W6001 warnings",
                check_array_object_map_set_constructors_produce_w6001
            ),
            (
                "setTimeout/setInterval produce W6001 warnings",
                check_settimeout_setinterval_produce_w6001_warnings
            ),
            (
                "multiple JS globals produce correct count of W6001 warnings",
                check_multiple_js_globals_produce_correct_count_of_w60
            ),
            (
                "push method produces W6002 warning",
                check_push_method_produces_w6002_warning
            ),
            (
                "forEach method produces W6002 warning",
                check_foreach_method_produces_w6002_warning
            ),
            (
                "indexOf method produces W6002 warning",
                check_indexof_method_produces_w6002_warning
            ),
            (
                "string JS methods produce W6002 warnings",
                check_string_js_methods_produce_w6002_warnings
            ),
            (
                "functional methods (every, some, find) produce W6002 warnings",
                check_functional_methods_every_some_find_produce_w6002
            ),
            (
                "find with a lambda callback produces W6002 warning",
                check_find_with_a_lambda_callback_produces_w6002_warni
            ),
            (
                "conversion methods (toFixed, toString) produce W6002 warnings",
                check_conversion_methods_tofixed_tostring_produce_w600
            ),
            (
                "multiple JS methods produce correct count of W6002 warnings",
                check_multiple_js_methods_produce_correct_count_of_w60
            ),
            (
                "undefined keyword produces W6003 warning",
                check_undefined_keyword_produces_w6003_warning
            ),
            (
                "typeof keyword produces W6003 warning",
                check_typeof_keyword_produces_w6003_warning
            ),
            (
                "void keyword produces W6003 warning",
                check_void_keyword_produces_w6003_warning
            ),
            (
                "JS keywords produce correct count of W6003 warnings",
                check_js_keywords_produce_correct_count_of_w6003_warni
            ),
            (
                "length property produces W6004 warning",
                check_length_property_produces_w6004_warning
            ),
            (
                "prototype property produces W6004 warning",
                check_prototype_property_produces_w6004_warning
            ),
            (
                "JS properties produce correct count of W6004 warnings",
                check_js_properties_produce_correct_count_of_w6004_war
            )
        ]
    );
}


test "str.find with string arguments produces no W6002 warning" {
    file_path = os.path.join(FIXTURES, "py_str_find.jac");
    prog = JacProgram();
    prog.compile(file_path);
    warnings = get_warnings_with_code(prog, "W6002");
    warning_msgs = [str(w) for w in warnings];
    assert not any("find" in w for w in warning_msgs) , f"str.find is Python-congruent and must not warn, got: {warning_msgs}";
}


test "user_defined_members.jac cases" {
    def check_user_defined_methods_sharing_js_names_do_not_war {
        file_path = os.path.join(FIXTURES, "user_defined_members.jac");
        prog = JacProgram();
        prog.compile(file_path);

        warnings = get_warnings_with_code(prog, "W6002");
        warning_msgs = [str(w) for w in warnings];
        assert not any("parse" in w for w in warning_msgs) , f"Config.parse is a declared method, must not warn: {warning_msgs}";
        assert not any("assign" in w for w in warning_msgs) , f"Config.assign is a declared method, must not warn: {warning_msgs}";
        # The fixture calls .push twice: once on Config (declared) and once on a
        # bare list (JS idiom). Only the list call may warn.
        push_hits = len(
            [
                w
                for w in warning_msgs
                if "push" in w
            ]
        );
        assert push_hits == 1 , f"Expected exactly the list .push() call to warn, got: {warning_msgs}";
    }

    def check_user_declared_length_field_access_does_not_warn {
        file_path = os.path.join(FIXTURES, "user_defined_members.jac");
        prog = JacProgram();
        prog.compile(file_path);

        warnings = get_warnings_with_code(prog, "W6004");
        warning_msgs = [str(w) for w in warnings];
        # cfg.length resolves to the declared field; items.length stays JS slop.
        length_hits = len(
            [
                w
                for w in warning_msgs
                if "length" in w
            ]
        );
        assert length_hits == 1 , f"Expected exactly the list .length access to warn, got: {warning_msgs}";
    }
    run_cases(
        [
            (
                "user-defined methods sharing JS names do not warn W6002",
                check_user_defined_methods_sharing_js_names_do_not_war
            ),
            (
                "user-declared length field access does not warn W6004",
                check_user_declared_length_field_access_does_not_warn
            )
        ]
    );
}


# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Clean code: no portability warnings
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
test "clean Jac code produces no portability warnings" {
    file_path = os.path.join(FIXTURES, "clean_jac.jac");
    prog = JacProgram();
    prog.compile(file_path);
    portability_warnings = [
        w
        for w in prog.warnings_had
        if w.code is not None and w.code.code.startswith("W6")
    ];
    assert len(portability_warnings) == 0 , f"Expected no portability warnings for clean code, got: {[
        str(w) for w in portability_warnings
    ]}";
}

test "mixed code cases on mixed_usage.jac" {
    # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    # Mixed usage
    # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    def check_mixed_code_produces_warnings_only_for_js_idioms {
        file_path = os.path.join(FIXTURES, "mixed_usage.jac");
        prog = JacProgram();
        prog.compile(file_path);

        # Should have W6001 for console
        assert has_warning_code(prog, "W6001") , "Expected W6001 for console.log in mixed code";
        # Should have W6002 for push, forEach
        assert has_warning_code(prog, "W6002") , "Expected W6002 for .push()/.forEach() in mixed code";
        # Should have W6004 for .length
        assert has_warning_code(prog, "W6004") , "Expected W6004 for .length in mixed code";
    }

    def check_mixed_code_warning_messages_include_alternatives {
        file_path = os.path.join(FIXTURES, "mixed_usage.jac");
        prog = JacProgram();
        prog.compile(file_path);

        w6001_warnings = get_warnings_with_code(prog, "W6001");
        # Check that warning message suggests the alternative
        assert any("print()" in str(w) for w in w6001_warnings) , f"Expected W6001 to suggest 'print()' as alternative, got: {[
            str(w) for w in w6001_warnings
        ]}";
    }
    run_cases(
        [
            (
                "mixed code produces warnings only for JS idioms",
                check_mixed_code_produces_warnings_only_for_js_idioms
            ),
            (
                "mixed code warning messages include alternatives",
                check_mixed_code_warning_messages_include_alternatives
            )
        ]
    );
}
