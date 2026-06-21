# FPS Game - Phase 1: playable core (movement+physics, bots, maps, shooting).
# No persistence, no menu, no network. Loads straight into a round.
#
# Structure (Phase 1, per PLAN.md P1-RISK-1): the whole simulation lives in the
# entry module's na{} block so it compiles to /static/main.wasm, which the shim
# (raylib_shim.cl.jac) instantiates. The cl{} block is the page + HUD.

# ─── Client: page, canvas, HUD. The WebGL shim emulates raylib's rlgl + input
#     and drives init()/frame() per animation frame; on_tick updates the HUD. ──
cl {
    import from .raylib_shim { run_game }

    def:pub app -> JsxElement {
        can with entry {
            # React (StrictMode in dev) mounts the component twice, which would
            # start two game loops + two sets of input listeners fighting each
            # other. Guard so the game initializes exactly once per page.
            win: any = window;
            if win.__fps_started {
                return;
            }
            win.__fps_started = True;
            existing: any = document.getElementById("fps-styles");
            if not existing {
                css = """
                body { margin: 0; background: #0b0e16; overflow: hidden; }
                #page { min-height: 100vh; box-sizing: border-box; color: #cdd6e6;
                        font: 13px/1.4 ui-monospace, SFMono-Regular, Menlo, monospace;
                        display: flex; flex-direction: column; align-items: center;
                        gap: 8px; padding: 12px; }
                #wrap { position: relative; }
                #glcanvas { background: #0f121c; border: 1px solid #232a3d;
                            border-radius: 6px; display: block; cursor: crosshair; }
                #cross { position: absolute; left: 50%; top: 50%; width: 18px; height: 18px;
                         transform: translate(-50%, -50%); pointer-events: none; }
                #cross::before, #cross::after { content: ""; position: absolute;
                         background: #e8f0ff; opacity: 0.85; }
                #cross::before { left: 50%; top: 0; width: 2px; height: 100%; transform: translateX(-50%); }
                #cross::after { top: 50%; left: 0; height: 2px; width: 100%; transform: translateY(-50%); }
                #hud { position: absolute; left: 12px; bottom: 10px; pointer-events: none;
                       text-shadow: 0 1px 2px #000; font-size: 15px; }
                #hud b { color: #f5c451; }
                #stat { position: absolute; right: 12px; top: 10px; text-align: right;
                        pointer-events: none; text-shadow: 0 1px 2px #000; }
                #hitmark { position: absolute; left: 50%; top: 50%; transform: translate(-50%,-50%);
                           color: #ff5a5a; font-size: 22px; font-weight: 700; opacity: 0;
                           pointer-events: none; transition: opacity 0.08s; }
                #death { position: absolute; inset: 0; display: none; align-items: center;
                         justify-content: center; flex-direction: column; gap: 6px;
                         background: rgba(120,12,12,0.32); color: #ffd7d7; font-size: 26px;
                         font-weight: 700; pointer-events: none; }
                #death .sub { font-size: 14px; font-weight: 400; opacity: 0.85; }
                #hint { opacity: 0.65; }
                #hint b { color: #f5c451; }
                """;
                st: any = document.createElement("style");
                st.id = "fps-styles";
                st.textContent = css;
                head: any = document.head;
                head.appendChild(st);
            }
            run_game(
                document.getElementById("glcanvas"),
                lambda exports: any , fps: int {
                    hp: any = document.getElementById("hud-hp");
                    am: any = document.getElementById("hud-ammo");
                    sc: any = document.getElementById("stat-score");
                    kd: any = document.getElementById("stat-kd");
                    fp: any = document.getElementById("stat-fps");
                    death: any = document.getElementById("death");
                    hitm: any = document.getElementById("hitmark");
                    hp.textContent = exports.get_health();
                    am.textContent = f"{exports.get_mag()} / {exports.get_ammo()}";
                    sc.textContent = exports.get_score();
                    kd.textContent = f"{exports.get_kills()} / {exports.get_deaths()}";
                    fp.textContent = fps;
                    death.style.display = "flex"
                        if exports.get_alive() == 0
                        else "none";
                    hitm.style.opacity = "1" if exports.get_hit() == 1 else "0";
                }
            );
        }
        return
            <div id="page">
                <div id="hint">
                    {"Click to capture mouse · "}
                    <b>WASD</b>
                    {" move · "}
                    <b>Space</b>
                    {" jump · mouse aim · "}
                    <b>click</b>
                    {" fire · "}
                    <b>R</b>
                    {" reload · "}
                    <b>Tab</b>
                    {" release"}
                </div>
                <div id="wrap">
                    <canvas id="glcanvas" width={960} height={600}></canvas>
                    <div id="cross"></div>
                    <div id="hitmark">✕</div>
                    <div id="stat">
                        {"score "}
                        <b id="stat-score">0</b>
                        {" · K/D "}
                        <b id="stat-kd">0 / 0</b>
                        {" · "}
                        <b id="stat-fps">0</b>
                        {" fps"}
                    </div>
                    <div id="hud">
                        {"HP "}
                        <b id="hud-hp">100</b>
                        {"   AMMO "}
                        <b id="hud-ammo">30 / 90</b>
                    </div>
                    <div id="death">
                        <div>You died</div>
                        <div className="sub">respawning...</div>
                    </div>
                </div>
            </div>;
    }
}

# ─── Native entry points (compile to main.wasm; native-ready for Phase 5). ────
#     The simulation itself lives in sim/*.na.jac; this block is just the thin
#     wasm interface the shim calls (init / frame / HUD getters) over one World.
na {
    import from .sim.types { World }
    import from .sim.world { world_init, world_frame, new_round, world_set_map }

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

    """Switch map and restart the round (0 or 1)."""
    def set_map(mid: int) {
        world_set_map(WORLD, mid);
    }

    """Restart the current round."""
    def restart {
        new_round(WORLD);
    }
}
