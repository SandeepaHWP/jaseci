"""Jac Argcomplete Plugin - Shell completion support.

This plugin provides shell tab completion for Jac CLI via argcomplete.
It registers completion on CLI startup so shells can auto-complete commands.
"""
import from jaclang.pycore.runtime { hookimpl, plugin_manager }
import from typing { Any }

"""Jac Argcomplete Plugin for shell completion."""
class JacArgcompletePlugin {
    """Register shell completion on CLI startup."""
    @hookimpl
    static def on_cli_startup(parser: Any) -> None {
        try {
            import argcomplete;
            argcomplete.autocomplete(parser);
        } except Exception {
            pass;
        }
    }
}

# Register the plugin
with entry {
    plugin_manager.register(JacArgcompletePlugin());
}
