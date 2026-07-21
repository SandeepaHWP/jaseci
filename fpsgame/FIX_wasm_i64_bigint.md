# Fix: `TypeError: Cannot convert 1 to a BigInt` when switching maps

**Date:** 2026-06-29
**Area:** `fpsgame/raylib_shim.cl.jac` (`run_game`, the JS to wasm call boundary)
**Status:** Fixed and verified (both maps load; no refresh needed to switch)

---

## Symptom

In the Phase 2A Settings screen, choosing the **Open** map and pressing Play
worked, but choosing **Cover** produced a blank game screen and this client error:

```
[Client] Cannot convert 1 to a BigInt
TypeError: Cannot convert 1 to a BigInt
    at raylib_shim.cl.jac:501
```

Worse, after the failure, switching back to **Open** and pressing Play also
showed a blank screen: the game only recovered after a full page refresh.

## Root cause

Two things compounded.

### 1. Jac `int` params are wasm `i64`, which need a JS `BigInt`

The native export is declared with a plain `int`:

```jac
def set_map(mid: int) { world_set_map(WORLD, mid); }
```

Jac lowers `int` to a wasm **i64**. WebAssembly i64 parameters cannot be passed
a JavaScript `number` across the boundary; they must be passed a `BigInt`. The
shim was calling it with a plain number:

```jac
inst.exports.set_map(opts.get("map_id", 0));   // passes 1 (number) -> throws
```

So `set_map(1)` threw `TypeError: Cannot convert 1 to a BigInt`.

Why **Open** worked but **Cover** did not: the call is guarded by
`if opts.get("map_id", 0) > 0`. Map 0 (Open) is the wasm default and skips
`set_map` entirely, so the bug never fired. Map 1 (Cover) is the only path that
actually calls `set_map`, so only Cover hit it.

This was a latent Phase 1 bug: `set_map` was exported but never called from JS
until 2A wired up the map selector, so the i64 boundary issue only surfaced now.

### 2. A thrown start wedged the re-entrancy guard

`run_game` sets `window.__fps_active = True` up front (the StrictMode / double
start guard). The `set_map` throw happened *after* that flag was set but *before*
the loop started, and nothing reset it. With `__fps_active` stuck True, every
later Play returned immediately at `if guard.__fps_active { return; }`, so the
screen stayed blank until a refresh cleared the window globals.

## The fix

**1. Pass a `BigInt` to the i64 parameter:**

```jac
if opts is not None and opts.get("map_id", 0) > 0 {
    inst.exports.set_map(BigInt(opts.get("map_id", 0)));
}
```

**2. Reset the guard if the start throws**, so a failed start can never wedge
the game:

```jac
try {
    inst.exports.__jac_glob_init();
    inst.exports.init();
    if opts is not None and opts.get("map_id", 0) > 0 {
        inst.exports.set_map(BigInt(opts.get("map_id", 0)));
    }
} except Exception as exc {
    guard.__fps_active = False;
    _remove_input(sh);
    raise exc;
}
```

## Verification

`jac start main.jac`, hard-refresh, then:

- Settings -> Cover -> Save -> Play loads the cover map.
- Settings -> Open -> Save -> Play loads the open map.
- Switching between them no longer requires a page refresh.

## Takeaway

Any wasm export that takes a Jac `int` (i64) must be called from the shim with a
`BigInt` argument, e.g. `exports.fn(BigInt(n))`. Plain JS numbers only work for
`f32`/`f64` (Jac `float`) and `i32` params. The HUD getters and `init` / `frame`
take no args, so `set_map` was the first export to expose this; future exports
that take an `int` (e.g. `set_bots`, `set_fov` in the settings-plumbing step)
must wrap their argument in `BigInt(...)` the same way. Also: any code path that
sets the `__fps_active` start guard should reset it on failure so an error never
wedges the game into a refresh-required state.
