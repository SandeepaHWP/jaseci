# FPS Game (deadshot.io-style) — Full Implementation Plan

A browser 3D first-person shooter built in **Jac**. Single-player first, multiplayer last.
This document is the complete, file-by-file, task-by-task build plan. Nothing here is
"high level" — every file, struct, function, and step we need is listed and checkable.

Project root: `jaseci/fpsgame/` (git-ignored).

---

## 0. Core Architecture (read once, never forget)

**One simulation, compiled to two targets.**

The gameplay simulation (movement, physics, bullets, hit registration) is written **once**
in an `na {}` codespace as a self-contained module. It compiles to:

- **WebAssembly** → runs in the browser as the client (and, in Phases 1–4, as the whole game).
- **Native** → runs on the server as the authority (only needed in Phase 5).

Same source = same math on both sides = no multiplayer desync. This is the whole reason
we use Jac. **Rule: sim logic never touches render, input, DOM, network, or the graph.**

Three codespaces:

| Codespace | Compiles to | Holds |
|-----------|-------------|-------|
| `na {}`   | wasm + native | simulation: state structs, physics, weapons, bots, maps |
| `cl {}`   | JavaScript (React) | rendering, input, HUD, menus, screens |
| `sv {}`   | Python (REST/graph) | accounts, persistence, leaderboards, lobbies (Phase 2+) |

Reference example we are cloning the structure of:
`jac/examples/raylib_shooter/web/` (`main.jac`, `raylib_shim.cl.jac`, `jac.toml`).

---

## 1. Target File Tree (final state, all phases)

```
fpsgame/
├── PLAN.md                      # this file
├── jac.toml                     # project + npm deps + plugins
├── main.jac                     # entry: cl{} app shell + router; mounts screens
│
├── sim/                         # na{} core simulation (wasm + native) -- AS BUILT (8 files)
│   ├── types.na.jac             # constants + Vec3, Box, Tracer, Ent, World
│   ├── mathx.na.jac             # jcos/jsin/fsqrt, LCG rand, atan2_deg
│   ├── physics.na.jac           # resolve, move_and_collide, ray_vs_box/world/ent
│   ├── maps.na.jac              # add_box, map_load (2 maps), pick_spawn
│   ├── render.na.jac            # raylib FFI + rlgl wrappers + draw_world
│   ├── combat.na.jac            # fire (hitscan), damage/death, reload, spawn_ent
│   ├── bots.na.jac              # patrol AI: assign_route, ping-pong waypoints, shoot-on-LoS
│   └── world.na.jac             # handle_input, new_round, world_init/frame/set_map
│   #  (weapons folded into combat+types; api exports live in main.jac's na{})
│
├── client/                      # cl{} browser side
│   ├── render.cl.jac            # WebGL render of world from exported sim state
│   ├── raylib_shim.cl.jac       # WebGL/DOM rlgl shim (copied + trimmed from example)
│   ├── input.cl.jac             # keyboard + mouse capture → input bitfield
│   ├── hud.cl.jac               # crosshair, health, ammo, score, killfeed overlay
│   ├── audio.cl.jac             # sfx (Phase 4)
│   ├── netclient.cl.jac         # WebSocket client (Phase 5)
│   └── screens/
│       ├── menu.cl.jac          # main menu
│       ├── settings.cl.jac      # settings screen
│       ├── game.cl.jac          # in-game screen (canvas + hud)
│       ├── gameover.cl.jac      # round summary
│       └── lobby.cl.jac         # multiplayer lobby (Phase 5)
│
├── server/                      # sv{} backend (Phase 2+)
│   ├── models.jac               # node/edge graph: Player, Profile, Match, Score
│   ├── auth.jac                 # login/register walkers
│   ├── scores.jac               # save score, leaderboard walkers
│   ├── settings_store.jac       # persist user settings
│   └── rooms.jac                # lobby/matchmaking (Phase 5)
│
└── shared/
    └── constants.jac            # tunables shared across codespaces (speeds, sizes, keys)
```

> Note: `na{}`/`cl{}`/`sv{}` can also be co-located in one file (as the example does).
> We split into modules for a real app. If a multi-file `na{}` import path misbehaves
> early, collapse `sim/*` back into one `sim.na.jac` and re-split later — track as P1-RISK.

---

## Progress Log & Gotchas (Phase 0–1)

Key things learned/fixed while getting Phase 1 playable:

- **jaclang core fix (committed in `5b1164819`):** `jac start` returned `500` on `/static/main.wasm`
  (`send_static_file method is not implemented`) — a tree-wide bug (the shipped raylib example
  failed too). Fixed by implementing `ResponseBuilder.send_static_file` and delegating from the
  base, in 3 files: `jac/jaclang/runtimelib/server.jac`, `…/runtimelib/impl/server.impl.jac`,
  `…/jac0core/impl/runtime.impl.jac`.
- **WASD "one-direction" bug:** compound `mvx += …` miscompiled to a constant in the wasm/native
  backend; fixed by explicit `mvx = mvx + …` in `handle_input`. (Worth reporting upstream.)
- **Shim hardening (`raylib_shim.cl.jac`):** (1) run-once guard `window.__fps_game_running` to stop
  React StrictMode's double-mount from starting two game loops; (2) wasm cache-bust
  `fetch("/static/main.wasm?t="+Date.now(), {cache:"no-store"})` because the URL has no content
  hash and the browser served stale wasm across rebuilds.
- **Workflow gotchas:** run `jac start` **from inside `fpsgame/`** (running from the repo root picks
  up jaclang's own `jac.toml` and pollutes it). If a rebuild doesn't pick up source changes, the
  build cache is sticky — `rm -rf .jac/client` forces a clean rebuild.
- **jactastic split:** ✅ DONE — sim is 8 `sim/*.na.jac` modules linking into one `main.wasm`
  (~56 KB), state threaded via a shared `World` object. `main.jac` is now a thin ~190-line entry.
- **Bot AI reworked:** bots were also drifting to the corner (they chased the player). Replaced
  chase with **random per-bot patrol routes** that ping-pong between 2-4 waypoints (a-b-a-b /
  a-b-c-b-a), with a per-waypoint timeout so they never stick; they still shoot the player on
  line of sight. (Bot firing is currently commented out in `sim/bots.na.jac` -- uncomment the
  marked block to re-enable; the supporting imports are kept.)
- **Jump/gravity dead -> backend constant bug:** jump never worked because gravity was not being
  applied. Root cause: the imported `GRAV` constant read wrong in the native/wasm arithmetic
  (`e.vy += GRAV * step`), so `vy` never accumulated -> player never fell -> `on_ground` never set
  -> the `on_ground`-gated jump never fired. Fix: explicit assignment + **inlined literal**
  (`e.vy = e.vy - 22.0 * step`) in `sim/physics.na.jac`. `GRAV` stays in `types` as the documented
  tunable. Same family as the `+=` miscompile (#WASD) -- both worth reporting upstream.

---

## PHASE 0 — Setup & Baseline  ✅ DONE

Goal: the stock example runs in the browser; we have a fresh project skeleton that builds.

- [x] P0-001  Install toolkit (repo `.venv`).
- [x] P0-002  Run the reference raylib_shooter/web; confirmed it plays.
- [x] P0-003  Read `raylib_shooter/web/main.jac`; noted the `cl{}`/`na{}` split and `run_game` handoff.
- [x] P0-004  Read `raylib_shooter/web/raylib_shim.cl.jac`; noted the rlgl surface it emulates.
- [x] P0-005  Read `littleX/social_graph.jac` for `node`/`edge`/`walker` patterns (Phase 2+).
- [x] P0-006  Created `fpsgame/jac.toml` (project + npm deps + `[plugins.client]`; the client runtime auto-added react-router-dom/zod/etc).
- [x] P0-007  Copied shim → `fpsgame/raylib_shim.cl.jac` (kept at project root, not `client/`).
- [x] P0-008  `cl{}` `def:pub app -> JsxElement` renders `<canvas id="glcanvas">`.
- [x] P0-009  `na{}` block with `init`/`frame` + HUD getters.
- [x] P0-010  `jac start` in `fpsgame/` renders the scene. **Phase 0 done.**

---

## PHASE 1 — Playable Core (NO persistence, NO menu, NO network)  ✅ PLAYABLE

Goal: load straight into a round. Move with physics, shoot, fight bots on a real map, die,
restart, close. Nothing is saved.

> **Status (as built):** ✅ Playable in-browser via `jac start`, and now **split into modules**
> (the jactastic refactor is DONE). `main.jac` is a thin entry: `cl{}` page + HUD and a small
> `na{}` block that owns one `glob WORLD: World` and exports `init`/`frame`/HUD getters. All sim
> logic lives in `sim/*.na.jac` and links into one `main.wasm` (verified ~56 KB).
>
> **Actual module layout (8 files under `sim/`):**
> `types` (constants + `Vec3`/`Box`/`Tracer`/`Ent`/`World`), `mathx` (jcos/jsin/fsqrt, LCG rand,
> atan2), `physics` (resolve, move_and_collide, ray casts), `maps` (colliders + spawns),
> `render` (raylib FFI + rlgl wrappers + `draw_world`), `combat` (fire/damage/reload/spawn),
> `bots` (patrol AI), `world` (input + lifecycle + per-frame step). State is threaded via the
> shared `World` object (module-global reassignment doesn't cross Jac modules).
>
> **Key design note:** all mutable state is on `World`, passed explicitly — this is also the
> Phase-5 foundation (one authoritative `World` per match, same sim compiled to native).
>
> **Bot AI (reworked):** bots no longer chase the player into a corner. Each bot gets a **random
> patrol route of 2–4 waypoints** and **ping-pongs** along it (a-b-a-b / a-b-c-b-a) with a
> per-waypoint timeout so it never gets stuck; it still faces movement and **shoots the player on
> line of sight**. Lives in `sim/bots.na.jac` (`assign_route`, `_next_waypoint`, `bot_update`).
>
> **Implemented:** combined `Ent` (player+bot), `Box`/`Vec3`/`Tracer`; jcos/jsin/fsqrt + LCG
> rand; 2 maps (open + cover) with perimeter walls; gravity/jump/AABB collision; ray-vs-AABB
> **hitscan** + per-shot tracer; damage/death/respawn; **patrol bot AI** (above); full HUD
> (HP/ammo/score/K-D/fps, crosshair, hit marker, death overlay); `set_map`/`restart`.
>
> **Deferred (not blocking Phase 1):** projectile `Bullet`s (using hitscan), multi-weapon
> `Weapon` table (single rifle via constants), headshot zone, weapon viewmodel, window-resize
> aspect handling, vec/clamp/lerp math helpers, per-`World.rng` seed (currently module-global LCG).
>
> The detailed `sim/*` checklist below is the original target outline; the **actual** layout is
> the 8 modules listed above (no separate `weapons`/`api` files — weapons fold into `combat` +
> `types` constants, the `api` exports live in `main.jac`; `render` was added for the FFI).

### 1A. Sim data model — `sim/types.na.jac`
- [ ] P1-001  `obj Vec3 { has x: float, y: float, z: float; }`
- [ ] P1-002  `obj PlayerState`: pos(Vec3), vel(Vec3), yaw, pitch, health, ammo, mag, weapon_id, fire_cd, reload_cd, on_ground(bool), alive(bool), score(int).
- [ ] P1-003  `obj Bullet`: pos(Vec3), vel(Vec3), life(float), owner_id(int), damage(int), active(bool).
- [ ] P1-004  `obj Bot`: state(PlayerState), ai_state(int), target_pos(Vec3), think_cd(float), reaction(float).
- [ ] P1-005  `obj InputState`: bitfield for keys (fwd/back/left/right/jump/fire/reload), dyaw, dpitch.
- [ ] P1-006  `obj World`: player(PlayerState), bots(list[Bot]), bullets(list[Bullet]), map_id(int), time(float), rng(int).
- [ ] P1-007  Constants: gravity, move_speed, jump_v, player_radius, player_height, eye_height.

### 1B. Math — `sim/mathx.na.jac`
- [ ] P1-008  `jcos`/`jsin` (range-reduced Taylor — copy from example).
- [ ] P1-009  `jsqrt` (Newton iteration), `clamp`, `lerp`, `vlen`, `vnorm`, `vadd`/`vsub`/`vscale`/`vdot`.
- [ ] P1-010  `rand01`/`rand_range` LCG; seed lives in `World.rng` (deterministic — no host RNG).

### 1C. Maps — `sim/maps.na.jac`
- [ ] P1-011  `obj Box { has min: Vec3, max: Vec3; }` (AABB collider).
- [ ] P1-012  `def map_colliders(map_id: int) -> list[Box]` returning floor + walls + a few crates/ramps.
- [ ] P1-013  `def spawn_points(map_id: int) -> list[Vec3]`.
- [ ] P1-014  At least 2 maps (`map_id` 0 and 1): one open arena, one with cover.
- [ ] P1-015  `def map_bounds(map_id: int) -> Box` for kill-plane / out-of-bounds.

### 1D. Physics — `sim/physics.na.jac`
- [ ] P1-016  `def apply_gravity(s: PlayerState, dt: float)`.
- [ ] P1-017  `def aabb_vs_box(pos, radius, height, box) -> Vec3` penetration resolution.
- [ ] P1-018  `def move_and_collide(s, world, dt)`: integrate velocity, resolve against all `map_colliders`.
- [ ] P1-019  `def ground_check(s, colliders) -> bool` → sets `on_ground`.
- [ ] P1-020  `def try_jump(s)`: if `on_ground`, set vertical velocity.
- [ ] P1-021  `def raycast(origin: Vec3, dir: Vec3, colliders, max_t) -> float` (ray vs AABB slab test) — for hitscan + bot LoS.
- [ ] P1-022  Clamp pitch to [-85, 85]; wrap yaw.

### 1E. Weapons — `sim/weapons.na.jac`
- [ ] P1-023  `obj Weapon`: id, name, damage, fire_rate, mag_size, reload_time, spread, recoil, range, projectile(bool).
- [ ] P1-024  `def weapon_table() -> list[Weapon]`: pistol, rifle, shotgun (start with 1, add later).
- [ ] P1-025  `def can_fire(s, now) -> bool` (fire_cd + ammo).
- [ ] P1-026  `def start_reload(s)` / `def finish_reload(s)`.

### 1F. Combat — `sim/combat.na.jac`
- [ ] P1-027  `def fire_weapon(shooter: PlayerState, world, now)`: hitscan path = raycast vs bots+map, apply damage; projectile path = spawn `Bullet`.
- [ ] P1-028  `def step_bullets(world, dt)`: integrate, collide vs map + bots, expire by life.
- [ ] P1-029  `def apply_damage(target: PlayerState, dmg: int, world)`: reduce health, handle death.
- [ ] P1-030  `def on_death(victim, killer_id, world)`: mark dead, increment killer score, schedule respawn.
- [ ] P1-031  `def hitbox_test(ray, target: PlayerState) -> bool` (capsule/AABB around player).
- [ ] P1-032  Headshot multiplier zone (upper hitbox).

### 1G. Bots — `sim/bots.na.jac`
- [ ] P1-033  `def bot_spawn(world, map_id)`: place N bots at spawn points.
- [ ] P1-034  `def bot_think(bot, world, dt)`: choose target (nearest alive), set desired move/aim.
- [ ] P1-035  `def bot_move(bot, world, dt)`: steer toward target with separation, use `move_and_collide`.
- [ ] P1-036  `def bot_aim(bot, world)`: lead/aim at player with `reaction` delay + spread.
- [ ] P1-037  `def bot_shoot(bot, world, now)`: line-of-sight via `raycast`, then `fire_weapon`.
- [ ] P1-038  `def bot_respawn(bot, world)` after death timer.
- [ ] P1-039  Difficulty knobs: reaction time, accuracy, aggression.

### 1H. World orchestration — `sim/world.na.jac`
- [ ] P1-040  `def world_init(map_id, bot_count) -> World`: build player, bots, empty bullet pool, seed rng.
- [ ] P1-041  `def world_reset(world)`: restart round in place.
- [ ] P1-042  `def player_respawn(world)` at a free spawn point.
- [ ] P1-043  `def world_step(world, input: InputState, dt)`: input→player intent→physics→fire→bullets→bots→deaths→timers. The single tick function (reused by server in Phase 5).

### 1I. Exported sim API — `sim/api.na.jac`
- [ ] P1-044  `glob WORLD: World` module-level singleton (browser entry pattern from example).
- [ ] P1-045  `def init(map_id: int, bots: int)`: build `WORLD`, open window/canvas sizing.
- [ ] P1-046  `def set_input(keys: int, dyaw: float, dpitch: float)`: marshal input from JS each frame.
- [ ] P1-047  `def frame() -> bool`: read input, `world_step`, render via rlgl, return should_close.
- [ ] P1-048  Readout exports for HUD: `get_health`, `get_ammo`, `get_mag`, `get_score`, `get_alive`, `get_bot_count`.
- [ ] P1-049  `def restart()`.

### 1J. Rendering (inside `na{}` via rlgl, like the example) — `sim/api.na.jac` + shim
- [ ] P1-050  Reuse example draw helpers: `begin_frame`, `set_camera`, `draw_floor`, `draw_box`, `end_camera`, `end_frame`, `draw_fps`.
- [ ] P1-051  `def draw_world(world)`: floor grid + map colliders as shaded boxes + bots as boxes + bullets + muzzle flash.
- [ ] P1-052  Draw bots with a distinct color; dead bots hidden.
- [ ] P1-053  Draw simple weapon viewmodel (a box bottom-right) + recoil kick.
- [ ] P1-054  Crosshair (2D overlay) — or defer to HUD layer in `cl{}`.

### 1K. Client glue — `client/input.cl.jac`, `client/render.cl.jac`, `main.jac`
- [ ] P1-055  `input.cl.jac`: capture keydown/keyup → key bitfield; pointer-lock mouse → dyaw/dpitch deltas; expose `read_input()`.
- [ ] P1-056  `main.jac` `cl{}`: `app` mounts `<canvas id="glcanvas">`; on entry call `run_game(canvas, on_frame)`.
- [ ] P1-057  Per-frame: read input from `input.cl.jac`, call `set_input(...)`, then sim `frame()`.
- [ ] P1-058  Pointer-lock UX: click canvas to capture, Tab/Esc to release (copy example logic).
- [ ] P1-059  Window resize handling → update camera aspect.

### 1L. Phase 1 gameplay tuning & exit criteria
- [ ] P1-060  Tune move speed, gravity, jump height, mouse sensitivity for good feel.
- [ ] P1-061  Tune fire rate, damage, bot difficulty for a fair fight.
- [ ] P1-062  Death → brief "you died" overlay → auto respawn or restart key.
- [ ] P1-063  Round/score display via HUD readouts.
- [ ] P1-064  Manual playtest checklist: collide with walls, can't fall through floor, can't leave bounds, jump works, bots chase + shoot, you can die and kill.
- [x] **P1-DONE**  Playable round vs bots on 2 maps, restartable, no persistence. (Committed in `5b1164819`; folder is git-ignored but force-added.)

**Risks (resolved):**
- [x] P1-RISK-1  Multi-file `na{}` imports → **RESOLVED**: spike + full split both linked into one `main.wasm`. (Split currently reverted/deferred.)
- [x] P1-RISK-2  Float/FFI quirks → hit two real ones: `_quad` 12-param clib note, and **compound `+=` miscompiling to a constant in the wasm backend** (the WASD "one-direction" bug — fixed by using explicit `mvx = mvx + ...`).
- [x] P1-RISK-3  rlgl shim extended: added `KeyR` to keymap + `IsMouseButtonDown` (full-auto fire).

---

## PHASE 2 — Single-Player + Persistence + Main Menu

Goal: real main menu, settings, and saved scores/settings that survive reloads. Still bots-only.

### 2A. Screens — `client/screens/*.cl.jac` + router in `main.jac`
- [ ] P2-001  `main.jac`: app-level state machine `screen: "menu"|"settings"|"game"|"gameover"`.
- [ ] P2-002  `menu.cl.jac`: Play, Settings, (Leaderboard), title, version.
- [ ] P2-003  `settings.cl.jac`: mouse sensitivity, FOV, master volume, key rebinds, map select, bot count/difficulty.
- [ ] P2-004  `game.cl.jac`: hosts canvas + HUD; mount/unmount starts/stops the sim loop cleanly.
- [ ] P2-005  `gameover.cl.jac`: round stats (kills, deaths, accuracy, time) + Play Again / Menu.
- [ ] P2-006  Navigation wiring + back buttons + Esc-to-menu.
- [ ] P2-007  Clean teardown: stop `requestAnimationFrame`, release pointer-lock, free wasm world on unmount.

### 2B. HUD — `client/hud.cl.jac`
- [ ] P2-008  React HUD overlay reading sim exports each frame: health bar, ammo/mag, score, crosshair, low-ammo/reload indicator.
- [ ] P2-009  Hit marker on damage dealt; damage vignette on damage taken.
- [ ] P2-010  Kill feed list (last N events) — events surfaced from sim via an export ring buffer.

### 2C. Persistence backend — `server/*.jac` (`sv{}` + graph)
- [ ] P2-011  `server/models.jac`: `node Player { has username, created_at; }`, `node Profile { has high_score, total_kills, settings_json; }`, `edge Owns`, `node ScoreEntry { has score, map_id, ts; }`.
- [ ] P2-012  `server/settings_store.jac`: `walker:pub save_settings`, `walker:pub load_settings`.
- [ ] P2-013  `server/scores.jac`: `walker:pub submit_score`, `walker:pub get_high_score`, `walker:pub leaderboard(top: int)`.
- [ ] P2-014  Decide identity for Phase 2: anonymous per-browser id (localStorage uuid) vs real login (defer login to Phase 3). Use anon id now.
- [ ] P2-015  `jac.toml`: keep `[plugins.client]`; `jac start` already serves `sv{}` endpoints — confirm auto-generated client stubs are callable from `cl{}`.

### 2D. Client ↔ server wiring
- [ ] P2-016  On settings change → call `save_settings` (auto-generated stub); on boot → `load_settings`.
- [ ] P2-017  On round end → `submit_score`; menu shows `get_high_score`.
- [ ] P2-018  Optional leaderboard panel in menu via `leaderboard`.
- [ ] P2-019  Graceful offline fallback to localStorage if server unavailable.
- [ ] **P2-DONE**  Menu → settings persisted → play vs bots → score saved → reload keeps high score + settings.

---

## PHASE 3 — Full Single-Player App (bots only, no multiplayer)

Goal: a complete, shippable single-player product.

### 3A. Accounts
- [ ] P3-001  `server/auth.jac`: `walker:pub register`, `walker:pub login` (hash+salt), session token.
- [ ] P3-002  Migrate anon profiles → real accounts on first login.
- [ ] P3-003  Login/register screens; auth-gated leaderboard.
- [ ] P3-004  Confirm compile-time auth: which `walker:pub`/`def:pub` require auth (Jac is secure-by-default).

### 3B. Game modes (single-player)
- [ ] P3-005  Wave survival mode (escalating bot waves).
- [ ] P3-006  Time attack / target practice mode.
- [ ] P3-007  Free-for-all vs bots with score target.
- [ ] P3-008  Mode select in menu; mode rules parameterize `world_init`/`world_step`.

### 3C. Content
- [ ] P3-009  3–5 finished maps with art pass (colors, props, lighting fakes).
- [ ] P3-010  Full weapon roster (pistol, rifle, shotgun, smg, sniper) with distinct feel.
- [ ] P3-011  Weapon pickups / loadout selection.
- [ ] P3-012  Bot difficulty tiers + per-mode tuning.

### 3D. Progression
- [ ] P3-013  XP/level or unlocks stored on `Profile`.
- [ ] P3-014  Per-map and per-mode leaderboards (graph walkers).
- [ ] P3-015  Match history (`node Match` + `edge Played`).

### 3E. Polish baseline
- [ ] P3-016  Pause menu, resume, restart, quit-to-menu.
- [ ] P3-017  Loading states + error toasts on server calls.
- [ ] P3-018  Full end-to-end QA pass of the single-player loop.
- [ ] **P3-DONE**  Shippable single-player game: accounts, modes, maps, weapons, progression, leaderboards.

---

## PHASE 4 — Enhancements

Goal: make it feel good. No new architecture.

- [ ] P4-001  `client/audio.cl.jac`: sfx (fire, hit, reload, footstep, death), volume from settings.
- [ ] P4-002  Particles: muzzle flash, impact sparks, blood/hit puffs, tracers.
- [ ] P4-003  Recoil/spread patterns per weapon; ADS (aim-down-sights) + FOV change.
- [ ] P4-004  Minimap / radar in HUD.
- [ ] P4-005  Better bot AI: cover usage, strafing, grenade/special (optional).
- [ ] P4-006  Optional `by llm()` bot "director" for taunts/difficulty adaptation (byllm plugin).
- [ ] P4-007  Visual upgrade path: evaluate swapping rlgl shim for Three.js in `cl{}` render (keep `na{}` sim untouched).
- [ ] P4-008  Mobile/touch controls + responsive layout.
- [ ] P4-009  Accessibility: colorblind crosshair, sensitivity presets, key rebinding completeness.
- [ ] P4-010  Performance pass: profile wasm frame time, pool allocations, cap draw calls.
- [ ] P4-011  Settings: graphics quality, FOV slider, resolution scale.
- [ ] **P4-DONE**  Polished, juicy single-player game.

---

## PHASE 5 — Multiplayer (the mountain: ~60% of total effort)

Goal: real-time PvP. The `na{}` sim now also compiles native for the authoritative server.

### 5A. Build the sim for the server
- [ ] P5-001  Compile `sim/*.na.jac` to **native** for server use (`jac nacompile` / sv import).
- [ ] P5-002  Verify wasm-vs-native **float determinism** with a fixed-input replay test (CRITICAL — do this first).
- [ ] P5-003  Make `world_step` fully deterministic: fixed dt, integer/seeded rng only, no wall-clock, no host calls.

### 5B. Transport
- [ ] P5-004  Study `jac/jaclang/runtimelib/transport.jac` (`WebSocketTransport`, `MessageType`).
- [ ] P5-005  `client/netclient.cl.jac`: open WS, (re)connect, send input frames, receive snapshots.
- [ ] P5-006  Server WS endpoint: accept connections, map socket→player, room assignment.
- [ ] P5-007  Wire protocol: input msg `{seq, keys, dyaw, dpitch, t}`; snapshot msg `{tick, players[], bullets[], events[]}`. Binary-pack if needed.

### 5C. Authoritative server loop
- [ ] P5-008  Fixed-tick server loop (20–30Hz) per room: drain inputs → `world_step` (native sim) → broadcast snapshot.
- [ ] P5-009  Server owns spawns, deaths, scores, round timer.
- [ ] P5-010  Anti-cheat: validate input rates, ignore client-claimed positions/hits.
- [ ] P5-011  Lag compensation: keep ~200ms ring of player positions; rewind for hit registration.

### 5D. Client prediction & smoothing
- [ ] P5-012  Client runs the same wasm `world_step` on local input (prediction).
- [ ] P5-013  Reconciliation: on snapshot, replay unacked inputs from authoritative state; correct/snap.
- [ ] P5-014  Interpolation buffer for remote players (render ~100ms in the past).
- [ ] P5-015  Extrapolation for dropped packets; smooth error correction (no teleport).

### 5E. Rooms / lobbies / matchmaking — `server/rooms.jac`
- [ ] P5-016  `node Room`, `walker:pub create_room`, `walker:pub join_room`, `walker:pub list_rooms`.
- [ ] P5-017  Quick-match matchmaking; room capacity, ready-up, start.
- [ ] P5-018  `client/screens/lobby.cl.jac`: browse/create/join, player list, ready, countdown.
- [ ] P5-019  Spectator + late-join handling.

### 5F. Multiplayer UX
- [ ] P5-020  Nameplates, team colors, scoreboard (Tab), live kill feed from server events.
- [ ] P5-021  Disconnect/reconnect handling; fill bots for empty slots.
- [ ] P5-022  Ping display + network quality indicator.
- [ ] **P5-DONE**  Two+ browsers play a fair, smooth, server-authoritative match.

---

## PHASE 6 (optional) — Deploy & Scale

- [ ] P6-001  `jac start --scale` via `jac-scale` (auto K8s + Redis + MongoDB).
- [ ] P6-002  Persistent graph = production DB; configure storage.
- [ ] P6-003  Multiple game-server instances + room sharding via Redis.
- [ ] P6-004  Domain, TLS, CDN for client bundle.
- [ ] P6-005  Metrics/logging/alerting; load test concurrent rooms.

---

## Appendix A — Jac construct cheat sheet (used here)

- `na { ... }` — native/wasm codespace. Our sim. `import from raylib { def ... }` externs → wasm imports (browser) or native lib (server).
- `cl { ... }` — client codespace → React/JS. `def:pub app -> JsxElement` is the page. JSX inline.
- `sv { ... }` — server codespace → Python. `def:pub` → `POST /function/<name>`; `walker:pub` → `POST /walker/<name>`; client stubs auto-generated.
- `node` / `edge` / `walker` — graph persistence; the graph IS the database (no ORM).
- `obj` — plain struct/class. `has field: type = default;`. `def name -> ret { ... }`.
- `glob` — module-global (e.g. `glob WORLD: World`).
- `jac start` — build cl bundle + na→wasm + serve. `--dev` = hot reload. `jac build` = artifacts only.

## Appendix B — Conventions

- Sim is pure: no DOM, no network, no graph, no wall-clock inside `na{}`.
- Fixed timestep for anything that must match server later (Phase 5).
- Run `jac format --lintfix <file>` on every `.jac` before snapshotting.
- Keep `shared/constants.jac` as the single source of tunables.

## Appendix C — Definition of Done per phase
- P1: playable vs bots, 2 maps, physics, restart, no save.
- P2: menu + persisted settings/scores.
- P3: accounts, modes, full content, progression — shippable single-player.
- P4: audio/particles/polish/perf.
- P5: server-authoritative real-time multiplayer with prediction.
</content>
</invoke>
