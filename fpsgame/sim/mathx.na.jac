"""Deterministic math helpers for the FPS sim.

No libm dependency: trig is a range-reduced Taylor series, sqrt is Newton
iteration, RNG is a self-contained LCG. Pure (apart from the private LCG seed),
so the same results hold for the wasm (client) and native (server) builds -- the
determinism Phase 5 relies on.

The LCG seed `_rng` is a module-private global shared by the whole sim. That is
fine for single-player; Phase 5 (multiple authoritative worlds) should move the
seed onto the World object so each match is independently deterministic.
"""

"""cos via range-reduced Taylor series (deterministic, no libm)."""
def:pub jcos(a: float) -> float {
    twopi = 6.283185307179586;
    pi = 3.141592653589793;
    while a > pi {
        a -= twopi;
    }
    while a < -pi {
        a += twopi;
    }
    x2 = a * a;
    x4 = x2 * x2;
    x6 = x4 * x2;
    x8 = x4 * x4;
    x10 = x8 * x2;
    x12 = x8 * x4;
    return 1.0 - x2 / 2.0 + x4 / 24.0 - x6 / 720.0 + x8 / 40320.0 - x10 / 3628800.0 + x12 / 479001600.0;
}

"""sin(a) = cos(a - pi/2)."""
def:pub jsin(a: float) -> float {
    return jcos(a - 1.5707963267948796);
}

"""sqrt via Newton iteration."""
def:pub fsqrt(v: float) -> float {
    if v <= 0.0 {
        return 0.0;
    }
    g = v;
    i = 0;
    while i < 20 {
        g = 0.5 * (g + v / g);
        i += 1;
    }
    return g;
}

glob _rng: int = 987654321;

"""Uniform pseudo-random float in [0, 1) via a 31-bit LCG (deterministic)."""
def:pub rand01 -> float {
    global _rng;
    _rng = (_rng * 1103515245 + 12345) % 2147483648;
    return float(_rng) / 2147483648.0;
}

"""Random float in [lo, hi)."""
def:pub rand_range(lo: float, hi: float) -> float {
    return lo + rand01() * (hi - lo);
}

"""atan(t) for 0<=t<=1 via a short polynomial approximation."""
def:pub atan_unit(t: float) -> float {
    t3 = t * t * t;
    t5 = t3 * t * t;
    t7 = t5 * t * t;
    return t - t3 / 3.0 + t5 / 5.0 - t7 / 7.0;
}

"""atan2 in degrees (coarse, deterministic) for facing direction."""
def:pub atan2_deg(y: float, x: float) -> float {
    ax = x if x >= 0.0 else -x;
    ay = y if y >= 0.0 else -y;
    ang = 0.0;
    if ax < 0.000001 and ay < 0.000001 {
        return 0.0;
    }
    if ax >= ay {
        t = ay / ax;
        ang = atan_unit(t);
    } else {
        t = ax / ay;
        ang = 1.5707963267948966 - atan_unit(t);
    }
    if x < 0.0 {
        ang = 3.141592653589793 - ang;
    }
    if y < 0.0 {
        ang = -ang;
    }
    return ang / 0.017453292519943295;
}
