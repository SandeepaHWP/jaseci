"""Jac Super - Enhanced console output for Jac CLI.

This package provides Rich-enhanced console output for Jac CLI commands,
offering elegant, colorful terminal output with themes, panels, tables, and spinners.
"""

__version__ = "0.1.0"


def completion_override() -> None:
    """Override the completion command handler with jac-super's implementation.

    This is called when the plugin module is loaded to inject the actual
    completion implementation into the stub command defined in jac core.
    """
    try:
        from jac_super.commands.completion import completion
        from jaclang.cli.registry import get_registry

        registry = get_registry()
        command_spec = registry.get("completion")
        if command_spec:
            command_spec.handler = completion
    except Exception:
        # If override fails, the stub handler will be used instead
        pass


# Set up completion handler override at initialization
completion_override()
