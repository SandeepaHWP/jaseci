"""Rich-enhanced ArgumentParser for jac-super.

Drop-in replacement for argparse.ArgumentParser that overrides print_help()
to render beautiful Rich panels instead of plain text.
"""
import argparse;
import sys;
import from typing { Any }

import from jac_super.plugin.impl.rich_help { rich_format_help }

"""Argparse subclass that renders help with Rich panels and highlighting."""
class JacSuperArgumentParser(argparse.ArgumentParser) {

    """Override print_help to use Rich renderer."""
    def print_help(self: JacSuperArgumentParser, file: Any = None) -> None {
        if file is None {
            file = sys.stdout;
        }
        # Only use Rich output when printing to stdout/stderr
        if file is sys.stdout or file is sys.stderr {
            try {
                rich_format_help(self);
            } except Exception {
                # Fallback to standard help if Rich fails for any reason
                super().print_help(file);
            }
        } else {
            super().print_help(file);
        }
    }

    """Override format_help to also return Rich-rendered text as a plain string fallback."""
    def format_help(self: JacSuperArgumentParser) -> str {
        # Return standard format_help for programmatic callers
        # (e.g. tests that capture help text as a string)
        return super().format_help();
    }
}
