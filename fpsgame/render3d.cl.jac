"""Three.js renderer for the FPS sim (Phase 4.5B).

Pull-based rendering: the na{} sim is pure state now; this module reads it through
the `get_*` wasm exports each frame and draws a real lit/shadowed 3D scene. The sim
never calls a draw function. Built from Three.js primitives (no external models yet
-- those arrive in Phase 4.6).

cl{} typing: Three classes are constructed with `new(Class, ...)` (like the shim's
`new(Uint8Array, ...)`). Values read from `exports` are Any, so they are funnelled
through `float()`/`int()` of an f-string (typed builtins reject Any, and relational
ops don't work on Any). Per-index getters take a wasm i64 -> pass `BigInt(i)`.
"""

import from "three" {
    Scene,
    PerspectiveCamera,
    WebGLRenderer,
    DirectionalLight,
    HemisphereLight,
    AmbientLight,
    Fog,
    Color,
    DoubleSide,
    BoxGeometry,
    CapsuleGeometry,
    SphereGeometry,
    PlaneGeometry,
    MeshStandardMaterial,
    MeshBasicMaterial,
    Mesh,
    Group,
    PCFSoftShadowMap,
    ACESFilmicToneMapping,
    SRGBColorSpace
}

obj R3D {
    has scene: any = None,
        cam: any = None,
        renderer: any = None,
        gun: any = None,
        flash: any = None,
        bots: list = [],
        tracers: list = [],
        flash_op: float = 0.0,
        recoil: float = 0.0,
        static_built: bool = False;
}

"""A first-person gun viewmodel built from a couple of boxes."""
def _make_gun -> any {
    g = new(Group);
    mat = new(
        MeshStandardMaterial, {"color": 0x222730, "roughness": 0.5, "metalness": 0.5}
    );
    body = new(Mesh, new(BoxGeometry, 0.09, 0.13, 0.5), mat);
    body.position.set(0.0, 0.0, -0.25);
    g.add(body);
    barrel = new(Mesh, new(BoxGeometry, 0.05, 0.05, 0.45), mat);
    barrel.position.set(0.0, 0.04, -0.6);
    g.add(barrel);
    grip = new(Mesh, new(BoxGeometry, 0.07, 0.16, 0.1), mat);
    grip.position.set(0.0, -0.12, -0.08);
    grip.rotation.x = 0.3;
    g.add(grip);
    g.position.set(0.22, -0.2, -0.3);
    return g;
}

"""A bot: capsule body + sphere head + a small facing nub, all shadow-casting."""
def _make_bot(r: any) -> any {
    g = new(Group);
    bodymat = new(
        MeshStandardMaterial, {"color": 0xd84545, "roughness": 0.7, "metalness": 0.05}
    );
    body = new(Mesh, new(CapsuleGeometry, 0.35, 1.0, 6, 12), bodymat);
    body.position.set(0.0, 0.9, 0.0);
    body.castShadow = True;
    g.add(body);
    headmat = new(MeshStandardMaterial, {"color": 0xf0a060, "roughness": 0.6});
    head = new(Mesh, new(SphereGeometry, 0.28, 18, 14), headmat);
    head.position.set(0.0, 1.78, 0.0);
    head.castShadow = True;
    g.add(head);
    nub = new(Mesh, new(BoxGeometry, 0.1, 0.1, 0.45), bodymat);
    nub.position.set(0.18, 1.1, -0.3);
    g.add(nub);
    r.scene.add(g);
    return g;
}

"""Build the scene, camera, renderer, lights, ground and gun on `canvas`.
`fov` is the vertical field of view in degrees (from the settings screen)."""
def:pub make_renderer(canvas: any, fov: any) -> any {
    r = R3D();
    r.scene = new(Scene);
    r.scene.background = new(Color, 0x9fbcd6);
    r.scene.fog = new(Fog, 0x9fbcd6, 35.0, 110.0);
    r.cam = new(PerspectiveCamera, fov, 960.0 / 600.0, 0.05, 400.0);
    r.renderer = new(WebGLRenderer, {"canvas": canvas, "antialias": True});
    r.renderer.setSize(960, 600, False);
    r.renderer.shadowMap.enabled = True;
    r.renderer.shadowMap.type = PCFSoftShadowMap;
    r.renderer.toneMapping = ACESFilmicToneMapping;
    r.renderer.outputColorSpace = SRGBColorSpace;
    # ── lighting ──
    sun = new(DirectionalLight, 0xfff2e0, 2.2);
    sun.position.set(22.0, 42.0, 16.0);
    sun.castShadow = True;
    sun.shadow.mapSize.width = 2048;
    sun.shadow.mapSize.height = 2048;
    sun.shadow.camera.near = 1.0;
    sun.shadow.camera.far = 140.0;
    sun.shadow.camera.left = -40.0;
    sun.shadow.camera.right = 40.0;
    sun.shadow.camera.top = 40.0;
    sun.shadow.camera.bottom = -40.0;
    r.scene.add(sun);
    r.scene.add(new(HemisphereLight, 0xbfd4ff, 0x20281c, 0.9));
    r.scene.add(new(AmbientLight, 0xffffff, 0.2));
    # ── ground ──
    gmat = new(
        MeshStandardMaterial,
        {"color": 0x3a7d34, "roughness": 0.97, "metalness": 0.0, "side": DoubleSide}
    );
    ground = new(Mesh, new(PlaneGeometry, 300.0, 300.0), gmat);
    ground.rotation.x = -1.5707963267948966;
    ground.receiveShadow = True;
    r.scene.add(ground);
    # ── gun viewmodel (parented to the camera; camera added to the scene so its
    #    children render) + muzzle flash ──
    r.gun = _make_gun();
    r.flash = new(
        Mesh,
        new(PlaneGeometry, 0.32, 0.32),
        new(MeshBasicMaterial, {"color": 0xfff1a0, "transparent": True, "opacity": 0.0})
    );
    r.flash.position.set(0.0, 0.04, -0.85);
    r.gun.add(r.flash);
    r.cam.add(r.gun);
    r.scene.add(r.cam);
    return r;
}

"""Build the static map geometry once from the collider getters (idempotent)."""
def:pub build_static(r: any, exports: any) {
    if r.static_built {
        return;
    }
    n: int = int(f"{exports.get_collider_count()}");
    mat = new(
        MeshStandardMaterial, {"color": 0x55617f, "roughness": 0.85, "metalness": 0.1}
    );
    i: int = 0;
    while i < n {
        bi = BigInt(i);
        minx: float = float(f"{exports.get_collider_minx(bi)}");
        miny: float = float(f"{exports.get_collider_miny(bi)}");
        minz: float = float(f"{exports.get_collider_minz(bi)}");
        maxx: float = float(f"{exports.get_collider_maxx(bi)}");
        maxy: float = float(f"{exports.get_collider_maxy(bi)}");
        maxz: float = float(f"{exports.get_collider_maxz(bi)}");
        sx: float = maxx - minx;
        sy: float = maxy - miny;
        sz: float = maxz - minz;
        box = new(Mesh, new(BoxGeometry, sx, sy, sz), mat);
        box.position.set((minx + maxx) / 2.0, (miny + maxy) / 2.0, (minz + maxz) / 2.0);
        box.castShadow = True;
        box.receiveShadow = True;
        r.scene.add(box);
        i = i + 1;
    }
    r.static_built = True;
}

"""Position/scale the tracer-beam pool from the tracer getters."""
def _update_tracers(r: any, exports: any) {
    n: int = int(f"{exports.get_tracer_count()}");
    i: int = 0;
    while i < n {
        bi = BigInt(i);
        if i >= len(r.tracers) {
            tm = new(MeshBasicMaterial, {"color": 0xffe070});
            t = new(Mesh, new(BoxGeometry, 0.025, 0.025, 1.0), tm);
            r.scene.add(t);
            r.tracers.append(t);
        }
        t = r.tracers[i];
        x0: float = float(f"{exports.get_tracer_x0(bi)}");
        y0: float = float(f"{exports.get_tracer_y0(bi)}");
        z0: float = float(f"{exports.get_tracer_z0(bi)}");
        x1: float = float(f"{exports.get_tracer_x1(bi)}");
        y1: float = float(f"{exports.get_tracer_y1(bi)}");
        z1: float = float(f"{exports.get_tracer_z1(bi)}");
        dx: float = x1 - x0;
        dy: float = y1 - y0;
        dz: float = z1 - z0;
        ln: float = Math.sqrt(dx * dx + dy * dy + dz * dz);
        t.position.set((x0 + x1) / 2.0, (y0 + y1) / 2.0, (z0 + z1) / 2.0);
        t.scale.set(1.0, 1.0, ln if ln > 0.001 else 0.001);
        t.lookAt(x1, y1, z1);
        t.visible = True;
        i = i + 1;
    }
    j: int = n;
    while j < len(r.tracers) {
        r.tracers[j].visible = False;
        j = j + 1;
    }
}

"""Read sim state via the exports and render one frame."""
def:pub draw(r: any, exports: any) {
    build_static(r, exports);
    # ── camera ──
    cx: float = float(f"{exports.get_cam_x()}");
    cy: float = float(f"{exports.get_cam_y()}");
    cz: float = float(f"{exports.get_cam_z()}");
    yaw: float = float(f"{exports.get_cam_yaw()}");
    pitch: float = float(f"{exports.get_cam_pitch()}");
    yr: float = yaw * 0.017453292519943295;
    pr: float = pitch * 0.017453292519943295;
    cp: float = Math.cos(pr);
    fx: float = -Math.sin(yr) * cp;
    fy: float = Math.sin(pr);
    fz: float = -Math.cos(yr) * cp;
    r.cam.position.set(cx, cy, cz);
    r.cam.lookAt(cx + fx, cy + fy, cz + fz);
    # ── bots ──
    n: int = int(f"{exports.get_bot_count()}");
    i: int = 0;
    while i < n {
        bi = BigInt(i);
        if i >= len(r.bots) {
            r.bots.append(_make_bot(r));
        }
        b = r.bots[i];
        alive: int = int(f"{exports.get_bot_alive(bi)}");
        if alive == 1 {
            bx: float = float(f"{exports.get_bot_x(bi)}");
            by: float = float(f"{exports.get_bot_y(bi)}");
            bz: float = float(f"{exports.get_bot_z(bi)}");
            byaw: float = float(f"{exports.get_bot_yaw(bi)}");
            b.position.set(bx, by, bz);
            b.rotation.y = -byaw * 0.017453292519943295;
            b.visible = True;
        } else {
            b.visible = False;
        }
        i = i + 1;
    }
    j: int = n;
    while j < len(r.bots) {
        r.bots[j].visible = False;
        j = j + 1;
    }
    # ── muzzle flash + recoil ──
    mz: int = int(f"{exports.get_muzzle()}");
    if mz == 1 {
        r.flash_op = 0.95;
        r.recoil = 0.06;
    } else {
        r.flash_op = r.flash_op * 0.55;
    }
    r.flash.material.opacity = r.flash_op;
    r.gun.position.z = -0.3 + r.recoil;
    r.recoil = r.recoil * 0.8;
    # ── tracers + present ──
    _update_tracers(r, exports);
    r.renderer.render(r.scene, r.cam);
}

"""Free GPU resources (called on stop)."""
def:pub dispose_renderer(r: any) {
    if r and r.renderer {
        r.renderer.dispose();
    }
}
