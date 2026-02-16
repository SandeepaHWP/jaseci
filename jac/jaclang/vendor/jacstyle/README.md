# Jacstyle

**Beautiful, Rich-powered CLI styling for Jac**

Jacstyle is a lightweight library that provides Rich-based help formatting for `argparse`-based command-line interfaces. It was created to enhance the Jac CLI with modern, visually appealing help messages while maintaining compatibility with the existing `argparse` infrastructure.

---

## Table of Contents

- [Overview](#overview)
- [Purpose](#purpose)
- [Architecture](#architecture)
- [Components](#components)
- [Integration](#integration)
- [Usage](#usage)
- [Design Philosophy](#design-philosophy)

---

## Overview

Jacstyle is a drop-in replacement for `argparse.ArgumentParser` that renders help messages using the [Rich](https://github.com/Textualize/rich) library. Instead of plain text help output, you get:

- 🎨 **Rounded panels** for organized sections
- 🌈 **Syntax-highlighted** command names and options
- 📊 **Structured tables** for arguments and options
- ✨ **Consistent theming** across all CLI commands

## Purpose

### Before Jacstyle
```
usage: jac run [-h] [--debug] filename

positional arguments:
  filename    .jac file to run

options:
  -h, --help  show this help message and exit
  --debug     Enable debug mode
```

### After Jacstyle
```
╭─ Usage ────────────────────────────────────────╮
│ jac run [-h] [--debug] filename                │
╰────────────────────────────────────────────────╯

╭─ Arguments ────────────────────────────────────╮
│ filename  .jac file to run                     │
╰────────────────────────────────────────────────╯

╭─ Options ──────────────────────────────────────╮
│ -h, --help  Show this help message and exit   │
│ --debug     Enable debug mode                  │
╰────────────────────────────────────────────────╯
```

---

## Architecture

Jacstyle consists of three main components:

### 1. **`JacArgumentParser`** (`core.py`)
A subclass of `argparse.ArgumentParser` that:
- Inherits all `argparse` functionality
- Overrides `format_help()` to use Rich rendering
- Maintains backward compatibility with existing code

### 2. **Rich Formatting Utilities** (`rich_utils.py`)
Core rendering logic that:
- Parses `argparse` help text and metadata
- Generates Rich-based panels, tables, and text
- Handles syntax highlighting for commands and options
- Provides consistent theming

### 3. **Data Models** (`models.py`)
Type-safe representations of CLI elements:
- `Argument`: Positional parameters
- `Option`: Named flags and options  
- `Command`: Subcommands in command groups

---

## Components

### `JacArgumentParser` (core.py)

```python
from jacstyle import JacArgumentParser

# Drop-in replacement for argparse.ArgumentParser
parser = JacArgumentParser(
    prog="jac",
    description="Jac Programming Language CLI"
)

parser.add_argument("filename", help=".jac file to run")
parser.add_argument("--debug", action="store_true", help="Enable debug mode")

# Help is automatically Rich-formatted
parser.print_help()
```

**Key Features:**
- 100% compatible with `argparse` API
- No changes required to existing argument definitions
- Automatic Rich rendering for all help output

### Rich Formatting (`rich_utils.py`)

The `rich_format_help()` function is the heart of Jacstyle:

```python
def rich_format_help(
    *,
    obj: argparse.ArgumentParser,
    markup_mode: MarkupModeStrict,
) -> None:
    """Format help using Rich components."""
    console = _get_rich_console()
    
    # Render Usage section
    console.print(
        Panel(
            usage_content,
            title="Usage",
            box=box.ROUNDED,
            border_style="bold blue"
        )
    )
    
    # Render Arguments, Options, Commands
    # ... (see implementation for details)
```

**Rendering Pipeline:**
1. Parse `argparse` metadata (actions, groups, subparsers)
2. Extract arguments, options, and commands
3. Generate Rich components (Panels, Tables, Text)
4. Apply consistent theming and styling
5. Print to console with proper formatting

### Data Models (`models.py`)

Type-safe representations ensure consistency:

```python
@dataclass
class Argument:
    """Represents a positional argument."""
    metavar: str
    help: str
    required: bool
    choices: list[str] | None

@dataclass
class Option:
    """Represents a named option/flag."""
    name1: str  # Primary name (e.g., "-h")
    name2: str | None  # Secondary name (e.g., "--help")
    metavar: str | None
    help: str
    required: bool
    choices: list[str] | None

@dataclass  
class Command:
    """Represents a subcommand."""
    name: str
    help: str
```

---

## Integration

### Step 1: Import Jacstyle

```python
from jaclang.vendor.jacstyle import JacArgumentParser
```

### Step 2: Replace `ArgumentParser`

```python
# Before
parser = argparse.ArgumentParser(prog="jac", description="...")

# After
parser = JacArgumentParser(prog="jac", description="...")
```

### Step 3: Use as Normal

All existing `argparse` code works without modification:

```python
parser.add_argument("file", help="Input file")
parser.add_argument("--verbose", "-v", action="store_true")
subparsers = parser.add_subparsers(dest="command")
run_parser = subparsers.add_parser("run", help="Run a Jac program")
# ... etc
```

### Integration in Jac CLI

In `jaclang/cli/impl/registry.impl.jac`:

```jac
impl CommandRegistry.init -> None {
    import from jaclang.vendor.jacstyle { JacArgumentParser }
    
    # Create root parser with Rich formatting
    self.root_parser = JacArgumentParser(
        prog="jac",
        description="Jac Programming Language CLI"
    );
    
    # Add subcommands
    self.subparsers = self.root_parser.add_subparsers(...);
    # ... rest of CLI setup
}
```

---

## Usage

### Basic Example

```python
from jacstyle import JacArgumentParser

parser = JacArgumentParser(
    prog="myapp",
    description="My awesome application"
)

parser.add_argument("input", help="Input file to process")
parser.add_argument("--output", "-o", help="Output destination")
parser.add_argument("--verbose", "-v", action="store_true", help="Verbose output")

# Automatically renders beautiful help
parser.print_help()
```

### With Subcommands

```python
parser = JacArgumentParser(prog="tool", description="Multi-command tool")

subparsers = parser.add_subparsers(dest="command", title="Commands")

# Add 'build' command
build = subparsers.add_parser("build", help="Build the project")
build.add_argument("target", help="Build target")

# Add 'test' command
test = subparsers.add_parser("test", help="Run tests")
test.add_argument("--coverage", action="store_true")

parser.print_help()
```

### Output Structure

Jacstyle organizes help into clear sections:

1. **Usage**: Command syntax with optional/required indicators
2. **Description**: Program or command description
3. **Arguments**: Positional parameters (if any)
4. **Options**: Named flags and options (if any)
5. **Commands**: Available subcommands (if any)

All sections use rounded panels with consistent theming.

---

## Design Philosophy

### 1. **Drop-in Compatibility**
- Zero breaking changes to existing `argparse` code
- Subclass-based approach preserves all functionality
- Works with all `argparse` features (groups, mutually exclusive, etc.)

### 2. **Visual Consistency**
- Rounded boxes (`box.ROUNDED`) throughout
- Consistent color scheme (blue for usage, theme-based for content)
- Aligned spacing and padding

### 3. **Information Hierarchy**
- Usage shown first in prominent panel
- Clear sections for different element types
- Syntax highlighting draws attention to important parts

### 4. **Accessibility**
- Falls back gracefully if Rich unavailable
- Respects `NO_COLOR` environment variable
- Works in all terminal types

### 5. **Minimal Dependencies**
- Only requires `rich` library
- Pure Python implementation
- No external binaries or system dependencies

---

## Technical Details

### Argument Parsing

Jacstyle introspects `argparse` internals to extract metadata:

```python
def _get_positionals(obj: argparse.ArgumentParser) -> list[Argument]:
    """Extract positional arguments from parser."""
    positionals = []
    for action in obj._get_positional_actions():
        if action.help == argparse.SUPPRESS:
            continue
        positionals.append(Argument(
            metavar=action.metavar or action.dest,
            help=action.help or "",
            required=action.required,
            choices=action.choices
        ))
    return positionals
```

### Subcommand Detection

```python
def _get_subcommands(obj: argparse.ArgumentParser) -> list[Command]:
    """Extract subcommands from parser."""
    for action in obj._actions:
        if isinstance(action, argparse._SubParsersAction):
            for name, subparser in action.choices.items():
                commands.append(Command(
                    name=name,
                    help=subparser.description or ""
                ))
    return commands
```

### Rich Console Setup

```python
def _get_rich_console(stderr: bool = False) -> Console:
    """Get configured Rich console."""
    file = sys.stderr if stderr else sys.stdout
    return Console(
        file=file,
        force_terminal=True,
        legacy_windows=False
    )
```

---

## Future Enhancements

Potential additions to Jacstyle:

- **Theming Support**: Customizable color schemes
- **Advanced Layouts**: Multi-column option display
- **Interactive Mode**: Arrow-key navigation for commands
- **Shell Completion**: Integration with `argcomplete`
- **Markdown Export**: Generate help docs from parsers

---

## License

Jacstyle is part of the Jac project and follows the same license terms.

---

## Credits

Jacstyle was created to enhance the Jac CLI experience using the excellent [Rich](https://github.com/Textualize/rich) library by Will McGugan.

**Inspirations:**
- Typer's Rich-based help formatting
- Click's structured help output
- Modern CLI tools (gh, cargo, npm)
