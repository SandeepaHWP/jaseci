"""Rich-based argparse help formatter for jac-super.

Ported from jaclang.vendor.jacstyle.rich_utils into Jac.
Provides beautiful, Typer-inspired help output for all Jac CLI commands.
"""
import argparse;
import inspect;
import sys;
import from typing { Any, List }

import from rich { box }
import from rich.align { Align }
import from rich.columns { Columns }
import from rich.console { Console }
import from rich.emoji { Emoji }
import from rich.highlighter { RegexHighlighter }
import from rich.markdown { Markdown }
import from rich.padding { Padding }
import from rich.panel { Panel }
import from rich.table { Table }
import from rich.text { Text }
import from rich.theme { Theme }

# ===============================================================================
# Style constants — mirrors jacstyle/rich_utils.py
# ===============================================================================

glob STYLE_OPTION = "bold cyan",
     STYLE_SWITCH = "bold green",
     STYLE_NEGATIVE_OPTION = "bold magenta",
     STYLE_NEGATIVE_SWITCH = "bold red",
     STYLE_METAVAR = "bold yellow",
     STYLE_METAVAR_SEPARATOR = "dim",
     STYLE_USAGE = "yellow",
     STYLE_USAGE_COMMAND = "bold",
     STYLE_HELPTEXT = "dim",
     STYLE_OPTION_HELP = "",
     STYLE_OPTION_DEFAULT = "dim",
     STYLE_REQUIRED_SHORT = "red",
     STYLE_REQUIRED_LONG = "dim red",
     STYLE_OPTIONS_PANEL_BORDER = "dim",
     STYLE_COMMANDS_PANEL_BORDER = "dim",
     STYLE_COMMANDS_TABLE_FIRST_COLUMN = "bold cyan",
     ALIGN_OPTIONS_PANEL = "left",
     ALIGN_COMMANDS_PANEL = "left",
     MAX_WIDTH: (int | None) = None,
     COLOR_SYSTEM = "auto",
     FORCE_TERMINAL = True,
     DEPRECATED_STRING = "(deprecated) ",
     DEFAULT_STRING = "[default: {}]",
     REQUIRED_SHORT_STRING = "*",
     REQUIRED_LONG_STRING = "[required]",
     ARGUMENTS_PANEL_TITLE = "Arguments",
     OPTIONS_PANEL_TITLE = "Options",
     COMMANDS_PANEL_TITLE = "Commands";

# ===============================================================================
# Highlighters
# ===============================================================================

"""Highlights CLI option strings and metavars."""
class OptionHighlighter(RegexHighlighter) {
    with entry {
        highlights = [
            r"(^|\W)(?P<switch>\-\w+)(?![a-zA-Z0-9])",
            r"(^|\W)(?P<option>\-\-[\w\-]+)(?![a-zA-Z0-9])",
            r"(?P<metavar>\<[^\>]+\>)",
            r"(?P<usage>Usage: )",
        ];
    }
}

"""Highlights [ | ] and <> metavar separator characters."""
class MetavarHighlighter(RegexHighlighter) {
    with entry {
        highlights = [
            r"^(?P<metavar_sep>(\[|<))",
            r"(?P<metavar_sep>\|)",
            r"(?P<metavar_sep>(\]|>))(\.\.\.)?$",
        ];
    }
}

# Module-level highlighter instances
glob _option_highlighter = OptionHighlighter(),
     _metavar_highlighter = MetavarHighlighter();

# ===============================================================================
# Console factory
# ===============================================================================

"""Create a Rich Console pre-configured with the Jac CLI theme."""
def _get_rich_console(stderr: bool = False) -> Console {
    return Console(
        theme=Theme({
            "option": STYLE_OPTION,
            "switch": STYLE_SWITCH,
            "negative_option": STYLE_NEGATIVE_OPTION,
            "negative_switch": STYLE_NEGATIVE_SWITCH,
            "metavar": STYLE_METAVAR,
            "metavar_sep": STYLE_METAVAR_SEPARATOR,
            "usage": STYLE_USAGE,
        }),
        highlighter=_option_highlighter,
        color_system=COLOR_SYSTEM,
        force_terminal=FORCE_TERMINAL,
        width=MAX_WIDTH,
        stderr=stderr,
    );
}

# ===============================================================================
# Text helpers
# ===============================================================================

"""Convert a plain string into Rich Text or Markdown, applying the highlighter."""
def _make_rich_text(text: str, style: str = "") -> Text {
    cleaned = inspect.cleandoc(text);
    return _option_highlighter(Text.from_markup(cleaned, style=style));
}

"""Yield the parser description as a Rich renderable."""
def _get_help_text(obj: Any) -> Any {
    help_text = inspect.cleandoc(obj.description or "");
    if help_text {
        return _make_rich_text(help_text, style=STYLE_HELPTEXT);
    }
    return Text("");
}

# ===============================================================================
# Parameter help column
# ===============================================================================

"""Build the help + default + required Columns for a single argparse action."""
def _get_parameter_help(action: Any) -> Columns {
    items: list = [];

    help_value = action.help or "";
    if hasattr(action, 'deprecated') and action.deprecated {
        help_value = DEPRECATED_STRING + help_value;
    }
    if help_value {
        items.append(_make_rich_text(help_value, style=STYLE_OPTION_HELP));
    }

    # Show default unless it's a boolean flag
    if (
        action.default != argparse.SUPPRESS
        and action.default is not None
        and not isinstance(action, (argparse._StoreTrueAction, argparse._StoreFalseAction))
    ) {
        items.append(Text(DEFAULT_STRING.format(str(action.default)), style=STYLE_OPTION_DEFAULT));
    }

    if action.required {
        items.append(Text(REQUIRED_LONG_STRING, style=STYLE_REQUIRED_LONG));
    }

    return Columns(items);
}

# ===============================================================================
# Panel printers
# ===============================================================================

"""Print a rounded panel containing a table of options/arguments."""
def _print_options_panel(
    name: str,
    actions: list,
    console: Console
) -> None {
    if not actions {
        return;
    }

    options_rows = [];
    for action in actions {
        opt_long_strs = [];
        opt_short_strs = [];
        for opt_str in action.option_strings {
            if "--" in opt_str {
                opt_long_strs.append(opt_str);
            } else {
                opt_short_strs.append(opt_str);
            }
        }

        metavar = Text(style=STYLE_METAVAR, overflow="fold");
        if not action.option_strings {
            metavar.append(action.dest.upper());
        } elif action.metavar {
            metavar.append(action.metavar);
        } elif action.type and hasattr(action.type, '__name__') {
            metavar.append(action.type.__name__.upper());
        } elif isinstance(action, (argparse._StoreAction, argparse._AppendAction)) and action.nargs != 0 {
            metavar.append(action.dest.upper());
        }

        required_mark = Text(REQUIRED_SHORT_STRING, style=STYLE_REQUIRED_SHORT) if action.required else Text("");

        long_col = _option_highlighter(Text(",".join(opt_long_strs) if opt_long_strs else (action.dest.upper() if not action.option_strings else "")));
        short_col = _option_highlighter(Text(",".join(opt_short_strs)));

        options_rows.append([
            long_col,
            short_col,
            _metavar_highlighter(metavar),
            _get_parameter_help(action),
        ]);
    }

    table = Table(
        highlight=True,
        show_header=False,
        expand=True,
        box=None,
        show_lines=False,
    );
    table.add_column(style=STYLE_OPTION);   # long opt
    table.add_column(style=STYLE_OPTION);   # short opt
    table.add_column(style=STYLE_METAVAR);  # metavar
    table.add_column();                      # help

    for row in options_rows {
        table.add_row(*row);
    }

    console.print(
        Panel(
            table,
            border_style=STYLE_OPTIONS_PANEL_BORDER,
            title=name,
            title_align=ALIGN_OPTIONS_PANEL,
            box=box.ROUNDED,
        )
    );
}

"""Print a rounded panel listing all subcommands and their descriptions."""
def _print_commands_panel(
    name: str,
    subparsers_action: Any,
    console: Console
) -> None {
    if not subparsers_action {
        return;
    }

    commands_table = Table(
        highlight=False,
        show_header=False,
        expand=True,
        box=None,
    );
    commands_table.add_column(style=STYLE_COMMANDS_TABLE_FIRST_COLUMN, no_wrap=True);
    commands_table.add_column(justify="left", no_wrap=False, ratio=10);

    for (cmd_name, subparser) in subparsers_action.choices.items() {
        if subparser.description {
            helptext = subparser.description.partition('\n')[0];
        } else {
            helptext = "";
        }
        commands_table.add_row(
            Text(cmd_name),
            _make_rich_text(helptext),
        );
    }

    if commands_table.row_count {
        console.print(
            Panel(
                commands_table,
                border_style=STYLE_COMMANDS_PANEL_BORDER,
                title=name,
                title_align=ALIGN_COMMANDS_PANEL,
                box=box.ROUNDED,
            )
        );
    }
}

# ===============================================================================
# Top-level entry point
# ===============================================================================

"""Render full Rich help output for an argparse.ArgumentParser."""
def rich_format_help(obj: Any) -> None {
    console = _get_rich_console();

    # Usage panel
    usage_text = obj.format_usage().replace("usage: ", "");
    console.print(
        Panel(
            _option_highlighter(usage_text),
            style=STYLE_USAGE,
            border_style=STYLE_USAGE_COMMAND,
            title="Usage",
            title_align="left",
            box=box.ROUNDED,
            padding=(1, 2),
        )
    );

    # Description
    help_text = _get_help_text(obj);
    if help_text {
        console.print(Padding(Align(help_text, pad=False), (0, 1, 1, 1)));
    }

    # Categorise actions
    positionals = [];
    options = [];
    subparsers_action = None;

    for action in obj._actions {
        if isinstance(action, argparse._SubParsersAction) {
            subparsers_action = action;
            continue;
        }
        if action.option_strings {
            options.append(action);
        } else {
            positionals.append(action);
        }
    }

    if positionals {
        _print_options_panel(ARGUMENTS_PANEL_TITLE, positionals, console);
    }
    if options {
        _print_options_panel(OPTIONS_PANEL_TITLE, options, console);
    }
    if subparsers_action {
        _print_commands_panel(COMMANDS_PANEL_TITLE, subparsers_action, console);
    }

    # Epilog
    if obj.epilog {
        console.print(
            Padding(Align(_make_rich_text(obj.epilog), pad=False), 1)
        );
    }
}
