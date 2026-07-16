"""Weapons, hitscan fire, damage/death, reload, and (re)spawning entities."""

import from .types {
    World,
    Ent,
    Tracer,
    Weapon,
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
import from .mathx { rand_range, fsqrt }

"""Build the weapon roster into world.weapons, indexed by the GUN_* ids. Entry 1
(rifle) is built from the W_* tunables so it stays exactly the weapon Phase 1
shipped. Appended in place like map_load builds colliders -- returning a list of
freshly built objects from a function does not survive the native backend."""
def:pub build_weapons(world: World) {
    world.weapons = [];
    world.weapons.append(
        Weapon(
            dmg=26,
            fire_cd=0.28,
            mag=12,
            reload_t=1.2,
            max_range=120.0,
            spread=0.006,
            pellets=1,
            ammo_max=72
        )
    );
    world.weapons.append(
        Weapon(
            dmg=W_DMG,
            fire_cd=W_FIRE_CD,
            mag=W_MAG,
            reload_t=W_RELOAD,
            max_range=W_RANGE,
            spread=0.0,
            pellets=1,
            ammo_max=90
        )
    );
    world.weapons.append(
        Weapon(
            dmg=11,
            fire_cd=0.75,
            mag=6,
            reload_t=2.2,
            max_range=45.0,
            spread=0.07,
            pellets=8,
            ammo_max=36
        )
    );
    world.weapons.append(
        Weapon(
            dmg=13,
            fire_cd=0.07,
            mag=35,
            reload_t=1.4,
            max_range=90.0,
            spread=0.035,
            pellets=1,
            ammo_max=140
        )
    );
    world.weapons.append(
        Weapon(
            dmg=95,
            fire_cd=1.15,
            mag=5,
            reload_t=2.6,
            max_range=400.0,
            spread=0.0,
            pellets=1,
            ammo_max=30
        )
    );
}

# The roster is read through these scalar accessors, never by handing a Weapon
# back to a caller: returning an object borrowed from a list frees the list's
# entry (the caller drops it), so the table would fill with reused memory. Read
# the field inline off the subscript instead -- the same shape as get_bot_x.
"""Clamp an entity's weapon id to a valid index into the table."""
def _gun_idx(world: World, e: Ent) -> int {
    if e.weapon_id < 0 or e.weapon_id >= len(world.weapons) {
        return 0;
    }
    return e.weapon_id;
}

def:pub gun_dmg(world: World, e: Ent) -> int {
    if len(world.weapons) == 0 {
        return W_DMG;
    }
    return world.weapons[_gun_idx(world, e)].dmg;
}

def:pub gun_fire_cd(world: World, e: Ent) -> float {
    if len(world.weapons) == 0 {
        return W_FIRE_CD;
    }
    return world.weapons[_gun_idx(world, e)].fire_cd;
}

def:pub gun_mag(world: World, e: Ent) -> int {
    if len(world.weapons) == 0 {
        return W_MAG;
    }
    return world.weapons[_gun_idx(world, e)].mag;
}

def:pub gun_reload_t(world: World, e: Ent) -> float {
    if len(world.weapons) == 0 {
        return W_RELOAD;
    }
    return world.weapons[_gun_idx(world, e)].reload_t;
}

def:pub gun_max_range(world: World, e: Ent) -> float {
    if len(world.weapons) == 0 {
        return W_RANGE;
    }
    return world.weapons[_gun_idx(world, e)].max_range;
}

def:pub gun_spread(world: World, e: Ent) -> float {
    if len(world.weapons) == 0 {
        return 0.0;
    }
    return world.weapons[_gun_idx(world, e)].spread;
}

def:pub gun_pellets(world: World, e: Ent) -> int {
    if len(world.weapons) == 0 {
        return 1;
    }
    return world.weapons[_gun_idx(world, e)].pellets;
}

def:pub gun_ammo_max(world: World, e: Ent) -> int {
    if len(world.weapons) == 0 {
        return 90;
    }
    return world.weapons[_gun_idx(world, e)].ammo_max;
}

"""Switch weapon: refill to the new gun's mag/ammo and cancel any reload.
Each gun carries its own mag size, so the old magazine cannot carry over."""
def:pub set_weapon(world: World, e: Ent, gun: int) {
    if gun < 0 or gun >= len(world.weapons) or gun == e.weapon_id {
        return;
    }
    e.weapon_id = gun;
    e.mag = gun_mag(world, e);
    e.ammo = gun_ammo_max(world, e);
    e.reloading = False;
    e.reload_cd = 0.0;
    e.fire_cd = 0.0;
}

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

"""Fire one hitscan ray from eye along (dx,dy,dz); resolve closest target.
Takes the weapon's range/damage as scalars -- see the accessor note above."""
def _fire_ray(
    world: World,
    shooter: Ent,
    dx: float,
    dy: float,
    dz: float,
    max_range: float,
    dmg: int
) {
    ox = shooter.x;
    oy = shooter.y + EYE_H;
    oz = shooter.z;
    wall_t = ray_world(world, ox, oy, oz, dx, dy, dz, max_range);
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
        damage(victim, dmg, shooter);
        if not shooter.is_bot {
            world.hit_flash = 0.12;
        }
    }
}

"""Fire one shot: one ray per pellet, each jittered by the weapon's spread.
A 1-pellet, 0-spread weapon (the rifle) is a single exact ray as before."""
def:pub fire(world: World, shooter: Ent, dx: float, dy: float, dz: float) {
    pellets = gun_pellets(world, shooter);
    spread = gun_spread(world, shooter);
    rng = gun_max_range(world, shooter);
    dmg = gun_dmg(world, shooter);
    n = pellets if pellets > 1 else 1;
    for i in range(n) {
        ax = dx;
        ay = dy;
        az = dz;
        if spread > 0.0 {
            ax = dx + rand_range(-spread, spread);
            ay = dy + rand_range(-spread, spread);
            az = dz + rand_range(-spread, spread);
            ln = fsqrt(ax * ax + ay * ay + az * az);
            if ln > 0.001 {
                ax = ax / ln;
                ay = ay / ln;
                az = az / ln;
            }
        }
        _fire_ray(world, shooter, ax, ay, az, rng, dmg);
    }
}

"""Try to fire shooter's weapon this frame (respects cooldown, ammo, reload)."""
def:pub try_fire(world: World, shooter: Ent, dx: float, dy: float, dz: float) {
    if shooter.reloading or shooter.fire_cd > 0.0 or shooter.mag <= 0 {
        return;
    }
    shooter.mag -= 1;
    shooter.fire_cd = gun_fire_cd(world, shooter);
    fire(world, shooter, dx, dy, dz);
    # one-frame muzzle-flash trigger for the (cl{}) renderer; player shots only.
    if not shooter.is_bot {
        world.muzzle_t = 0.05;
    }
}

"""Begin reloading if it makes sense."""
def:pub start_reload(world: World, e: Ent) {
    if e.reloading or e.mag >= gun_mag(world, e) or e.ammo <= 0 {
        return;
    }
    e.reloading = True;
    e.reload_cd = gun_reload_t(world, e);
}

"""Advance weapon timers; finish a reload when the timer elapses."""
def:pub tick_weapon(world: World, e: Ent, step: float) {
    if e.fire_cd > 0.0 {
        e.fire_cd -= step;
    }
    if e.reloading {
        e.reload_cd -= step;
        if e.reload_cd <= 0.0 {
            need = gun_mag(world, e) - e.mag;
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
    e.mag = gun_mag(world, e);
    e.ammo = gun_ammo_max(world, e);
    e.reloading = False;
    e.reload_cd = 0.0;
    e.fire_cd = 0.0;
    e.respawn_cd = 0.0;
}
