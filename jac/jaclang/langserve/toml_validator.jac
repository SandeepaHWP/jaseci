"""Jac TOML config file validator."""

import jaclang.lsp.types as lspt;

def validate_jac_toml(content: str) -> list[lspt.Diagnostic];
def find_key_line(lines: list[str], section: str, key: str) -> int;
def find_section_line(lines: list[str], section: str) -> int;
