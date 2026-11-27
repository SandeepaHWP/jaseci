import ctypes;
import jaclang.compiler.frontend.unitree as uni;
import from tests.support { compile_native, get_func, run_cases }

test "native field factories use ordinary calls and fresh values per instance, and related cases" {
    def check_native_field_factories_use_ordinary_calls_and_fr {
        (engine, _) = compile_native("native_field_factories.jac");
        probe = get_func(engine, "probe", ctypes.c_bool);
        assert probe();
        assert probe();
    }

    def check_field_helpers_preserve_deferred_and_keyword_only {
        (engine, _) = compile_native("native_object_field_descriptors.jac");
        probe = get_func(engine, "probe", ctypes.c_bool);
        assert probe();
        assert probe();
    }
    run_cases(
        [
            (
                "native field factories use ordinary calls and fresh values per instance",
                check_native_field_factories_use_ordinary_calls_and_fr
            ),
            (
                "field helpers preserve deferred and keyword-only constructor slots",
                check_field_helpers_preserve_deferred_and_keyword_only
            )
        ]
    );
}


test "synthetic pipe calls preserve the source graph after lowering" {
    # A synthetic call left linked to its operands only goes away at a cycle
    # collection, so collection stays off while the graph is read.
    import gc;
    collecting = gc.isenabled();
    gc.disable();
    try {
        (engine, module) = compile_native("pipe_fwd.jac");
        chain = get_func(engine, "pipe_chain", ctypes.c_int64, ctypes.c_int64);
        spread = get_func(
            engine, "pipe_tuple", ctypes.c_int64, ctypes.c_int64, ctypes.c_int64
        );
        assert chain(5) == 7;
        assert spread(3, 4) == 7;
        for expr in module.get_all_sub_nodes(uni.BinaryExpr) {
            assert expr.left.parent is expr;
            assert expr.right.parent is expr;
        }
    } finally {
        if collecting {
            gc.enable();
        }
    }
}
