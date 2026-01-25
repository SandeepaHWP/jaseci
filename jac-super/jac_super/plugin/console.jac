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
        def completion -> int {
            # 1. Get the shell path (e.g., '/bin/zsh') and extract the name ('zsh')
            shell_path = os.environ.get("SHELL", "/bin/bash");
            shell_name = os.path.basename(shell_path);

            # 2. Map shell names to their config files
            rc_map = {"bash": "~/.bashrc", "zsh": "~/.zshrc"};

            if shell_name not in rc_map {
                print(f"Could not auto-install for detected shell: {shell_name}");
                print("Invalid shell Type");
                return 1;
            }

            target_file = rc_map[shell_name];

            # 3. Append the completion logic to the config file
            print(f"Detected {shell_name}. Installing to {target_file}...");
            os.system(
                f"register-python-argcomplete --shell={shell_name} jac >> {target_file}"
            );

            print(f"Done! Restart your shell or run: source {target_file}");
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
