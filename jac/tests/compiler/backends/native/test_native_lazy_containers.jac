"""Behavioral + IR-shape tests for lazy-empty containers (native).

A fresh (empty) list/dict/set is a single header allocation: cap starts
at 0 with NULL data buffers, and the first insert materializes storage
(list grow 0 -> 8, hash rehash 0 -> 8). The IR tests pin the shape (the
emitted `new` helpers contain no data-buffer malloc/calloc), and the
behavioral tests cover every cap-0 touch point: len/iterate/contains/
clear on never-filled containers, first-insert growth through repeated
doublings, and dropping empty containers (the destructor and grow paths
must tolerate NULL buffers).
"""

import ctypes;
import from tests.support { compile_native, get_func, run_cases }

"""Body text of the first defined function whose name starts with `prefix`."""
def fn_body(ir: any, prefix: str) -> str {
    text = str(ir.gen.llvm_ir);
    start = text.find(f'@"{prefix}');
    assert start >= 0 , f"no function starting with {prefix} in IR";
    line_start = text.rfind("define", 0, start);
    assert line_start >= 0 , f"{prefix} found only as a declaration";
    body_end = text.find("\n}", line_start);
    return text[line_start:body_end] if body_end > 0 else text[line_start:];
}

test "lazy_containers.jac allocation cases" {
    def check_lazy_list_new_allocates_no_data_buffer {
        (eng, ir) = compile_native("lazy_containers.jac");

        body = fn_body(ir, "__list_new_");
        assert body.count('@"malloc"') == 0 , "an empty list must not malloc element storage";
        assert body.count('@"calloc"') == 0;
    }

    def check_lazy_dict_new_allocates_no_key_val_ctrl_order_bu {
        (eng, ir) = compile_native("lazy_containers.jac");

        body = fn_body(ir, "__dict_new_");
        assert body.count('@"malloc"') == 0 , "an empty dict must not malloc its table buffers";
        assert body.count('@"calloc"') == 0;
    }
    run_cases(
        [
            (
                "lazy: list new allocates no data buffer",
                check_lazy_list_new_allocates_no_data_buffer
            ),
            (
                "lazy: dict new allocates no key/val/ctrl/order buffers",
                check_lazy_dict_new_allocates_no_key_val_ctrl_order_bu
            )
        ]
    );
}


test "lazy_containers.jac behaviour cases" {
    def check_lazy_empty_list_len_and_iteration {
        (eng, _) = compile_native("lazy_containers.jac");

        f = get_func(eng, "empty_list_ops", ctypes.c_int64, ctypes.c_int64);
        assert f(7) == 7;
    }

    def check_lazy_list_grows_from_cap_0_through_doublings {
        (eng, _) = compile_native("lazy_containers.jac");

        f = get_func(eng, "list_fill_from_empty", ctypes.c_int64, ctypes.c_int64);
        # sum(0..99) + len = 4950 + 100; crosses 0->8->16->32->64->128.
        assert f(100) == 5050;
        assert f(1) == 1;
        assert f(0) == 0;
    }

    def check_lazy_insert_into_a_never_filled_list {
        (eng, _) = compile_native("lazy_containers.jac");

        f = get_func(eng, "list_insert_into_empty", ctypes.c_int64);
        assert f() == 43;
    }

    def check_lazy_empty_dict_len_contains_iterate_clear {
        (eng, _) = compile_native("lazy_containers.jac");

        f = get_func(eng, "empty_dict_ops", ctypes.c_int64, ctypes.c_int64);
        assert f(5) == 0;
    }

    def check_lazy_dict_grows_from_cap_0_and_reads_back {
        (eng, _) = compile_native("lazy_containers.jac");

        f = get_func(eng, "dict_fill_from_empty", ctypes.c_int64, ctypes.c_int64);
        # sum of i*2 for i in 0..49 = 2450, + len 50; crosses several rehashes.
        assert f(50) == 2500;
        assert f(1) == 1;
    }

    def check_lazy_str_keyed_dict_from_empty_insert_update_con {
        (eng, _) = compile_native("lazy_containers.jac");

        f = get_func(eng, "str_dict_from_empty", ctypes.c_int64);
        assert f() == 15;
    }

    def check_lazy_set_emptied_then_refilled_through_rehash {
        (eng, _) = compile_native("lazy_containers.jac");

        f = get_func(eng, "set_ops", ctypes.c_int64, ctypes.c_int64);
        assert f(20) == 20;
    }

    def check_lazy_many_empty_containers_created_and_dropped_d {
        (eng, _) = compile_native("lazy_containers.jac");

        f = get_func(eng, "many_empty_dropped", ctypes.c_int64, ctypes.c_int64);
        # 2 per multiple of 10 in 0..9999 -> 2000.
        assert f(10000) == 2000;
    }

    def check_lazy_clear_on_a_never_filled_dict_then_refill {
        (eng, _) = compile_native("lazy_containers.jac");

        f = get_func(eng, "clear_then_refill", ctypes.c_int64);
        assert f() == 21;
    }

    def check_lazy_empty_lists_stored_inside_a_dict {
        (eng, _) = compile_native("lazy_containers.jac");

        f = get_func(eng, "nested_empty", ctypes.c_int64, ctypes.c_int64);
        # even i keep one element: 10 of 20.
        assert f(20) == 10;
    }
    run_cases(
        [
            (
                "lazy: empty list len and iteration",
                check_lazy_empty_list_len_and_iteration
            ),
            (
                "lazy: list grows from cap 0 through doublings",
                check_lazy_list_grows_from_cap_0_through_doublings
            ),
            (
                "lazy: insert into a never-filled list",
                check_lazy_insert_into_a_never_filled_list
            ),
            (
                "lazy: empty dict len/contains/iterate/clear",
                check_lazy_empty_dict_len_contains_iterate_clear
            ),
            (
                "lazy: dict grows from cap 0 and reads back",
                check_lazy_dict_grows_from_cap_0_and_reads_back
            ),
            (
                "lazy: str-keyed dict from empty (insert, update, contains)",
                check_lazy_str_keyed_dict_from_empty_insert_update_con
            ),
            (
                "lazy: set emptied then refilled through rehash",
                check_lazy_set_emptied_then_refilled_through_rehash
            ),
            (
                "lazy: many empty containers created and dropped (destructor on NULL)",
                check_lazy_many_empty_containers_created_and_dropped_d
            ),
            (
                "lazy: clear on a never-filled dict, then refill",
                check_lazy_clear_on_a_never_filled_dict_then_refill
            ),
            (
                "lazy: empty lists stored inside a dict",
                check_lazy_empty_lists_stored_inside_a_dict
            )
        ]
    );
}
