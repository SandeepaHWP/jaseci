
# Extracted and modified for argparse from Typer's rich_utils.py

import inspect
import io
import argparse
from typing import Any, Literal, Optional, Union, List

from rich import box
from rich.align import Align
from rich.columns import Columns
from rich.console import Console, RenderableType, group
from rich.emoji import Emoji
from rich.highlighter import RegexHighlighter
from rich.markdown import Markdown
from rich.markup import escape
from rich.padding import Padding
from rich.panel import Panel
from rich.table import Table
from rich.text import Text
from rich.theme import Theme
from rich.traceback import Traceback

from .models import DeveloperExceptionConfig

# Default styles
STYLE_OPTION = "bold cyan"
STYLE_SWITCH = "bold green"
STYLE_NEGATIVE_OPTION = "bold magenta"
STYLE_NEGATIVE_SWITCH = "bold red"
STYLE_METAVAR = "bold yellow"
STYLE_METAVAR_SEPARATOR = "dim"
STYLE_USAGE = "yellow"
STYLE_USAGE_COMMAND = "bold"
STYLE_DEPRECATED = "red"
STYLE_DEPRECATED_COMMAND = "dim"
STYLE_HELPTEXT_FIRST_LINE = ""
STYLE_HELPTEXT = "dim"
STYLE_OPTION_HELP = ""
STYLE_OPTION_DEFAULT = "dim"
STYLE_OPTION_ENVVAR = "dim yellow"
STYLE_REQUIRED_SHORT = "red"
STYLE_REQUIRED_LONG = "dim red"
STYLE_OPTIONS_PANEL_BORDER = "dim"
ALIGN_OPTIONS_PANEL: Literal["left", "center", "right"] = "left"
STYLE_OPTIONS_TABLE_SHOW_LINES = False
STYLE_OPTIONS_TABLE_LEADING = 0
STYLE_OPTIONS_TABLE_PAD_EDGE = False
STYLE_OPTIONS_TABLE_PADDING = (0, 1)
STYLE_OPTIONS_TABLE_BOX = ""
STYLE_OPTIONS_TABLE_ROW_STYLES = None
STYLE_OPTIONS_TABLE_BORDER_STYLE = None
STYLE_COMMANDS_PANEL_BORDER = "dim"
ALIGN_COMMANDS_PANEL: Literal["left", "center", "right"] = "left"
STYLE_COMMANDS_TABLE_SHOW_LINES = False
STYLE_COMMANDS_TABLE_LEADING = 0
STYLE_COMMANDS_TABLE_PAD_EDGE = False
STYLE_COMMANDS_TABLE_PADDING = (0, 1)
STYLE_COMMANDS_TABLE_BOX = ""
STYLE_COMMANDS_TABLE_ROW_STYLES = None
STYLE_COMMANDS_TABLE_BORDER_STYLE = None
STYLE_COMMANDS_TABLE_FIRST_COLUMN = "bold cyan"
STYLE_ERRORS_PANEL_BORDER = "red"
ALIGN_ERRORS_PANEL: Literal["left", "center", "right"] = "left"
STYLE_ERRORS_SUGGESTION = "dim"
STYLE_ABORTED = "red"
_TERMINAL_WIDTH = None 
MAX_WIDTH = None
COLOR_SYSTEM: Optional[Literal["auto", "standard", "256", "truecolor", "windows"]] = "auto"
FORCE_TERMINAL = True

# Fixed strings
DEPRECATED_STRING = "(deprecated) "
DEFAULT_STRING = "[default: {}]"
ENVVAR_STRING = "[env var: {}]"
REQUIRED_SHORT_STRING = "*"
REQUIRED_LONG_STRING = "[required]"
RANGE_STRING = " [{}]"
ARGUMENTS_PANEL_TITLE = "Arguments"
OPTIONS_PANEL_TITLE = "Options"
COMMANDS_PANEL_TITLE = "Commands"
ERRORS_PANEL_TITLE = "Error"
ABORTED_TEXT = "Aborted."
RICH_HELP = "Try [blue]'{command_path} --help'[/] for help."

MARKUP_MODE_MARKDOWN = "markdown"
MARKUP_MODE_RICH = "rich"
ANSI_PREFIX = "\033["

MarkupModeStrict = Literal["markdown", "rich"]


# Rich regex highlighter
class OptionHighlighter(RegexHighlighter):
    """Highlights our special options."""

    highlights = [
        r"(^|\W)(?P<switch>\-\w+)(?![a-zA-Z0-9])",
        r"(^|\W)(?P<option>\-\-[\w\-]+)(?![a-zA-Z0-9])",
        r"(?P<metavar>\<[^\>]+\>)",
        r"(?P<usage>Usage: )",
    ]


# Highlighter to make [ | ] and <> dim
class MetavarHighlighter(RegexHighlighter):
    highlights = [
        r"^(?P<metavar_sep>(\[|<))",
        r"(?P<metavar_sep>\|)",
        r"(?P<metavar_sep>(\]|>))(\.\.\.)?$",
    ]

highlighter = OptionHighlighter()
metavar_highlighter = MetavarHighlighter()


def _get_rich_console(stderr: bool = False) -> Console:
    return Console(
        theme=Theme(
            {
                "option": STYLE_OPTION,
                "switch": STYLE_SWITCH,
                "negative_option": STYLE_NEGATIVE_OPTION,
                "negative_switch": STYLE_NEGATIVE_SWITCH,
                "metavar": STYLE_METAVAR,
                "metavar_sep": STYLE_METAVAR_SEPARATOR,
                "usage": STYLE_USAGE,
            },
        ),
        highlighter=highlighter,
        color_system=COLOR_SYSTEM,
        force_terminal=FORCE_TERMINAL,
        width=MAX_WIDTH,
        stderr=stderr,
    )


def _make_rich_text(
    *, text: str, style: str = "", markup_mode: MarkupModeStrict
) -> Union[Markdown, Text]:
    text = inspect.cleandoc(text)
    if markup_mode == MARKUP_MODE_MARKDOWN:
        text = Emoji.replace(text)
        return Markdown(text, style=style)
    else:
        return highlighter(Text.from_markup(text, style=style))


@group()
def _get_help_text(
    *,
    obj: argparse.ArgumentParser,
    markup_mode: MarkupModeStrict,
) -> Any:
    help_text = inspect.cleandoc(obj.description or "")
    if help_text:
        yield _make_rich_text(
            text=help_text,
            style=STYLE_HELPTEXT,
            markup_mode=markup_mode,
        )


def _get_parameter_help(
    *,
    action: argparse.Action,
    markup_mode: MarkupModeStrict,
) -> Columns:
    items: List[Union[Text, Markdown]] = []

    help_value = action.help or ""
    if hasattr(action, 'deprecated') and action.deprecated: # type: ignore
        help_value = DEPRECATED_STRING + help_value

    if help_value:
        items.append(
            _make_rich_text(
                text=help_value,
                style=STYLE_OPTION_HELP,
                markup_mode=markup_mode,
            )
        )

    # Default value (skip for booleans/flags usually, but argparse defaults are important)
    if action.default != argparse.SUPPRESS and action.default is not None:
         # Skip showing default for boolean flags that default to False/True if it's obvious from help?
         # Typer shows defaults. Let's show defaults unless it's a store_true/store_false action?
         # Actually store_true defaults to False, usually we don't show that.
        if not isinstance(action, (argparse._StoreTrueAction, argparse._StoreFalseAction)):
            items.append(
                 Text(
                     DEFAULT_STRING.format(str(action.default)),
                     style=STYLE_OPTION_DEFAULT,
                 )
             )

    if action.required:
        items.append(Text(REQUIRED_LONG_STRING, style=STYLE_REQUIRED_LONG))
    
    return Columns(items)


def _print_options_panel(
    *,
    name: str,
    actions: List[argparse.Action],
    markup_mode: MarkupModeStrict,
    console: Console,
) -> None:
    if not actions:
        return

    options_rows = []
    required_rows = []
    
    for action in actions:
        # separate long and short options
        opt_long_strs = []
        opt_short_strs = []
        for opt_str in action.option_strings:
            if "--" in opt_str:
                opt_long_strs.append(opt_str)
            else:
                opt_short_strs.append(opt_str)

        metavar = Text(style=STYLE_METAVAR, overflow="fold")
        
        # Positional args don't have option strings
        if not action.option_strings:
             metavar.append(action.dest.upper())
        elif action.metavar:
             metavar.append(action.metavar)
        elif action.type and hasattr(action.type, '__name__'):
             metavar.append(action.type.__name__.upper())
        elif isinstance(action, (argparse._StoreAction, argparse._AppendAction)) and action.nargs != 0:
             # Fallback
             metavar.append(action.dest.upper())

        required = Text(REQUIRED_SHORT_STRING, style=STYLE_REQUIRED_SHORT) if action.required else ""
        required_rows.append(required)
        
        options_rows.append(
            [
                highlighter(",".join(opt_long_strs) if opt_long_strs else (action.dest.upper() if not action.option_strings else "")),
                highlighter(",".join(opt_short_strs)),
                metavar_highlighter(metavar),
                _get_parameter_help(
                    action=action,
                    markup_mode=markup_mode,
                ),
            ]
        )

    table = Table(
        highlight=True,
        show_header=False,
        expand=True,
        box=None,
        show_lines=False,
    )
    # Add columns to ensure alignment
    table.add_column(style=STYLE_OPTION) # Long
    table.add_column(style=STYLE_OPTION) # Short
    table.add_column(style=STYLE_METAVAR) # Metavar
    table.add_column() # Help

    for row in options_rows:
        table.add_row(*row)

    console.print(
        Panel(
            table,
            border_style=STYLE_OPTIONS_PANEL_BORDER,
            title=name,
            title_align=ALIGN_OPTIONS_PANEL,
            box=box.ROUNDED,
        )
    )

def _print_commands_panel(
    *,
    name: str,
    subparsers_action: argparse._SubParsersAction,
    markup_mode: MarkupModeStrict,
    console: Console,
) -> None:
    if not subparsers_action:
        return

    commands_table = Table(
        highlight=False,
        show_header=False,
        expand=True,
        box=None,
    )
    commands_table.add_column(style=STYLE_COMMANDS_TABLE_FIRST_COLUMN, no_wrap=True)
    commands_table.add_column("Description", justify="left", no_wrap=False, ratio=10)
    
    for cmd_name, subparser in subparsers_action.choices.items():
        helptext = subparser.description or subparser.format_usage() # Fallback
        # Extract first line of description if available
        if subparser.description:
             helptext = subparser.description.partition('\n')[0]
        else:
            # Try to get help from the action choices help if possible?
            # Argparse makes this hard. The help is stored in the action choices.
            # We iterate choices.items() which gives (name, parser).
            pass

        commands_table.add_row(
            Text(cmd_name),
            _make_rich_text(text=helptext, markup_mode=markup_mode)
        )

    if commands_table.row_count:
        console.print(
            Panel(
                commands_table,
                border_style=STYLE_COMMANDS_PANEL_BORDER,
                title=name,
                title_align=ALIGN_COMMANDS_PANEL,
                box=box.ROUNDED,
            )
        )

def rich_format_help(
    *,
    obj: argparse.ArgumentParser,
    markup_mode: MarkupModeStrict,
) -> None:
    console = _get_rich_console()

    # Usage
    usage_text = obj.format_usage().replace("usage: ", "");
    console.print(
        Panel(
            highlighter(usage_text),
            style=STYLE_USAGE,
            border_style=STYLE_USAGE_COMMAND,
            title="Usage",
            title_align="left",
            box=box.ROUNDED,
            padding=(1, 2),
        )
    )

    # Description
    console.print(
        Padding(
            Align(_get_help_text(obj=obj, markup_mode=markup_mode), pad=False),
            (0, 1, 1, 1)
        )
    )


    # We need to manually separate actions into groups
    # 1. Positional Arguments
    # 2. Options
    # 3. Subcommands (if any)
    
    positionals = []
    options = []
    subparsers_action = None

    for action in obj._actions:
        if isinstance(action, argparse._SubParsersAction):
            subparsers_action = action
            continue
        if isinstance(action, argparse._HelpAction) or isinstance(action, argparse._VersionAction):
             # Treat help/version as options
             pass
        
        if action.option_strings:
            options.append(action)
        else:
            positionals.append(action)

    if positionals:
        _print_options_panel(
            name=ARGUMENTS_PANEL_TITLE,
            actions=positionals,
            markup_mode=markup_mode,
            console=console
        )

    if options:
        _print_options_panel(
            name=OPTIONS_PANEL_TITLE,
            actions=options,
            markup_mode=markup_mode,
            console=console
        )
        
    if subparsers_action:
        _print_commands_panel(
            name=COMMANDS_PANEL_TITLE,
            subparsers_action=subparsers_action,
            markup_mode=markup_mode,
            console=console
        )

    # Epilog
    if obj.epilog:
        console.print(Padding(Align(_make_rich_text(text=obj.epilog, markup_mode=markup_mode), pad=False), 1))
