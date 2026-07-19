# fpsgame model test bench

Standalone three.js pages for previewing and posing the weapon GLBs **outside**
the game - no jac build, just a static web server, so edits show on a refresh.
This is where we cracked the viewmodel bug: the model rendered fine here while
invisible in the game, which isolated it to the game's own code.

## Run

```
cd fpsgame/test
python3 -m http.server 8765
```

Then open one of:

- **Viewmodel tuner** - http://localhost:8765/viewmodel-tuner/
  FPS-style forward view with sliders for the gun's rotation / position / scale.
  Drag until it looks right; the panel prints the exact values to paste into
  `render3d.cl.jac`'s `_load_gun_model`. Scale is ONE uniform factor for all
  guns so they keep real relative sizes (pistol small, sniper big).

- **Orbit preview** - http://localhost:8765/orbit-preview/
  Inspect a single model: orbit / zoom, colored axes (red=X green=Y blue=Z),
  and a readout of size / mesh count / bbox center. Good for checking a new
  GLB loads and which way its barrel points.

## Folders

- `models/` - sample GLBs copied from `../assets/models/` (rifle, pistol, sniper).
- `viewmodel-tuner/` - the pose tuner page.
- `orbit-preview/` - the single-model inspector page.

three.js is pulled from a CDN (unpkg, pinned to 0.169.0 to match the app).

## Current tuned pose (in the game)

```
wrap.rotation.set(0.0, 1.86, 0.12);
holder position = (0.22, -0.2, -0.32);
uniform scale    = 0.19;
```
