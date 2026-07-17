# FPS Game - Phase 2A: screens + router + clean game lifecycle.
#
# Layout: this file is the thin entry -- the server graph (below), the cl{}
# app shell + screen router, and the na{} wasm interface. The screens live in
# client/ (styles, hud, screens/*.cl.jac); the sim lives in sim/*.na.jac.
#
# cl{} typing notes (the React/DOM layer IS type-checked at build):
#   * input handlers take `e: ChangeEvent` so e.target.value is `str`, then
#     int()/str() convert (typed builtins reject `Any`).
#   * values read back from the wasm `exports` object are `Any`; relational ops
#     (>, >=) don't work on `Any`, so they're funneled to `int` via an
#     f-string -> int() round-trip before comparing.
#   * sensitivity is carried as a 1..60 percentage; the sim wiring in the next
#     step divides by 100. No float math lives in the UI.

# ─── Persistence (Phase 2C) ──────────────────────────────────────────────────
# Server-side graph: one Profile node per browser, keyed by an anonymous
# client_id (a localStorage UUID -- no login yet, that's Phase 3). Walkers are
# spawned from cl{} via `root spawn <walker>(...)`. The graph is in-memory
# unless MongoDB is configured, so it survives reloads but not server restarts.
"""A player's saved settings + stats, one per anonymous browser client_id."""
node Profile {
    has client_id: str,
        high_score: int = 0,
        total_kills: int = 0,
        sens: int = 12,
        fov: int = 90,
        bots: int = 5,
        map_id: int = 0,
        target: int = 5;
}

"""Find this client's Profile under root, or create it; visit it."""
walker:pub load_profile {
    has client_id: str;

    can run with Root entry {
        existing = [
            p
            for p in [-->[?:Profile]]
            if p.client_id == self.client_id
        ];
        if existing {
            visit existing[0];
        } else {
            fresh = here ++> Profile(client_id=self.client_id);
            visit fresh;
        }
    }

    can give with Profile entry {
        report here;
    }
}

"""Persist the settings for this client's Profile."""
walker:pub persist_settings {
    has client_id: str,
        sens: int,
        fov: int,
        bots: int,
        map_id: int,
        target: int;

    can run with Root entry {
        existing = [
            p
            for p in [-->[?:Profile]]
            if p.client_id == self.client_id
        ];
        if existing {
            visit existing[0];
        } else {
            fresh = here ++> Profile(client_id=self.client_id);
            visit fresh;
        }
    }

    can apply with Profile entry {
        here.sens = self.sens;
        here.fov = self.fov;
        here.bots = self.bots;
        here.map_id = self.map_id;
        here.target = self.target;
        report here;
    }
}

"""Record a round result: bump total kills, keep the best as high score."""
walker:pub submit_score {
    has client_id: str,
        kills: int;

    can run with Root entry {
        existing = [
            p
            for p in [-->[?:Profile]]
            if p.client_id == self.client_id
        ];
        if existing {
            visit existing[0];
        } else {
            fresh = here ++> Profile(client_id=self.client_id);
            visit fresh;
        }
    }

    can apply with Profile entry {
        here.total_kills += self.kills;
        if self.kills > here.high_score {
            here.high_score = self.kills;
        }
        report here;
    }
}

cl {
    import from .client.styles { ensure_styles }
    import from .client.screens.menu { Menu }
    import from .client.screens.settings { Settings }
    import from .client.screens.game { GameView }
    import from .client.screens.gameover { GameOver }

    # ── App shell: the screen state machine / router ───────────────────────────
    def:pub app -> JsxElement {
        has screen: str = "menu",
            mode: int = 0,
            sens: int = 12,
            fov: int = 90,
            bots: int = 5,
            mapId: int = 0,
            target: int = 5,
            statWon: bool = False,
            statKills: int = 0,
            statDeaths: int = 0,
            statTime: int = 0,
            highScore: int = 0,
            clientId: str = "";

        # Boot: ensure an anonymous client_id, then load this browser's saved
        # Profile (settings + high score) from the server graph.
        async can with entry {
            ensure_styles();
            win: any = window;
            ls: any = win.localStorage;
            existing_cid: any = ls.getItem("fps_cid");
            cid: str = f"{existing_cid}"
                if existing_cid
                else f"{win.crypto.randomUUID()}";
            if not existing_cid {
                ls.setItem("fps_cid", cid);
            }
            clientId = cid;
            result: any = root spawn load_profile(client_id=cid);
            p: any = None;
            if result and result.reports and result.reports.length {
                p = result.reports[0];
                # a single `report here` may arrive as the node or as [node];
                # unwrap one list level if present (arrays have .length, nodes don't)
                if p and p.length {
                    p = p[0];
                }
            }
            if p {
                sens = int(f"{p.sens}");
                fov = int(f"{p.fov}");
                bots = int(f"{p.bots}");
                mapId = int(f"{p.map_id}");
                target = int(f"{p.target}");
                highScore = int(f"{p.high_score}");
            }
        }
        def go_play {
            screen = "game";
        }
        def go_settings {
            screen = "settings";
        }
        def go_menu {
            screen = "menu";
        }
        def set_mode(m: int) {
            mode = m;
        }
        async def save_settings(ns: int, nf: int, nb: int, nm: int, nt: int) {
            sens = ns;
            fov = nf;
            bots = nb;
            mapId = nm;
            target = nt;
            screen = "menu";
            root spawn persist_settings(
                client_id=clientId, sens=ns, fov=nf, bots=nb, map_id=nm, target=nt
            );
        }
        async def end_game(won: bool, kills: int, deaths: int, secs: int) {
            statWon = won;
            statKills = kills;
            statDeaths = deaths;
            statTime = secs;
            if kills > highScore {
                highScore = kills;
            }
            screen = "gameover";
            root spawn submit_score(client_id=clientId, kills=kills);
        }
        return
            <div id="page">
                {(
                    <Menu
                        onPlay={go_play}
                        onSettings={go_settings}
                        highScore={highScore}
                        mode={mode}
                        onMode={set_mode}
                    />
                )
                    if screen == "menu"
                    else (
                        <Settings
                            sens={sens}
                            fov={fov}
                            bots={bots}
                            mapId={mapId}
                            target={target}
                            onSave={save_settings}
                            onBack={go_menu}
                        />
                    )
                        if screen == "settings"
                        else (
                            <GameView
                                mapId={mapId}
                                target={target}
                                sens={sens}
                                fov={fov}
                                bots={bots}
                                mode={mode}
                                onExit={go_menu}
                                onGameOver={end_game}
                            />
                        )
                            if screen == "game"
                            else (
                                <GameOver
                                    won={statWon}
                                    kills={statKills}
                                    deaths={statDeaths}
                                    timeSec={statTime}
                                    onPlayAgain={go_play}
                                    onMenu={go_menu}
                                />
                            )}
            </div>;
    }
}

# ─── Native entry points (compile to main.wasm; native-ready for Phase 5). ────
#     The simulation itself lives in sim/*.na.jac; this block is just the thin
#     wasm interface the shim calls (init / frame / HUD getters) over one World.
na {
    import from .sim.types { World, EYE_H }
    import from .sim.world {
        world_init,
        world_frame,
        new_round,
        world_set_map,
        time_left,
        round_over
    }

    glob WORLD: World = World();

    """Open the window and build the first round."""
    def init {
        world_init(WORLD);
    }

    """Advance and render one frame. Returns True when the game wants to close."""
    def frame -> bool {
        return world_frame(WORLD);
    }

    # ── HUD readouts (called from the cl{} on_tick hook) ───────────────────────
    def get_health -> int {
        return WORLD.player.health;
    }

    def get_mag -> int {
        return WORLD.player.mag;
    }

    def get_ammo -> int {
        return WORLD.player.ammo;
    }

    def get_score -> int {
        return WORLD.player.kills;
    }

    def get_kills -> int {
        return WORLD.player.kills;
    }

    def get_deaths -> int {
        return WORLD.player.deaths;
    }

    def get_alive -> int {
        return 1 if WORLD.player.alive else 0;
    }

    def get_hit -> int {
        return 1 if WORLD.hit_flash > 0.0 else 0;
    }

    def get_reloading -> int {
        return 1 if WORLD.player.reloading else 0;
    }

    """Current weapon id; the HUD maps it to a display name."""
    def get_weapon -> int {
        return WORLD.player.weapon_id;
    }

    # ── Render state getters (Phase 4.5: the cl{} Three.js renderer reads these) ─
    #    Floats return as JS numbers directly. Index args (i) are wasm i64, so the
    #    renderer must call them as fn(BigInt(i)) -- see FIX_wasm_i64_bigint.md.

    # camera (player eye + look angles)
    def get_cam_x -> float {
        return WORLD.player.x;
    }

    def get_cam_y -> float {
        return WORLD.player.y + EYE_H;
    }

    def get_cam_z -> float {
        return WORLD.player.z;
    }

    def get_cam_yaw -> float {
        return WORLD.player.yaw;
    }

    def get_cam_pitch -> float {
        return WORLD.player.pitch;
    }

    # bots (per-index transforms)
    def get_bot_count -> int {
        return len(WORLD.bots);
    }

    def get_bot_x(i: int) -> float {
        return WORLD.bots[i].x;
    }

    def get_bot_y(i: int) -> float {
        return WORLD.bots[i].y;
    }

    def get_bot_z(i: int) -> float {
        return WORLD.bots[i].z;
    }

    def get_bot_yaw(i: int) -> float {
        return WORLD.bots[i].yaw;
    }

    def get_bot_alive(i: int) -> int {
        return 1 if WORLD.bots[i].alive else 0;
    }

    # static map colliders (read once per map for scene geometry)
    def get_collider_count -> int {
        return len(WORLD.colliders);
    }

    def get_collider_minx(i: int) -> float {
        return WORLD.colliders[i].minx;
    }

    def get_collider_miny(i: int) -> float {
        return WORLD.colliders[i].miny;
    }

    def get_collider_minz(i: int) -> float {
        return WORLD.colliders[i].minz;
    }

    def get_collider_maxx(i: int) -> float {
        return WORLD.colliders[i].maxx;
    }

    def get_collider_maxy(i: int) -> float {
        return WORLD.colliders[i].maxy;
    }

    def get_collider_maxz(i: int) -> float {
        return WORLD.colliders[i].maxz;
    }

    # shot tracers (per-index endpoints) + muzzle flash trigger
    def get_tracer_count -> int {
        return len(WORLD.tracers);
    }

    def get_tracer_x0(i: int) -> float {
        return WORLD.tracers[i].x0;
    }

    def get_tracer_y0(i: int) -> float {
        return WORLD.tracers[i].y0;
    }

    def get_tracer_z0(i: int) -> float {
        return WORLD.tracers[i].z0;
    }

    def get_tracer_x1(i: int) -> float {
        return WORLD.tracers[i].x1;
    }

    def get_tracer_y1(i: int) -> float {
        return WORLD.tracers[i].y1;
    }

    def get_tracer_z1(i: int) -> float {
        return WORLD.tracers[i].z1;
    }

    def get_muzzle -> int {
        return 1 if WORLD.muzzle_t > 0.0 else 0;
    }

    """Set mouse sensitivity from a 1..60 percentage (12 -> 0.12)."""
    def set_sensitivity(pct: int) {
        WORLD.sens = float(pct) * 0.01;
    }

    """Set how many bots spawn each round (applied on the next new_round)."""
    def set_bots(n: int) {
        WORLD.bot_count = n;
    }

    """Switch map and restart the round (0 or 1)."""
    def set_map(mid: int) {
        world_set_map(WORLD, mid);
    }

    """Set the game mode, 0 = ffa / 1 = time attack (applied on new_round)."""
    def set_mode(m: int) {
        WORLD.mode = m;
    }

    """Whole seconds left on the round clock; 0 when the mode has no clock."""
    def get_time_left -> int {
        return int(time_left(WORLD));
    }

    """1 once a clocked round has run out of time."""
    def get_round_over -> int {
        return 1 if round_over(WORLD) else 0;
    }

    """Restart the current round."""
    def restart {
        new_round(WORLD);
    }
}
