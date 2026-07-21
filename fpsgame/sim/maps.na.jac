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

# The big-arena half-extent (96x96 floor -- 4x the old 48x48 play area). The
# renderer aligns its tiled floor + water pool (NE corner ~33,33) to this.
glob MAP_EXT: float = 48.0;

"""The armoury: one weapon table per gun, in a row along the far west wall."""
def:pub add_armoury(world: World) {
    add_table(world, -44.0, -6.0, GUN_PISTOL);
    add_table(world, -44.0, -3.0, GUN_RIFLE);
    add_table(world, -44.0, 0.0, GUN_SHOTGUN);
    add_table(world, -44.0, 3.0, GUN_SMG);
    add_table(world, -44.0, 6.0, GUN_SNIPER);
}

"""Load colliders + spawn points for a map id. map 0 = open, map 1 = cover.
Big 96x96 arena: brick perimeter + interior structures, a colourful tiled floor
and a water pool (both drawn by the renderer)."""
def:pub map_load(world: World, mid: int) {
    world.colliders = [];
    world.spawns = [];
    world.pickups = [];
    ext = MAP_EXT;
    wall_h = 7.0;
    # perimeter walls
    add_box(world, 0.0, wall_h * 0.5, -ext, ext, wall_h * 0.5, 0.6);
    add_box(world, 0.0, wall_h * 0.5, ext, ext, wall_h * 0.5, 0.6);
    add_box(world, -ext, wall_h * 0.5, 0.0, 0.6, wall_h * 0.5, ext);
    add_box(world, ext, wall_h * 0.5, 0.0, 0.6, wall_h * 0.5, ext);
    if mid == 0 {
        # central raised platform
        add_box(world, 0.0, 1.6, 0.0, 7.0, 1.6, 7.0);
        # four corner blocks
        add_box(world, -20.0, 1.6, -20.0, 3.5, 1.6, 3.5);
        add_box(world, 20.0, 1.6, 20.0, 3.5, 1.6, 3.5);
        add_box(world, 20.0, 1.6, -20.0, 3.5, 1.6, 3.5);
        add_box(world, -20.0, 1.6, 20.0, 3.5, 1.6, 3.5);
        # sightline walls (not on the west armoury side or the NE water pool)
        add_box(world, 0.0, 2.2, -24.0, 11.0, 2.2, 0.7);
        add_box(world, -24.0, 2.2, 0.0, 0.7, 2.2, 11.0);
        add_box(world, 0.0, 2.2, 24.0, 11.0, 2.2, 0.7);
        # low cover
        add_box(world, 12.0, 0.9, -12.0, 2.2, 0.9, 2.2);
        add_box(world, -12.0, 0.9, 12.0, 2.2, 0.9, 2.2);
    } else {
        add_box(world, 0.0, 2.6, 0.0, 3.2, 2.6, 3.2);
        add_box(world, -18.0, 1.5, -18.0, 4.5, 1.5, 0.8);
        add_box(world, 18.0, 1.5, 18.0, 4.5, 1.5, 0.8);
        add_box(world, -18.0, 1.5, 18.0, 0.8, 1.5, 4.5);
        add_box(world, 18.0, 1.5, -18.0, 0.8, 1.5, 4.5);
        add_box(world, 30.0, 1.3, 0.0, 1.3, 1.3, 7.0);
        add_box(world, -30.0, 1.3, 0.0, 1.3, 1.3, 7.0);
        add_box(world, 0.0, 1.3, -30.0, 7.0, 1.3, 1.3);
    }
    add_armoury(world);
    # spawns spread to the corners/edges of the big arena
    world.spawns.append(Vec3(x=-40.0, y=0.0, z=-40.0));
    world.spawns.append(Vec3(x=40.0, y=0.0, z=40.0));
    world.spawns.append(Vec3(x=-40.0, y=0.0, z=40.0));
    world.spawns.append(Vec3(x=40.0, y=0.0, z=-40.0));
    world.spawns.append(Vec3(x=0.0, y=0.0, z=-42.0));
    world.spawns.append(Vec3(x=0.0, y=0.0, z=42.0));
    world.spawns.append(Vec3(x=-42.0, y=0.0, z=0.0));
    world.spawns.append(Vec3(x=14.0, y=0.0, z=0.0));
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
