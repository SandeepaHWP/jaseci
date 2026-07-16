"""WebGL shim for the rlgl/input externs of a wasm-compiled na game.

A reusable client library (the moral equivalent of raylib for the browser):
it emulates the scalar rlgl immediate-mode API + input on WebGL/DOM, supplies
the libc/__multi3 the Jac native runtime needs, instantiates /static/<name>.wasm,
and drives init()/frame() per requestAnimationFrame. Lives in a .cl.jac so it is
compiled (not strictly type-checked) like other client deps."""

obj Shim {
    has gl: any = None,
        canvas: any = None,
        exports: any = None,
        mem: any = None,
        heap: any = 0,
        proj: list = [],
        mv: list = [],
        pstack: list = [],
        mvstack: list = [],
        mode: int = 0x1700,
        verts: list = [],
        color: list = [1.0, 1.0, 1.0, 1.0],
        bmode: int = 4,
        vbo: any = None,
        aPos: int = 0,
        aCol: int = 0,
        uMVP: any = None,
        keys: dict = {},
        pressed: dict = {},
        mpressed: dict = {},
        mdown: dict = {},
        mouseX: float = 0.0,
        mouseY: float = 0.0,
        locked: bool = False,
        dt: float = 0.016,
        time: float = 0.0,
        t0: float = 0.0,
        draws: int = 0,
        on_tick: any = None,
        # --- lifecycle (Phase 2A: start/stop so screens can mount/unmount) ---
        alive: bool = False,
        raf: any = None,
        on_exit: any = None,
        on_render: any = None,
        h_keydown: any = None,
        h_keyup: any = None,
        h_mousedown: any = None,
        h_mouseup: any = None,
        h_mousemove: any = None,
        h_plock: any = None;
}

def _m_ident -> list {
    return [
        1.0,
        0.0,
        0.0,
        0.0,
        0.0,
        1.0,
        0.0,
        0.0,
        0.0,
        0.0,
        1.0,
        0.0,
        0.0,
        0.0,
        0.0,
        1.0
    ];
}

def _m_mul(a: list, b: list) -> list {
    c = [
        0.0,
        0.0,
        0.0,
        0.0,
        0.0,
        0.0,
        0.0,
        0.0,
        0.0,
        0.0,
        0.0,
        0.0,
        0.0,
        0.0,
        0.0,
        0.0
    ];
    col = 0;
    while col < 4 {
        row = 0;
        while row < 4 {
            s = 0.0;
            k = 0;
            while k < 4 {
                s = s + a[row + 4 * k] * b[k + 4 * col];
                k = k + 1;
            }
            c[row + 4 * col] = s;
            row = row + 1;
        }
        col = col + 1;
    }
    return c;
}

def _m_translate(x: float, y: float, z: float) -> list {
    m = _m_ident();
    m[12] = x;
    m[13] = y;
    m[14] = z;
    return m;
}

def _m_rotate(ang: float, x: float, y: float, z: float) -> list {
    a = ang * 3.141592653589793 / 180.0;
    c = Math.cos(a);
    s = Math.sin(a);
    ln = Math.hypot(x, y, z);
    if ln == 0.0 {
        ln = 1.0;
    }
    x = x / ln;
    y = y / ln;
    z = z / ln;
    t = 1.0 - c;
    return [
        x * x * t + c,
        y * x * t + z * s,
        x * z * t - y * s,
        0.0,
        x * y * t - z * s,
        y * y * t + c,
        y * z * t + x * s,
        0.0,
        x * z * t + y * s,
        y * z * t - x * s,
        z * z * t + c,
        0.0,
        0.0,
        0.0,
        0.0,
        1.0
    ];
}

def _m_frustum(l: float, r: float, b: float, t: float, n: float, f: float) -> list {
    return [
        2.0 * n / (r - l),
        0.0,
        0.0,
        0.0,
        0.0,
        2.0 * n / (t - b),
        0.0,
        0.0,
        (r + l) / (r - l),
        (t + b) / (t - b),
        -(f + n) / (f - n),
        -1.0,
        0.0,
        0.0,
        -2.0 * f * n / (f - n),
        0.0
    ];
}

def _m_ortho(l: float, r: float, b: float, t: float, n: float, f: float) -> list {
    return [
        2.0 / (r - l),
        0.0,
        0.0,
        0.0,
        0.0,
        2.0 / (t - b),
        0.0,
        0.0,
        0.0,
        0.0,
        -2.0 / (f - n),
        0.0,
        -(r + l) / (r - l),
        -(t + b) / (t - b),
        -(f + n) / (f - n),
        1.0
    ];
}

def _cur(sh: any) -> list {
    return sh.proj if sh.mode == 0x1701 else sh.mv;
}

def _setcur(sh: any, m: list) {
    if sh.mode == 0x1701 {
        sh.proj = m;
    } else {
        sh.mv = m;
    }
}

def _read_cstr(sh: any, p: int) -> str {
    u8 = new(Uint8Array, sh.mem.buffer);
    s = "";
    i = p;
    while u8[i] != 0 {
        s = s + String.fromCharCode(u8[i]);
        i = i + 1;
    }
    return s;
}

def _flush(sh: any) -> None {
    if len(sh.verts) == 0 {
        return;
    }
    gl = sh.gl;
    mvp = _m_mul(sh.proj, sh.mv);
    gl.bindBuffer(gl.ARRAY_BUFFER, sh.vbo);
    gl.bufferData(gl.ARRAY_BUFFER, new(Float32Array, sh.verts), gl.STREAM_DRAW);
    gl.enableVertexAttribArray(sh.aPos);
    gl.vertexAttribPointer(sh.aPos, 3, gl.FLOAT, False, 28, 0);
    gl.enableVertexAttribArray(sh.aCol);
    gl.vertexAttribPointer(sh.aCol, 4, gl.FLOAT, False, 28, 12);
    gl.uniformMatrix4fv(sh.uMVP, False, new(Float32Array, mvp));
    prim = gl.LINES if sh.bmode == 1 else gl.TRIANGLES;
    gl.drawArrays(prim, 0, len(sh.verts) // 7);
    sh.draws = sh.draws + 1;
    sh.verts = [];
}

def _build_env(sh: any) -> dict {
    return {
        "InitWindow": lambda (w: int, h: int, t: int) { document.title = _read_cstr(
            sh, t
        ); },
        "WindowShouldClose": lambda { return 0; },
        "CloseWindow": lambda { },
        "SetTargetFPS": lambda (f: int) { },
        "BeginDrawing": lambda { sh.gl.viewport(0, 0, 960, 600); },
        "EndDrawing": lambda { },
        "EndMode3D": lambda { _flush(sh); },
        "GetFrameTime": lambda { return sh.dt; },
        "GetTime": lambda { return sh.time; },
        "DrawFPS": lambda (x: int, y: int) { },
        "IsKeyDown": lambda (k: int) { return sh.keys.get(k, 0); },
        "IsKeyPressed": lambda (k: int) { return sh.pressed.get(k, 0); },
        "GetMouseX": lambda { return sh.mouseX; },
        "GetMouseY": lambda { return sh.mouseY; },
        "IsMouseButtonPressed": lambda (b: int) { return sh.mpressed.get(b, 0); },
        "IsMouseButtonDown": lambda (b: int) { return sh.mdown.get(b, 0); },
        "DisableCursor": lambda { sh.canvas.requestPointerLock(); },
        "EnableCursor": lambda { document.exitPointerLock(); },
        "rlClearColor": lambda (r: int, g: int, b: int, a: int) { sh.gl.clearColor(
            float(r) / 255.0, float(g) / 255.0, float(b) / 255.0, 1.0
        ); },
        "rlClearScreenBuffers": lambda { sh.gl.clear(16384 | 256); },
        "rlEnableDepthTest": lambda { sh.gl.enable(sh.gl.DEPTH_TEST); },
        "rlDisableDepthTest": lambda { sh.gl.disable(sh.gl.DEPTH_TEST); },
        "rlMatrixMode": lambda (m: int) { sh.mode = m; },
        "rlLoadIdentity": lambda { _setcur(sh, _m_ident()); },
        "rlPushMatrix": lambda { if sh.mode == 0x1701 {
            sh.pstack.append(sh.proj);
        } else {
            sh.mvstack.append(sh.mv);
        } },
        "rlPopMatrix": lambda { if sh.mode == 0x1701 {
            sh.proj = sh.pstack.pop();
        } else {
            sh.mv = sh.mvstack.pop();
        } },
        "rlTranslatef": lambda (x: float, y: float, z: float) { _setcur(
            sh, _m_mul(_cur(sh), _m_translate(x, y, z))
        ); },
        "rlRotatef": lambda (a: float, x: float, y: float, z: float) { _setcur(
            sh, _m_mul(_cur(sh), _m_rotate(a, x, y, z))
        ); },
        "rlFrustum": lambda (
            l: float, r: float, b: float, t: float, n: float, f: float
        ) { _setcur(sh, _m_mul(_cur(sh), _m_frustum(l, r, b, t, n, f))); },
        "rlOrtho": lambda (
            l: float, r: float, b: float, t: float, n: float, f: float
        ) { _setcur(sh, _m_mul(_cur(sh), _m_ortho(l, r, b, t, n, f))); },
        "rlBegin": lambda (m: int) {
            sh.bmode = m;
            sh.verts = [];
        },
        "rlEnd": lambda { _flush(sh); },
        "rlVertex3f": lambda (x: float, y: float, z: float) {
            sh.verts.append(x);
            sh.verts.append(y);
            sh.verts.append(z);
            sh.verts.append(sh.color[0]);
            sh.verts.append(sh.color[1]);
            sh.verts.append(sh.color[2]);
            sh.verts.append(sh.color[3]);
        },
        "rlColor4ub": lambda (r: int, g: int, b: int, a: int) { sh.color = [
            float(r) / 255.0,
            float(g) / 255.0,
            float(b) / 255.0,
            1.0
        ]; },
        "rlSetLineWidth": lambda (w: float) { sh.gl.lineWidth(w); },
        "FileExists": lambda (p: int) { return 0; },
        "LoadFileText": lambda (p: int) { return 0; },
        "TextToInteger": lambda (p: int) { return 0; },
        "SaveFileText": lambda (p: int, t: int) { return 0; },
        "malloc": lambda (n: int) {
            # n arrives as an i64 (BigInt at the JS boundary); coerce so the
            # bump-allocator arithmetic stays Number-only (see web shim).
            sz = Number(n);
            p = sh.heap;
            sh.heap = (sh.heap + sz + 7) & ~7;
            return p;
        },
        "calloc": lambda (c: int, s: int) {
            n = Number(c) * Number(s);
            p = sh.heap;
            sh.heap = (sh.heap + n + 7) & ~7;
            new(Uint8Array, sh.mem.buffer).fill(0, p, p + n);
            return p;
        },
        "realloc": lambda (p: int, n: int) {
            # Bump allocator keeps no block sizes, so grow by fresh-alloc +
            # copy; reading past the old block is harmless (caller reads only
            # its own prefix). Used by upstream's __rc_push_root to grow roots.
            sz = Number(n);
            if sz == 0 {
                return 0;
            }
            np = sh.heap;
            sh.heap = (sh.heap + sz + 7) & ~7;
            if p != 0 {
                # copyWithin clamps its indices, so a short tail is a no-op.
                new(Uint8Array, sh.mem.buffer).copyWithin(np, p, p + sz);
            }
            return np;
        },
        "free": lambda (p: int) { },
        "malloc_usable_size": lambda (p: int) { return 0; },
        # Direct call always returns 0; the unwind path goes through longjmp,
        # which raises rather than jumping back in (see longjmp below).
        "setjmp": lambda (env_ptr: int) { return 0; },
        "memcpy": lambda (d: int, s: int, n: int) {
            sz = Number(n);
            new(Uint8Array, sh.mem.buffer).copyWithin(d, s, s + sz);
            return d;
        },
        "memcmp": lambda (a: int, b: int, n: int) {
            u8 = new(Uint8Array, sh.mem.buffer);
            sz = Number(n);
            i = 0;
            while i < sz {
                df = u8[a + i] - u8[b + i];
                if df != 0 {
                    return df;
                }
                i = i + 1;
            }
            return 0;
        },
        "puts": lambda (p: int) { return 0; },
        "printf": lambda (a: int) { return 0; },
        "snprintf": lambda (a: int, b: int, c: int, d: int) { return 0; },
        "getenv": lambda (p: int) { return 0; },
        "fflush": lambda (p: int) { return 0; },
        "abort": lambda { },
        "longjmp": lambda (env_ptr: int, val: int) {
        # Upstream's wasm codegen (na_ir_gen_pass exceptions) lowers
        # exception unwinding through setjmp/longjmp, so the module now
        # imports env.longjmp. A true non-local jump back into wasm isn't
        # possible from JS, but the sim takes no exception path in normal
        # play -- this is emitted-but-unreached scaffolding that only needs
        # to be callable to link. Throw loudly if it ever actually fires.
        raise Error(f"wasm longjmp(val={val}): unhandled sim exception"); },
        "__multi3": lambda (res: int, al: int, ah: int, bl: int, bh: int) {
            k = (BigInt(1) << BigInt(64)) - BigInt(1);
            a = (BigInt.asUintN(64, ah) << BigInt(64)) | BigInt.asUintN(64, al);
            b = (BigInt.asUintN(64, bh) << BigInt(64)) | BigInt.asUintN(64, bl);
            p = BigInt.asUintN(128, a * b);
            dv = new(DataView, sh.mem.buffer);
            dv.setBigUint64(res, p & k, True);
            dv.setBigUint64(res + 8, (p >> BigInt(64)) & k, True);
        }
    };
}

def _init_gl(sh: any) {
    gl = sh.gl;
    vs = "attribute vec3 aPos; attribute vec4 aCol; uniform mat4 uMVP; varying vec4 vCol; void main(){ gl_Position = uMVP * vec4(aPos,1.0); vCol = aCol; }";
    fs = "precision mediump float; varying vec4 vCol; void main(){ gl_FragColor = vCol; }";
    vsh = gl.createShader(gl.VERTEX_SHADER);
    gl.shaderSource(vsh, vs);
    gl.compileShader(vsh);
    fsh = gl.createShader(gl.FRAGMENT_SHADER);
    gl.shaderSource(fsh, fs);
    gl.compileShader(fsh);
    prog = gl.createProgram();
    gl.attachShader(prog, vsh);
    gl.attachShader(prog, fsh);
    gl.linkProgram(prog);
    gl.useProgram(prog);
    sh.aPos = gl.getAttribLocation(prog, "aPos");
    sh.aCol = gl.getAttribLocation(prog, "aCol");
    sh.uMVP = gl.getUniformLocation(prog, "uMVP");
    sh.vbo = gl.createBuffer();
    gl.clearColor(0.0, 0.0, 0.0, 1.0);
    gl.disable(gl.CULL_FACE);
}

def _keymap(code: str) -> int {
    m = {
        "KeyW": 87,
        "KeyA": 65,
        "KeyS": 83,
        "KeyD": 68,
        "KeyR": 82,
        "Space": 32,
        "Tab": 258,
        "ArrowRight": 262,
        "ArrowLeft": 263,
        "ArrowDown": 264,
        "ArrowUp": 265
    };
    return m.get(code, 0);
}

# Handlers are stored on the shim so _remove_input can detach the exact same
# references on stop (anonymous listeners can't be removed -> would leak across
# rounds). Esc fires the on_exit hook (back to menu).
def _install_input(sh: any) {
    sh.h_keydown = lambda (e: any) {
        if e.code == "Escape" {
            if sh.on_exit is not None {
                sh.on_exit();
            }
            return;
        }
        kc = _keymap(e.code);
        if kc != 0 {
            e.preventDefault();
            # Only flag a fresh press when the key wasn't already held, so OS
            # key-repeat doesn't re-trigger IsKeyPressed taps (e.g. Tab, R).
            if not sh.keys.get(kc, 0) {
                sh.pressed[kc] = 1;
            }
            sh.keys[kc] = 1;
        }
    };
    window.addEventListener("keydown", sh.h_keydown);
    sh.h_keyup = lambda (e: any) {
        kc = _keymap(e.code);
        if kc != 0 {
            sh.keys[kc] = 0;
        }
    };
    window.addEventListener("keyup", sh.h_keyup);
    sh.h_mousedown = lambda (e: any) {
        sh.mpressed[0] = 1;
        sh.mdown[0] = 1;
    };
    sh.canvas.addEventListener("mousedown", sh.h_mousedown);
    sh.h_mouseup = lambda (e: any) { sh.mdown[0] = 0; };
    document.addEventListener("mouseup", sh.h_mouseup);
    sh.h_mousemove = lambda (e: any) { if sh.locked {
        sh.mouseX = sh.mouseX + e.movementX;
        sh.mouseY = sh.mouseY + e.movementY;
    } else {
        sh.mouseX = e.offsetX;
        sh.mouseY = e.offsetY;
    } };
    document.addEventListener("mousemove", sh.h_mousemove);
    sh.h_plock = lambda (e: any) { sh.locked = document.pointerLockElement == sh.canvas; };
    document.addEventListener("pointerlockchange", sh.h_plock);
}

"""Detach every listener installed by _install_input (clean teardown)."""
def _remove_input(sh: any) {
    if sh.h_keydown is not None {
        window.removeEventListener("keydown", sh.h_keydown);
    }
    if sh.h_keyup is not None {
        window.removeEventListener("keyup", sh.h_keyup);
    }
    if sh.h_mousedown is not None {
        sh.canvas.removeEventListener("mousedown", sh.h_mousedown);
    }
    if sh.h_mouseup is not None {
        document.removeEventListener("mouseup", sh.h_mouseup);
    }
    if sh.h_mousemove is not None {
        document.removeEventListener("mousemove", sh.h_mousemove);
    }
    if sh.h_plock is not None {
        document.removeEventListener("pointerlockchange", sh.h_plock);
    }
}

def _frame_tick(sh: any, ts: float) {
    # Bail if the game was stopped (screen unmounted) mid-flight.
    if not sh.alive {
        return;
    }
    if sh.t0 == 0.0 {
        sh.t0 = ts;
    }
    now = (ts - sh.t0) / 1000.0;
    sh.dt = (now - sh.time) if sh.time > 0.0 else 0.016;
    if sh.dt > 0.05 {
        sh.dt = 0.05;
    }
    sh.time = now;
    closed = sh.exports.frame();
    # Pull-based render: the sim stepped above; the renderer reads its state.
    if sh.on_render is not None {
        sh.on_render(sh.exports);
    }
    # Optional per-frame hook so a page can drive a HUD (score/fps) without the
    # shim needing to know anything game-specific. on_tick may stop the game
    # (e.g. win/lose), so re-check sh.alive before scheduling the next frame.
    if sh.on_tick is not None {
        fps = Math.round(1.0 / sh.dt) if sh.dt > 0.0 else 0;
        sh.on_tick(sh.exports, fps);
    }
    sh.pressed = {};
    sh.mpressed = {};
    if sh.alive and not closed {
        sh.raf = requestAnimationFrame(lambda (t2: float) { _frame_tick(sh, t2); });
    }
}

"""Start a fresh game on `canvas`. on_tick(exports, fps) drives the HUD and may
stop the game; on_exit() is called when the player presses Esc. opts carries
per-round settings (currently {"map_id": int}). Returns nothing -- the live shim
is parked on window.__fps_shim so on_tick / on_exit can stop it."""
async def:pub run_game(
    canvas: any,
    on_tick: any = None,
    on_exit: any = None,
    on_render: any = None,
    opts: any = None
) {
    # Re-entrancy guard, resettable by stop_game (unlike the old permanent flag).
    # Covers React StrictMode's dev double-mount: the second start is a no-op.
    guard: any = window;
    if guard.__fps_active {
        return;
    }
    guard.__fps_active = True;
    sh = Shim();
    sh.alive = True;
    sh.on_tick = on_tick;
    sh.on_exit = on_exit;
    sh.on_render = on_render;
    sh.canvas = canvas;
    # Rendering moved out of the sim (Phase 4.5): the shim no longer creates a GL
    # context -- the Three.js renderer (render3d.cl.jac) owns the canvas now. The
    # leftover rlgl env entries stay but are never imported by the (pure-state) wasm.
    _install_input(sh);
    env = {"env": _build_env(sh)};
    # Cache-bust: /static/main.wasm has no content hash in its URL, so the
    # browser would otherwise serve a stale wasm across rebuilds. Re-instantiating
    # per round also gives a fresh wasm heap each game (resets bump allocator).
    wasm_url = f"/static/main.wasm?t={Date.now()}";
    res: any = await WebAssembly.instantiateStreaming(
        fetch(wasm_url, {"cache": "no-store"}), env
    );
    inst: any = res.instance;
    sh.exports = inst.exports;
    sh.mem = inst.exports.memory;
    sh.heap = inst.exports.__heap_base.value;
    # If anything here throws, reset the guard + detach listeners so a failed
    # start can't wedge the game (otherwise __fps_active stays True and every
    # later Play is a silent no-op until a page refresh).
    try {
        inst.exports.__jac_glob_init();
        # Apply settings BEFORE init so new_round sees the bot count. Jac `int`
        # params are wasm i64, which cross the JS boundary as BigInt.
        if opts is not None {
            inst.exports.set_sensitivity(BigInt(opts.get("sens", 12)));
            inst.exports.set_bots(BigInt(opts.get("bots", 5)));
        }
        inst.exports.init();
        # Apply the chosen map (0 = open, 1 = cover) after init.
        if opts is not None and opts.get("map_id", 0) > 0 {
            inst.exports.set_map(BigInt(opts.get("map_id", 0)));
        }
    } except Exception as exc {
        guard.__fps_active = False;
        _remove_input(sh);
        raise exc;
    }
    # A late stop_game (unmount during the await) must win the race.
    if not sh.alive {
        guard.__fps_active = False;
        return;
    }
    guard.__fps_shim = sh;
    sh.raf = requestAnimationFrame(lambda (ts: float) { _frame_tick(sh, ts); });
}

"""Stop the running game: halt the loop, detach listeners, release the pointer.
Idempotent. Leaves the wasm instance for GC (a fresh one is built next round)."""
def:pub stop_game(sh: any) {
    if sh is None or not sh.alive {
        return;
    }
    sh.alive = False;
    if sh.raf is not None {
        cancelAnimationFrame(sh.raf);
    }
    _remove_input(sh);
    if document.pointerLockElement {
        document.exitPointerLock();
    }
    win: any = window;
    win.__fps_active = False;
    win.__fps_shim = None;
}
