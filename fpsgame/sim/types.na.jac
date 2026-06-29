"""Shared data model + tunables for the FPS sim.

`World` holds every piece of mutable game state. It is threaded explicitly
through the sim functions instead of using module globals, because reassigning
an imported global does not propagate across Jac modules (same as Python's
`from x import y` rebinding). Field writes on the shared `World` reference do
propagate -- and a single explicit state object is exactly what the Phase 5
authoritative server needs (one `World` per match).
"""

# ── tunables (single source) ───────────────────────────────────────────────
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
     MOUSE_SENS: float = 0.12,
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
     BOT_COUNT: int = 5,
     BOT_SPD_FRAC: float = 0.6,
     WP_REACH: float = 1.0,
     WP_TIMEOUT: float = 4.0;

# ── data model ──────────────────────────────────────────────────────────────
"""A 3D point (spawn locations, patrol waypoints)."""
obj Vec3 {
    has x: float = 0.0,
        y: float = 0.0,
        z: float = 0.0;
}

"""An axis-aligned bounding box collider."""
obj Box {
    has minx: float = 0.0,
        miny: float = 0.0,
        minz: float = 0.0,
        maxx: float = 0.0,
        maxy: float = 0.0,
        maxz: float = 0.0;
}

"""A short-lived shot tracer line segment."""
obj Tracer {
    has x0: float = 0.0,
        y0: float = 0.0,
        z0: float = 0.0,
        x1: float = 0.0,
        y1: float = 0.0,
        z1: float = 0.0,
        life: float = 0.0;
}

"""A player or bot: position, velocity, look angles, health, weapon + AI state."""
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
        # --- bot patrol state ---
        route: list[Vec3] = [],
        wp_idx: int = 0,
        wp_dir: int = 1,
        wp_timer: float = 0.0;
}

"""All mutable game state for one match/round."""
obj World {
    has player: Ent = Ent(),
        bots: list[Ent] = [],
        colliders: list[Box] = [],
        spawns: list[Vec3] = [],
        tracers: list[Tracer] = [],
        map_id: int = 0,
        world_t: float = 0.0,
        hit_flash: float = 0.0,
        muzzle_t: float = 0.0,
        prev_mx: float = 0.0,
        prev_my: float = 0.0,
        mouse_warmup: int = 12,
        mouse_captured: bool = False,
        # tunables set from the settings screen (defaults match the constants)
        sens: float = 0.12,
        bot_count: int = 5;
}
