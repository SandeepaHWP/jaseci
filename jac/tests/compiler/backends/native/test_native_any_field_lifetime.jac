import ctypes;
import from tests.support { compile_native, get_func, run_cases }

test "any_field_lifetime.jac cases" {
    def check_tagged_object_fields_release_their_owned_payload {
        (engine, module) = compile_native("any_field_lifetime.jac");

        release = get_func(engine, "release_field", None);
        count = get_func(engine, "drop_count", ctypes.c_int64);
        before = count();
        release();
        assert count() == before + 2;
    }

    def check_tagged_field_replacement_retains_borrowed_payloa {
        (engine, module) = compile_native("any_field_lifetime.jac");

        run = get_func(engine, "borrowed_field", ctypes.c_int64);
        count = get_func(engine, "drop_count", ctypes.c_int64);
        before = count();
        assert run() == 1;
        assert count() == before + 2;
    }
    def check_cycle_tracing_follows_tagged_object_fields {
        (engine, module) = compile_native("any_field_lifetime.jac");

        address = engine.get_global_value_address("__rc_cycles_enabled");
        assert isinstance(address, int) and address;
        ctypes.cast(address, ctypes.POINTER(ctypes.c_uint8))[0] = 1;
        make_cycle = get_func(engine, "make_cycle", None);
        collect = get_func(engine, "collect", None);
        count = get_func(engine, "drop_count", ctypes.c_int64);
        before = count();
        make_cycle();
        collect();
        assert count() == before + 2;
    }
    run_cases(
        [
            (
                "tagged object fields release their owned payloads",
                check_tagged_object_fields_release_their_owned_payload
            ),
            (
                "tagged field replacement retains borrowed payloads before releasing old values",
                check_tagged_field_replacement_retains_borrowed_payloa
            ),
            (
                "cycle tracing follows tagged object fields",
                check_cycle_tracing_follows_tagged_object_fields
            )
        ]
    );
}
