"""Field declarations validate values and synthesized constructor contracts."""
import from jaclang.compiler.driver.program { JacProgram }
import from jaclang.compiler.driver.compile_options { CompileOptions }
import from tests.support { run_cases }


def check_fields(source: str) -> list[str] {
    program = JacProgram();
    program.compile(
        file_path="object_field_contract.jac",
        use_str=source,
        options=CompileOptions(no_cgen=True, no_ir_cache=True, force_codespace="server")
    );
    return [str(alert) for alert in program.errors_had];
}

test "an aliased ObjectField marker preserves the declared value type" {
    errors = check_fields(
        "import from jaclang.runtime.object_model { ObjectField as declare }\n"
            + "def make_value -> int { return 7; }\n"
            + "obj Example { has value: int = declare(default_factory=make_value); }\n"
            + "def read -> int { return Example().value; }\n"
    );
    assert not errors , str(errors);
}

test "ObjectField markers retain import provenance before type analysis" {
    import from jaclang.compiler.field_semantics { is_field_marker }
    import from jaclang.compiler.frontend.unitree { FuncCall, HasVar }
    program = JacProgram();
    module = program.compile(
        file_path="early_field_marker.jac",
        use_str="import from jaclang.runtime.object_model { ObjectField as declare }\n"
            + "obj Example { has values: list[int] = declare(default_factory=`list); }\n"
            + "def ordinary -> int { return 3; }\n"
            + "obj Other { has value: int = ordinary(); }\n",
        options=CompileOptions(symtab_ir_only=True, need_full_ast=True)
    );
    assert not program.errors_had;
    markers: dict[str, bool] = {};
    for field_var in module.get_all_sub_nodes(HasVar) {
        call = field_var.value;
        assert isinstance(call, FuncCall);
        markers[field_var.name.value] = is_field_marker(call);
    }
    assert markers == {"values": True, "value": False};
}

test "incorrect ObjectField defaults are rejected, and related cases" {
    def check_incorrect_objectfield_defaults_are_rejected {
        errors = check_fields(
            "import from jaclang.runtime.object_model { ObjectField }\n"
                + "obj Example { has value: int = ObjectField(`default='wrong'); }\n"
        );
        assert any("Cannot assign" in error for error in errors) , str(errors);
    }

    def check_a_same_named_ordinary_function_does_not_bypass_a {
        errors = check_fields(
            "def ObjectField -> str { return 'wrong'; }\n"
                + "obj Example { has value: int = ObjectField(); }\n"
        );
        assert any("Cannot assign" in error for error in errors) , str(errors);
    }

    def check_ordinary_object_defaults_validate_without_field {
        errors = check_fields(
            "def make_value -> str { return 'wrong'; }\n"
                + "obj Example { has value: int = make_value(); }\n"
        );
        assert any("Cannot assign" in error for error in errors) , str(errors);
    }
    run_cases(
        [
            (
                "incorrect ObjectField defaults are rejected",
                check_incorrect_objectfield_defaults_are_rejected
            ),
            (
                "a same-named ordinary function does not bypass assignment checking",
                check_a_same_named_ordinary_function_does_not_bypass_a
            ),
            (
                "ordinary object defaults validate without field configuration imports",
                check_ordinary_object_defaults_validate_without_field
            )
        ]
    );
}

test "incorrect factory return types are rejected, and related cases" {
    def check_incorrect_factory_return_types_are_rejected {
        errors = check_fields(
            "import from jaclang.runtime.object_model { ObjectField }\n"
                + "def make_value -> str { return 'wrong'; }\n"
                + "obj Example { has value: int = ObjectField(default_factory=make_value); }\n"
        );
        assert any("Cannot assign" in error for error in errors) , str(errors);
    }

    def check_property_writes_use_the_setter_parameter_rather {
        errors = check_fields(
            "obj Example { has value: int | str { getter { return 3; } "
                + "setter(value: int) {} } }\n"
                + "def update { item = Example(); item.value = 'wrong'; }\n"
        );
        assert any("Cannot assign" in error for error in errors) , str(errors);
    }
    run_cases(
        [
            (
                "incorrect factory return types are rejected",
                check_incorrect_factory_return_types_are_rejected
            ),
            (
                "property writes use the setter parameter rather than the getter result",
                check_property_writes_use_the_setter_parameter_rather
            )
        ]
    );
}

test "factories requiring arguments are rejected, and related cases" {
    def check_factories_requiring_arguments_are_rejected {
        errors = check_fields(
            "import from jaclang.runtime.object_model { ObjectField }\n"
                + "def make_value(arg: int) -> int { return arg; }\n"
                + "obj Example { has value: int = ObjectField(default_factory=make_value); }\n"
        );
        assert errors , "An ObjectField factory must be callable without arguments";
    }

    def check_deferred_fields_are_not_accepted_as_constructor {
        errors = check_fields(
            "import from jaclang.runtime.object_model { ObjectField }\n"
                + "obj Example { has value: int = ObjectField(`init=False); }\n"
                + "def make -> Example { return Example(value=3); }\n"
        );
        assert errors , "An init=False ObjectField must not become a constructor parameter";
    }
    run_cases(
        [
            (
                "factories requiring arguments are rejected",
                check_factories_requiring_arguments_are_rejected
            ),
            (
                "deferred fields are not accepted as constructor arguments",
                check_deferred_fields_are_not_accepted_as_constructor
            )
        ]
    );
}

test "class factories must accept an empty constructor call" {
    for declaration in [
        "obj Item { has required: int; }",
        "class Item { def init(self: Item, required: int) {} }"
    ] {
        errors = check_fields(
            "import from jaclang.runtime.object_model { ObjectField }\n"
                + declaration
                + "\n"
                + "obj Example { has item: Item = ObjectField(default_factory=Item); }\n"
        );
        assert any("required" in error for error in errors) , str(errors);
    }
    errors = check_fields(
        "import from jaclang.runtime.object_model { ObjectField }\n"
            + "obj Item { has value: int = 4; }\n"
            + "obj Example { has item: Item = ObjectField(default_factory=Item), values: list[int] = ObjectField(default_factory=`list); }\n"
    );
    assert not errors , str(errors);
}


test "property setters can accept an optional value while getters remain precise, and related cases" {
    def check_property_setters_can_accept_an_optional_value_wh {
        errors = check_fields(
            "obj Example { has value: int { getter { return 3; } "
                + "setter(value: int | None) {} } }\n"
                + "def update -> int { item = Example(); item.value = None; return item.value + 1; }\n"
        );
        assert not errors , str(errors);
    }

    def check_internal_objectfield_descriptors_remain_supporte {
        errors = check_fields(
            "import from jaclang.runtime.object_model { ObjectField }\n"
                + "obj Example { has values: list[int] = ObjectField(default_factory=`list); }\n"
                + "def read -> list[int] { return Example().values; }\n"
        );
        assert not errors , str(errors);
    }
    run_cases(
        [
            (
                "property setters can accept an optional value while getters remain precise",
                check_property_setters_can_accept_an_optional_value_wh
            ),
            (
                "internal ObjectField descriptors remain supported",
                check_internal_objectfield_descriptors_remain_supporte
            )
        ]
    );
}


test "native deferred declaration excludes the constructor parameter" {
    errors = check_fields(
        "obj Example { has value: int postinit; def postinit { self.value = 3; } }\n"
            + "def make -> Example { return Example(value=3); }\n"
    );
    assert errors , "A postinit field must not become a constructor parameter";
}
