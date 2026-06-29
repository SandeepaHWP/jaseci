"""Player input, round lifecycle, and the per-frame update+render step.

This is the orchestration layer: it wires input -> physics -> combat -> bots ->
render together over a single `World`. The exported entry points in main.jac are
thin wrappers around `world_init` / `world_frame`.
"""

import from .types {
    World,
    Ent,
    Tracer,
    KEY_W,
    KEY_A,
    KEY_S,
    KEY_D,
    KEY_R,
    KEY_SPACE,
    KEY_LEFT,
    KEY_RIGHT,
    KEY_UP,
    KEY_DOWN,
    KEY_TAB,
    MOUSE_LEFT,
    DEG2RAD,
    MOVE_SPD,
    JUMP_V
}
import from .mathx { jsin, jcos, fsqrt }
import from .render {
    open_window,
    dt,
    key_held,
    key_tapped,
    mouse_x,
    mouse_y,
    mouse_pressed,
    mouse_held,
    lock_mouse,
    unlock_mouse
}
import from .physics { move_and_collide }
import from .combat { tick_weapon, start_reload, try_fire, spawn_ent }
import from .maps { map_load }
import from .bots { bot_update, assign_route }

"""Read keyboard + mouse and drive the player (look, move, jump, fire, reload)."""
def:pub handle_input(world: World, step: float) {
    if key_tapped(KEY_TAB) {
        if world.mouse_captured {
            unlock_mouse();
            world.mouse_captured = False;
        } else {
            lock_mouse();
            world.mouse_captured = True;
            world.mouse_warmup = 8;
        }
    }
    if not world.mouse_captured and mouse_pressed(MOUSE_LEFT) {
        lock_mouse();
        world.mouse_captured = True;
        world.mouse_warmup = 8;
    }
    turn = 90.0 * step;
    if key_held(KEY_LEFT) {
        world.player.yaw += turn;
    }
    if key_held(KEY_RIGHT) {
        world.player.yaw -= turn;
    }
    if key_held(KEY_UP) {
        world.player.pitch += turn;
    }
    if key_held(KEY_DOWN) {
        world.player.pitch -= turn;
    }
    if world.mouse_captured {
        mx = mouse_x();
        my = mouse_y();
        if world.mouse_warmup > 0 {
            world.mouse_warmup -= 1;
        } else {
            ddx = mx - world.prev_mx;
            ddy = my - world.prev_my;
            if ddx < 150.0 and ddx > -150.0 and ddy < 150.0 and ddy > -150.0 {
                world.player.yaw -= ddx * world.sens;
                world.player.pitch -= ddy * world.sens;
            }
        }
        world.prev_mx = mx;
        world.prev_my = my;
    }
    if world.player.pitch > 85.0 {
        world.player.pitch = 85.0;
    }
    if world.player.pitch < -85.0 {
        world.player.pitch = -85.0;
    }
    if not world.player.alive {
        world.player.vx = 0.0;
        world.player.vz = 0.0;
        return;
    }
    yaw_r = world.player.yaw * DEG2RAD;
    sy = jsin(yaw_r);
    cy = jcos(yaw_r);
    # forward = (-sin, -cos); right = (cos, -sin).
    # NOTE: build the wish vector with explicit `mvx = mvx + ...` assignment.
    # The compound `mvx += ...` form miscompiles to a constant in the native /
    # wasm backend here, so keep these as plain assignments.
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
    world.player.vx = mvx * MOVE_SPD;
    world.player.vz = mvz * MOVE_SPD;
    if key_held(KEY_SPACE) and world.player.on_ground {
        world.player.vy = JUMP_V;
    }
    if key_tapped(KEY_R) {
        start_reload(world.player);
    }
    if mouse_held(MOUSE_LEFT) and world.mouse_captured {
        yp = world.player.pitch * DEG2RAD;
        cp = jcos(yp);
        dx = -jsin(yaw_r) * cp;
        dy = jsin(yp);
        dz = -jcos(yaw_r) * cp;
        if world.player.mag <= 0 {
            start_reload(world.player);
        } else {
            try_fire(world, world.player, dx, dy, dz);
        }
    }
}

"""(Re)build the world for the current map and spawn everyone."""
def:pub new_round(world: World) {
    map_load(world, world.map_id);
    spawn_ent(world, world.player);
    world.player.kills = 0;
    world.player.deaths = 0;
    world.bots = [];
    for n in range(world.bot_count) {
        b = Ent(is_bot=True);
        spawn_ent(world, b);
        assign_route(b);
        world.bots.append(b);
    }
    world.tracers = [];
    world.world_t = 0.0;
}

"""Open the window and build the first round."""
def:pub world_init(world: World) {
    open_window(960, 600, "Jac FPS - Phase 1");
    new_round(world);
}

"""Switch map (0 or 1) and restart the round."""
def:pub world_set_map(world: World, mid: int) {
    world.map_id = mid % 2;
    new_round(world);
}

"""Advance the sim one frame. Rendering lives in cl{} now (Phase 4.5): this only
steps the world; the Three.js renderer reads state via the get_* exports."""
def:pub world_frame(world: World) -> bool {
    step = dt();
    world.world_t += step;
    if world.hit_flash > 0.0 {
        world.hit_flash -= step;
    }
    if world.muzzle_t > 0.0 {
        world.muzzle_t -= step;
    }
    handle_input(world, step);
    tick_weapon(world.player, step);
    if world.player.alive {
        move_and_collide(world, world.player, step);
    } else {
        world.player.respawn_cd -= step;
        if world.player.respawn_cd <= 0.0 {
            spawn_ent(world, world.player);
        }
    }
    for b in world.bots {
        bot_update(world, b, step);
        if b.alive {
            move_and_collide(world, b, step);
        }
    }
    # age tracers
    alive_tr: list[Tracer] = [];
    for t in world.tracers {
        t.life -= step;
        if t.life > 0.0 {
            alive_tr.append(t);
        }
    }
    world.tracers = alive_tr;
    return False;
}
