"""Custom recursive descent parser for jac.toml config files."""

import jaclang.lsp.types as lspt;

# ---------------------------------------------------------------------------
# Token types
# ---------------------------------------------------------------------------
enum TomlTokenKind {
    BARE_KEY = "BARE_KEY",
    STRING = "STRING",
    INTEGER = "INTEGER",
    BOOL = "BOOL",
    LBRACKET = "[",
    RBRACKET = "]",
    LBRACE = "{",
    RBRACE = "}",
    COMMA = ",",
    DOT = ".",
    EQUALS = "=",
    NEWLINE = "NEWLINE",
    COMMENT = "COMMENT",
    WS = "WS",
    EOF = "EOF",
    ERROR = "ERROR"
}

# ---------------------------------------------------------------------------
# Source location and token
# ---------------------------------------------------------------------------
obj TomlSourceLoc {
    has line: int = 1,
        col_start: int = 1,
        col_end: int = 1;
}

obj TomlToken {
    has kind: TomlTokenKind,
        value: str = "",
        loc: TomlSourceLoc by postinit;

    def postinit -> None;
}

# ---------------------------------------------------------------------------
# Value / AST nodes
# ---------------------------------------------------------------------------
obj TomlValue {
    has kind: str,          # "string"|"integer"|"bool"|"array"|"inline_table"|"error"
        raw: object = None, # Python value: str, int, bool, list, dict, or None
        tok: TomlToken by postinit;

    def postinit -> None;
}

obj TomlKeyValue {
    has key: str,
        key_tok: TomlToken,
        value: TomlValue,
        section: str = "";
}

obj TomlSection {
    has name: str,
        tok: TomlToken,
        kv_pairs: list = [];
}

obj TomlDocument {
    has top_level: list = [],
        sections: dict = {};

    def add_section(sec: TomlSection) -> None;
    def add_kv(kv: TomlKeyValue, sec_name: str) -> None;
    def lookup(section: str, key: str) -> TomlValue | None;
}

# ---------------------------------------------------------------------------
# Lexer
# ---------------------------------------------------------------------------
obj TomlLexer {
    has source: str,
        pos: int = 0,
        line: int = 1,
        col: int = 1,
        _source_len: int by postinit,
        diags: list = [];

    def postinit -> None;

    def current -> str;
    def peek(offset: int = 1) -> str;
    def advance -> str;
    def at_end -> bool;
    def match_char(ch: str) -> bool;

    def is_bare_key_char(ch: str) -> bool;
    def is_digit(ch: str) -> bool;
    def is_alpha(ch: str) -> bool;

    def make_loc(start_line: int, start_col: int, end_col: int) -> TomlSourceLoc;
    def make_token(kind: TomlTokenKind, value: str, start_line: int, start_col: int, end_col: int) -> TomlToken;
    def emit_lex_error(msg: str, line: int, col: int, col_end: int) -> None;

    def scan_bare_key -> TomlToken;
    def scan_string -> TomlToken;
    def scan_integer -> TomlToken;
    def scan_comment -> TomlToken;
    def scan_whitespace -> TomlToken;
    def next_token -> TomlToken;
    def tokenize -> list;
}

# ---------------------------------------------------------------------------
# Parser
# ---------------------------------------------------------------------------
obj TomlParser {
    has tokens: list,
        pos: int = 0,
        _tokens_len: int by postinit,
        diags: list = [];

    def postinit -> None;

    def current -> TomlToken;
    def peek(offset: int = 1) -> TomlToken;
    def advance -> TomlToken;
    def at_end -> bool;
    def skip_ws -> None;
    def skip_ws_and_newlines -> None;
    def match_tok(kind: TomlTokenKind) -> TomlToken | None;
    def expect(kind: TomlTokenKind) -> TomlToken;

    def emit_error(msg: str, tok: TomlToken) -> None;
    def emit_warn(msg: str, tok: TomlToken) -> None;
    def recover_to_next_line -> None;

    def parse -> TomlDocument;
    def parse_document -> TomlDocument;
    def parse_section_header -> TomlSection;
    def parse_key_value -> TomlKeyValue;
    def parse_key -> str;
    def parse_value -> TomlValue;
    def parse_string -> TomlValue;
    def parse_integer -> TomlValue;
    def parse_bool -> TomlValue;
    def parse_array -> TomlValue;
    def parse_inline_table -> TomlValue;
}

# ---------------------------------------------------------------------------
# Module-level entry point
# ---------------------------------------------------------------------------
def toml_parse(content: str) -> tuple;
