"""Implementation of jac.toml validation using custom RD parser."""

impl validate_jac_toml(content: str) -> list[lspt.Diagnostic] {
    import from jaclang.langserve.toml_parser { toml_parse };

    (doc, diags) = toml_parse(content);

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

    open_sections = {
        "plugins", "dependencies", "dev-dependencies",
        "scripts", "environments", "jacpack"
    };

    # Python type → TOML value kind string
    type_kind: dict = {
        str: "string",
        int: "integer",
        bool: "bool",
        list: "array",
        dict: "inline_table"
    };

    def make_diag(tok: object, msg: str, sev: object) -> lspt.Diagnostic {
        return lspt.Diagnostic(
            range=lspt.Range(
                start=lspt.Position(
                    line=tok.loc.line - 1,
                    character=tok.loc.col_start - 1
                ),
                end=lspt.Position(
                    line=tok.loc.line - 1,
                    character=max(tok.loc.col_end - 1, tok.loc.col_start)
                )
            ),
            message=msg,
            severity=sev,
            source="jac-toml"
        );
    }

    # Pass 1 - unknown top-level sections
    for (sec_name, sec) in doc.sections.items() {
        top = sec_name.split(".")[0];
        if top not in known_sections {
            diags.append(make_diag(
                sec.tok,
                f"Unknown section '[{sec_name}]'. Known: {', '.join(sorted(known_sections))}",
                lspt.DiagnosticSeverity.Warning
            ));
        }
    }

    # Pass 2 - per-section field validation
    for (section, fields) in section_fields.items() {
        sec = doc.sections.get(section);
        if sec is None {
            continue;
        }
        top_section = section.split(".")[0];

        for kv in sec.kv_pairs {
            if kv.value.kind == "error" {
                continue;  # parse error already emitted
            }

            if kv.key not in fields {
                if top_section not in open_sections {
                    diags.append(make_diag(
                        kv.key_tok,
                        f"Unknown field '{kv.key}' in [{section}].",
                        lspt.DiagnosticSeverity.Warning
                    ));
                }
                continue;
            }

            expected_type = fields[kv.key];
            expected_kind = type_kind.get(expected_type, "string");

            # bool is a subtype of int in Python - handle explicitly
            if expected_type == bool {
                if kv.value.kind != "bool" {
                    diags.append(make_diag(
                        kv.key_tok,
                        f"'{kv.key}' in [{section}] must be a bool, got {kv.value.kind}.",
                        lspt.DiagnosticSeverity.Error
                    ));
                    continue;
                }
            } elif kv.value.kind != expected_kind {
                type_name = expected_type.__name__;
                diags.append(make_diag(
                    kv.key_tok,
                    f"'{kv.key}' in [{section}] must be a {type_name}, got {kv.value.kind}.",
                    lspt.DiagnosticSeverity.Error
                ));
                continue;
            }

            key_pair = (section, kv.key);
            if key_pair in enum_values and kv.value.raw not in enum_values[key_pair] {
                allowed = enum_values[key_pair];
                diags.append(make_diag(
                    kv.key_tok,
                    f"'{kv.key}' in [{section}] must be one of: {allowed}. Got '{kv.value.raw}'.",
                    lspt.DiagnosticSeverity.Error
                ));
            }

            if key_pair in int_ranges {
                (lo, hi) = int_ranges[key_pair];
                if not (lo <= kv.value.raw <= hi) {
                    diags.append(make_diag(
                        kv.key_tok,
                        f"'{kv.key}' in [{section}] must be between {lo} and {hi}. Got {kv.value.raw}.",
                        lspt.DiagnosticSeverity.Error
                    ));
                }
            }
        }
    }

    return diags;
}
