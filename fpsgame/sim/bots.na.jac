"""Bot AI: each bot patrols a random route of waypoints, ping-ponging back and
forth (a-b-a-b for 2 points, a-b-c-b-a for 3, etc.), and shoots the player
whenever it has line of sight. Bots no longer all chase the player into one
corner -- their movement is independent, randomised patrols.

All vector math uses explicit `x = x op y` assignments (never compound `+=`/`/=`),
because the wasm/native backend miscompiled compound assignment to a constant.
"""

import from .types {
    World,
    Ent,
    Vec3,
    EYE_H,
    MOVE_SPD,
    BOT_SPD_FRAC,
    WP_REACH,
    WP_TIMEOUT
}
import from .mathx { fsqrt, atan2_deg, rand_range, rand01 }
import from .physics { ray_world }
import from .combat { spawn_ent, try_fire, start_reload, tick_weapon }

"""Give a bot a fresh random patrol route (2-4 waypoints in the arena)."""
def:pub assign_route(b: Ent) {
    b.route = [];
    n = 2 + int(rand01() * 3.0);
    i = 0;
    while i < n {
        b.route.append(
            Vec3(x=rand_range(-16.0, 16.0), y=0.0, z=rand_range(-16.0, 16.0))
        );
        i = i + 1;
    }
    b.wp_idx = 0;
    b.wp_dir = 1;
    b.wp_timer = WP_TIMEOUT;
}

"""Advance to the next waypoint, ping-ponging at the ends of the route."""
def _next_waypoint(b: Ent) {
    b.wp_idx = b.wp_idx + b.wp_dir;
    last = len(b.route) - 1;
    if b.wp_idx >= last {
        b.wp_idx = last;
        b.wp_dir = -1;
    }
    if b.wp_idx <= 0 {
        b.wp_idx = 0;
        b.wp_dir = 1;
    }
    b.wp_timer = WP_TIMEOUT;
}

"""Patrol the route and shoot the player on sight."""
def:pub bot_update(world: World, b: Ent, step: float) {
    if not b.alive {
        b.respawn_cd -= step;
        if b.respawn_cd <= 0.0 {
            spawn_ent(world, b);
            assign_route(b);
        }
        return;
    }
    if len(b.route) == 0 {
        assign_route(b);
    }
    # --- move toward the current waypoint ---
    tgt = b.route[b.wp_idx];
    dx = tgt.x - b.x;
    dz = tgt.z - b.z;
    dist = fsqrt(dx * dx + dz * dz);
    b.wp_timer = b.wp_timer - step;
    # reached it, or spent too long trying (blocked) -> pick the next one
    if dist < WP_REACH or b.wp_timer <= 0.0 {
        _next_waypoint(b);
        tgt = b.route[b.wp_idx];
        dx = tgt.x - b.x;
        dz = tgt.z - b.z;
        dist = fsqrt(dx * dx + dz * dz);
    }
    ndx = 0.0;
    ndz = 0.0;
    if dist > 0.001 {
        ndx = dx / dist;
        ndz = dz / dist;
    }
    spd = MOVE_SPD * BOT_SPD_FRAC;
    b.vx = ndx * spd;
    b.vz = ndz * spd;
    if dist > 0.001 {
        b.yaw = atan2_deg(-ndx, -ndz);
    }
    # --- shoot the player when there is a clear line of sight ---
    # TEMPORARILY DISABLED: bots patrol but do not fire. Uncomment to re-enable.
    # (ray_world / try_fire / start_reload / tick_weapon imports stay for this.)
    # ox = b.x;
    # oy = b.y + EYE_H;
    # oz = b.z;
    # aimx = world.player.x - ox;
    # aimy = (world.player.y + EYE_H * 0.6) - oy;
    # aimz = world.player.z - oz;
    # al = fsqrt(aimx * aimx + aimy * aimy + aimz * aimz);
    # if al > 0.001 {
    #     aimx = aimx / al;
    #     aimy = aimy / al;
    #     aimz = aimz / al;
    # }
    # wall_t = ray_world(world, ox, oy, oz, aimx, aimy, aimz, al);
    # tick_weapon(world, b, step);
    # if wall_t >= al - 0.2 and world.player.alive {
    #     sxp = rand_range(-0.04, 0.04);
    #     syp = rand_range(-0.04, 0.04);
    #     try_fire(world, b, aimx + sxp, aimy + syp, aimz);
    #     if b.mag <= 0 {
    #         start_reload(world, b);
    #     }
    # }
}
