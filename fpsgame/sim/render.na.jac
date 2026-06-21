"""raylib/rlgl interface: the FFI import, input wrappers, and 3D draw helpers.

All raylib externs live here so the rest of the sim never touches the FFI
directly. In the browser these externs are satisfied by raylib_shim.cl.jac
(WebGL/DOM); in a native build they link against real raylib.
"""

import from .types { World, Box, Ent, Tracer }

import from raylib {
    def InitWindow(width: i32, height: i32, title: str) -> None;  def WindowShouldClose -> bool;  def CloseWindow -> None;  def BeginDrawing -> None;  def EndDrawing -> None;  def rlClearColor(
        r: u8, g: u8, b: u8, a: u8
    ) -> None;  def rlClearScreenBuffers -> None;  def DrawFPS(
        pos_x: i32, pos_y: i32
    ) -> None;  def IsKeyDown(key: i32) -> bool;  def IsKeyPressed(key: i32) -> bool;  def GetFrameTime -> f32;  def GetMouseX -> i32;  def GetMouseY -> i32;  def IsMouseButtonPressed(
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

# ── window + input wrappers ─────────────────────────────────────────────────
def:pub open_window(width: int, height: int, title: str) {
    InitWindow(width, height, title);
}

def:pub dt -> float {
    return GetFrameTime();
}

def:pub key_held(code: int) -> bool {
    return IsKeyDown(code);
}

def:pub key_tapped(code: int) -> bool {
    return IsKeyPressed(code);
}

def:pub mouse_x -> float {
    return float(GetMouseX());
}

def:pub mouse_y -> float {
    return float(GetMouseY());
}

def:pub mouse_pressed(button: int) -> bool {
    return IsMouseButtonPressed(button);
}

def:pub mouse_held(button: int) -> bool {
    return IsMouseButtonDown(button);
}

def:pub lock_mouse {
    DisableCursor();
}

def:pub unlock_mouse {
    EnableCursor();
}

# ── frame + camera ──────────────────────────────────────────────────────────
def:pub begin_frame(r: int, g: int, b: int) {
    BeginDrawing();
    rlClearColor(r, g, b, 255);
    rlClearScreenBuffers();
    rlEnableDepthTest();
}

def:pub end_frame {
    EndDrawing();
}

def:pub end_camera(width: float, height: float) {
    EndMode3D();
    rlMatrixMode(RL_PROJECTION);
    rlLoadIdentity();
    rlOrtho(0.0, width, height, 0.0, -1.0, 1.0);
    rlMatrixMode(RL_MODELVIEW);
    rlLoadIdentity();
}

def:pub draw_fps(x: int, y: int) {
    DrawFPS(x, y);
}

"""Perspective camera at (px,py,pz) looking by yaw/pitch (degrees), aspect=w/h."""
def:pub set_camera(
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

# ── primitives ──────────────────────────────────────────────────────────────
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
def:pub draw_box(
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
def:pub draw_floor(half: int, step: float) {
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

"""Draw the whole world: floor, map boxes, bots, tracers."""
def:pub draw_world(world: World) {
    draw_floor(20, 1.5);
    for b in world.colliders {
        cx = (b.minx + b.maxx) * 0.5;
        cy = (b.miny + b.maxy) * 0.5;
        cz = (b.minz + b.maxz) * 0.5;
        sx = b.maxx - b.minx;
        sy = b.maxy - b.miny;
        sz = b.maxz - b.minz;
        draw_box(cx, cy, cz, sx, sy, sz, 70, 80, 110);
    }
    for e in world.bots {
        if e.alive {
            draw_box(e.x, e.y + 0.9, e.z, 0.8, 1.8, 0.8, 235, 80, 60);
            draw_box(e.x, e.y + 1.9, e.z, 0.5, 0.5, 0.5, 250, 120, 90);
        }
    }
    rlSetLineWidth(2.0);
    rlBegin(RL_LINES);
    rlColor4ub(255, 230, 120, 255);
    for t in world.tracers {
        rlVertex3f(t.x0, t.y0, t.z0);
        rlVertex3f(t.x1, t.y1, t.z1);
    }
    rlEnd();
}
