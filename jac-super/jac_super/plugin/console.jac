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
            def _setup_argcomplete(shell: str, config_file: str) -> None {
                print(f"Setting up {shell} completion...");

                try {
                    result = subprocess.run(
                        ["register-python-argcomplete", f"--shell={shell}", "jac"],
                        capture_output=True,
                        text=True,
                        check=True
                    );

                    completion_code = result.stdout;

                    # Check if already registered (idempotent)
                    if os.path.exists(config_file) {
                        with open(config_file, 'r') as f {
                            existing = f.read();
                            if "python_argcomplete" in existing {
                                print(
                                    f"Completion already registered in {config_file}"
                                );
                                return;
                            }
                        }
                    }

                    # Append to config file
                    with open(config_file, 'a') as f {
                        f.write(
                            '\n\n# jac shell completion (added by jac completion)\n'
                        );
                        f.write(completion_code);
                    }

                    print(f"Completion registered in {config_file}");
                    print(f"Reload your shell: source {config_file}");
                } except FileNotFoundError {
                    print("register-python-argcomplete not found");
                    print("Install argcomplete: pip install argcomplete");
                    raise ;
                } except Exception as e {
                    print(f"Failed to register completion: {str(e)}");
                    raise ;
                }
            }

            # Map shell names to config files
            shell_map = {"bash": ("~/.bashrc", "bash"), "zsh": ("~/.zshrc", "zsh"),};
            if shell not in shell_map {
                print(f"Unsupported shell: {shell}");
                print("Supported shells: bash, zsh");
                return 1;
            }
            config_file = shell_map[shell][0];
            shell_type = shell_map[shell][1];
            expanded_path = os.path.expanduser(config_file);
            try {
                _setup_argcomplete(shell_type, expanded_path);
                return 0;
            } except Exception as e {
                print(f"Failed to setup completion: {str(e)}");
                return 1;
            }
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
