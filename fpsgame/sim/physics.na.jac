"""Collision resolution and ray casting against the world's box colliders."""

import from .types { World, Ent, Box, PLAYER_R, PLAYER_H }

"""Resolve an entity AABB out of one box along the least-penetration axis."""
def:pub resolve(e: Ent, b: Box) {
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
def:pub move_and_collide(world: World, e: Ent, step: float) {
    # Gravity. The constant is inlined (-22.0) on purpose: the imported `GRAV`
    # constant from types read wrong in the native/wasm backend and silently
    # dropped gravity (no fall -> on_ground never set -> jump never fired). Keep
    # it a literal here until that backend bug is resolved; `GRAV` in types
    # remains the documented tunable.
    e.vy = e.vy - 22.0 * step;
    e.on_ground = False;
    e.x = e.x + e.vx * step;
    e.y = e.y + e.vy * step;
    e.z = e.z + e.vz * step;
    if e.y < 0.0 {
        e.y = 0.0;
        e.vy = 0.0;
        e.on_ground = True;
    }
    for b in world.colliders {
        resolve(e, b);
    }
}

"""Ray vs AABB slab test. Returns hit distance t, or -1.0 if no hit within tmax."""
def:pub ray_vs_box(
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
def:pub ray_world(
    world: World,
    ox: float,
    oy: float,
    oz: float,
    dx: float,
    dy: float,
    dz: float,
    tmax: float
) -> float {
    best = tmax;
    for b in world.colliders {
        t = ray_vs_box(ox, oy, oz, dx, dy, dz, b, tmax);
        if t >= 0.0 and t < best {
            best = t;
        }
    }
    return best;
}

"""Ray vs an entity's body AABB. Returns t or -1.0."""
def:pub ray_vs_ent(
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
