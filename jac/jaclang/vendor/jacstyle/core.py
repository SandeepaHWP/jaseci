
import argparse
import sys
import io
from typing import Any, Optional, Sequence, Union

from . import rich_utils

class JacArgumentParser(argparse.ArgumentParser):
    """
    An argparse.ArgumentParser subclass that uses Rich for formatting help output.
    """
    
    def __init__(
        self,
        *args: Any,
        rich_markup_mode: str = "rich",
        **kwargs: Any
    ) -> None:
        super().__init__(*args, **kwargs)
        self.rich_markup_mode = rich_markup_mode

    def format_help(self) -> str:
        # We override format_help to return an empty string because
        # we are going to print the help directly to stdout using Rich console
        # inside print_help. 
        # But if something calls format_help directly (like some tests), 
        # they might expect a string. 
        # For now, let's implement print_help and see.
        return super().format_help()

    def print_help(self, file: Any = None) -> None:
        if file is None:
            file = sys.stdout
            
        # If we are printing to stdout/stderr, use Rich
        try:
             # Capture Rich output to a string if needed, or just print directly?
             # rich_utils functions print directly to a console.
             # If file is not None and not stdout/stderr, we might need to capture.
             
             # Create a console for the specific file
             console = rich_utils._get_rich_console(stderr=file is sys.stderr)
             
             # Redirect print logic to our rich utils
             # logic in rich_utils needs to change to accept 'console' argument or we mock it?
             # I updated rich_utils functions to take 'console' where possible or create one.
             
             # Let's refactor rich_utils.rich_format_help to take a console object
             # I did that in previous step partially? No, mostly it created its own console.
             # Wait, rich_utils.rich_format_help creates a console.
             
             # We should probably capture the output of rich_utils and write it to 'file'
             # to be fully compatible with argparse API.
             
             from rich.console import Console
             
             # Temporary console to capture output
             capture_console = Console(file=io.StringIO(), force_terminal=True, width=rich_utils.MAX_WIDTH)
             # Monkey patch _get_rich_console ?? No, that's ugly.
             
             # Let's just trust rich_utils to do the right thing for stdout.
             if file is sys.stdout or file is None:
                 rich_utils.rich_format_help(obj=self, markup_mode=self.rich_markup_mode)
             else:
                 # Fallback to standard help if not stdout (e.g. stringIO)
                 # Or implement capture logic
                 super().print_help(file)
                 
        except Exception:
            # Fallback in case of error
            super().print_help(file)

class JacHelpFormatter(argparse.HelpFormatter):
    """
    A custom help formatter that does nothing, as we override print_help in Parser.
    Kept for compatibility if needed.
    """
    pass
