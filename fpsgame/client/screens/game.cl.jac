"""In-game screen: canvas + HUD; owns the round lifecycle (start/stop/teardown)."""

import from ...raylib_shim { run_game, stop_game }
import from ...render3d { make_renderer, draw, dispose_renderer }
import from ..hud { Hud }
import from ..styles { ensure_styles }

# ── In-game view: canvas + React HUD; owns the game lifecycle ──────────────
def:pub GameView(
    mapId: int,
    target: int,
    sens: int,
    fov: int,
    bots: int,
    mode: int,
    onExit: any,
    onGameOver: any
) -> JsxElement {
    can with entry {
        ensure_styles();
        w: any = window;
        w.__fps_ending = False;
        w.__fps_prev_hp = 100;
        w.__fps_prev_kills = 0;
        w.__fps_prev_deaths = 0;
        w.__fps_feed = [];
        w.__fps_vig = 0;
        start_ms: float = float(f"{Date.now()}");
        canvas: any = document.getElementById("glcanvas");
        # Fresh Three.js renderer per round (each round mounts a new canvas);
        # dispose the previous one first so it doesn't leak GPU resources.
        # Build + draw the renderer INSIDE the rAF callback (not here in the
        # effect): errors thrown in requestAnimationFrame go to window.onerror
        # (captured by our [fps] hook with the real message), whereas effect
        # errors get swallowed by React's error boundary.
        # Truthiness, NOT `is not None`: window props are undefined on the
        # first round, and `undefined is not None` is true in Jac (None==null),
        # which would call dispose on undefined and throw.
        if w.__fps_r3d {
            dispose_renderer(w.__fps_r3d);
        }
        w.__fps_r3d_tried = False;
        on_render = lambda (exports: any) {
            w5: any = window;
            if not w5.__fps_r3d_tried {
                w5.__fps_r3d_tried = True;
                rr: any = make_renderer(canvas, fov);
                w5.__fps_r3d = rr;
            }
            dr: any = w5.__fps_r3d;
            if dr {
                draw(dr, exports);
            }
        };
        # Per-frame: convert sim state (Any) to ints, diff against window-stored
        # prev values for HUD effects (damage vignette + kill feed), push to the
        # React HUD, then check win/lose.
        on_tick = lambda (exports: any, fps: int) {
            w2: any = window;
            hp: int = int(f"{exports.get_health()}");
            mag: int = int(f"{exports.get_mag()}");
            ammo: int = int(f"{exports.get_ammo()}");
            kills: int = int(f"{exports.get_kills()}");
            deaths: int = int(f"{exports.get_deaths()}");
            alive: int = int(f"{exports.get_alive()}");
            hit: int = int(f"{exports.get_hit()}");
            reload: int = int(f"{exports.get_reloading()}");
            gun: int = int(f"{exports.get_weapon()}");
            tleft: int = int(f"{exports.get_time_left()}");
            timeup: int = int(f"{exports.get_round_over()}");
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
                    gun,
                    tleft,
                    mode,
                    feed
                );
            }
            if w2.__fps_ending {
                return;
            }
            won: bool = kills >= target;
            # time attack ends on the clock; you win only if you hit the target
            if alive == 0 or won or timeup == 1 {
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
        run_game(
            canvas,
            on_tick,
            on_exit,
            on_render,
            {"map_id": mapId, "sens": sens, "bots": bots, "mode": mode}
        );
    }
    return
        <div id="wrap">
            <div id="hint">
                {"WASD move · Space jump · mouse aim · click fire · R reload · 1-5 weapon · Tab release · Esc menu"}
            </div>
            <canvas id="glcanvas" width={960} height={600}></canvas>
            <Hud/>
        </div>;
}
