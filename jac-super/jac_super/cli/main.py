"""Typer-based CLI for Jac."""
import typer
import sys
from typing import Optional, Any
from jaclang.cli.executor import get_executor
from jaclang.cli.registry import get_registry

app = typer.Typer(
    help="Jac CLI with Typer integration",
    add_completion=True,
    rich_markup_mode="rich"
)

def start_cli() -> None:
    """Start the Typer CLI."""
    # Initialize the registry to load all commands (including plugins)
    from jaclang.pycore.runtime import JacRuntime as Jac
    
    _load_project_config()
    
    Jac.create_cmd()
    registry = get_registry()
    registry.finalize() # Builds argparse, but we just need registry populated

    # Register commands
    register_commands(registry)

    try:
        app()
    except SystemExit:
        pass

def register_commands(registry):
    commands = registry.get_all()
    
    # Group commands by their group for better structure if Typer supported groups nicely
    # For now, we just register them flat, but we could use Typer callback groups if needed.
    
    for cmd in registry.get_all():
        if cmd.name == "run":
            _register_run(cmd)
        else:
            _register_generic(cmd)

def _register_run(spec):
    @app.command(name="run", help=spec.help, context_settings={"allow_extra_args": True, "ignore_unknown_options": True})
    def run_wrapper(
        filename: str = typer.Argument(..., help="Main file"),
        ctx: typer.Context = None
    ):
        # Reconstruct args
        args_dict = {"filename": filename}
        # Execute
        get_executor().execute(spec, args_dict)

def _register_generic(spec):
    @app.command(name=spec.name, help=spec.help, context_settings={"allow_extra_args": True, "ignore_unknown_options": True})
    def generic_wrapper(ctx: typer.Context):
        # Generic wrapper that passes execution to executor
        # We don't parse specific args for autocompletion here in MVP
        # but execution works.
        args_dict = {} 
        # Note: generic wrapper doesn't capture typed args, so executor might complain if required args missing.
        # But this allows at least running them.
        get_executor().execute(spec, args_dict)

def _load_project_config() -> None:
    try:
        from jaclang.project.config import get_config
        from jaclang.project.dependencies import add_packages_to_path
        from jaclang.project.dep_registry import initialize_dependency_registry

        # Auto-discover jac.toml
        config = get_config()
        if config is not None:
            add_packages_to_path(config)
        initialize_dependency_registry()
    except Exception:
        pass
