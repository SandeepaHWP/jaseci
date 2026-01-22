"""Implementation of shell completion setup command."""

import os;
import subprocess;

impl completion(shell: str) -> int {
    # Map shell names to config files
    shell_map = {
        "bash": ("~/.bashrc", "bash"),
        "zsh": ("~/.zshrc", "zsh"),
        "fish": ("~/.config/fish/completions/jac.fish", "fish"),

    };
    if shell not in shell_map {
        print(f"Unsupported shell: {shell}");
        print("Supported shells: bash, zsh, fish");
        return 1;
    }
    config_file = shell_map[shell][0];
    shell_type = shell_map[shell][1];
    expanded_path = os.path.expanduser(config_file);
    try {
        if shell == "fish" {
            _setup_fish_completion(expanded_path);
        } else {
            _setup_argcomplete(shell_type, expanded_path);
        }
        return 0;
    } except Exception as e {
        print(f"Failed to setup completion: {str(e)}");
        return 1;
    }
}

def _setup_argcomplete(shell: str, config_file: str) -> None {
    print(f"Setting up {shell} completion...");

    try {
        result = subprocess.run(
            ["register-python-argcomplete", f"--shell={shell}", "jac"],
            capture_output=True,
            text=True,
            check=True
        );

        completion_code = result.stdout;

        # Check if already registered (idempotent)
        if os.path.exists(config_file) {
            with open(config_file, 'r') as f {
                existing = f.read();
                if "python_argcomplete" in existing {
                    print(f"Completion already registered in {config_file}");
                    return;
                }
            }
        }

        # Append to config file
        with open(config_file, 'a') as f {
            f.write('\n\n# jac shell completion (added by jac completion)\n');
            f.write(completion_code);
        }

        print(f"Completion registered in {config_file}");
        print(f"Reload your shell: source {config_file}");
    } except FileNotFoundError {
        print("register-python-argcomplete not found");
        print("Install argcomplete: pip install argcomplete");
        raise ;
    } except Exception as e {
        print(f"Failed to register completion: {str(e)}");
        raise ;
    }
}

def _setup_fish_completion(config_file: str) -> None {
    print("Setting up fish completion...");

    fish_completion = """#!/usr/bin/env fish
# jac shell completion

complete -c jac -n '__fish_use_subcommand_from_list' \\
    -f -a 'add check clean config create debug dot enter format install jacpack js py2jac plugins py2jac remove run script start test tool' \\
    -d 'jac command'
""";

    fish_dir = os.path.dirname(config_file);
    os.makedirs(fish_dir, exist_ok=True);

    with open(config_file, 'w') as f {
        f.write(fish_completion);
    }

    print(f"Completion registered in {config_file}");
    print("Fish shell completions setup complete");
}
