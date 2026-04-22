"""Jac TOML config file validator."""

import jaclang.lsp.types as lspt;

def validate_jac_toml(content: str) -> list[lspt.Diagnostic];
