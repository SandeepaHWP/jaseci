import json;
import re;
import shutil;
import subprocess;
import from pathlib { Path }
import from tempfile { TemporaryDirectory }
import from jaclang.client.vite_client_bundle { ViteClientBundleBuilder }
import from jaclang.compiler.driver.program { JacProgram }
import from jaclang.compiler.backends.es.js_paths {
    client_output_path,
    relative_js_specifier
}
import from jaclang.project.config { set_config }

def _compiler(project: Path, program: JacProgram | None = None) -> any {
    (project / "jac.toml").write_text(
        '[project]\nname = "external-imports"\nkind = "web-app"\n'
    );
    (project / "package.json").write_text(
        '{"name":"external-imports","type":"module"}'
    );
    return ViteClientBundleBuilder(
        vite_package_json=project / "package.json", program=program or JacProgram()
    )._get_compiler().jac_client_compiler;
}

def _emitted(compiler: any, source: Path) -> Path {
    matches = [
        path
        for path in compiler.compiled_dir.rglob("*.js")
        if path.read_text().startswith(f"/* Source: {source.resolve()} */")
    ];
    assert len(matches) == 1 , f"expected one output for {source}, found {matches}";
    return matches[0];
}

def _assert_import(importer: Path, target: Path) {
    specs = re.findall(r'(?:from\s+|import\s*\(?\s*)"([^"\n]+)"', importer.read_text());
    assert any(
        (importer.parent / spec).resolve() == target.resolve()
        for spec in specs
        if spec.startswith(".")
    ) , f"{importer} does not import {target}: {specs}";
}

test "external output paths cannot collide with project files or escape the compiled directory" {
    with TemporaryDirectory() as tmp {
        base = Path(tmp).resolve();
        project = base / "myapp";
        project.mkdir();
        shared = base / "shared" / "Card.jac";
        external = Path(client_output_path(str(shared), str(project)));
        internal_source = project / external.with_suffix(".jac");
        internal = Path(client_output_path(str(internal_source), str(project)));
        assert external != internal;
        compiled = base / "compiled";
        assert (compiled / external).resolve().is_relative_to(compiled);
        assert (compiled / internal).resolve().is_relative_to(compiled);
        spec = relative_js_specifier(str(shared), str(internal_source), str(project));
        assert (compiled / internal).parent.joinpath(spec).resolve()
            == (compiled / external).resolve();
    }
}

test "external static imports preserve nested dependencies and imports back into the app" {
    with TemporaryDirectory() as tmp {
        set_config(None);
        base = Path(tmp).resolve();
        project = base / "myapp";
        project.mkdir();
        shared = base / "shared";
        (shared / "nested").mkdir(parents=True);
        compiler = _compiler(project);
        local = project / "Local.jac";
        local.write_text('def:pub Local -> any { return <span>local</span>; }\n');
        label = shared / "nested" / "Label.jac";
        label.write_text('def:pub Label -> any { return <span>label</span>; }\n');
        javascript = shared / "utils.js";
        javascript.write_text('export const label = "external";\n');
        card = shared / "Card.jac";
        card.write_text(
            'import from .nested.Label { Label }\n'
            'import from ..myapp.Local { Local }\n'
            'import "./utils.js";\n'
            'def:pub Card -> any { return <div><Label/><Local/></div>; }\n'
        );
        entry_file = project / "frontend.jac";
        entry_file.write_text(
            'import from ..shared.Card { Card }\n'
            'def:pub app -> any { return <Card/>; }\n'
        );
        try {
            compiler.emit_dependencies(entry_file, source_root=project);
            _assert_import(_emitted(compiler, entry_file), _emitted(compiler, card));
            _assert_import(_emitted(compiler, card), _emitted(compiler, label));
            _assert_import(_emitted(compiler, card), _emitted(compiler, local));
            copied_js = compiler._output_path_for(javascript, project);
            assert copied_js.read_text() == javascript.read_text();
            _assert_import(_emitted(compiler, card), copied_js);
        } finally {
            set_config(None);
        }
    }
}

test "external imports keep same-named modules distinct on cold and warm emission" {
    with TemporaryDirectory() as tmp {
        set_config(None);
        base = Path(tmp).resolve();
        project = base / "myapp";
        project.mkdir();
        compiler = _compiler(project);
        cards: list[Path] = [];
        for name in ["a", "b"] {
            folder = base / name;
            folder.mkdir();
            card = folder / "Card.jac";
            card.write_text(
                f'def:pub Card{name} -> any {{ return <div>{name}</div>; }}\n'
            );
            cards.append(card);
        }
        entry_file = project / "frontend.jac";
        entry_file.write_text(
            'import from ..a.Card { Carda }\n'
            'import from ..b.Card { Cardb }\n'
            'def:pub app -> any { return <div><Carda/><Cardb/></div>; }\n'
        );
        try {
            for build_index in range(2) {
                compiler.emit_dependencies(entry_file, source_root=project);
                outputs = [_emitted(compiler, card) for card in cards];
                assert outputs[0] != outputs[1];
                for output in outputs {
                    _assert_import(_emitted(compiler, entry_file), output);
                    source_map = json.loads(output.with_suffix(".js.map").read_text());
                    assert source_map["file"] == output.name;
                }
                for card in cards {
                    output = _emitted(compiler, card);
                    assert output.is_relative_to(compiler.compiled_dir);
                    source_map = json.loads(output.with_suffix(".js.map").read_text());
                    assert source_map["sources"] == [str(card)];
                }
                if build_index == 0 {
                    compiler = _compiler(project);
                }
            }
        } finally {
            set_config(None);
        }
    }
}

test "a shared module gets imports for each consumer's layout rather than a cached previous layout" {
    with TemporaryDirectory() as tmp {
        set_config(None);
        base = Path(tmp).resolve();
        app_a = base / "app_a";
        app_b = base / "app_b";
        shared = base / "shared";
        app_a.mkdir();
        app_b.mkdir();
        shared.mkdir();
        (shared / "jac.toml").write_text(
            '[project]\nname = "@tests/shared-ui"\nexports = ["*"]\n'
        );
        local = app_a / "Local.jac";
        local.write_text('def:pub Local -> any { return <span>local</span>; }\n');
        component = shared / "Card.jac";
        component.write_text(
            'import from ..app_a.Local { Local }\n'
            'def:pub Card -> any { return <Local/>; }\n'
        );
        program = JacProgram();
        try {
            for project in [app_a, app_b, app_a] {
                compiler = _compiler(project, program);
                entry_file = project / "frontend.jac";
                entry_file.write_text(
                    'import from ..shared.Card { Card }\n'
                    'def:pub app -> any { return <Card/>; }\n'
                );
                compiler.emit_dependencies(entry_file, source_root=project);
                _assert_import(
                    _emitted(compiler, entry_file), _emitted(compiler, component)
                );
                _assert_import(
                    _emitted(compiler, component), _emitted(compiler, local)
                );
            }
        } finally {
            set_config(None);
        }
    }
}

test "real Vite bundles external components with identical filenames" {
    node_bin = shutil.which("node");
    if node_bin is None {
        testskip("Node is required for the real Vite build");
    }
    found = subprocess.run(
        [node_bin, "-p", 'require.resolve("vite/package.json")'],
        capture_output=True,
        text=True,
        timeout=10
    );
    if found.returncode != 0 {
        testskip("Vite must already be installed on Node's search path (NODE_PATH)");
    }
    vite_package = Path(found.stdout.strip());
    node_modules = vite_package.parent.parent;
    with TemporaryDirectory() as tmp {
        set_config(None);
        base = Path(tmp).resolve();
        project = base / "myapp";
        project.mkdir();
        _compiler(project);
        client_dir = project / ".jac" / "client";
        client_dir.mkdir(parents=True, exist_ok=True);
        linked_modules = client_dir / "node_modules";
        linked_modules.mkdir();
        for package in node_modules.iterdir() {
            if not package.name.startswith(".") {
                (linked_modules / package.name).symlink_to(
                    package, target_is_directory=package.is_dir()
                );
            }
        }
        for name in ["a", "b"] {
            folder = base / name;
            folder.mkdir();
            (folder / "Card.jac").write_text(
                'def:pub Card'
                    + name
                    + ' -> any { return <div>EXTERNAL_CARD_'
                    + name
                    + '</div>; }\n'
            );
        }
        entry_file = project / "frontend.jac";
        entry_file.write_text(
            'import from ..a.Card { Carda }\n'
            'import from ..b.Card { Cardb }\n'
            'def:pub app -> any { return <div><Carda/><Cardb/></div>; }\n'
        );
        try {
            compiler = ViteClientBundleBuilder(
                vite_package_json=project / "package.json", program=JacProgram()
            )._get_compiler();
            compiler.compile(None, entry_file);
            config = compiler.vite_bundler.create_vite_config(
                entry_file=compiler.compiled_dir / "_entry.js"
            );
            result = subprocess.run(
                [
                    node_bin,
                    str(vite_package.parent / "bin" / "vite.js"),
                    "build",
                    "--config",
                    str(config)
                ],
                cwd=client_dir,
                capture_output=True,
                text=True,
                timeout=60
            );
            assert result.returncode == 0 , result.stdout + result.stderr;
            bundled = "\n".join(
                path.read_text()
                for path in compiler.vite_bundler.output_dir.rglob("*.js")
            );
            assert "EXTERNAL_CARD_a" in bundled and "EXTERNAL_CARD_b" in bundled;
        } finally {
            set_config(None);
        }
    }
}
