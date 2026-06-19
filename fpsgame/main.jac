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

# ─── Simulation + rendering (compiles to wasm; native-ready for Phase 5). ──────
na {
    import from raylib {
        def InitWindow(width: i32, height: i32, title: str) -> None;  def WindowShouldClose -> bool;  def CloseWindow -> None;  def BeginDrawing -> None;  def EndDrawing -> None;  def rlClearColor(
            r: u8, g: u8, b: u8, a: u8
        ) -> None;  def rlClearScreenBuffers -> None;  def DrawFPS(
            pos_x: i32, pos_y: i32
        ) -> None;  def IsKeyDown(key: i32) -> bool;  def IsKeyPressed(
            key: i32
        ) -> bool;  def GetFrameTime -> f32;  def GetMouseX -> i32;  def GetMouseY -> i32;  def IsMouseButtonPressed(
            button: i32
        ) -> bool;  def IsMouseButtonDown(button: i32) -> bool;  def DisableCursor -> None;  def EnableCursor -> None;  def rlMatrixMode(
            mode: i32
        ) -> None;  def rlLoadIdentity -> None;  def rlPushMatrix -> None;  def rlPopMatrix -> None;  def rlTranslatef(
            x: f32, y: f32, z: f32
        ) -> None;  def rlRotatef(angle: f32, x: f32, y: f32, z: f32) -> None;  def rlFrustum(
            left: f64, right: f64, bottom: f64, top: f64, znear: f64, zfar: f64
        ) -> None;  def rlOrtho(
            left: f64, right: f64, bottom: f64, top: f64, znear: f64, zfar: f64
        ) -> None;  def rlBegin(mode: i32) -> None;  def rlEnd -> None;  def rlVertex3f(
            x: f32, y: f32, z: f32
        ) -> None;  def rlColor4ub(r: u8, g: u8, b: u8, a: u8) -> None;  def rlEnableDepthTest -> None;  def rlDisableDepthTest -> None;  def rlSetLineWidth(
            width: f32
        ) -> None;  def EndMode3D -> None;  def GetTime -> f64;
    }

    glob RL_MODELVIEW: int = 0x1700,
         RL_PROJECTION: int = 0x1701,
         RL_LINES: int = 0x0001,
         RL_TRIANGLES: int = 0x0004;

    # --- tunables (single source for Phase 1) ---
    glob KEY_W: int = 87,
         KEY_A: int = 65,
         KEY_S: int = 83,
         KEY_D: int = 68,
         KEY_R: int = 82,
         KEY_SPACE: int = 32,
         KEY_RIGHT: int = 262,
         KEY_LEFT: int = 263,
         KEY_DOWN: int = 264,
         KEY_UP: int = 265,
         KEY_TAB: int = 258,
         MOUSE_LEFT: int = 0,
         DEG2RAD: float = 0.017453292519943295,
         GRAV: float = -22.0,
         JUMP_V: float = 8.0,
         MOVE_SPD: float = 7.0,
         PLAYER_R: float = 0.4,
         PLAYER_H: float = 1.8,
         EYE_H: float = 1.6,
         W_DMG: int = 20,
         W_FIRE_CD: float = 0.11,
         W_MAG: int = 30,
         W_RELOAD: float = 1.5,
         W_RANGE: float = 200.0,
         RESPAWN_T: float = 2.0,
         BOT_COUNT: int = 5;

    # --- world state ---
    obj Ent {
        has x: float = 0.0,
            y: float = 0.0,
            z: float = 0.0,
            vx: float = 0.0,
            vy: float = 0.0,
            vz: float = 0.0,
            yaw: float = 0.0,
            pitch: float = 0.0,
            health: int = 100,
            alive: bool = True,
            on_ground: bool = False,
            ammo: int = 90,
            mag: int = 30,
            fire_cd: float = 0.0,
            reload_cd: float = 0.0,
            reloading: bool = False,
            respawn_cd: float = 0.0,
            kills: int = 0,
            deaths: int = 0,
            is_bot: bool = False,
            think_cd: float = 0.0,
            strafe: float = 1.0;
    }

    obj Box {
        has minx: float = 0.0,
            miny: float = 0.0,
            minz: float = 0.0,
            maxx: float = 0.0,
            maxy: float = 0.0,
            maxz: float = 0.0;
    }

    obj Vec3 {
        has x: float = 0.0,
            y: float = 0.0,
            z: float = 0.0;
    }

    obj Tracer {
        has x0: float = 0.0,
            y0: float = 0.0,
            z0: float = 0.0,
            x1: float = 0.0,
            y1: float = 0.0,
            z1: float = 0.0,
            life: float = 0.0;
    }

    glob player: Ent = Ent(),
         bots: list[Ent] = [],
         colliders: list[Box] = [],
         spawns: list[Vec3] = [],
         tracers: list[Tracer] = [],
         map_id: int = 0,
         world_t: float = 0.0,
         hit_flash: float = 0.0,
         rng: int = 987654321,
         prev_mx: float = 0.0,
         prev_my: float = 0.0,
         mouse_warmup: int = 12,
         mouse_sens: float = 0.12,
         mouse_captured: bool = False;

    # ── math ──────────────────────────────────────────────────────────────────
    """cos via range-reduced Taylor series (deterministic, no libm)."""
    def jcos(a: float) -> float {
        twopi = 6.283185307179586;
        pi = 3.141592653589793;
        while a > pi {
            a -= twopi;
        }
        while a < -pi {
            a += twopi;
        }
        x2 = a * a;
        x4 = x2 * x2;
        x6 = x4 * x2;
        x8 = x4 * x4;
        x10 = x8 * x2;
        x12 = x8 * x4;
        return 1.0 - x2 / 2.0 + x4 / 24.0 - x6 / 720.0 + x8 / 40320.0 - x10 / 3628800.0 + x12 / 479001600.0;
    }

    """sin(a) = cos(a - pi/2)."""
    def jsin(a: float) -> float {
        return jcos(a - 1.5707963267948796);
    }

    """sqrt via Newton iteration."""
    def fsqrt(v: float) -> float {
        if v <= 0.0 {
            return 0.0;
        }
        g = v;
        i = 0;
        while i < 20 {
            g = 0.5 * (g + v / g);
            i += 1;
        }
        return g;
    }

    """Uniform pseudo-random float in [0, 1) via a 31-bit LCG (deterministic)."""
    def rand01 -> float {
        global rng;
        rng = (rng * 1103515245 + 12345) % 2147483648;
        return float(rng) / 2147483648.0;
    }

    """Random float in [lo, hi)."""
    def rand_range(lo: float, hi: float) -> float {
        return lo + rand01() * (hi - lo);
    }

    # ── raylib wrappers ────────────────────────────────────────────────────────
    def open_window(width: int, height: int, title: str) {
        InitWindow(width, height, title);
    }

    def dt -> float {
        return GetFrameTime();
    }

    def key_held(code: int) -> bool {
        return IsKeyDown(code);
    }

    def key_tapped(code: int) -> bool {
        return IsKeyPressed(code);
    }

    def mouse_x -> float {
        return float(GetMouseX());
    }

    def mouse_y -> float {
        return float(GetMouseY());
    }

    def mouse_pressed(button: int) -> bool {
        return IsMouseButtonPressed(button);
    }

    def mouse_held(button: int) -> bool {
        return IsMouseButtonDown(button);
    }

    def lock_mouse {
        DisableCursor();
    }

    def unlock_mouse {
        EnableCursor();
    }

    def begin_frame(r: int, g: int, b: int) {
        BeginDrawing();
        rlClearColor(r, g, b, 255);
        rlClearScreenBuffers();
        rlEnableDepthTest();
    }

    def end_frame {
        EndDrawing();
    }

    def end_camera(width: float, height: float) {
        EndMode3D();
        rlMatrixMode(RL_PROJECTION);
        rlLoadIdentity();
        rlOrtho(0.0, width, height, 0.0, -1.0, 1.0);
        rlMatrixMode(RL_MODELVIEW);
        rlLoadIdentity();
    }

    def draw_fps(x: int, y: int) {
        DrawFPS(x, y);
    }

    """Perspective camera at (px,py,pz) looking by yaw/pitch (degrees), aspect=w/h."""
    def set_camera(
        px: float, py: float, pz: float, yaw_deg: float, pitch_deg: float, aspect: float
    ) {
        near = 0.05;
        far_plane = 400.0;
        top = near * 0.57735026;
        right = top * aspect;
        rlMatrixMode(RL_PROJECTION);
        rlLoadIdentity();
        rlFrustum(-right, right, -top, top, near, far_plane);
        rlMatrixMode(RL_MODELVIEW);
        rlLoadIdentity();
        rlRotatef(-pitch_deg, 1.0, 0.0, 0.0);
        rlRotatef(-yaw_deg, 0.0, 1.0, 0.0);
        rlTranslatef(-px, -py, -pz);
    }

    """Emit one quad (corners 0->1->2->3, CCW) as two triangles."""
    def _quad(
        p0: float,
        p1: float,
        p2: float,
        p3: float,
        p4: float,
        p5: float,
        p6: float,
        p7: float,
        p8: float,
        p9: float,
        p10: float,
        p11: float
    ) {
        rlVertex3f(p0, p1, p2);
        rlVertex3f(p3, p4, p5);
        rlVertex3f(p6, p7, p8);
        rlVertex3f(p0, p1, p2);
        rlVertex3f(p6, p7, p8);
        rlVertex3f(p9, p10, p11);
    }

    """Scale a 0-255 channel by a percentage (cheap face shading)."""
    def _shade(c: int, pct: int) -> int {
        v = c * pct // 100;
        return v if v < 255 else 255;
    }

    """Draw an axis-aligned colored box centered at (cx,cy,cz), size (sx,sy,sz)."""
    def draw_box(
        cx: float,
        cy: float,
        cz: float,
        sx: float,
        sy: float,
        sz: float,
        r: int,
        g: int,
        b: int
    ) {
        hx = sx * 0.5;
        hy = sy * 0.5;
        hz = sz * 0.5;
        rlPushMatrix();
        rlTranslatef(cx, cy, cz);
        rlBegin(RL_TRIANGLES);
        rlColor4ub(_shade(r, 100), _shade(g, 100), _shade(b, 100), 255);
        _quad(-hx, hy, hz, hx, hy, hz, hx, hy, -hz, -hx, hy, -hz);
        rlColor4ub(_shade(r, 85), _shade(g, 85), _shade(b, 85), 255);
        _quad(-hx, -hy, hz, hx, -hy, hz, hx, hy, hz, -hx, hy, hz);
        _quad(hx, -hy, -hz, -hx, -hy, -hz, -hx, hy, -hz, hx, hy, -hz);
        rlColor4ub(_shade(r, 70), _shade(g, 70), _shade(b, 70), 255);
        _quad(hx, -hy, hz, hx, -hy, -hz, hx, hy, -hz, hx, hy, hz);
        _quad(-hx, -hy, -hz, -hx, -hy, hz, -hx, hy, hz, -hx, hy, -hz);
        rlColor4ub(_shade(r, 45), _shade(g, 45), _shade(b, 45), 255);
        _quad(-hx, -hy, -hz, hx, -hy, -hz, hx, -hy, hz, -hx, -hy, hz);
        rlEnd();
        rlPopMatrix();
    }

    """Draw a flat floor grid on y=0."""
    def draw_floor(half: int, step: float) {
        ext = float(half) * step;
        rlSetLineWidth(1.0);
        rlBegin(RL_LINES);
        rlColor4ub(55, 60, 75, 255);
        i = -half;
        while i <= half {
            f = float(i) * step;
            rlVertex3f(f, 0.0, -ext);
            rlVertex3f(f, 0.0, ext);
            rlVertex3f(-ext, 0.0, f);
            rlVertex3f(ext, 0.0, f);
            i += 1;
        }
        rlEnd();
    }

    # ── maps ───────────────────────────────────────────────────────────────────
    """Append an axis-aligned box collider given center + half-extents."""
    def add_box(cx: float, cy: float, cz: float, hx: float, hy: float, hz: float) {
        colliders.append(
            Box(
                minx=cx - hx,
                miny=cy - hy,
                minz=cz - hz,
                maxx=cx + hx,
                maxy=cy + hy,
                maxz=cz + hz
            )
        );
    }

    """Load colliders + spawn points for a map id. map 0 = open, map 1 = cover."""
    def map_load(mid: int) {
        global colliders,spawns;
        colliders = [];
        spawns = [];
        ext = 24.0;
        wall_h = 6.0;
        # perimeter walls
        add_box(0.0, wall_h * 0.5, -ext, ext, wall_h * 0.5, 0.5);
        add_box(0.0, wall_h * 0.5, ext, ext, wall_h * 0.5, 0.5);
        add_box(-ext, wall_h * 0.5, 0.0, 0.5, wall_h * 0.5, ext);
        add_box(ext, wall_h * 0.5, 0.0, 0.5, wall_h * 0.5, ext);
        if mid == 0 {
            add_box(-6.0, 1.0, -4.0, 1.5, 1.0, 1.5);
            add_box(7.0, 1.0, 3.0, 1.5, 1.0, 1.5);
            add_box(0.0, 1.5, 8.0, 2.0, 1.5, 1.0);
            add_box(-9.0, 1.0, 9.0, 1.0, 1.0, 1.0);
        } else {
            add_box(0.0, 2.0, 0.0, 2.0, 2.0, 2.0);
            add_box(-8.0, 1.2, -8.0, 2.5, 1.2, 0.6);
            add_box(8.0, 1.2, 8.0, 2.5, 1.2, 0.6);
            add_box(-8.0, 1.2, 8.0, 0.6, 1.2, 2.5);
            add_box(8.0, 1.2, -8.0, 0.6, 1.2, 2.5);
            add_box(12.0, 1.0, 0.0, 1.0, 1.0, 4.0);
            add_box(-12.0, 1.0, 0.0, 1.0, 1.0, 4.0);
        }
        spawns.append(Vec3(x=-18.0, y=0.0, z=-18.0));
        spawns.append(Vec3(x=18.0, y=0.0, z=18.0));
        spawns.append(Vec3(x=-18.0, y=0.0, z=18.0));
        spawns.append(Vec3(x=18.0, y=0.0, z=-18.0));
        spawns.append(Vec3(x=0.0, y=0.0, z=-19.0));
        spawns.append(Vec3(x=0.0, y=0.0, z=19.0));
    }

    """A random spawn point from the map's spawn list."""
    def pick_spawn -> Vec3 {
        n = len(spawns);
        if n == 0 {
            return Vec3(x=0.0, y=0.0, z=0.0);
        }
        idx = int(rand01() * float(n)) % n;
        return spawns[idx];
    }

    # ── physics ────────────────────────────────────────────────────────────────
    """Resolve an entity AABB out of one box along the least-penetration axis."""
    def resolve(e: Ent, b: Box) {
        pminx = e.x - PLAYER_R;
        pmaxx = e.x + PLAYER_R;
        pminy = e.y;
        pmaxy = e.y + PLAYER_H;
        pminz = e.z - PLAYER_R;
        pmaxz = e.z + PLAYER_R;
        if pmaxx <= b.minx or pminx >= b.maxx {
            return;
        }
        if pmaxy <= b.miny or pminy >= b.maxy {
            return;
        }
        if pmaxz <= b.minz or pminz >= b.maxz {
            return;
        }
        ox1 = pmaxx - b.minx;
        ox2 = b.maxx - pminx;
        ox = ox1 if ox1 < ox2 else ox2;
        oy1 = pmaxy - b.miny;
        oy2 = b.maxy - pminy;
        oy = oy1 if oy1 < oy2 else oy2;
        oz1 = pmaxz - b.minz;
        oz2 = b.maxz - pminz;
        oz = oz1 if oz1 < oz2 else oz2;
        if ox <= oy and ox <= oz {
            if ox1 < ox2 {
                e.x -= ox;
            } else {
                e.x += ox;
            }
            e.vx = 0.0;
        } else {
            if oy <= oz {
                if oy1 < oy2 {
                    e.y -= oy;
                    e.vy = 0.0;
                } else {
                    e.y += oy;
                    e.vy = 0.0;
                    e.on_ground = True;
                }
            } else {
                if oz1 < oz2 {
                    e.z -= oz;
                } else {
                    e.z += oz;
                }
                e.vz = 0.0;
            }
        }
    }

    """Integrate velocity, apply gravity, resolve collisions + ground plane."""
    def move_and_collide(e: Ent, step: float) {
        e.vy += GRAV * step;
        e.on_ground = False;
        e.x += e.vx * step;
        e.y += e.vy * step;
        e.z += e.vz * step;
        if e.y < 0.0 {
            e.y = 0.0;
            e.vy = 0.0;
            e.on_ground = True;
        }
        for b in colliders {
            resolve(e, b);
        }
    }

    # ── raycast (hitscan + bot line-of-sight) ──────────────────────────────────
    """Ray vs AABB slab test. Returns hit distance t, or -1.0 if no hit within tmax."""
    def ray_vs_box(
        ox: float,
        oy: float,
        oz: float,
        dx: float,
        dy: float,
        dz: float,
        b: Box,
        tmax: float
    ) -> float {
        tmin = 0.0;
        tm = tmax;
        # x slab
        if dx > -0.000001 and dx < 0.000001 {
            if ox < b.minx or ox > b.maxx {
                return -1.0;
            }
        } else {
            inv = 1.0 / dx;
            t1 = (b.minx - ox) * inv;
            t2 = (b.maxx - ox) * inv;
            if t1 > t2 {
                tmp = t1;
                t1 = t2;
                t2 = tmp;
            }
            if t1 > tmin {
                tmin = t1;
            }
            if t2 < tm {
                tm = t2;
            }
            if tmin > tm {
                return -1.0;
            }
        }
        # y slab
        if dy > -0.000001 and dy < 0.000001 {
            if oy < b.miny or oy > b.maxy {
                return -1.0;
            }
        } else {
            inv = 1.0 / dy;
            t1 = (b.miny - oy) * inv;
            t2 = (b.maxy - oy) * inv;
            if t1 > t2 {
                tmp = t1;
                t1 = t2;
                t2 = tmp;
            }
            if t1 > tmin {
                tmin = t1;
            }
            if t2 < tm {
                tm = t2;
            }
            if tmin > tm {
                return -1.0;
            }
        }
        # z slab
        if dz > -0.000001 and dz < 0.000001 {
            if oz < b.minz or oz > b.maxz {
                return -1.0;
            }
        } else {
            inv = 1.0 / dz;
            t1 = (b.minz - oz) * inv;
            t2 = (b.maxz - oz) * inv;
            if t1 > t2 {
                tmp = t1;
                t1 = t2;
                t2 = tmp;
            }
            if t1 > tmin {
                tmin = t1;
            }
            if t2 < tm {
                tm = t2;
            }
            if tmin > tm {
                return -1.0;
            }
        }
        return tmin;
    }

    """Closest map-collider hit distance along a ray, or tmax if clear."""
    def ray_world(
        ox: float, oy: float, oz: float, dx: float, dy: float, dz: float, tmax: float
    ) -> float {
        best = tmax;
        for b in colliders {
            t = ray_vs_box(ox, oy, oz, dx, dy, dz, b, tmax);
            if t >= 0.0 and t < best {
                best = t;
            }
        }
        return best;
    }

    """Ray vs an entity's body AABB. Returns t or -1.0."""
    def ray_vs_ent(
        ox: float,
        oy: float,
        oz: float,
        dx: float,
        dy: float,
        dz: float,
        e: Ent,
        tmax: float
    ) -> float {
        b = Box(
            minx=e.x - PLAYER_R,
            miny=e.y,
            minz=e.z - PLAYER_R,
            maxx=e.x + PLAYER_R,
            maxy=e.y + PLAYER_H,
            maxz=e.z + PLAYER_R
        );
        return ray_vs_box(ox, oy, oz, dx, dy, dz, b, tmax);
    }

    # ── combat ─────────────────────────────────────────────────────────────────
    """Apply damage to an entity; trigger death + score on kill."""
    def damage(victim: Ent, dmg: int, attacker: Ent) {
        if not victim.alive {
            return;
        }
        victim.health -= dmg;
        if victim.health <= 0 {
            victim.health = 0;
            victim.alive = False;
            victim.deaths += 1;
            victim.respawn_cd = RESPAWN_T;
            attacker.kills += 1;
        }
    }

    """Fire a hitscan shot from eye along (dx,dy,dz); resolve closest target."""
    def fire(shooter: Ent, dx: float, dy: float, dz: float) {
        global hit_flash;
        ox = shooter.x;
        oy = shooter.y + EYE_H;
        oz = shooter.z;
        wall_t = ray_world(ox, oy, oz, dx, dy, dz, W_RANGE);
        best_t = wall_t;
        victim: Ent = shooter;
        found = False;
        if shooter.is_bot {
            t = ray_vs_ent(ox, oy, oz, dx, dy, dz, player, best_t);
            if t >= 0.0 and t < best_t and player.alive {
                best_t = t;
                victim = player;
                found = True;
            }
        } else {
            for b in bots {
                if b.alive {
                    t = ray_vs_ent(ox, oy, oz, dx, dy, dz, b, best_t);
                    if t >= 0.0 and t < best_t {
                        best_t = t;
                        victim = b;
                        found = True;
                    }
                }
            }
        }
        # tracer to the impact point
        tracers.append(
            Tracer(
                x0=ox + dx * 0.4,
                y0=oy - 0.1,
                z0=oz + dz * 0.4,
                x1=ox + dx * best_t,
                y1=oy + dy * best_t,
                z1=oz + dz * best_t,
                life=0.05
            )
        );
        if found {
            damage(victim, W_DMG, shooter);
            if not shooter.is_bot {
                hit_flash = 0.12;
            }
        }
    }

    """Try to fire shooter's weapon this frame (respects cooldown, ammo, reload)."""
    def try_fire(shooter: Ent, dx: float, dy: float, dz: float) {
        if shooter.reloading or shooter.fire_cd > 0.0 or shooter.mag <= 0 {
            return;
        }
        shooter.mag -= 1;
        shooter.fire_cd = W_FIRE_CD;
        fire(shooter, dx, dy, dz);
    }

    """Begin reloading if it makes sense."""
    def start_reload(e: Ent) {
        if e.reloading or e.mag >= W_MAG or e.ammo <= 0 {
            return;
        }
        e.reloading = True;
        e.reload_cd = W_RELOAD;
    }

    """Advance weapon timers; finish a reload when the timer elapses."""
    def tick_weapon(e: Ent, step: float) {
        if e.fire_cd > 0.0 {
            e.fire_cd -= step;
        }
        if e.reloading {
            e.reload_cd -= step;
            if e.reload_cd <= 0.0 {
                need = W_MAG - e.mag;
                take = need if need < e.ammo else e.ammo;
                e.mag += take;
                e.ammo -= take;
                e.reloading = False;
            }
        }
    }

    # ── spawning ───────────────────────────────────────────────────────────────
    """Reset an entity to full health at a spawn point."""
    def spawn_ent(e: Ent) {
        sp = pick_spawn();
        e.x = sp.x;
        e.y = sp.y;
        e.z = sp.z;
        e.vx = 0.0;
        e.vy = 0.0;
        e.vz = 0.0;
        e.health = 100;
        e.alive = True;
        e.mag = W_MAG;
        e.ammo = 90;
        e.reloading = False;
        e.reload_cd = 0.0;
        e.fire_cd = 0.0;
        e.respawn_cd = 0.0;
    }

    # ── player input + control ─────────────────────────────────────────────────
    """Read keyboard + mouse and drive the player (look, move, jump, fire, reload)."""
    def handle_input(step: float) {
        global prev_mx,prev_my,mouse_warmup,mouse_captured;
        if key_tapped(KEY_TAB) {
            if mouse_captured {
                unlock_mouse();
                mouse_captured = False;
            } else {
                lock_mouse();
                mouse_captured = True;
                mouse_warmup = 8;
            }
        }
        if not mouse_captured and mouse_pressed(MOUSE_LEFT) {
            lock_mouse();
            mouse_captured = True;
            mouse_warmup = 8;
        }
        turn = 90.0 * step;
        if key_held(KEY_LEFT) {
            player.yaw += turn;
        }
        if key_held(KEY_RIGHT) {
            player.yaw -= turn;
        }
        if key_held(KEY_UP) {
            player.pitch += turn;
        }
        if key_held(KEY_DOWN) {
            player.pitch -= turn;
        }
        if mouse_captured {
            mx = mouse_x();
            my = mouse_y();
            if mouse_warmup > 0 {
                mouse_warmup -= 1;
            } else {
                ddx = mx - prev_mx;
                ddy = my - prev_my;
                if ddx < 150.0 and ddx > -150.0 and ddy < 150.0 and ddy > -150.0 {
                    player.yaw -= ddx * mouse_sens;
                    player.pitch -= ddy * mouse_sens;
                }
            }
            prev_mx = mx;
            prev_my = my;
        }
        if player.pitch > 85.0 {
            player.pitch = 85.0;
        }
        if player.pitch < -85.0 {
            player.pitch = -85.0;
        }
        if not player.alive {
            player.vx = 0.0;
            player.vz = 0.0;
            return;
        }
        yaw_r = player.yaw * DEG2RAD;
        sy = jsin(yaw_r);
        cy = jcos(yaw_r);
        # forward = (-sin, -cos); right = (cos, -sin).
        # NOTE: build the wish vector with explicit `mvx = mvx + ...` assignment.
        # The compound `mvx += ...` form miscompiles to a constant in the native
        # / wasm backend here, so keep these as plain assignments.
        mvx = 0.0;
        mvz = 0.0;
        if key_held(KEY_W) {
            mvx = mvx - sy;
            mvz = mvz - cy;
        }
        if key_held(KEY_S) {
            mvx = mvx + sy;
            mvz = mvz + cy;
        }
        if key_held(KEY_D) {
            mvx = mvx + cy;
            mvz = mvz - sy;
        }
        if key_held(KEY_A) {
            mvx = mvx - cy;
            mvz = mvz + sy;
        }
        ml = fsqrt(mvx * mvx + mvz * mvz);
        if ml > 0.0 {
            mvx = mvx / ml;
            mvz = mvz / ml;
        }
        player.vx = mvx * MOVE_SPD;
        player.vz = mvz * MOVE_SPD;
        if key_held(KEY_SPACE) and player.on_ground {
            player.vy = JUMP_V;
        }
        if key_tapped(KEY_R) {
            start_reload(player);
        }
        if mouse_held(MOUSE_LEFT) and mouse_captured {
            yp = player.pitch * DEG2RAD;
            cp = jcos(yp);
            dx = -jsin(yaw_r) * cp;
            dy = jsin(yp);
            dz = -jcos(yaw_r) * cp;
            if player.mag <= 0 {
                start_reload(player);
            } else {
                try_fire(player, dx, dy, dz);
            }
        }
    }

    # ── bot AI ─────────────────────────────────────────────────────────────────
    """Steer a bot toward the player, keep line of sight, and shoot."""
    def bot_update(b: Ent, step: float) {
        if not b.alive {
            b.respawn_cd -= step;
            if b.respawn_cd <= 0.0 {
                spawn_ent(b);
            }
            return;
        }
        dx = player.x - b.x;
        dz = player.z - b.z;
        dist = fsqrt(dx * dx + dz * dz);
        ndx = 0.0;
        ndz = 0.0;
        if dist > 0.001 {
            ndx = dx / dist;
            ndz = dz / dist;
        }
        # face the player
        b.yaw = _atan2_deg(-ndx, -ndz);
        # strafe occasionally
        b.think_cd -= step;
        if b.think_cd <= 0.0 {
            b.think_cd = rand_range(0.6, 1.6);
            b.strafe = 1.0 if rand01() > 0.5 else -1.0;
        }
        # desired velocity: approach to ~8 units, strafe sideways
        approach = 1.0;
        if dist < 8.0 {
            approach = -0.3;
        }
        sx = -ndz * b.strafe;
        sz = ndx * b.strafe;
        mvx = ndx * approach + sx * 0.6;
        mvz = ndz * approach + sz * 0.6;
        ml = fsqrt(mvx * mvx + mvz * mvz);
        if ml > 0.0 {
            mvx /= ml;
            mvz /= ml;
        }
        spd = MOVE_SPD * 0.7;
        b.vx = mvx * spd;
        b.vz = mvz * spd;
        # line of sight + shoot
        ox = b.x;
        oy = b.y + EYE_H;
        oz = b.z;
        aimx = player.x - ox;
        aimy = (player.y + EYE_H * 0.6) - oy;
        aimz = player.z - oz;
        al = fsqrt(aimx * aimx + aimy * aimy + aimz * aimz);
        if al > 0.001 {
            aimx /= al;
            aimy /= al;
            aimz /= al;
        }
        wall_t = ray_world(ox, oy, oz, aimx, aimy, aimz, al);
        tick_weapon(b, step);
        if wall_t >= al - 0.2 and player.alive {
            # spread for fairness
            sxp = rand_range(-0.04, 0.04);
            syp = rand_range(-0.04, 0.04);
            try_fire(b, aimx + sxp, aimy + syp, aimz);
            if b.mag <= 0 {
                start_reload(b);
            }
        }
    }

    """atan2 in degrees (coarse, deterministic) for bot facing."""
    def _atan2_deg(y: float, x: float) -> float {
        # reduce to atan via series on |t|<=1, handle octants
        ax = x if x >= 0.0 else -x;
        ay = y if y >= 0.0 else -y;
        ang = 0.0;
        if ax < 0.000001 and ay < 0.000001 {
            return 0.0;
        }
        if ax >= ay {
            t = ay / ax;
            ang = _atan_unit(t);
        } else {
            t = ax / ay;
            ang = 1.5707963267948966 - _atan_unit(t);
        }
        if x < 0.0 {
            ang = 3.141592653589793 - ang;
        }
        if y < 0.0 {
            ang = -ang;
        }
        return ang / DEG2RAD;
    }

    """atan(t) for 0<=t<=1 via a short polynomial approximation."""
    def _atan_unit(t: float) -> float {
        t3 = t * t * t;
        t5 = t3 * t * t;
        t7 = t5 * t * t;
        return t - t3 / 3.0 + t5 / 5.0 - t7 / 7.0;
    }

    # ── rendering ──────────────────────────────────────────────────────────────
    """Draw the whole world: floor, map boxes, bots, tracers."""
    def draw_world {
        draw_floor(20, 1.5);
        for b in colliders {
            cx = (b.minx + b.maxx) * 0.5;
            cy = (b.miny + b.maxy) * 0.5;
            cz = (b.minz + b.maxz) * 0.5;
            sx = b.maxx - b.minx;
            sy = b.maxy - b.miny;
            sz = b.maxz - b.minz;
            draw_box(cx, cy, cz, sx, sy, sz, 70, 80, 110);
        }
        for e in bots {
            if e.alive {
                draw_box(e.x, e.y + 0.9, e.z, 0.8, 1.8, 0.8, 235, 80, 60);
                draw_box(e.x, e.y + 1.9, e.z, 0.5, 0.5, 0.5, 250, 120, 90);
            }
        }
        rlSetLineWidth(2.0);
        rlBegin(RL_LINES);
        rlColor4ub(255, 230, 120, 255);
        for t in tracers {
            rlVertex3f(t.x0, t.y0, t.z0);
            rlVertex3f(t.x1, t.y1, t.z1);
        }
        rlEnd();
    }

    # ── round lifecycle ────────────────────────────────────────────────────────
    """(Re)build the world for the current map and spawn everyone."""
    def new_round {
        global bots,tracers,world_t;
        map_load(map_id);
        spawn_ent(player);
        player.kills = 0;
        player.deaths = 0;
        bots = [];
        for n in range(BOT_COUNT) {
            b = Ent(is_bot=True);
            spawn_ent(b);
            bots.append(b);
        }
        tracers = [];
        world_t = 0.0;
    }

    # ── exported entry points (called by the shim) ─────────────────────────────
    """Open the window and build the first round."""
    def init {
        open_window(960, 600, "Jac FPS - Phase 1");
        new_round();
    }

    """Advance and render one frame. Returns True when the game wants to close."""
    def frame -> bool {
        global world_t,hit_flash;
        step = dt();
        world_t += step;
        if hit_flash > 0.0 {
            hit_flash -= step;
        }
        handle_input(step);
        tick_weapon(player, step);
        if player.alive {
            move_and_collide(player, step);
        } else {
            player.respawn_cd -= step;
            if player.respawn_cd <= 0.0 {
                spawn_ent(player);
            }
        }
        for b in bots {
            bot_update(b, step);
            if b.alive {
                move_and_collide(b, step);
            }
        }
        # age tracers
        alive_tr: list[Tracer] = [];
        for t in tracers {
            t.life -= step;
            if t.life > 0.0 {
                alive_tr.append(t);
            }
        }
        global tracers;
        tracers = alive_tr;
        # render
        begin_frame(15, 18, 28);
        set_camera(player.x, player.y + EYE_H, player.z, player.yaw, player.pitch, 1.6);
        draw_world();
        end_camera(960.0, 600.0);
        draw_fps(10, 10);
        end_frame();
        return False;
    }

    # ── HUD readouts (called from the cl{} on_tick hook) ───────────────────────
    def get_health -> int {
        return player.health;
    }

    def get_mag -> int {
        return player.mag;
    }

    def get_ammo -> int {
        return player.ammo;
    }

    def get_score -> int {
        return player.kills;
    }

    def get_kills -> int {
        return player.kills;
    }

    def get_deaths -> int {
        return player.deaths;
    }

    def get_alive -> int {
        return 1 if player.alive else 0;
    }

    def get_hit -> int {
        return 1 if hit_flash > 0.0 else 0;
    }

    """Switch map and restart the round (0 or 1)."""
    def set_map(mid: int) {
        global map_id;
        map_id = mid % 2;
        new_round();
    }

    """Restart the current round."""
    def restart {
        new_round();
    }
}
