# FPS Game - Phase 2A: screens + router + clean game lifecycle.
#
# The cl{} block is now an app shell with a screen state machine
# (menu | settings | game | gameover). The game itself is a child component
# (GameView) so it mounts when you enter the game screen and is torn down
# cleanly when you leave (stop_game halts the loop, detaches listeners, and
# releases the pointer). The na{} block (the wasm sim interface) is unchanged.
#
# cl{} typing notes (the React/DOM layer IS type-checked at build):
#   * input handlers take `e: ChangeEvent` so e.target.value is `str`, then
#     int()/str() convert (typed builtins reject `Any`).
#   * values read back from the wasm `exports` object are `Any`; relational ops
#     (>, >=) don't work on `Any`, so they're funneled to `int` via an
#     f-string -> int() round-trip before comparing.
#   * sensitivity is carried as a 1..60 percentage; the sim wiring in the next
#     step divides by 100. No float math lives in the UI.
cl {
    import from .raylib_shim { run_game, stop_game }

    """Inject the app stylesheet once (idempotent via the element id)."""
    def _ensure_styles {
        existing: any = document.getElementById("fps-styles");
        if existing {
            return;
        }
        css = """
        body { margin: 0; background: #0b0e16; overflow: hidden; }
        #page { min-height: 100vh; box-sizing: border-box; color: #cdd6e6;
                font: 13px/1.4 ui-monospace, SFMono-Regular, Menlo, monospace;
                display: flex; flex-direction: column; align-items: center;
                justify-content: center; gap: 8px; padding: 12px; }
        .screen { display: flex; flex-direction: column; align-items: center;
                  gap: 14px; padding: 28px 40px; background: #0f121c;
                  border: 1px solid #232a3d; border-radius: 12px; min-width: 360px; }
        .logo { font-size: 44px; font-weight: 800; letter-spacing: 2px; color: #e8f0ff; }
        .logo .accent { color: #f5c451; }
        .logo.win { color: #6ee7a8; } .logo.lose { color: #ff6b6b; }
        .tag, .ver, .note { opacity: 0.6; font-size: 12px; }
        .hs { margin-top: 6px; } .hs b, .logo .accent { color: #f5c451; }
        .btn { font: inherit; cursor: pointer; padding: 10px 22px; border-radius: 8px;
               border: 1px solid #2c3550; background: #161b2b; color: #cdd6e6; }
        .btn:hover { border-color: #3a4566; background: #1c2336; }
        .btn.primary { background: #f5c451; color: #1a1205; border-color: #f5c451; font-weight: 700; }
        .btn.big { font-size: 16px; padding: 12px 30px; min-width: 200px; }
        .btnrow { display: flex; gap: 10px; margin-top: 8px; }
        .row { display: flex; align-items: center; gap: 12px; width: 360px; }
        .row > span:first-child { width: 120px; } .row b { width: 36px; text-align: right; color: #f5c451; }
        .row input[type=range] { flex: 1; }
        .chip { font: inherit; cursor: pointer; padding: 5px 14px; border-radius: 6px;
                border: 1px solid #2c3550; background: #161b2b; color: #cdd6e6; }
        .chip.on { background: #f5c451; color: #1a1205; border-color: #f5c451; }
        .stats { display: flex; gap: 26px; margin: 6px 0; }
        .stat { display: flex; flex-direction: column; align-items: center; }
        .stat b { font-size: 30px; color: #f5c451; } .stat span { opacity: 0.6; font-size: 12px; }
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
        #hint { position: absolute; left: 50%; top: -26px; transform: translateX(-50%);
                white-space: nowrap; opacity: 0.6; }
        #hud-root { position: absolute; inset: 0; pointer-events: none; overflow: hidden;
                    border-radius: 6px; }
        #cross.hot::before, #cross.hot::after { background: #ff5a5a; opacity: 1; }
        #feed { position: absolute; left: 12px; top: 36px; display: flex;
                flex-direction: column; gap: 3px; align-items: flex-start; }
        .feeditem { background: rgba(0,0,0,0.45); padding: 2px 9px; border-radius: 4px;
                    font-size: 12px; color: #e8f0ff; animation: feedin 0.15s ease-out; }
        @keyframes feedin { from { opacity: 0; transform: translateX(-8px); } to { opacity: 1; } }
        #hpbar { width: 170px; height: 11px; background: rgba(255,255,255,0.14);
                 border-radius: 6px; overflow: hidden; margin-bottom: 5px; }
        #hpfill { height: 100%; background: linear-gradient(90deg, #ff5a5a, #f5c451, #6ee7a8);
                  transition: width 0.12s linear; }
        #ammo { font-size: 18px; font-weight: 700; color: #e8f0ff;
                text-shadow: 0 1px 2px #000; }
        #ammo.low { color: #ff6b6b; }
        #vignette { position: absolute; inset: 0;
                    box-shadow: inset 0 0 120px 36px rgba(190,20,20,0.6);
                    animation: vignflash 0.45s ease-out forwards; }
        @keyframes vignflash { from { opacity: 1; } to { opacity: 0; } }
        #death { position: absolute; inset: 0; display: flex; align-items: center;
                 justify-content: center; flex-direction: column; gap: 6px;
                 background: rgba(120,12,12,0.32); color: #ffd7d7; font-size: 26px;
                 font-weight: 700; }
        """;
        st: any = document.createElement("style");
        st.id = "fps-styles";
        st.textContent = css;
        head: any = document.head;
        head.appendChild(st);
    }

    # ── Main menu ──────────────────────────────────────────────────────────────
    def:pub Menu(onPlay: any, onSettings: any, highScore: int) -> JsxElement {
        return
            <div className="screen menu">
                <div className="logo">
                    {"JAC "}
                    <span className="accent">FPS</span>
                </div>
                <div className="tag">{"Phase 2 - single player"}</div>
                <button className="btn primary big" onClick={onPlay}>Play</button>
                <button className="btn big" onClick={onSettings}>Settings</button>
                <div className="hs">
                    {"High score "}
                    <b>{highScore}</b>
                </div>
                <div className="ver">v0.2.0</div>
            </div>;
    }

    # ── Settings (sensitivity carried as a 1..60 percentage) ───────────────────
    def:pub Settings(
        sens: int,
        fov: int,
        bots: int,
        mapId: int,
        target: int,
        onSave: any,
        onBack: any
    ) -> JsxElement {
        has s: int = 12,
            f: int = 90,
            b: int = 5,
            m: int = 0,
            t: int = 5;

        can with entry {
            s = sens;
            f = fov;
            b = bots;
            m = mapId;
            t = target;
        }
        return
            <div className="screen">
                <div className="logo" style={{"fontSize": "28px"}}>Settings</div>
                <div className="row">
                    <span>Mouse sensitivity</span>
                    <input
                        type="range"
                        min="1"
                        max="60"
                        value={str(s)}
                        onChange={lambda e: ChangeEvent {
                            v: str = e.target.value;
                            s = int(v);
                        }}
                    />
                    <b>{s}</b>
                </div>
                <div className="row">
                    <span>FOV</span>
                    <input
                        type="range"
                        min="60"
                        max="110"
                        value={str(f)}
                        onChange={lambda e: ChangeEvent {
                            v: str = e.target.value;
                            f = int(v);
                        }}
                    />
                    <b>{f}</b>
                </div>
                <div className="row">
                    <span>Bots</span>
                    <input
                        type="range"
                        min="1"
                        max="10"
                        value={str(b)}
                        onChange={lambda e: ChangeEvent {
                            v: str = e.target.value;
                            b = int(v);
                        }}
                    />
                    <b>{b}</b>
                </div>
                <div className="row">
                    <span>Score to win</span>
                    <input
                        type="range"
                        min="1"
                        max="20"
                        value={str(t)}
                        onChange={lambda e: ChangeEvent {
                            v: str = e.target.value;
                            t = int(v);
                        }}
                    />
                    <b>{t}</b>
                </div>
                <div className="row">
                    <span>Map</span>
                    <button
                        className={"chip on" if m == 0 else "chip"}
                        onClick={lambda { m = 0; }}
                    >
                        Open
                    </button>
                    <button
                        className={"chip on" if m == 1 else "chip"}
                        onClick={lambda { m = 1; }}
                    >
                        Cover
                    </button>
                </div>
                <div className="note">
                    {"Map + score-to-win apply now; sensitivity / FOV / bots are saved and wired into the sim in the next step."}
                </div>
                <div className="btnrow">
                    <button
                        className="btn primary big"
                        onClick={lambda { onSave(s, f, b, m, t); }}
                    >
                        Save
                    </button>
                    <button className="btn big" onClick={onBack}>Back</button>
                </div>
            </div>;
    }

    # ── React HUD overlay (driven by the shim each frame via window.__fps_hud) ──
    def:pub Hud -> JsxElement {
        has hp: int = 100,
            mag: int = 30,
            ammo: int = 90,
            kills: int = 0,
            deaths: int = 0,
            fps: int = 0,
            hit: bool = False,
            alive: bool = True,
            reloading: bool = False,
            low: bool = False,
            vig: int = 0,
            feed: list = [];

        can with entry {
            w: any = window;
            # The shim's on_tick pushes already-converted values here each frame.
            # This lambda only WRITES state (never reads it), so there is no React
            # stale-closure hazard; the diff logic lives in on_tick instead.
            w.__fps_hud = lambda nhp: int , nmag: int , nammo: int , nkills: int , ndeaths:
                int , nfps: int , nhit: bool , nalive: bool , nreload: bool , nlow:
                bool , nvig: int , nfeed: list {
                hp = nhp;
                mag = nmag;
                ammo = nammo;
                kills = nkills;
                deaths = ndeaths;
                fps = nfps;
                hit = nhit;
                alive = nalive;
                reloading = nreload;
                low = nlow;
                vig = nvig;
                feed = nfeed;
            };
        }
        hpw: str = f"{hp}%";
        ammo_txt: str = "RELOADING" if reloading else f"{mag} / {ammo}";
        return
            <div id="hud-root">
                <div id="cross" className={"hot" if hit else ""}></div>
                {(<div id="hitmark">✕</div>) if hit else None}
                {(<div id="vignette" key={f"v{vig}"}></div>) if vig > 0 else None}
                <div id="feed">
                    {for item in feed {
                        <div className="feeditem" key={item}>{item}</div>
                    }}
                </div>
                <div id="stat">
                    {"score "}
                    <b>{kills}</b>
                    {" · K/D "}
                    <b>{kills}</b>
                    {" / "}
                    <b>{deaths}</b>
                    {" · "}
                    <b>{fps}</b>
                    {" fps"}
                </div>
                <div id="hud">
                    <div id="hpbar">
                        <div id="hpfill" style={{"width": hpw}}></div>
                    </div>
                    <div id="ammo" className={"low" if (low or reloading) else ""}>
                        {ammo_txt}
                    </div>
                </div>
                {(
                    <div id="death">
                        <div>You Died</div>
                    </div>
                )
                    if not alive
                    else None}
            </div>;
    }

    # ── In-game view: canvas + React HUD; owns the game lifecycle ──────────────
    def:pub GameView(
        mapId: int, target: int, onExit: any, onGameOver: any
    ) -> JsxElement {
        can with entry {
            _ensure_styles();
            w: any = window;
            w.__fps_ending = False;
            w.__fps_prev_hp = 100;
            w.__fps_prev_kills = 0;
            w.__fps_prev_deaths = 0;
            w.__fps_feed = [];
            w.__fps_vig = 0;
            start_ms: float = float(f"{Date.now()}");
            canvas: any = document.getElementById("glcanvas");
            # Per-frame: convert sim state (Any) to ints, diff against window-stored
            # prev values for HUD effects (damage vignette + kill feed), push to the
            # React HUD, then check win/lose.
            on_tick = lambda exports: any , fps: int {
                w2: any = window;
                hp: int = int(f"{exports.get_health()}");
                mag: int = int(f"{exports.get_mag()}");
                ammo: int = int(f"{exports.get_ammo()}");
                kills: int = int(f"{exports.get_kills()}");
                deaths: int = int(f"{exports.get_deaths()}");
                alive: int = int(f"{exports.get_alive()}");
                hit: int = int(f"{exports.get_hit()}");
                reload: int = int(f"{exports.get_reloading()}");
                prev_hp: int = int(f"{w2.__fps_prev_hp}");
                prev_kills: int = int(f"{w2.__fps_prev_kills}");
                prev_deaths: int = int(f"{w2.__fps_prev_deaths}");
                vig: int = int(f"{w2.__fps_vig}");
                feed: any = w2.__fps_feed;
                if hp < prev_hp {
                    vig = vig + 1;
                }
                if kills > prev_kills {
                    feed.push(f"Eliminated bot #{kills}");
                }
                if deaths > prev_deaths {
                    feed.push(f"You were eliminated #{deaths}");
                }
                while int(f"{feed.length}") > 5 {
                    feed.shift();
                }
                w2.__fps_prev_hp = hp;
                w2.__fps_prev_kills = kills;
                w2.__fps_prev_deaths = deaths;
                w2.__fps_vig = vig;
                low: bool = mag <= 5;
                if w2.__fps_hud is not None {
                    w2.__fps_hud(
                        hp,
                        mag,
                        ammo,
                        kills,
                        deaths,
                        fps,
                        hit == 1,
                        alive == 1,
                        reload == 1,
                        low,
                        vig,
                        feed
                    );
                }
                if w2.__fps_ending {
                    return;
                }
                won: bool = kills >= target;
                if alive == 0 or won {
                    w2.__fps_ending = True;
                    now_ms: float = float(f"{Date.now()}");
                    secs: int = int((now_ms - start_ms) / 1000.0);
                    stop_game(w2.__fps_shim);
                    onGameOver(won, kills, deaths, secs);
                }
            };
            # Esc leaves the round and returns to the menu.
            on_exit = lambda {
                w3: any = window;
                stop_game(w3.__fps_shim);
                onExit();
            };
            run_game(canvas, on_tick, on_exit, {"map_id": mapId});
        }
        return
            <div id="wrap">
                <div id="hint">
                    {"WASD move · Space jump · mouse aim · click fire · R reload · Tab release · Esc menu"}
                </div>
                <canvas id="glcanvas" width={960} height={600}></canvas>
                <Hud/>
            </div>;
    }

    # ── Round summary ──────────────────────────────────────────────────────────
    def:pub GameOver(
        won: bool, kills: int, deaths: int, timeSec: int, onPlayAgain: any, onMenu: any
    ) -> JsxElement {
        return
            <div className="screen">
                <div className={"logo win" if won else "logo lose"}>
                    {"Victory" if won else "You Died"}
                </div>
                <div className="stats">
                    <div className="stat">
                        <b>{kills}</b>
                        <span>kills</span>
                    </div>
                    <div className="stat">
                        <b>{deaths}</b>
                        <span>deaths</span>
                    </div>
                    <div className="stat">
                        <b>{timeSec}</b>
                        <span>seconds</span>
                    </div>
                </div>
                <div className="btnrow">
                    <button className="btn primary big" onClick={onPlayAgain}>
                        Play Again
                    </button>
                    <button className="btn big" onClick={onMenu}>Menu</button>
                </div>
            </div>;
    }

    # ── App shell: the screen state machine / router ───────────────────────────
    def:pub app -> JsxElement {
        has screen: str = "menu",
            sens: int = 12,
            fov: int = 90,
            bots: int = 5,
            mapId: int = 0,
            target: int = 5,
            statWon: bool = False,
            statKills: int = 0,
            statDeaths: int = 0,
            statTime: int = 0,
            highScore: int = 0;

        can with entry {
            _ensure_styles();
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
        def save_settings(ns: int, nf: int, nb: int, nm: int, nt: int) {
            sens = ns;
            fov = nf;
            bots = nb;
            mapId = nm;
            target = nt;
            screen = "menu";
        }
        def end_game(won: bool, kills: int, deaths: int, secs: int) {
            statWon = won;
            statKills = kills;
            statDeaths = deaths;
            statTime = secs;
            if kills > highScore {
                highScore = kills;
            }
            screen = "gameover";
        }
        return
            <div id="page">
                {(
                    <Menu
                        onPlay={go_play}
                        onSettings={go_settings}
                        highScore={highScore}
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

    def get_reloading -> int {
        return 1 if WORLD.player.reloading else 0;
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
