"""Map geometry: builds the box colliders and spawn points for each map id."""

import from .types { World, Box, Vec3 }
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

"""Load colliders + spawn points for a map id. map 0 = open, map 1 = cover."""
def:pub map_load(world: World, mid: int) {
    world.colliders = [];
    world.spawns = [];
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
