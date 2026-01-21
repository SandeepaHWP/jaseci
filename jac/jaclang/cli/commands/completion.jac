"""Shell completion setup command.

Allows users to easily register shell completions for jac.
"""

import from jaclang.cli.command { Arg, ArgKind }
import from jaclang.cli.registry { get_registry }
import from jaclang.cli.console { console }

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
def completion(shell: str) -> int;
