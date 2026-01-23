"""Jac Super Console Plugin - Rich-enhanced console.

This plugin provides Rich-enhanced console output for Jac CLI.
It overrides the base console implementation to provide elegant,
colorful terminal output with themes, panels, tables, and spinners.
"""
import from jaclang.pycore.runtime { hookimpl, plugin_manager }
import from jaclang.cli.console { JacConsole as BaseJacConsole }
import from argparse { ArgumentParser }

"""Jac Super Plugin for console enhancement."""
class JacSuperPlugin {
    """Register jac-super commands (including overriding core stubs)."""
    @hookimpl
    static def create_cmd -> None {
        # Importing this package triggers registration of its commands via
        # @registry.command decorators (e.g., completion).
        import from jac_super.commands { completion }
    }

    """Get the Rich-enhanced console instance."""
    @hookimpl
    static def get_console -> BaseJacConsole {
        return JacSuperConsole();
    }

    @hookimpl
    static def cli_completion(parser: ArgumentParser) -> None {
        try {
            import argcomplete;
            argcomplete.autocomplete(parser);
        } except Exception { }
    }
}

# Register the plugin during module load
with entry {
    plugin_manager.register(JacSuperPlugin());
}
