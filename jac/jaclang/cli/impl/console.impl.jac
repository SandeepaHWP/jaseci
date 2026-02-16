"""Implementation of console utilities for terminal output."""

import os;
import sys;
import from contextlib { contextmanager }
import from typing { Any }

import from rich.console { Console }
import from rich.theme { Theme }
import from rich.padding { Padding }
import from rich.panel { Panel }
import from rich.table { Table }

# ===============================================================================
# JacConsole Implementation
# ===============================================================================
"""Initialize the console."""
impl JacConsole.init -> None {
    self.use_emoji = JacConsole._should_use_emoji();
    self.use_color = JacConsole._should_use_color();
    
    # Initialize Rich Console
    _theme = Theme({
        "info": "bold blue",
        "warning": "bold yellow",
        "error": "bold red",
        "success": "bold green",
        "header": "bold cyan",
    });
    self._console = Console(
        theme=_theme,
        force_terminal=True if self.use_color else False,
        no_color=not self.use_color,
    );
    self._stderr_console = Console(
        theme=_theme,
        stderr=True,
        force_terminal=True if self.use_color else False,
        no_color=not self.use_color,
    );
}
# ... (keeping existing implementation of _should_use_emoji and _should_use_color) ...

"""Print to stdout using Rich console.

Supports Rich markup and styling.
"""
impl JacConsole.print(*args: Any, **kwargs: Any) -> None {
     # If no console, initialize it (shouldn't really happen if init called)
    if not hasattr(self, '_console') {
        self.init();
    }
    self._console.print(*args, **kwargs);
}

"""Check if emoji should be used based on environment.

Returns:
    True if emoji should be used, False otherwise
"""
impl JacConsole._should_use_emoji -> bool {
    if os.environ.get('NO_EMOJI') or os.environ.get('TERM') == 'dumb' {
        return False;
    }
    if sys.platform == 'win32' and not os.environ.get('WT_SESSION') {
        return False;
    }
    return True;
}

"""Check if color should be used based on environment.

Returns:
    True if color should be used, False otherwise
"""
impl JacConsole._should_use_color -> bool {
    if os.environ.get('NO_COLOR') {
        return False;
    }
    if os.environ.get('TERM') == 'dumb' {
        return False;
    }
    return True;
}

"""Print to stdout, stripping Rich markup when Rich isn't available.

When markup=False is passed, skip all markup stripping (useful for raw code output).
Rich-specific kwargs (style, highlight, markup) are filtered before calling print().
"""
impl JacConsole.print(*args: Any, **kwargs: Any) -> None {
    import re;
    # Extract Rich-specific kwargs before passing to built-in print()
    skip_markup_strip = kwargs.pop('markup', True) is False;
    kwargs.pop('highlight', None);
    filtered_kwargs = {
        k: v
        for (k, v) in kwargs.items()
        if k not in ['style']
    };
    if skip_markup_strip {
        # Raw output mode - no markup stripping (for code output, etc.)
        print(*args, **filtered_kwargs);
    } else {
        # Strip Rich markup tags like [cyan], [/cyan], [bold], [dim], etc.
        # Only match closing tags [/...] and known Rich style/color keywords
        # to avoid stripping content like TOML headers [project] or graphviz [label=...]
        _rich_styles = (
            'bold|dim|italic|underline|strike|reverse|blink|overline|'
            'red|green|blue|cyan|magenta|yellow|white|black|'
            'bright_red|bright_green|bright_blue|bright_cyan|bright_magenta|bright_yellow|bright_white|'
            'grey0|grey100|muted|info|success|warning|error|link'
        );
        markup_pattern = re.compile(
            r'\[/[a-zA-Z_][a-zA-Z0-9_ ]*\]'  # Closing tags: [/bold], [/red], etc.
            r'|'
            r'\[(?:' + _rich_styles + r')(?:\s[^\]]*?)?\]'  # Opening style tags
        );
        stripped_args = tuple(
            markup_pattern.sub('', str(arg)) if isinstance(arg, str) else arg
            for arg in args
        );
        print(*stripped_args, **filtered_kwargs);
    }
    # Flush stdout so output is visible immediately when piped (piped stdout
    # uses block buffering, which can cause subprocess readline() to hang).
    sys.stdout.flush();
}

"""Context manager for status during long operations (basic implementation)."""
"""Context manager for status spinner."""
impl JacConsole.status(*args: Any, **kwargs: Any) -> object {
    if not hasattr(self, '_console') {
        self.init();
    }
    # Return Rich's status context manager
    return self._console.status(*args, **kwargs);
}

"""Print a success message with checkmark."""
"""Print a success message with checkmark."""
impl JacConsole.success(message: str, emoji: bool = True) -> None {
    if not hasattr(self, '_console') {
        self.init();
    }
    prefix = '✔' if emoji and self.use_emoji else '[SUCCESS]';
    self._console.print(f"[{'success' if self.use_color else ''}]{prefix} {message}[/]");
}

"""Print an error message with optional hint.

Args:
    message: The error message
    hint: Optional hint or suggestion
    emoji: Whether to use emoji (✖) or text ([ERROR])
"""
"""Print an error message with optional hint.

Args:
    message: The error message
    hint: Optional hint or suggestion
    emoji: Whether to use emoji (✖) or text ([ERROR])
"""
impl JacConsole.error(
    message: str, hint: str | None = None, emoji: bool = True
) -> None {
    if not hasattr(self, '_console') {
        self.init();
    }
    
    import from rich.panel { Panel }
    import from rich { box }
    import from rich.text { Text }
    
    prefix = '✖' if emoji and self.use_emoji else '[ERROR]';
    
    # Create error message text
    error_text = Text();
    error_text.append(f"{prefix} Error: ", style="bold red");
    error_text.append(message);
    
    if hint {
        error_text.append("\n\n");
        hint_prefix = '💡' if self.use_emoji else 'HINT:';
        error_text.append(f"{hint_prefix} ", style="bold yellow");
        error_text.append(hint, style="yellow");
    }
    
    # Wrap in red panel
    panel = Panel(
        error_text,
        border_style="bold red",
        box=box.ROUNDED,
        padding=(0, 1),
    );
    
    self._stderr_console.print(panel);
}

"""Print a warning message."""
"""Print a warning message."""
impl JacConsole.warning(message: str, emoji: bool = True) -> None {
    if not hasattr(self, '_console') {
        self.init();
    }
    prefix = '⚠' if emoji and self.use_emoji else '[WARNING]';
    self._console.print(f"[warning]{prefix} {message}[/warning]");
}

"""Print an info message."""
"""Print an info message."""
impl JacConsole.info(message: str, emoji: bool = True) -> None {
    if not hasattr(self, '_console') {
        self.init();
    }
    prefix = 'ℹ' if emoji and self.use_emoji else '[INFO]';
    self._console.print(f"[info]{prefix} {message}[/info]");
}

"""Print a header with optional version.

Args:
    title: Header title
    version: Optional version string
"""
impl JacConsole.print_header(title: str, version: str | None = None) -> None {
    if version {
        print(f"{title} v{version}");
    } else {
        print(title);
    }
}

"""Print a list of labeled URLs.

Args:
    urls: Dict or list of tuples mapping labels to URLs
          (e.g., {"Local": "http://localhost:3000"} or [("Local", "http://..."), ("Network", "http://...")])
    symbol: Symbol to use before each line (default: ➜)
"""
impl JacConsole.print_urls(urls: Any, symbol: str = '➜') -> None {
    items = urls.items() if isinstance(urls, dict) else urls;
    for (label, url) in items {
        padded_label = f"{label}:".ljust(10);
        print(f"  {symbol}  {padded_label} {url}");
    }
}

"""Print a bordered box with next steps.

Args:
    steps: List of step strings
    title: Box title (default: "Next Steps")
"""
impl JacConsole.print_next_steps(steps: list[str], title: str = 'Next Steps') -> None {
    print(f"\n{title}:");
    for (i, step) in enumerate(steps, 1) {
        print(f"  {i}. {step}");
    }
    print();
}

"""Print a list of items with symbols.

Args:
    items: List of items to print
    style: Style name (ignored in base implementation, used by Rich plugins)
    symbol: Symbol to prefix each item
"""
impl JacConsole.print_list(
    items: list[str], style: str = 'success', symbol: str = '✔'
) -> None {
    for item in items {
        print(f"  {symbol} {item}");
    }
}

"""Print a formatted table.

Args:
    headers: Column headers
    rows: List of rows (each row is a list of strings)
    title: Optional table title
"""
impl JacConsole.print_table(
    headers: list[str], rows: list[list[str]], title: str | None = None
) -> None {
    if title {
        print(f"\n{title}:");
    }
    # Calculate column widths
    col_widths: list[int] = [len(h) for h in headers];
    for row in rows {
        for (i, cell) in enumerate(row) {
            if i < len(col_widths) {
                col_widths[i] = max(col_widths[i], len(str(cell)));
            }
        }
    }
    # Print header
    header_row = ' | '.join(h.ljust(w) for (h, w) in zip(headers, col_widths));
    print(header_row);
    print('-' * len(header_row));
    # Print rows
    for row in rows {
        row_str = ' | '.join(
            str(cell).ljust(w) if i < len(col_widths) else str(cell)
            for (i, cell) in enumerate(row)
            for w in [col_widths[i] if i < len(col_widths) else len(str(cell))]
        );
        print(row_str);
    }
    print();
}

"""Context manager for spinner during long operations.

Usage:
    with console.spinner("Loading..."):
        # do work
        pass
"""
@ contextmanager
impl JacConsole.spinner(text: str) -> object {
    # Basic implementation - just print the message
    print(f"{text}...", end='', flush=True);
    try {
        yield None;
    } finally {
        print(" done");
    }
}

"""Print elapsed time in a nice format.

Args:
    seconds: Time in seconds
"""
impl JacConsole.print_elapsed_time(seconds: float) -> None {
    if seconds < 1 {
        ms = seconds * 1000;
        print(f"  Done in {ms:.0f}ms");
    } else {
        print(f"  Done in {seconds:.1f}s");
    }
}

"""Print file change notification with timestamp.

Args:
    filepath: Path to the file
    action: Action performed (changed, created, deleted)
"""
impl JacConsole.print_file_change(filepath: str, action: str = 'changed') -> None {
    import from datetime { datetime }
    timestamp = datetime.now().strftime('%H:%M:%S');
    emoji_map = {'changed': '⚡', 'created': '✨', 'deleted': '🗑️'};
    emoji = emoji_map.get(action, '📝') if self.use_emoji else action.upper();
    print(f"[{timestamp}] {emoji} {action.capitalize()}: {filepath}");
}

"""Print file watching status.

Args:
    pattern: File pattern being watched
    count: Number of files
"""
impl JacConsole.print_watching(pattern: str, count: int) -> None {
    watch_emoji = '👀' if self.use_emoji else '[WATCHING]';
    print(f"{watch_emoji} Watching for changes...");
    print(f"   Monitoring: {pattern} ({count} files)");
}

# ===============================================================================
# Module-level function implementations
# ===============================================================================
"""Get the console instance using the hook system, allowing plugins to override."""
impl _get_console -> JacConsole {
    global _console_instance;
    if _console_instance is None {
        import from jaclang.jac0core.runtime { JacRuntime as Jac }
        _console_instance = Jac.get_console();
        # If runtime doesn't provide a console, create our own
        if _console_instance is None {
            _console_instance = JacConsole();
        }
        _console_instance.init();
    }
    return _console_instance;
}
