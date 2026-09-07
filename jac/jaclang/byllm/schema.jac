import from dataclasses { is_dataclass }
import from enum { Enum }
import from types { FunctionType, MethodType, UnionType }
import from typing { Union, get_args, get_origin, get_type_hints }
import from jaclang.byllm._optdeps.pydantic { TypeAdapter }
import from jaclang.compiler.driver.mtp {
    Info,
    VarInfo,
    FieldInfo,
    ClassInfo,
    ParamInfo,
    EnumInfo,
    FunctionInfo
}
import from jaclang.byllm.exceptions { ConfigurationError }

glob _SCHEMA_OBJECT_WRAPPER = "schema_object_wrapper",
     _SCHEMA_DICT_WRAPPER = "schema_dict_wrapper";

def _as_info(v: object) -> (Info | str | tuple[any, ...] | None);
def _info_at(
    info: (Info | str | tuple[any, ...] | None), idx: int
) -> (Info | str | tuple[any, ...] | None);

def _type_to_schema(
    ty: type,
    title: str = "",
    desc: str = "",
    info: (Info | str | tuple[any, ...] | None) = None
) -> dict[any, any];

def _function_to_schema(
    fn: Callable, title: str = "", info: (Info | str | tuple[any, ...] | None) = None
) -> dict[any, any];

def _name_of_type(ty: type, info: (Info | str | tuple[any, ...] | None) = None) -> str;
def _convert_dict_to_schema(ty_dict: type) -> dict[any, any];
def _decode_dict(json_obj: dict[any, any]) -> dict[any, any];
def _wrap_to_object(schema: dict[str, object]) -> dict[str, object];
def _unwrap_from_object(json_obj: dict[any, any]) -> dict[any, any];
def type_to_schema(
    resp_type: type, info: (Info | str | tuple[any, ...] | None) = None
) -> dict[str, object];

def tool_to_schema(
    func: Callable, description: str, params_desc: dict[str, str], info: (Info | None)
) -> dict[str, object];

def json_to_instance(json_obj: dict[any, any], ty: type) -> object;

def _format_enum_hint(values: list[any], names: list[any]) -> str;

def _hints_from_schema(name: str, prop: dict[any, any]) -> list[str];

def schema_to_hint_text(rf: dict[any, any] | None) -> str;

def attach_schema_hint(messages: list[any], rf: dict[any, any] | None) -> list[any];

def inject_schema_hint(params: dict[any, any]) -> dict[any, any];
