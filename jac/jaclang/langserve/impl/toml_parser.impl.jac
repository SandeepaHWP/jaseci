"""Recursive descent lexer + parser for jac.toml config files."""

# ===========================================================================
# TomlToken postinit
# ===========================================================================
impl TomlToken.postinit -> None {
    if not hasattr(self, 'loc') or self.loc is None {
        self.loc = TomlSourceLoc();
    }
}

# ===========================================================================
# TomlValue postinit
# ===========================================================================
impl TomlValue.postinit -> None {
    if not hasattr(self, 'tok') or self.tok is None {
        self.tok = TomlToken(kind=TomlTokenKind.EOF, value="");
    }
}

# ===========================================================================
# TomlDocument
# ===========================================================================
impl TomlDocument.add_section(sec: TomlSection) -> None {
    self.sections[sec.name] = sec;
}

impl TomlDocument.add_kv(kv: TomlKeyValue, sec_name: str) -> None {
    kv.section = sec_name;
    if sec_name == "" {
        self.top_level.append(kv);
    } else {
        if sec_name in self.sections {
            self.sections[sec_name].kv_pairs.append(kv);
        }
    }
}

impl TomlDocument.lookup(section: str, key: str) -> TomlValue | None {
    sec = self.sections.get(section);
    if sec is None {
        return None;
    }
    for kv in sec.kv_pairs {
        if kv.key == key {
            return kv.value;
        }
    }
    return None;
}

# ===========================================================================
# TomlLexer
# ===========================================================================
impl TomlLexer.postinit -> None {
    self._source_len = len(self.source);
}

impl TomlLexer.current -> str {
    if self.pos < self._source_len {
        return self.source[self.pos];
    }
    return "";
}

impl TomlLexer.peek(offset: int = 1) -> str {
    idx = self.pos + offset;
    if idx < self._source_len {
        return self.source[idx];
    }
    return "";
}

impl TomlLexer.advance -> str {
    ch = self.current();
    self.pos += 1;
    if ch == "\n" {
        self.line += 1;
        self.col = 1;
    } else {
        self.col += 1;
    }
    return ch;
}

impl TomlLexer.at_end -> bool {
    return self.pos >= self._source_len;
}

impl TomlLexer.match_char(ch: str) -> bool {
    if self.current() == ch {
        self.advance();
        return True;
    }
    return False;
}

impl TomlLexer.is_bare_key_char(ch: str) -> bool {
    return ch.isalnum() or ch == "_" or ch == "-";
}

impl TomlLexer.is_digit(ch: str) -> bool {
    return ch.isdigit();
}

impl TomlLexer.is_alpha(ch: str) -> bool {
    return ch.isalpha();
}

impl TomlLexer.make_loc(start_line: int, start_col: int, end_col: int) -> TomlSourceLoc {
    loc = TomlSourceLoc();
    loc.line = start_line;
    loc.col_start = start_col;
    loc.col_end = end_col;
    return loc;
}

impl TomlLexer.make_token(
    kind: TomlTokenKind, value: str,
    start_line: int, start_col: int, end_col: int
) -> TomlToken {
    tok = TomlToken(kind=kind, value=value);
    tok.loc = self.make_loc(start_line, start_col, end_col);
    return tok;
}

impl TomlLexer.emit_lex_error(msg: str, line: int, col: int, col_end: int) -> None {
    self.diags.append(
        lspt.Diagnostic(
            range=lspt.Range(
                start=lspt.Position(line=line - 1, character=col - 1),
                end=lspt.Position(line=line - 1, character=col_end - 1)
            ),
            message=msg,
            severity=lspt.DiagnosticSeverity.Error,
            source="jac-toml"
        )
    );
}

impl TomlLexer.scan_bare_key -> TomlToken {
    start_line = self.line;
    start_col = self.col;
    value = "";
    while not self.at_end() and self.is_bare_key_char(self.current()) {
        value += self.advance();
    }
    # Reclassify true/false as BOOL
    if value == "true" or value == "false" {
        return self.make_token(TomlTokenKind.BOOL, value, start_line, start_col, self.col);
    }
    return self.make_token(TomlTokenKind.BARE_KEY, value, start_line, start_col, self.col);
}

impl TomlLexer.scan_string -> TomlToken {
    start_line = self.line;
    start_col = self.col;

    # Detect quote style
    quote_char = self.current();
    self.advance();  # consume first quote

    # Check for triple-quote
    is_triple = False;
    is_literal = (quote_char == "'");
    if self.current() == quote_char and self.peek() == quote_char {
        is_triple = True;
        self.advance();  # consume second quote
        self.advance();  # consume third quote
    }

    value = "";
    closed = False;

    if is_triple {
        # Consume until matching triple-quote
        while not self.at_end() {
            if (
                self.current() == quote_char
                and self.peek() == quote_char
                and self.peek(2) == quote_char
            ) {
                self.advance();
                self.advance();
                self.advance();
                closed = True;
                break;
            }
            value += self.advance();
        }
    } else {
        # Single-quoted string - consume until closing quote or newline
        while not self.at_end() {
            ch = self.current();
            if ch == "\n" {
                break;  # unclosed string - will emit error below
            }
            if ch == quote_char {
                self.advance();  # consume closing quote
                closed = True;
                break;
            }
            if ch == "\\" and not is_literal {
                # Basic string escape
                self.advance();  # consume backslash
                if not self.at_end() {
                    value += "\\" + self.advance();
                }
            } else {
                value += self.advance();
            }
        }
    }

    if not closed {
        self.emit_lex_error(
            f"Unclosed string starting with {quote_char!r}",
            start_line, start_col, self.col
        );
    }
    return self.make_token(TomlTokenKind.STRING, value, start_line, start_col, self.col);
}

impl TomlLexer.scan_integer -> TomlToken {
    start_line = self.line;
    start_col = self.col;
    value = "";
    while not self.at_end() and (self.is_digit(self.current()) or self.current() == "_") {
        value += self.advance();
    }
    return self.make_token(TomlTokenKind.INTEGER, value, start_line, start_col, self.col);
}

impl TomlLexer.scan_comment -> TomlToken {
    start_line = self.line;
    start_col = self.col;
    value = "";
    while not self.at_end() and self.current() != "\n" {
        value += self.advance();
    }
    return self.make_token(TomlTokenKind.COMMENT, value, start_line, start_col, self.col);
}

impl TomlLexer.scan_whitespace -> TomlToken {
    start_line = self.line;
    start_col = self.col;
    value = "";
    while not self.at_end() and self.current() in (" ", "\t", "\r") {
        value += self.advance();
    }
    return self.make_token(TomlTokenKind.WS, value, start_line, start_col, self.col);
}

impl TomlLexer.next_token -> TomlToken {
    if self.at_end() {
        return self.make_token(TomlTokenKind.EOF, "", self.line, self.col, self.col);
    }

    ch = self.current();
    start_line = self.line;
    start_col = self.col;

    # Whitespace (spaces, tabs, carriage returns)
    if ch in (" ", "\t", "\r") {
        return self.scan_whitespace();
    }

    # Newline
    if ch == "\n" {
        self.advance();
        return self.make_token(TomlTokenKind.NEWLINE, "\n", start_line, start_col, self.col);
    }

    # Comment
    if ch == "#" {
        return self.scan_comment();
    }

    # Single-char structural tokens
    if ch == "[" {
        self.advance();
        return self.make_token(TomlTokenKind.LBRACKET, "[", start_line, start_col, self.col);
    }
    if ch == "]" {
        self.advance();
        return self.make_token(TomlTokenKind.RBRACKET, "]", start_line, start_col, self.col);
    }
    if ch == "{" {
        self.advance();
        return self.make_token(TomlTokenKind.LBRACE, "{", start_line, start_col, self.col);
    }
    if ch == "}" {
        self.advance();
        return self.make_token(TomlTokenKind.RBRACE, "}", start_line, start_col, self.col);
    }
    if ch == "," {
        self.advance();
        return self.make_token(TomlTokenKind.COMMA, ",", start_line, start_col, self.col);
    }
    if ch == "." {
        self.advance();
        return self.make_token(TomlTokenKind.DOT, ".", start_line, start_col, self.col);
    }
    if ch == "=" {
        self.advance();
        return self.make_token(TomlTokenKind.EQUALS, "=", start_line, start_col, self.col);
    }

    # Strings
    if ch in ('"', "'") {
        return self.scan_string();
    }

    # Digits → integer
    if self.is_digit(ch) {
        return self.scan_integer();
    }

    # Alpha/underscore/hyphen → bare key (also catches true/false)
    if self.is_alpha(ch) or ch == "_" or ch == "-" {
        return self.scan_bare_key();
    }

    # Unknown character
    self.advance();
    self.emit_lex_error(f"Unexpected character {ch!r}", start_line, start_col, self.col);
    return self.make_token(TomlTokenKind.ERROR, ch, start_line, start_col, self.col);
}

impl TomlLexer.tokenize -> list {
    tokens = [];
    while True {
        tok = self.next_token();
        tokens.append(tok);
        if tok.kind == TomlTokenKind.EOF {
            break;
        }
    }
    return tokens;
}

# ===========================================================================
# TomlParser
# ===========================================================================
impl TomlParser.postinit -> None {
    self._tokens_len = len(self.tokens);
}

impl TomlParser.current -> TomlToken {
    if self.pos < self._tokens_len {
        return self.tokens[self.pos];
    }
    return self.tokens[-1];  # EOF
}

impl TomlParser.peek(offset: int = 1) -> TomlToken {
    idx = self.pos + offset;
    if idx < self._tokens_len {
        return self.tokens[idx];
    }
    return self.tokens[-1];  # EOF
}

impl TomlParser.advance -> TomlToken {
    tok = self.current();
    if self.pos < self._tokens_len - 1 {
        self.pos += 1;
    }
    return tok;
}

impl TomlParser.at_end -> bool {
    return self.current().kind == TomlTokenKind.EOF;
}

impl TomlParser.skip_ws -> None {
    while self.current().kind in (TomlTokenKind.WS, TomlTokenKind.COMMENT) {
        self.advance();
    }
}

impl TomlParser.skip_ws_and_newlines -> None {
    while self.current().kind in (
        TomlTokenKind.WS, TomlTokenKind.COMMENT, TomlTokenKind.NEWLINE
    ) {
        self.advance();
    }
}

impl TomlParser.match_tok(kind: TomlTokenKind) -> TomlToken | None {
    if self.current().kind == kind {
        return self.advance();
    }
    return None;
}

impl TomlParser.expect(kind: TomlTokenKind) -> TomlToken {
    if self.current().kind == kind {
        return self.advance();
    }
    tok = self.current();
    self.emit_error(
        f"Expected '{kind.value}', got '{tok.value or tok.kind.value}'",
        tok
    );
    return tok;  # do NOT advance - let caller decide recovery
}

impl TomlParser.emit_error(msg: str, tok: TomlToken) -> None {
    self.diags.append(
        lspt.Diagnostic(
            range=lspt.Range(
                start=lspt.Position(
                    line=tok.loc.line - 1,
                    character=tok.loc.col_start - 1
                ),
                end=lspt.Position(
                    line=tok.loc.line - 1,
                    character=max(tok.loc.col_end - 1, tok.loc.col_start)
                )
            ),
            message=msg,
            severity=lspt.DiagnosticSeverity.Error,
            source="jac-toml"
        )
    );
}

impl TomlParser.emit_warn(msg: str, tok: TomlToken) -> None {
    self.diags.append(
        lspt.Diagnostic(
            range=lspt.Range(
                start=lspt.Position(
                    line=tok.loc.line - 1,
                    character=tok.loc.col_start - 1
                ),
                end=lspt.Position(
                    line=tok.loc.line - 1,
                    character=max(tok.loc.col_end - 1, tok.loc.col_start)
                )
            ),
            message=msg,
            severity=lspt.DiagnosticSeverity.Warning,
            source="jac-toml"
        )
    );
}

impl TomlParser.recover_to_next_line -> None {
    while not self.at_end() and self.current().kind != TomlTokenKind.NEWLINE {
        self.advance();
    }
    if self.current().kind == TomlTokenKind.NEWLINE {
        self.advance();
    }
}

# ---------------------------------------------------------------------------
# Parse rules
# ---------------------------------------------------------------------------
impl TomlParser.parse_key -> str {
    tok = self.current();
    if tok.kind in (TomlTokenKind.BARE_KEY, TomlTokenKind.INTEGER) {
        self.advance();
        return tok.value;
    }
    if tok.kind == TomlTokenKind.STRING {
        self.advance();
        return tok.value;  # raw value (quotes already stripped by lexer)
    }
    if tok.kind == TomlTokenKind.BOOL {
        # true/false are valid bare keys in TOML
        self.advance();
        return tok.value;
    }
    self.emit_error(
        f"Expected a key (identifier or quoted string), got '{tok.value or tok.kind.value}'",
        tok
    );
    return "";
}

impl TomlParser.parse_string -> TomlValue {
    tok = self.advance();
    v = TomlValue(kind="string", raw=tok.value);
    v.tok = tok;
    return v;
}

impl TomlParser.parse_integer -> TomlValue {
    tok = self.advance();
    try {
        raw = int(tok.value.replace("_", ""));
    } except ValueError {
        self.emit_error(f"Invalid integer value '{tok.value}'", tok);
        raw = 0;
    }
    v = TomlValue(kind="integer", raw=raw);
    v.tok = tok;
    return v;
}

impl TomlParser.parse_bool -> TomlValue {
    tok = self.advance();
    v = TomlValue(kind="bool", raw=(tok.value == "true"));
    v.tok = tok;
    return v;
}

impl TomlParser.parse_array -> TomlValue {
    lbrak = self.advance();  # consume "["
    items = [];
    self.skip_ws_and_newlines();

    while not self.at_end() and self.current().kind != TomlTokenKind.RBRACKET {
        items.append(self.parse_value());
        self.skip_ws_and_newlines();

        if self.current().kind == TomlTokenKind.COMMA {
            self.advance();
            self.skip_ws_and_newlines();
        } elif self.current().kind != TomlTokenKind.RBRACKET {
            self.emit_error(
                f"Expected ',' or ']' in array, got '{self.current().value or self.current().kind.value}'",
                self.current()
            );
            break;
        }
    }

    self.skip_ws_and_newlines();
    if self.current().kind == TomlTokenKind.RBRACKET {
        self.advance();
    } else {
        self.emit_error("Unclosed array, expected ']'", self.current());
    }
    v = TomlValue(kind="array", raw=items);
    v.tok = lbrak;
    return v;
}

impl TomlParser.parse_inline_table -> TomlValue {
    lbrace = self.advance();  # consume "{"
    items = {};
    self.skip_ws();

    if self.current().kind != TomlTokenKind.RBRACE {
        key = self.parse_key();
        self.skip_ws();
        self.expect(TomlTokenKind.EQUALS);
        self.skip_ws();
        val = self.parse_value();
        items[key] = val.raw;
        self.skip_ws();

        while self.current().kind == TomlTokenKind.COMMA {
            self.advance();
            self.skip_ws();
            if self.current().kind == TomlTokenKind.RBRACE {
                break;  # trailing comma
            }
            key = self.parse_key();
            self.skip_ws();
            self.expect(TomlTokenKind.EQUALS);
            self.skip_ws();
            val = self.parse_value();
            items[key] = val.raw;
            self.skip_ws();
        }
    }

    if self.current().kind == TomlTokenKind.RBRACE {
        self.advance();
    } else {
        self.emit_error("Unclosed inline table, expected '}'", self.current());
    }
    v = TomlValue(kind="inline_table", raw=items);
    v.tok = lbrace;
    return v;
}

impl TomlParser.parse_value -> TomlValue {
    self.skip_ws();
    tok = self.current();

    if tok.kind == TomlTokenKind.STRING {
        return self.parse_string();
    }
    if tok.kind == TomlTokenKind.INTEGER {
        return self.parse_integer();
    }
    if tok.kind == TomlTokenKind.BOOL {
        return self.parse_bool();
    }
    if tok.kind == TomlTokenKind.LBRACKET {
        return self.parse_array();
    }
    if tok.kind == TomlTokenKind.LBRACE {
        return self.parse_inline_table();
    }

    self.emit_error(
        f"Expected a value (string, number, bool, array, or inline table), got '{tok.value or tok.kind.value}'",
        tok
    );
    # Return sentinel - semantic validator will skip type checking for this
    ev = TomlValue(kind="error", raw=None);
    ev.tok = tok;
    return ev;
}

impl TomlParser.parse_key_value -> TomlKeyValue {
    key_tok = self.current();
    key = self.parse_key();
    self.skip_ws();

    if self.current().kind != TomlTokenKind.EQUALS {
        self.emit_error(
            f"Expected '=' after key '{key}', got '{self.current().value or self.current().kind.value}'",
            self.current()
        );
        # Try to recover by parsing value anyway if something follows on this line
        if self.current().kind not in (TomlTokenKind.NEWLINE, TomlTokenKind.EOF) {
            val = self.parse_value();
        } else {
            ev = TomlValue(kind="error", raw=None);
            ev.tok = self.current();
            val = ev;
        }
        return TomlKeyValue(key=key, key_tok=key_tok, value=val);
    }

    self.advance();  # consume "="
    self.skip_ws();
    val = self.parse_value();
    return TomlKeyValue(key=key, key_tok=key_tok, value=val);
}

impl TomlParser.parse_section_header -> TomlSection {
    self.advance();  # consume "["
    self.skip_ws();

    # Parse dotted key - save first key token to use as the section's loc
    parts = [];
    first_key_tok = self.current();
    first_key = self.parse_key();
    parts.append(first_key);
    self.skip_ws();

    while self.current().kind == TomlTokenKind.DOT {
        self.advance();  # consume "."
        self.skip_ws();
        parts.append(self.parse_key());
        self.skip_ws();
    }

    sec_name = ".".join(parts);

    if self.current().kind == TomlTokenKind.RBRACKET {
        self.advance();
    } else {
        self.emit_error(
            f"Expected ']' to close section header '[{sec_name}', got '{self.current().value or self.current().kind.value}'",
            self.current()
        );
        # Don't advance - let the caller's newline recovery handle it

    }

    return TomlSection(name=sec_name, tok=first_key_tok);
}

impl TomlParser.parse_document -> TomlDocument {
    doc = TomlDocument();
    current_section_name = "";

    while not self.at_end() {
        last_pos = self.pos;  # stuck-detection
        self.skip_ws();

        tok = self.current();

        if tok.kind == TomlTokenKind.NEWLINE {
            self.advance();  # blank line
            continue;
        }

        if tok.kind == TomlTokenKind.COMMENT {
            self.advance();
            continue;
        }

        if tok.kind == TomlTokenKind.EOF {
            break;
        }

        if tok.kind == TomlTokenKind.LBRACKET {
            sec = self.parse_section_header();
            self.skip_ws();
            # Expect newline or end of file after section header
            if self.current().kind not in (TomlTokenKind.NEWLINE, TomlTokenKind.COMMENT, TomlTokenKind.EOF) {
                self.emit_error(
                    f"Expected newline after section header '[{sec.name}]'",
                    self.current()
                );
                self.recover_to_next_line();
            } elif self.current().kind == TomlTokenKind.NEWLINE {
                self.advance();
            }
            doc.add_section(sec);
            current_section_name = sec.name;
            continue;
        }

        if tok.kind in (
            TomlTokenKind.BARE_KEY, TomlTokenKind.STRING,
            TomlTokenKind.INTEGER, TomlTokenKind.BOOL
        ) {
            kv = self.parse_key_value();
            self.skip_ws();
            # Expect newline or end of file after key-value
            if self.current().kind not in (TomlTokenKind.NEWLINE, TomlTokenKind.COMMENT, TomlTokenKind.EOF) {
                self.emit_error(
                    f"Expected newline after key '{kv.key}', got '{self.current().value or self.current().kind.value}'",
                    self.current()
                );
                self.recover_to_next_line();
            } elif self.current().kind == TomlTokenKind.NEWLINE {
                self.advance();
            }
            doc.add_kv(kv, current_section_name);
            continue;
        }

        # Unexpected token at top level
        self.emit_error(
            f"Unexpected '{tok.value or tok.kind.value}' - expected a key, '[', or newline",
            tok
        );
        self.recover_to_next_line();

        # Stuck-detection: if we haven't advanced, force progress
        if self.pos == last_pos {
            self.advance();
        }
    }

    return doc;
}

impl TomlParser.parse -> TomlDocument {
    return self.parse_document();
}

# ===========================================================================
# Module-level entry point
# ===========================================================================
impl toml_parse(content: str) -> tuple {
    lexer = TomlLexer(source=content);
    tokens = lexer.tokenize();
    parser = TomlParser(tokens=tokens, diags=list(lexer.diags));
    doc = parser.parse();
    return (doc, parser.diags);
}
