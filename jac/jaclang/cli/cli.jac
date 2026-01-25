"""Command line interface tool for the Jac language.

This module provides the main CLI entry point. Command implementations
are in cli/impl/cli.impl.jac, and command registrations are in cli/commands/.
"""

# Import new registry infrastructure
import from jaclang.cli.registry { get_registry }
import from jaclang.cli.executor { get_executor }

# Import commands module to trigger auto-registration
import from jaclang.cli {
    commands
}

#===============================================================================
# ENTRY POINT
#===============================================================================

# Declaration for the standard CLI implementation (in impl/cli.impl.jac)
def run_standard_cli -> None;

"""Main CLI entry point with optional Typer delegation."""
def start_cli -> None {
     import sys;
    # Try to launch Typer-based CLI from jac-super if available
    try {
        import from jac_super.cli.main { start_cli as super_start_cli }
        super_start_cli();
        return;
    } except ImportError {
        # Fallback to standard CLI
    } except Exception {
        # Fallback to standard CLI
    }
    
    run_standard_cli();
}

with entry:__main__ {
    start_cli();
}
