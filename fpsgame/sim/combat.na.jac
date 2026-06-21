"""Weapons, hitscan fire, damage/death, reload, and (re)spawning entities."""

import from .types {
    World,
    Ent,
    Tracer,
    EYE_H,
    W_RANGE,
    W_DMG,
    W_FIRE_CD,
    W_MAG,
    W_RELOAD,
    RESPAWN_T
}
import from .physics { ray_world, ray_vs_ent }
import from .maps { pick_spawn }

"""Apply damage to an entity; trigger death + score on kill."""
def:pub damage(victim: Ent, dmg: int, attacker: Ent) {
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
def:pub fire(world: World, shooter: Ent, dx: float, dy: float, dz: float) {
    ox = shooter.x;
    oy = shooter.y + EYE_H;
    oz = shooter.z;
    wall_t = ray_world(world, ox, oy, oz, dx, dy, dz, W_RANGE);
    best_t = wall_t;
    victim: Ent = shooter;
    found = False;
    if shooter.is_bot {
        t = ray_vs_ent(ox, oy, oz, dx, dy, dz, world.player, best_t);
        if t >= 0.0 and t < best_t and world.player.alive {
            best_t = t;
            victim = world.player;
            found = True;
        }
    } else {
        for b in world.bots {
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
    world.tracers.append(
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
            world.hit_flash = 0.12;
        }
    }
}

"""Try to fire shooter's weapon this frame (respects cooldown, ammo, reload)."""
def:pub try_fire(world: World, shooter: Ent, dx: float, dy: float, dz: float) {
    if shooter.reloading or shooter.fire_cd > 0.0 or shooter.mag <= 0 {
        return;
    }
    shooter.mag -= 1;
    shooter.fire_cd = W_FIRE_CD;
    fire(world, shooter, dx, dy, dz);
}

"""Begin reloading if it makes sense."""
def:pub start_reload(e: Ent) {
    if e.reloading or e.mag >= W_MAG or e.ammo <= 0 {
        return;
    }
    e.reloading = True;
    e.reload_cd = W_RELOAD;
}

"""Advance weapon timers; finish a reload when the timer elapses."""
def:pub tick_weapon(e: Ent, step: float) {
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

"""Reset an entity to full health at a spawn point."""
def:pub spawn_ent(world: World, e: Ent) {
    sp = pick_spawn(world);
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
