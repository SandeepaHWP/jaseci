"""Implementation of jac.toml validation."""

impl find_section_line(lines: list[str], section: str) -> int {
    target = f"[{section}]";
    for (i, line) in enumerate(lines) {
        if line.strip() == target {
            return i;
        }
    }
    return 0;
}

impl find_key_line(lines: list[str], section: str, key: str) -> int {
    in_section = False;
    for (i, line) in enumerate(lines) {
        stripped = line.strip();
        if stripped == f"[{section}]" {
            in_section = True;
            continue;
        }
        if in_section and stripped.startswith("[") and not stripped.startswith(f"[{section}.") {
            in_section = False;
        }
        if in_section {
            if (
                stripped.startswith(f"{key} ")
                or stripped.startswith(f"{key}=")
                or stripped.startswith(f"{key}\t")
            ) {
                return i;
            }
        }
    }
    return find_section_line(lines, section);
}

impl validate_jac_toml(content: str) -> list[lspt.Diagnostic] {
    import tomllib;
    import re;

    diags: list[lspt.Diagnostic] = [];

    def make_diag(
        line: int, col: int, col_end: int, msg: str, sev: lspt.DiagnosticSeverity
    ) -> lspt.Diagnostic {
        return lspt.Diagnostic(
            range=lspt.Range(
                start=lspt.Position(line=line, character=col),
                end=lspt.Position(line=line, character=col_end)
            ),
            message=msg,
            severity=sev,
            source="jac-toml"
        );
    }

    data: dict = {};
    try {
        data = tomllib.loads(content);
    } except Exception as e {
        # TOMLDecodeError message format: "... (at line N, column M)"
        m = re.search(r'at line (\d+), column (\d+)', str(e));
        lineno = int(m.group(1)) if m else 1;
        colno = int(m.group(2)) if m else 1;
        line = max(0, lineno - 1);
        col = max(0, colno - 1);
        diags.append(make_diag(line, col, col + 1, str(e), lspt.DiagnosticSeverity.Error));
        return diags;
    }

    lines = content.splitlines();

    known_sections = {
        "project", "run", "build", "test", "serve", "format", "check",
        "dot", "cache", "storage", "plugins", "environment", "environments",
        "dependencies", "dev-dependencies", "scripts", "jacpack"
    };

    section_fields: dict = {
        "project": {
            "name": str, "version": str, "description": str,
            "authors": list, "license": str, "readme": str,
            "jac_version": str, "entry-point": str, "entry_point": str,
            "urls": dict
        },
        "run": {
            "session": str, "main": bool, "cache": bool,
            "autonative": bool, "topology_index": bool, "diagnostics": str
        },
        "build": {
            "typecheck": bool, "dir": str, "native": dict
        },
        "test": {
            "directory": str, "filter": str, "verbose": bool,
            "fail_fast": bool, "max_failures": int
        },
        "serve": {
            "port": int, "session": str, "main": bool,
            "cl_route_prefix": str, "base_route_app": str
        },
        "format": {
            "outfile": str
        },
        "check": {
            "print_errs": bool, "suppress": list, "suppress_categories": list
        },
        "dot": {
            "depth": int, "traverse": bool, "bfs": bool,
            "edge_limit": int, "node_limit": int, "format": str
        },
        "cache": {
            "enabled": bool, "dir": str
        },
        "plugins": {
            "discovery": str, "enabled": list, "disabled": list
        },
        "storage": {
            "storage_type": str, "base_path": str, "create_dirs": bool
        },
        "environment": {
            "default_profile": str
        },
        "build.native": {
            "opt_level": int, "dump_ir": str
        },
        "check.lint": {
            "select": list, "ignore": list, "exclude": list
        }
    };

    enum_values: dict = {
        ("run", "diagnostics"): ["error", "all", "none"],
        ("storage", "storage_type"): ["local", "s3", "gcs", "azure"],
        ("plugins", "discovery"): ["auto", "manual"]
    };

    int_ranges: dict = {
        ("build.native", "opt_level"): (0, 3)
    };

    for key in data {
        if key not in known_sections {
            line = find_section_line(lines, key);
            col = lines[line].find(key) if line < len(lines) else 0;
            diags.append(make_diag(
                line, col, col + len(key),
                f"Unknown section '[{key}]'. Did you mean one of: {', '.join(sorted(known_sections))}?",
                lspt.DiagnosticSeverity.Warning
            ));
        }
    }

    for (section, fields) in section_fields.items() {
        parts = section.split(".");
        sec_data: dict = data;
        valid = True;
        for part in parts {
            if isinstance(sec_data, dict) and part in sec_data {
                sec_data = sec_data[part];
            } else {
                valid = False;
                break;
            }
        }
        if not valid or not isinstance(sec_data, dict) {
            continue;
        }

        for (field, expected_type) in fields.items() {
            if field not in sec_data {
                continue;
            }
            value = sec_data[field];
            line = find_key_line(lines, section, field);
            col = lines[line].find(field) if line < len(lines) else 0;
            col_end = col + len(field);

            if not isinstance(value, expected_type) {
                type_name = expected_type.__name__;
                diags.append(make_diag(
                    line, col, col_end,
                    f"'{field}' in [{section}] must be a {type_name}, got {type(value).__name__}.",
                    lspt.DiagnosticSeverity.Error
                ));
                continue;
            }

            key_pair = (section, field);
            if key_pair in enum_values and value not in enum_values[key_pair] {
                allowed = enum_values[key_pair];
                diags.append(make_diag(
                    line, col, col_end,
                    f"'{field}' in [{section}] must be one of: {allowed}. Got '{value}'.",
                    lspt.DiagnosticSeverity.Error
                ));
            }

            if key_pair in int_ranges {
                (lo, hi) = int_ranges[key_pair];
                if not (lo <= value <= hi) {
                    diags.append(make_diag(
                        line, col, col_end,
                        f"'{field}' in [{section}] must be between {lo} and {hi}. Got {value}.",
                        lspt.DiagnosticSeverity.Error
                    ));
                }
            }
        }

        open_sections = {"plugins", "dependencies", "dev-dependencies",
                         "scripts", "environments", "jacpack"};
        top_section = parts[0];
        if top_section not in open_sections {
            for field in sec_data {
                if field not in fields {
                    line = find_key_line(lines, section, field);
                    col = lines[line].find(field) if line < len(lines) else 0;
                    diags.append(make_diag(
                        line, col, col + len(field),
                        f"Unknown field '{field}' in [{section}].",
                        lspt.DiagnosticSeverity.Warning
                    ));
                }
            }
        }
    }

    return diags;
}
