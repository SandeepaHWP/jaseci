"""Jac Super Console Plugin - Rich-enhanced console and help formatter.

This plugin provides:
  1. Rich-enhanced console output for Jac CLI (JacSuperConsole).
  2. Rich-formatted argparse help panels via a global argparse monkey-patch.

Both are activated automatically once jac-super is installed.
"""
import argparse;
import sys;
import from typing { Any }
import from jaclang.jac0core.runtime { hookimpl, plugin_manager }
import from jaclang.cli.console { JacConsole as BaseJacConsole }
import from jac_super.plugin.impl.rich_help { rich_format_help }

"""Jac Super Plugin for console and help enhancement."""
class JacSuperPlugin {
    """Get the Rich-enhanced console instance."""
    @hookimpl
    static def get_console -> BaseJacConsole {
        return JacSuperConsole();
    }
}

"""Patch argparse.ArgumentParser.print_help globally with Rich renderer.

By patching at the class level, every ArgumentParser instance (including
those built inside jaclang after this module loads) automatically gets
Rich help output. The original is saved and used as a fallback.
"""
def _install_rich_help_patch -> None {
    _original_print_help = argparse.ArgumentParser.print_help;

    def _rich_print_help(self: Any, file: Any = None) -> None {
        if file is None {
            file = sys.stdout;
        }
        if file is sys.stdout or file is sys.stderr {
            try {
                rich_format_help(self);
            } except Exception {
                _original_print_help(self, file);
            }
        } else {
            _original_print_help(self, file);
        }
    }

    argparse.ArgumentParser.print_help = _rich_print_help;
}

# Register the plugin and install the global Rich help patch
with entry {
    plugin_manager.register(JacSuperPlugin());
    _install_rich_help_patch();
}
