"""Jac Super Console Plugin - Rich-enhanced console.

This plugin provides Rich-enhanced console output for Jac CLI.
It overrides the base console implementation to provide elegant,
colorful terminal output with themes, panels, tables, and spinners.
"""
import os;
import subprocess;
import from jaclang.pycore.runtime { hookimpl, plugin_manager }
import from jaclang.cli.console { JacConsole as BaseJacConsole }
import from argparse { ArgumentParser }
import from jaclang.cli.command { Arg, ArgKind, CommandPriority }
import from jaclang.cli.registry { get_registry }

"""Jac Super Plugin for console enhancement."""
class JacSuperPlugin {
    """Register jac-super commands (including overriding core stubs)."""
    @hookimpl
    static def create_cmd -> None {
        registry = get_registry();

        @registry.command(
            name="completion",
            help="Setup shell completion for jac",
            args=[
                Arg.create(
                    "shell", kind=ArgKind.POSITIONAL, help="Shell type (bash, zsh)"
                ),

            ],
            group="tools",
            source="jac-super",
            priority=CommandPriority.PLUGIN
        )
        def completion(shell: str) -> int {
            # Map shell to config file
            rc_map = {"bash": "~/.bashrc", "zsh": "~/.zshrc"};
            if shell not in rc_map {
                return 1;
            }

            target_file = rc_map[shell];

            # 1. Use os.system to run the command AND append (>>) to the file in one go
            # 2. We use '>>' so it adds to the end of the file automatically
            cmd = f"register-python-argcomplete --shell={shell} jac >> {target_file}";

            print(f"Installing completion to {target_file}...");
            os.system(cmd);

            print(f"Done! Run this to activate: source {target_file}");
            return 0;
        }
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
