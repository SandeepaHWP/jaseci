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
    RESPAWN_T,
    PICKUP_REACH
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
            ammo_max=72,
            zoom=1.0
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
            ammo_max=90,
            zoom=0.7
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
            ammo_max=36,
            zoom=1.0
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
            ammo_max=140,
            zoom=0.85
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
            ammo_max=30,
            zoom=0.35
        )
    );
}

# The roster is read through these scalar accessors, never by handing a Weapon
# back to a caller: returning an object borrowed from a list frees the list's
# entry (the caller drops it), so the table would fill with reused memory. Read
# the field inline off the subscript instead -- the same shape as get_bot_x.
"""Clamp a weapon id to a valid index into the table."""
def _gun_idx(world: World, gun: int) -> int {
    if gun < 0 or gun >= len(world.weapons) {
        return 0;
    }
    return gun;
}

def:pub gun_dmg(world: World, gun: int) -> int {
    if len(world.weapons) == 0 {
        return W_DMG;
    }
    return world.weapons[_gun_idx(world, gun)].dmg;
}

def:pub gun_fire_cd(world: World, gun: int) -> float {
    if len(world.weapons) == 0 {
        return W_FIRE_CD;
    }
    return world.weapons[_gun_idx(world, gun)].fire_cd;
}

def:pub gun_mag(world: World, gun: int) -> int {
    if len(world.weapons) == 0 {
        return W_MAG;
    }
    return world.weapons[_gun_idx(world, gun)].mag;
}

def:pub gun_reload_t(world: World, gun: int) -> float {
    if len(world.weapons) == 0 {
        return W_RELOAD;
    }
    return world.weapons[_gun_idx(world, gun)].reload_t;
}

def:pub gun_max_range(world: World, gun: int) -> float {
    if len(world.weapons) == 0 {
        return W_RANGE;
    }
    return world.weapons[_gun_idx(world, gun)].max_range;
}

def:pub gun_spread(world: World, gun: int) -> float {
    if len(world.weapons) == 0 {
        return 0.0;
    }
    return world.weapons[_gun_idx(world, gun)].spread;
}

def:pub gun_zoom(world: World, gun: int) -> float {
    if len(world.weapons) == 0 {
        return 1.0;
    }
    return world.weapons[_gun_idx(world, gun)].zoom;
}

def:pub gun_pellets(world: World, gun: int) -> int {
    if len(world.weapons) == 0 {
        return 1;
    }
    return world.weapons[_gun_idx(world, gun)].pellets;
}

def:pub gun_ammo_max(world: World, gun: int) -> int {
    if len(world.weapons) == 0 {
        return 90;
    }
    return world.weapons[_gun_idx(world, gun)].ammo_max;
}

"""Index of the nearest pickup within PICKUP_REACH of e, or -1 for none."""
def:pub near_pickup(world: World, e: Ent) -> int {
    best = -1;
    best_d = PICKUP_REACH * PICKUP_REACH;
    i = 0;
    for p in world.pickups {
        dx = p.x - e.x;
        dy = p.y - e.y;
        dz = p.z - e.z;
        d2 = dx * dx + dy * dy + dz * dz;
        if d2 <= best_d {
            best_d = d2;
            best = i;
        }
        i = i + 1;
    }
    return best;
}

"""Swap the player's weapon with the pickup at idx, exchanging ammo both ways:
you leave your gun on the ground holding its remaining rounds, and take theirs
as they were left. Writes through the loop variable, never `list[i].f = x`."""
def:pub swap_pickup(world: World, e: Ent, idx: int) {
    if idx < 0 or idx >= len(world.pickups) {
        return;
    }
    og = e.weapon_id;
    om = e.mag;
    oa = e.ammo;
    i = 0;
    for p in world.pickups {
        if i == idx {
            e.weapon_id = p.weapon_id;
            e.mag = p.mag;
            e.ammo = p.ammo;
            p.weapon_id = og;
            p.mag = om;
            p.ammo = oa;
            # a swap interrupts a reload and the fire cadence
            e.reloading = False;
            e.reload_cd = 0.0;
            e.fire_cd = 0.0;
            return;
        }
        i = i + 1;
    }
}

"""Fill every pickup with a full load of its own weapon (called on new_round)."""
def:pub stock_pickups(world: World) {
    for p in world.pickups {
        p.mag = gun_mag(world, p.weapon_id);
        p.ammo = gun_ammo_max(world, p.weapon_id);
    }
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
    pellets = gun_pellets(world, shooter.weapon_id);
    spread = gun_spread(world, shooter.weapon_id);
    rng = gun_max_range(world, shooter.weapon_id);
    dmg = gun_dmg(world, shooter.weapon_id);
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
    shooter.fire_cd = gun_fire_cd(world, shooter.weapon_id);
    fire(world, shooter, dx, dy, dz);
    # one-frame muzzle-flash trigger for the (cl{}) renderer; player shots only.
    if not shooter.is_bot {
        world.muzzle_t = 0.05;
    }
}

"""Begin reloading if it makes sense."""
def:pub start_reload(world: World, e: Ent) {
    if e.reloading or e.mag >= gun_mag(world, e.weapon_id) or e.ammo <= 0 {
        return;
    }
    e.reloading = True;
    e.reload_cd = gun_reload_t(world, e.weapon_id);
}

"""Advance weapon timers; finish a reload when the timer elapses."""
def:pub tick_weapon(world: World, e: Ent, step: float) {
    if e.fire_cd > 0.0 {
        e.fire_cd -= step;
    }
    if e.reloading {
        e.reload_cd -= step;
        if e.reload_cd <= 0.0 {
            need = gun_mag(world, e.weapon_id) - e.mag;
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
    e.mag = gun_mag(world, e.weapon_id);
    e.ammo = gun_ammo_max(world, e.weapon_id);
    e.reloading = False;
    e.reload_cd = 0.0;
    e.fire_cd = 0.0;
    e.respawn_cd = 0.0;
}
