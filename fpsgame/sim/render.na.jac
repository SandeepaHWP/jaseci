"""Host I/O for the sim: input + frame-timing externs and their wrappers.

Phase 4.5 moved rendering out of the sim. The cl{} Three.js renderer now reads
sim state through the `get_*` exports in main.jac and draws it; the sim no longer
calls any draw functions. This module is what remains: thin wrappers over the host
input + timing externs, satisfied by raylib_shim.cl.jac in the browser (or real
raylib in a native build). The old rlgl draw externs and `draw_world` are gone, so
the wasm no longer imports any rendering functions.
"""

import from raylib {
    def InitWindow(width: i32, height: i32, title: str) -> None;  def GetFrameTime -> f32;  def IsKeyDown(
        key: i32
    ) -> bool;  def IsKeyPressed(key: i32) -> bool;  def GetMouseX -> i32;  def GetMouseY -> i32;  def IsMouseButtonPressed(
        button: i32
    ) -> bool;  def IsMouseButtonDown(button: i32) -> bool;  def DisableCursor -> None;  def EnableCursor -> None;
}

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
