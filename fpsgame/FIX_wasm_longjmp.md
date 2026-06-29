# Fix: `LinkError: env.longjmp ... requires a callable` after upstream sync

**Date:** 2026-06-29
**Area:** `fpsgame/raylib_shim.cl.jac` (WebGL shim → wasm import environment)
**Status:** ✅ Fixed & verified (world renders again)

---

## Symptom

After rebasing `fps_game_branch` onto the latest upstream `main` and rebuilding,
`jac start main.jac` served the page but the canvas stayed blank (just the HUD /
crosshair, no world). The dev-server log showed the wasm failing to instantiate:

```
[Client] WebAssembly.instantiate(): Import #15 "env" "longjmp":
function import requires a callable
    LinkError: WebAssembly.instantiate(): Import #15 "env" "longjmp":
    function import requires a callable
```

The wasm downloaded fine (`GET /static/main.wasm … 200`) - this is a **link-time**
failure: the module declares an import the host (our shim) doesn't provide, so it
never instantiates and `init()`/`frame()` never run.

## Root cause

The blank screen was **not** a game bug - it was a consequence of syncing upstream.

Upstream `main` landed a refactor of the native/wasm code generator
(`jac/jaclang/compiler/passes/native/na_ir_gen_pass.impl/exceptions.impl.jac`)
that now lowers Jac's exception / unwind handling through C-style
`setjmp` / `longjmp`:

```jac
longjmp_fn = self._get_or_declare_extern("longjmp", ir.VoidType(), [i8p, i32]);
longjmp_fn.attributes.add("noreturn");

```

So the recompiled `main.wasm` now imports `env.longjmp`. Our shim
(`raylib_shim.cl.jac`) was written against the **older** compiler, which never
emitted that import, so `_build_env(...)` didn't supply it. One missing import is
enough to fail the whole `WebAssembly.instantiateStreaming` link.

## Diagnosis

Parsed the import section of the freshly built wasm directly to see exactly what
the new module needs vs. what the shim provides:

```
.jac/client/dist/main.wasm  →  39 env imports
```

Every import was already satisfied by the shim **except one**:

```
#15  env.longjmp   ← missing
```

(`setjmp` is compiled in internally and is **not** imported - only `longjmp` is.)
So the fix was surgical: provide a single `longjmp` stub.

## The fix

Added a `longjmp` entry to `_build_env(...)` in `raylib_shim.cl.jac`:

```jac
"longjmp": lambda env_ptr: int , val: int {
    # Upstream's wasm codegen (na_ir_gen_pass exceptions) lowers
    # exception unwinding through setjmp/longjmp, so the module now
    # imports env.longjmp. A true non-local jump back into wasm isn't
    # possible from JS, but the sim takes no exception path in normal
    # play -- this is emitted-but-unreached scaffolding that only needs
    # to be callable to link. Throw loudly if it ever actually fires.
    raise Error(f"wasm longjmp(val={val}): unhandled sim exception");
},
```

### Why a throwing stub (not a no-op)

`longjmp` is a `noreturn` non-local jump back to the matching `setjmp` landing pad.
A JS function fundamentally **cannot** unwind the wasm stack, so there is no
faithful host implementation. Two facts make a throwing stub the right call:

1. The sim has no `try`/`raise` and ran correctly under the old compiler, so the
   `longjmp` path is **emitted-but-unreached** scaffolding - it only needs to be a
   *callable* so the module links.
2. If it ever *is* hit, that means a real unhandled exception in the sim. A no-op
   would return into a `noreturn` call site → wasm `unreachable` trap (opaque). A
   throw surfaces a clear, greppable message instead.

## Verification

1. Stop the dev server (Ctrl-C).
2. `jac start main.jac` (rebuilds the `cl{}` client bundle; the wasm is unchanged).
3. Hard-refresh the browser (Ctrl-Shift-R) to bypass the cached `client.js`.

Result: the wasm instantiates, and the floor grid + box colliders + patrolling
bots render. No `longjmp` exception fired during play, confirming it was unreached
scaffolding.

> If a rebuild ever fails to pick up a shim change, the client build cache is
> sticky: `rm -rf .jac/client && jac start main.jac` forces a clean rebuild.

## Takeaway

When syncing upstream changes that touch the **native/wasm code generator**, the
hand-written wasm import environment in `raylib_shim.cl.jac` can fall out of sync
with the set of `env.*` imports the compiler emits. If instantiation fails with
`... requires a callable`, dump the wasm's import section, diff it against
`_build_env(...)`, and add stubs for any new imports.
