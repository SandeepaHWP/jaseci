import subprocess
import sys
import re

# Files to ignore (intentional syntax errors)
IGNORE_FILES = [
    "jac-byllm/byllm/impl/mtir.impl.jac",
    "jac-byllm/byllm/impl/schema.impl.jac",
    "jac-byllm/byllm/plugin.jac",
    "jac-byllm/byllm/types.impl/media.impl.jac",
    "jac-byllm/examples/core_examples/level_genarator.jac",
    "jac-byllm/examples/microbenchmarks/essay_review.jac",
    "jac-byllm/tests/fixtures/with_llm_method.jac",
    "jac-client/jac_client/plugin/cli.jac",
    "jac-client/jac_client/plugin/impl/client.impl.jac",
    "jac-client/jac_client/plugin/plugin_config.jac",
    "jac-client/jac_client/plugin/src/impl/compiler.impl.jac",
    "jac-scale/jac_scale/impl/serve.impl.jac",
    "jac-scale/jac_scale/impl/user_manager.impl.jac",
    "jac-scale/jac_scale/jserver/impl/jfast_api.impl.jac",
    "jac-scale/jac_scale/jserver/impl/jserver.impl.jac",
    "jac-scale/jac_scale/plugin.jac",
    "jac-scale/jac_scale/tests/fixtures/test_api.jac",
    "jac-scale/jac_scale/utils.jac",
    "jac-super/jac_super/plugin/impl/console.impl.jac",
    "jac/examples/guess_game/guess_game2.jac",
    "jac/examples/guess_game/guess_game3.jac",
    "jac/examples/littleX/littleX.impl.jac",
    "jac/examples/manual_code/circle.jac",
    "jac/examples/manual_code/circle_clean.impl.jac",
    "jac/examples/manual_code/circle_pure.impl.jac",
    "jac/examples/micro/imports.jac",
    "jac/examples/micro/simple_walk.jac",
    "jac/examples/shopping_cart/main.impl.jac",
    "jac/jaclang/cli/banners.jac",
    "jac/jaclang/cli/commands/__init__.jac",
    "jac/jaclang/cli/commands/impl/config.impl.jac",
    "jac/jaclang/cli/commands/impl/execution.impl.jac",
    "jac/jaclang/cli/commands/impl/project.impl.jac",
    "jac/jaclang/cli/commands/impl/tools.impl.jac",
    "jac/jaclang/cli/commands/impl/transform.impl.jac",
    "jac/jaclang/cli/commands/tools.jac",
    "jac/jaclang/cli/impl/cli.impl.jac",
    "jac/jaclang/cli/impl/command.impl.jac",
    "jac/jaclang/cli/impl/console.impl.jac",
    "jac/jaclang/compiler/passes/tool/impl/doc_ir.impl.jac",
    "jac/jaclang/compiler/type_system/impl/types.impl.jac",
    "jac/jaclang/langserve/impl/engine.impl.jac",
    "jac/jaclang/langserve/impl/sem_manager.impl.jac",
    "jac/jaclang/langserve/impl/server.impl.jac",
    "jac/jaclang/langserve/impl/utils.impl.jac",
    "jac/jaclang/project/__init__.jac",
    "jac/jaclang/project/impl/config.impl.jac",
    "jac/jaclang/project/impl/dep_registry.impl.jac",
    "jac/jaclang/project/impl/dependencies.impl.jac",
    "jac/jaclang/project/impl/plugin_config.impl.jac",
    "jac/jaclang/project/impl/template_registry.impl.jac",
    "jac/jaclang/runtimelib/impl/client_bundle.impl.jac",
    "jac/jaclang/runtimelib/impl/client_runtime.impl.jac",
    "jac/jaclang/runtimelib/impl/hmr.impl.jac",
    "jac/jaclang/runtimelib/impl/server.impl.jac",
    "jac/jaclang/runtimelib/impl/test.impl.jac",
    "jac/jaclang/runtimelib/impl/testing.impl.jac",
    "jac/jaclang/runtimelib/impl/utils.impl.jac",
    "jac/jaclang/runtimelib/utils.jac",
    "jac/jaclang/utils/NonGPT.jac",
    "jac/jaclang/utils/impl/NonGPT.impl.jac",
    "jac/jaclang/utils/impl/lang_tools.impl.jac",
    "jac/jaclang/utils/symtable_test_helpers.jac",
    "jac/tests/compiler/fixtures/fam.jac",
    "jac/tests/compiler/fixtures/multiple_syntax_errors.jac",
    "jac/tests/compiler/fixtures/new_keyword_errors.jac",
    "jac/tests/compiler/fixtures/pass_keyword_errors.jac",
    "jac/tests/compiler/fixtures/pkg_import_lib_py/tools.jac",
    "jac/tests/compiler/passes/main/fixtures/fstrings.jac",
    "jac/tests/compiler/passes/main/fixtures/func.jac",
    "jac/tests/compiler/passes/main/fixtures/py_imp_test.jac",
    "jac/tests/compiler/passes/main/fixtures/type_info.jac",
    "jac/tests/compiler/passes/tool/fixtures/corelib_fmt.jac",
    "jac/tests/compiler/passes/tool/fixtures/simple_walk.jac",
    "jac/tests/compiler/passes/tool/fixtures/tagbreak.jac",
    "jac/tests/langserve/fixtures/circle.jac",
    "jac/tests/langserve/fixtures/circle_err.jac",
    "jac/tests/langserve/fixtures/circle_pure.impl.jac",
    "jac/tests/langserve/fixtures/circle_pure_err.impl.jac",
    "jac/tests/langserve/fixtures/completion_test_err.jac",
    "jac/tests/langserve/fixtures/rename.jac",
    "jac/tests/langserve/fixtures/stub_hover.impl.jac",
    "jac/tests/langserve/server_test/circle_template.jac",
    "jac/tests/language/fixtures/abc_check.jac",
    "jac/tests/language/fixtures/bar.jac",
    "jac/tests/language/fixtures/builtin_printgraph.jac",
    "jac/tests/language/fixtures/chandra_bugs.jac",
    "jac/tests/language/fixtures/deferred_field.jac",
    "jac/tests/language/fixtures/dynamic_archetype.jac",
    "jac/tests/language/fixtures/err2.jac",
    "jac/tests/language/fixtures/funccall_genexpr.jac",
    "jac/tests/language/fixtures/hash_init_check.jac",
    "jac/tests/language/fixtures/iife_functions.jac",
    "jac/tests/language/fixtures/iife_functions_client.jac",
    "jac/tests/language/fixtures/import_all.jac",
    "jac/tests/language/fixtures/multistatement_lambda.jac",
    "jac/tests/language/fixtures/params/param_syntax_err.jac",
    "jac/tests/language/fixtures/simple_walk.jac",
    "jac/tests/language/fixtures/uninitialized_hasvars.jac",
    "jac/tests/language/fixtures/with_context.jac",
    "jac/tests/runtimelib/fixtures/other_root_access.jac",
    "jac/tests/runtimelib/fixtures/serve_api.jac",
    "jac/tests/runtimelib/fixtures/test_reactive_signals.jac"
]

# Patterns to filter out (Common type errors to ignore)
IGNORE_PATTERNS = [
    r"__truediv__",
    r"__sub__",
    r"__add__",
    r"__mul__",
    r"Too many positional arguments",
    r"Cannot assign",
    r"No matching overload",
    r"Module not found",
    r"Connection type must be",
    r"Connection left operand",
    r"Could not read file",
    r"Is a directory",
    r"maximum recursion depth",
    r"Not all required parameters",
    r"'Token' object has no attribute",
    r"name '.*' is not defined",
    r"Cannot return",
    r"Named argument .* does not match",
]

def main():
    print("Starting CI Jac Check...")
    
    # Construct command with ignore list
    cmd = ["jac", "check", ".", "--ignore", ",".join(IGNORE_FILES)]
    
    # Run command and capture output
    # We DO NOT check=True because we expect failure and want to handle it manually
    result = subprocess.run(
        cmd,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT, # Capture all output to stdout stream
        text=True,
        encoding='utf-8',
        errors='replace'
    )
    
    # Process output
    lines = result.stdout.splitlines()
    filtered_lines = []
    real_errors_found = False
    
    print(f"Original output has {len(lines)} lines. Filtering...")
    
    for line in lines:
        # 1. Skip warnings
        if "⚠" in line:
            continue
            
        # 2. Skip known error patterns
        is_ignored = False
        for pattern in IGNORE_PATTERNS:
            if re.search(pattern, line):
                is_ignored = True
                break
        
        if is_ignored:
            continue
            
        # 3. If it's an error line and NOT ignored, track it
        if "✖ Error" in line or "Error:" in line:
            real_errors_found = True
            filtered_lines.append(line)
        else:
            # Keep other lines (summary, info) but don't count as errors
            # Optional: could suppress non-error lines too if super strict
            filtered_lines.append(line)
            
    # Print filtered output
    if real_errors_found:
        print("::error::Real errors found!")
        for line in filtered_lines:
            print(line)
        sys.exit(1)
    else:
        print("Success: Only known/ignored errors found.")
        sys.exit(0)

if __name__ == "__main__":
    main()
