"""Shell completion setup command.

This command provides shell completion setup for jac.
The implementation is provided by plugins (e.g., jac-super).
"""

import from jaclang.cli.command { Arg, ArgKind }
import from jaclang.cli.registry { get_registry }

glob registry = get_registry();

"""Register shell completion for jac."""
@registry.command(
    name="completion",
    help="Setup shell completion for jac",
    args=[
        Arg.create(
            "shell", kind=ArgKind.POSITIONAL, help="Shell type (bash, zsh, fish)"
        ),

    ],
    group="tools"
)
def completion(shell: str) -> int { }
