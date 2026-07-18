"""Map geometry: builds the box colliders and spawn points for each map id."""

import from .types {
    World,
    Box,
    Vec3,
    Pickup,
    GUN_PISTOL,
    GUN_RIFLE,
    GUN_SHOTGUN,
    GUN_SMG,
    GUN_SNIPER
}
import from .mathx { rand01 }

"""Append an axis-aligned box collider given center + half-extents."""
def:pub add_box(
    world: World, cx: float, cy: float, cz: float, hx: float, hy: float, hz: float
) {
    world.colliders.append(
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

"""Append a weapon pickup. mag/ammo are stocked by new_round, not here: maps
cannot import combat (combat already imports pick_spawn from here)."""
def:pub add_pickup(world: World, x: float, y: float, z: float, gun: int) {
    world.pickups.append(Pickup(x=x, y=y, z=z, weapon_id=gun));
}

"""A weapon table against a wall: a low block plus the gun resting on top.
The gun sits at 1.25 -- reach is measured from the player's feet, so anything
much higher than the player is un-grabbable no matter how close you stand."""
def:pub add_table(world: World, x: float, z: float, gun: int) {
    add_box(world, x, 0.5, z, 0.9, 0.5, 0.9);
    add_pickup(world, x, 1.25, z, gun);
}

"""The armoury: one weapon table per gun, in a row along the west wall."""
def:pub add_armoury(world: World) {
    add_table(world, -20.0, -6.0, GUN_PISTOL);
    add_table(world, -20.0, -3.0, GUN_RIFLE);
    add_table(world, -20.0, 0.0, GUN_SHOTGUN);
    add_table(world, -20.0, 3.0, GUN_SMG);
    add_table(world, -20.0, 6.0, GUN_SNIPER);
}

"""Load colliders + spawn points for a map id. map 0 = open, map 1 = cover."""
def:pub map_load(world: World, mid: int) {
    world.colliders = [];
    world.spawns = [];
    world.pickups = [];
    ext = 24.0;
    wall_h = 6.0;
    # perimeter walls
    add_box(world, 0.0, wall_h * 0.5, -ext, ext, wall_h * 0.5, 0.5);
    add_box(world, 0.0, wall_h * 0.5, ext, ext, wall_h * 0.5, 0.5);
    add_box(world, -ext, wall_h * 0.5, 0.0, 0.5, wall_h * 0.5, ext);
    add_box(world, ext, wall_h * 0.5, 0.0, 0.5, wall_h * 0.5, ext);
    if mid == 0 {
        add_box(world, -6.0, 1.0, -4.0, 1.5, 1.0, 1.5);
        add_box(world, 7.0, 1.0, 3.0, 1.5, 1.0, 1.5);
        add_box(world, 0.0, 1.5, 8.0, 2.0, 1.5, 1.0);
        add_box(world, -9.0, 1.0, 9.0, 1.0, 1.0, 1.0);
    } else {
        add_box(world, 0.0, 2.0, 0.0, 2.0, 2.0, 2.0);
        add_box(world, -8.0, 1.2, -8.0, 2.5, 1.2, 0.6);
        add_box(world, 8.0, 1.2, 8.0, 2.5, 1.2, 0.6);
        add_box(world, -8.0, 1.2, 8.0, 0.6, 1.2, 2.5);
        add_box(world, 8.0, 1.2, -8.0, 0.6, 1.2, 2.5);
        add_box(world, 12.0, 1.0, 0.0, 1.0, 1.0, 4.0);
        add_box(world, -12.0, 1.0, 0.0, 1.0, 1.0, 4.0);
    }
    add_armoury(world);
    world.spawns.append(Vec3(x=-18.0, y=0.0, z=-18.0));
    world.spawns.append(Vec3(x=18.0, y=0.0, z=18.0));
    world.spawns.append(Vec3(x=-18.0, y=0.0, z=18.0));
    world.spawns.append(Vec3(x=18.0, y=0.0, z=-18.0));
    world.spawns.append(Vec3(x=0.0, y=0.0, z=-19.0));
    world.spawns.append(Vec3(x=0.0, y=0.0, z=19.0));
}

"""A random spawn point from the map's spawn list."""
def:pub pick_spawn(world: World) -> Vec3 {
    n = len(world.spawns);
    if n == 0 {
        return Vec3(x=0.0, y=0.0, z=0.0);
    }
    idx = int(rand01() * float(n)) % n;
    return world.spawns[idx];
}
