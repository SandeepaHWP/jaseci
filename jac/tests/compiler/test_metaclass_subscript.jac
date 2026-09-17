"""Subscripting a class object runs its metaclass `__getitem__` before generic
specialization, the way Python resolves `Cls[x]`."""

import from jaclang.compiler.driver.program { JacProgram }
import from jaclang.compiler.driver.compile_options { CompileOptions }

def check_src(src: str) -> list[str] {
    prog = JacProgram();
    prog.compile(
        file_path="metasub.jac", use_str=src, options=CompileOptions(no_cgen=True)
    );
    return [str(e) for e in prog.errors_had];
}

test "enum member lookup by name types as that enum" {
    src = "import from enum { StrEnum }\n"
        + "class Tokens(StrEnum) {\n    A = 'a';\n}\n"
        + "class Other(StrEnum) {\n    B = 'b';\n}\n"
        + "def probe -> Tokens {\n    return Tokens['A'];\n}\n";
    errs = check_src(src);
    assert not errs , errs;
}

glob META_SRC: str = "class Meta(type) {\n"
         + "    def __getitem__(cls: Meta, key: str) -> int {\n        return len(key);\n    }\n"
         + "}\n"
         + "class Foo(metaclass=Meta) {}\n";

test "a user metaclass __getitem__ is dispatched from the class object" {
    errs = check_src(META_SRC + "def probe -> int {\n    return Foo['abc'];\n}\n");
    assert not errs , errs;
}

test "invalid keys to a metaclass __getitem__ are reported" {
    for key in ["123", "1:3"] {
        errs = check_src(META_SRC + f"def probe -> None {{\n    x = Foo[{key}];\n}}\n");
        assert errs and "parameter 'key'" in " ".join(errs) , (key, errs);
    }
}

test "generic classes without a metaclass __getitem__ still specialize" {
    src = "import from abc { ABC }\n"
        + "obj Box[T] {\n    has item: T;\n}\n"
        + "obj Node[T](ABC) {\n    has item: T;\n}\n"
        + "def probe -> Box[int] {\n    return Box[int](item=3);\n}\n"
        + "def probe_abc -> Node[int] {\n    return Node[int](item=1);\n}\n";
    errs = check_src(src);
    assert not errs , errs;
}
