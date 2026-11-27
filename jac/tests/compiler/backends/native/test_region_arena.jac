"""Native region arena tests (#7491 R1).

An `in <handle> {}` open bump-allocates its object instantiations into the
handle's arena (sentinel-stamped headers, inert to every RC fast path) and
reclaims wholesale at the handle's drop point: dtor-log walk (LIFO), then
one bulk chunk free. These tests pin the allocation routing at the IR level
and the drop-hook/teardown behavior through the JIT.
"""

import ctypes;
import os;
import from tests.support { TESTS_DIR, get_func, names_function, run_cases }
import from jaclang.compiler.driver.program { JacProgram }
import from jaclang.compiler.driver.compile_options { CompileOptions }
import jaclang.compiler.frontend.unitree as uni;
import from jaclang.compiler.backends.native.llvm.binding { ExecutionEngine }

glob FIXTURES = os.path.join(
         TESTS_DIR, "compiler", "backends", "native", "fixtures"
     );

"""Compile a .jac fixture and return the JIT engine."""
def compile_native(
    fixture: str, gc_mode: str | None = None, opt_level: int | None = None
) -> tuple[ExecutionEngine, uni.Module] {
    prog = JacProgram();
    opts = (
        CompileOptions(na_gc_mode=gc_mode, opt_level=opt_level)
            if (gc_mode is not None or opt_level is not None)
            else None
    );
    ir = prog.compile(file_path=str(os.path.join(FIXTURES, fixture)), options=opts);
    errors = [str(e) for e in prog.errors_had] if prog.errors_had else [];
    assert not prog.errors_had , f"Compilation errors in {fixture}: {errors}";
    eng = ir.gen.native_engine;
    assert isinstance(eng, ExecutionEngine) , f"No native engine produced for {fixture}";
    return (eng, ir);
}

"""Count call sites of `name` in either printer's spelling (quoted or bare)."""
def calls_to(body: str, name: str) -> int {
    return (
        body.count('@"' + name + '"(')
        + body.count("@" + name + "(")
        + body.count("." + name + '"(')
    );
}

"""Slice one function's textual IR out of the module dump."""
def fn_ir(ir: uni.Module, name: str) -> str {
    out: list[str] = [];
    inside = False;
    for ln in str(ir.gen.llvm_ir).split("\n") {
        if not inside and ln.startswith("define") and names_function(ln, name) {
            inside = True;
        }
        if inside {
            out.append(ln);
            if ln == "}" {
                break;
            }
        }
    }
    assert out , f"No IR found for function '{name}'";
    return "\n".join(out);
}

test "arena: every droppable construction consults the current region" {
    # Stack-eligible objects (like region_arena's Box) may still take the
    # stack path; droppable types carry a region-alloc arm beside the heap
    # arm, selected by the thread's current region at run time.
    (eng, ir) = compile_native("region_dtor.jac", opt_level=0);
    body = fn_ir(ir, "dtor_order");
    n_cur = calls_to(body, "__jac_region_current");
    assert n_cur == 3 , f"expected 3 current-region reads in dtor_order, found {n_cur}";
    n_arena = calls_to(body, "__jac_region_alloc");
    assert n_arena == 3 , f"expected 3 region-alloc arms in dtor_order, found {n_arena}";
    n_drop = calls_to(body, "__jac_region_drop");
    assert n_drop >= 1 , f"expected a region drop at the close, found {n_drop}";
}

test "dynamic extent: a helper called under an open allocates in the region, and related cases" {
    def check_dynamic_extent_a_helper_called_under_an_open_all {
        (eng, ir) = compile_native("region_callee_extent.jac");
        scenario = get_func(eng, "scenario", ctypes.c_int64);
        result = scenario();
        assert result == 3 , f"scenario() == {result}, expected 3";
        read_log = get_func(eng, "read_log", ctypes.c_int64);
        log = read_log();
        # both helper results live in r: hooks fire LIFO at r's drop, not at
        # build()'s frame exit
        assert log == 21 , f"helper allocations must drop with the handle: {log} != 21";
    }

    def check_arena_dynamic_extent_made_in_a_helper_grown_remo {
        (eng, ir) = compile_native("region_extent.jac");
        scenario = get_func(eng, "scenario", ctypes.c_int64);
        result = scenario();
        # nothing drops while the handle travels through make/grow/grow
        assert result == 0 , f"scenario() == {result}, expected 0 before drop";
        read_log = get_func(eng, "read_log", ctypes.c_int64);
        log = read_log();
        # one arena, all three dtor-log entries, LIFO across the whole extent
        assert log == 321 , f"remote drop must run the full dtor log: {log} != 321";
    }

    def check_r3_region_resident_topology_traverses_live_and_r {
        (eng, ir) = compile_native("region_graph.jac");
        scenario = get_func(eng, "scenario", ctypes.c_int64);
        result = scenario();
        assert result == 3 , f"scenario() == {result}, expected traversal sum 3";
        read_log = get_func(eng, "read_log", ctypes.c_int64);
        log = read_log();
        assert log == 2 , f"handle drop must reclaim both nodes: {log} != 2";
    }

    def check_r3_growth_rule_mid_traversal_allocations_land_in {
        (eng, ir) = compile_native("region_growth.jac");
        scenario = get_func(eng, "scenario", ctypes.c_int64);
        result = scenario();
        assert result == 2 , f"scenario() == {result}, expected 2 grown nodes";
        read_log = get_func(eng, "read_log", ctypes.c_int64);
        log = read_log();
        assert log == 3 , f"drop must reclaim seed + grown nodes: {log} != 3";
    }
    run_cases(
        [
            (
                "dynamic extent: a helper called under an open allocates in the region",
                check_dynamic_extent_a_helper_called_under_an_open_all
            ),
            (
                "arena: dynamic extent -- made in a helper, grown remotely, dropped here",
                check_arena_dynamic_extent_made_in_a_helper_grown_remo
            ),
            (
                "R3: region-resident topology traverses live and reclaims at drop",
                check_r3_region_resident_topology_traverses_live_and_r
            ),
            (
                "R3: growth rule -- mid-traversal allocations land in region_of(here)",
                check_r3_growth_rule_mid_traversal_allocations_land_in
            )
        ]
    );
}

test "dynamic extent: flow bodies under an open join and tear down once" {
    (eng, ir) = compile_native("region_flow_extent.jac");
    scenario = get_func(eng, "scenario", ctypes.c_int64);
    result = scenario();
    assert result == 60 , f"scenario() == {result}, expected 60";
}

test "arena: anonymous open sums correctly through the JIT" {
    (eng, ir) = compile_native("region_arena.jac");
    region_sum = get_func(eng, "region_sum", ctypes.c_int64, ctypes.c_int64);
    result = region_sum(5);
    assert result == 10 , f"region_sum(5) == {result}, expected 10";
}

test "region_dtor.jac cases" {
    def check_arena_dtor_log_runs_drop_hooks_lifo_at_the_close {
        (eng, ir) = compile_native("region_dtor.jac");

        dtor_order = get_func(eng, "dtor_order", ctypes.c_int64);
        result = dtor_order();
        assert result == 321 , f"dtor_order() == {result}, expected LIFO 321";
    }

    def check_arena_named_handle_drops_on_reassignment_and_at {
        (eng, ir) = compile_native("region_dtor.jac");

        named_handle = get_func(eng, "named_handle", ctypes.c_int64);
        result = named_handle();
        # before reassignment nothing dropped (0), reassigning the handle drops
        # the first arena (7); the second arena drops at scope exit, AFTER the
        # return value is computed (handles hold to scope exit so borrows of
        # region values stay valid past the handle's own last mention, R2).
        assert result == 707 , f"named_handle() == {result}, expected 707";
        read_log = get_func(eng, "read_log", ctypes.c_int64);
        log = read_log();
        assert log == 79 , f"scope exit must run the dtor log: log {log} != 79";
    }

    def check_arena_early_return_inside_an_open_still_tears_th {
        (eng, ir) = compile_native("region_dtor.jac");

        early_return = get_func(eng, "early_return", ctypes.c_int64, ctypes.c_int64);
        result = early_return(1);
        assert result == 0 , f"early_return(1) == {result}, expected 0";
        read_log = get_func(eng, "read_log", ctypes.c_int64);
        log = read_log();
        assert log == 5 , f"return path must drop the arena: log {log} != 5";
        result2 = early_return(0);
        assert result2 == 105 , f"early_return(0) == {result2}, expected 105";
    }

    def check_arena_managed_values_cross_an_open_safely {
        (eng, ir) = compile_native("region_dtor.jac");

        mixed_managed = get_func(eng, "mixed_managed", ctypes.c_int64, ctypes.c_int64);
        result = mixed_managed(4);
        assert result == 6 , f"mixed_managed(4) == {result}, expected 6";
    }
    run_cases(
        [
            (
                "arena: dtor-log runs drop hooks LIFO at the close of an anonymous open",
                check_arena_dtor_log_runs_drop_hooks_lifo_at_the_close
            ),
            (
                "arena: named handle drops on reassignment and at scope exit",
                check_arena_named_handle_drops_on_reassignment_and_at
            ),
            (
                "arena: early return inside an open still tears the region down",
                check_arena_early_return_inside_an_open_still_tears_th
            ),
            (
                "arena: managed values cross an open safely",
                check_arena_managed_values_cross_an_open_safely
            )
        ]
    );
}


test "phase W: walkers reclaim -- spawn-heavy loop fires drop per walker" {
    (eng, ir) = compile_native("walker_reclaim.jac");
    run = get_func(eng, "run", ctypes.c_int64, ctypes.c_int64);
    result = run(4);
    assert result == 12 , f"run(4) == {result}, expected 12";
    read_dropped = get_func(eng, "read_dropped", ctypes.c_int64);
    n_dropped = read_dropped();
    assert n_dropped == 4 , f"expected 4 reclaimed walkers, got {n_dropped}";
}


test "R4: own rebox copies a string out of a region" {
    (eng, ir) = compile_native("region_rebox.jac");
    out = get_func(eng, "out", ctypes.c_char_p);
    result = out();
    assert result == b"hi" , f"out() == {result}, expected b'hi'";
}

test "a user archetype named Region shadows the builtin cleanly" {
    (eng, ir) = compile_native("region_shadow.jac", opt_level=0);
    body = fn_ir(ir, "shadowed");
    n_new = calls_to(body, "__jac_region_new");
    assert n_new == 0 , f"user Region must not intercept arena setup: {n_new}";
    shadowed = get_func(eng, "shadowed", ctypes.c_int64);
    result = shadowed();
    assert result == 7 , f"shadowed() == {result}, expected 7";
}

test "nested functions preserve an event's active region" {
    (eng, _) = compile_native("region_nested_event.jac");
    scenario = get_func(eng, "scenario", ctypes.c_int64);
    assert scenario() == 12;
}

test "a constructor whose argument raises leaves no stale field for the close" {
    (eng, _) = compile_native("region_partial_ctor.jac");
    probe = get_func(eng, "probe", ctypes.c_int64);
    # 20 rounds of fill(50) (300 each) plus one caught failure (1 each).
    assert probe() == 6020;
}
