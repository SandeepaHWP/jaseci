"""End-to-end tests for the native length-aware bytes type, the struct module,
and binary file I/O (#6404 Track 0).

These exercise the sv↔na-congruent surface a binary parser needs:
  - a `bytes` type that carries an explicit length (embedded NULs survive),
  - `struct.pack`/`unpack`/`calcsize` for int/float byte-reinterpretation,
  - `open(path, "rb").read()` returning that length-aware bytes buffer.
"""

import from tests.support {
    compile_native,
    get_func,
    native_address,
    native_force_opts,
    run_cases
}
import ctypes;
import os;
import tempfile;
import from pathlib { Path }
import from jaclang.compiler.driver.program { JacProgram }

glob FIXTURES = str(Path(__file__).resolve().parent / "fixtures");

class JacStrABI(ctypes.Structure) {
    # Register view of a by-value JacStr {root, data, len} return. LLVM
    # lowers the aggregate return into scalar return registers; a 16-byte
    # two-pointer struct restype makes libffi read the first two of them,
    # which yields root and data. len rides in the third return register,
    # unreachable through libffi, but Jac string payloads are always
    # NUL-terminated at len so a bounded read is recovered from data.
    has _fields_: list[tuple[str, type]] = [
        ("root", ctypes.c_void_p),
        ("data", ctypes.c_void_p)
    ];
}

def get_sfunc(eng: any, name: str, restype: type | None, *argtypes: type) -> any {
    # descriptor-ABI variant of get_func: a c_char_p spelling here means a
    # Jac `str` (the by-value {root, data, len} descriptor at the native
    # ABI). LLVM decomposes a by-value descriptor param into three scalar
    # slots, so each str param is declared as (root, data, len) scalars and
    # bytes/str args build their backing storage via jac_str_new; str
    # returns come back as the full bytes of the result string, so existing
    # comparisons keep working.
    addr = native_address(eng, name);
    assert addr != 0 , f"Function '{name}' not found in JIT engine";
    real_res: any = JacStrABI if restype == ctypes.c_char_p else restype;
    str_slots: list[bool] = [];
    real_args: list[any] = [];
    for a in argtypes {
        if a == ctypes.c_char_p {
            str_slots.append(True);
            real_args.append(ctypes.c_void_p);
            real_args.append(ctypes.c_void_p);
            real_args.append(ctypes.c_int64);
        } else {
            str_slots.append(False);
            real_args.append(a);
        }
    }
    raw = ctypes.CFUNCTYPE(real_res, *real_args)(addr);
    sn_addr = 0;
    for sn in ("jac_str_new", "__jac_str_new") {
        try {
            sn_addr = native_address(eng, sn);
        } except Exception {
            sn_addr = 0;
        }
        if sn_addr {
            break;
        }
    }
    mkstr = (
        ctypes.CFUNCTYPE(ctypes.c_void_p, ctypes.c_char_p, ctypes.c_int64)(sn_addr)
            if sn_addr
            else None
    );
    def _call(*args: any) -> any {
        c_args: list[any] = [];
        for (a, is_str) in zip(args, str_slots) {
            if is_str {
                assert mkstr is not None , "jac_str_new not found in JIT engine";
                b = a.encode("utf-8") if isinstance(a, str) else a;
                p = mkstr(b, len(b));
                c_args.append(p);
                c_args.append(p);
                c_args.append(len(b));
            } else {
                c_args.append(a);
            }
        }
        r = raw(*c_args);
        if real_res is JacStrABI {
            if not r.data {
                return b"";
            }
            return ctypes.string_at(r.data);
        }
        return r;
    }
    return _call;
}

test "bytes_ops.jac cases" {
    # ─── bytes type: length awareness, indexing, slicing, equality ───
    def check_bytes_literal_length_counts_embedded_nul {
        (eng, _) = compile_native("bytes_ops.jac");

        f = get_func(eng, "lit_len", ctypes.c_int64);
        assert f() == 5;
    }

    def check_bytes_index_returns_embedded_nul_byte {
        (eng, _) = compile_native("bytes_ops.jac");

        f = get_func(eng, "idx_nul", ctypes.c_int64);
        assert f() == 0;
    }

    def check_bytes_data_past_nul_is_reachable {
        (eng, _) = compile_native("bytes_ops.jac");

        f = get_func(eng, "idx_after_nul", ctypes.c_int64);
        assert f() == 67;
    }

    def check_bytes_negative_index {
        (eng, _) = compile_native("bytes_ops.jac");

        f = get_func(eng, "neg_index", ctypes.c_int64);
        assert f() == 68;
    }

    def check_bytes_slice_length {
        (eng, _) = compile_native("bytes_ops.jac");

        f = get_func(eng, "slice_len", ctypes.c_int64);
        assert f() == 5;
    }

    def check_bytes_slice_index {
        (eng, _) = compile_native("bytes_ops.jac");

        f = get_func(eng, "slice_idx", ctypes.c_int64);
        assert f() == 119;
    }

    def check_bytes_equality_true {
        (eng, _) = compile_native("bytes_ops.jac");

        f = get_func(eng, "eq_true", ctypes.c_int64);
        assert f() == 1;
    }

    def check_bytes_equality_differs_after_nul {
        (eng, _) = compile_native("bytes_ops.jac");

        f = get_func(eng, "eq_false_after_nul", ctypes.c_int64);
        assert f() == 0;
    }

    def check_bytes_equality_differs_by_length {
        (eng, _) = compile_native("bytes_ops.jac");

        f = get_func(eng, "eq_len_differs", ctypes.c_int64);
        assert f() == 0;
    }

    def check_str_encode_length {
        (eng, _) = compile_native("bytes_ops.jac");

        f = get_func(eng, "encode_len", ctypes.c_int64);
        assert f() == 5;
    }

    def check_int_from_bytes_little_endian_length_aware {
        (eng, _) = compile_native("bytes_ops.jac");

        f = get_func(eng, "from_bytes_le", ctypes.c_int64);
        assert f() == 256;
    }

    def check_int_from_bytes_big_endian {
        (eng, _) = compile_native("bytes_ops.jac");

        f = get_func(eng, "from_bytes_be", ctypes.c_int64);
        assert f() == 1;
    }

    def check_int_to_bytes_roundtrip {
        (eng, _) = compile_native("bytes_ops.jac");

        f = get_func(eng, "to_bytes_roundtrip", ctypes.c_int64);
        assert f() == 258;
    }

    def check_empty_bytes_length {
        (eng, _) = compile_native("bytes_ops.jac");

        f = get_func(eng, "empty_len", ctypes.c_int64);
        assert f() == 0;
    }

    # ─── bytes building: concatenation and the bytes()/bytearray() constructors ───
    def check_bytes_concat_length {
        (eng, _) = compile_native("bytes_ops.jac");

        f = get_func(eng, "concat_len", ctypes.c_int64);
        assert f() == 2;
    }

    def check_bytes_concat_keeps_embedded_nul_length_aware {
        (eng, _) = compile_native("bytes_ops.jac");

        f = get_func(eng, "concat_embedded_nul_len", ctypes.c_int64);
        assert f() == 4;
    }

    def check_bytes_concat_copies_right_operand_at_correct_off {
        (eng, _) = compile_native("bytes_ops.jac");

        f = get_func(eng, "concat_idx", ctypes.c_int64);
        assert f() == 67;
    }

    def check_bytes_constructor_length_counts_bytes_past_nul {
        (eng, _) = compile_native("bytes_ops.jac");

        f = get_func(eng, "ctor_len", ctypes.c_int64);
        assert f() == 3;
    }

    def check_bytes_constructor_byte_after_nul_is_reachable {
        (eng, _) = compile_native("bytes_ops.jac");

        f = get_func(eng, "ctor_idx_after_nul", ctypes.c_int64);
        assert f() == 66;
    }

    def check_bytearray_constructor_length_counts_bytes_past_n {
        (eng, _) = compile_native("bytes_ops.jac");

        f = get_func(eng, "bytearray_ctor_len", ctypes.c_int64);
        assert f() == 3;
    }

    # ─── #6749: ops the i8*→jacbytes* migration left on the old assumption ───
    # Grouped one-compile-per-gap; each embedded-NUL case is what the old
    # strlen/strstr/strcmp paths got wrong.
    def check_bytes_repeat_is_length_aware_6749 {
        (eng, _) = compile_native("bytes_ops.jac");

        assert get_func(eng, "repeat_len", ctypes.c_int64)() == 6;
        assert get_func(eng, "repeat_idx", ctypes.c_int64)() == 98;
        assert get_func(eng, "repeat_nul_len", ctypes.c_int64)() == 6;
        assert get_func(eng, "repeat_nul_idx", ctypes.c_int64)() == 0;
        assert get_func(eng, "repeat_zero", ctypes.c_int64)() == 0;
    }

    def check_bytes_membership_is_length_aware_6749 {
        (eng, _) = compile_native("bytes_ops.jac");

        assert get_func(eng, "in_true", ctypes.c_int64)() == 1;
        assert get_func(eng, "in_false", ctypes.c_int64)() == 0;
        assert get_func(eng, "in_nul", ctypes.c_int64)() == 1;
        assert get_func(eng, "not_in_true", ctypes.c_int64)() == 1;
        assert get_func(eng, "in_empty", ctypes.c_int64)() == 1;
    }

    def check_bytes_iteration_yields_int_bytes_6749 {
        (eng, _) = compile_native("bytes_ops.jac");

        assert get_func(eng, "iter_sum", ctypes.c_int64)() == 294;
        assert get_func(eng, "iter_count_nul", ctypes.c_int64)() == 3;
        assert get_func(eng, "iter_sum_nul", ctypes.c_int64)() == 195;
        assert get_func(eng, "iter_protocol_sum", ctypes.c_int64)() == 294;
    }

    def check_bytes_truthiness_is_emptiness_not_nullness_6749 {
        (eng, _) = compile_native("bytes_ops.jac");

        assert get_func(eng, "truthy_empty", ctypes.c_int64)() == 0;
        assert get_func(eng, "truthy_nonempty", ctypes.c_int64)() == 1;
        assert get_func(eng, "truthy_nul", ctypes.c_int64)() == 1;
        assert get_func(eng, "bool_empty", ctypes.c_int64)() == 0;
        assert get_func(eng, "bool_nonempty", ctypes.c_int64)() == 1;
    }

    def check_bytes_repr_matches_cpython_b_6749 {
        (eng, _) = compile_native("bytes_ops.jac");

        assert get_func(eng, "repr_abc_ok", ctypes.c_int64)() == 1;
        assert get_func(eng, "repr_nul_ok", ctypes.c_int64)() == 1;
        assert get_func(eng, "repr_empty_ok", ctypes.c_int64)() == 1;
        assert get_func(eng, "repr_quote_ok", ctypes.c_int64)() == 1;
        assert get_func(eng, "repr_special_ok", ctypes.c_int64)() == 1;
        assert get_func(eng, "repr_backslash_ok", ctypes.c_int64)() == 1;
        assert get_func(eng, "repr_hi_ok", ctypes.c_int64)() == 1;
    }

    def check_bytes_dict_key_is_length_aware_6749 {
        (eng, _) = compile_native("bytes_ops.jac");

        assert get_func(eng, "dict_get", ctypes.c_int64)() == 7;
        assert get_func(eng, "dict_nul", ctypes.c_int64)() == 5;
        assert get_func(eng, "dict_distinct_len", ctypes.c_int64)() == 2;
        assert get_func(eng, "dict_distinct_len2", ctypes.c_int64)() == 1;
    }

    def check_bytes_ordering_is_lexicographic_unsigned_6749 {
        (eng, _) = compile_native("bytes_ops.jac");

        assert get_func(eng, "lt_true", ctypes.c_int64)() == 1;
        assert get_func(eng, "lt_false", ctypes.c_int64)() == 0;
        assert get_func(eng, "lt_prefix", ctypes.c_int64)() == 1;
        assert get_func(eng, "gt_true", ctypes.c_int64)() == 1;
        assert get_func(eng, "lte_eq", ctypes.c_int64)() == 1;
        assert get_func(eng, "gte_eq", ctypes.c_int64)() == 1;
        assert get_func(eng, "cmp_nul", ctypes.c_int64)() == 1;
        assert get_func(eng, "cmp_hi", ctypes.c_int64)() == 1;
    }

    def check_bytes_vs_none_comparison_is_null_safe_6751 {
        (eng, _) = compile_native("bytes_ops.jac");

        # None operand: equal only to None (CPython identity), never deref null
        assert get_func(eng, "none_eq_bytes", ctypes.c_int64)() == 0;
        assert get_func(eng, "bytes_eq_none", ctypes.c_int64)() == 0;
        assert get_func(eng, "none_ne_bytes", ctypes.c_int64)() == 1;
        assert get_func(eng, "cnone_eq_bytes", ctypes.c_int64)() == 0;
        assert get_func(eng, "cnone_ne_bytes", ctypes.c_int64)() == 1;
        # both None -> equal; non-null operand still compares by value
        assert get_func(eng, "both_none_eq", ctypes.c_int64)() == 1;
        assert get_func(eng, "both_none_ne", ctypes.c_int64)() == 0;
        assert get_func(eng, "some_eq_bytes", ctypes.c_int64)() == 1;
        assert get_func(eng, "some_eq_diff", ctypes.c_int64)() == 0;
        # ordering (< > <= >=) against an un-narrowed None operand is rejected
        # at check time (E1121, pinned in test_native_optional_ptr.jac)
    }

    def check_builtin_repr_supports_native_bytes_without_demot {
        (eng, _) = compile_native("bytes_ops.jac");

        assert get_func(eng, "builtin_repr_ok", ctypes.c_int64)() == 1;
    }

    def check_string_containment_preserves_embedded_nul_bounda {
        (eng, _) = compile_native("bytes_ops.jac");

        assert get_func(eng, "string_contains_nul", ctypes.c_int64)() == 1;
    }
    run_cases(
        [
            (
                "bytes literal length counts embedded NUL",
                check_bytes_literal_length_counts_embedded_nul
            ),
            (
                "bytes index returns embedded NUL byte",
                check_bytes_index_returns_embedded_nul_byte
            ),
            (
                "bytes data past NUL is reachable",
                check_bytes_data_past_nul_is_reachable
            ),
            ("bytes negative index", check_bytes_negative_index),
            ("bytes slice length", check_bytes_slice_length),
            ("bytes slice index", check_bytes_slice_index),
            ("bytes equality true", check_bytes_equality_true),
            (
                "bytes equality differs after NUL",
                check_bytes_equality_differs_after_nul
            ),
            (
                "bytes equality differs by length",
                check_bytes_equality_differs_by_length
            ),
            ("str encode length", check_str_encode_length),
            (
                "int from_bytes little-endian length-aware",
                check_int_from_bytes_little_endian_length_aware
            ),
            ("int from_bytes big-endian", check_int_from_bytes_big_endian),
            ("int to_bytes roundtrip", check_int_to_bytes_roundtrip),
            ("empty bytes length", check_empty_bytes_length),
            ("bytes concat length", check_bytes_concat_length),
            (
                "bytes concat keeps embedded NUL (length-aware)",
                check_bytes_concat_keeps_embedded_nul_length_aware
            ),
            (
                "bytes concat copies right operand at correct offset",
                check_bytes_concat_copies_right_operand_at_correct_off
            ),
            (
                "bytes() constructor length counts bytes past NUL",
                check_bytes_constructor_length_counts_bytes_past_nul
            ),
            (
                "bytes() constructor byte after NUL is reachable",
                check_bytes_constructor_byte_after_nul_is_reachable
            ),
            (
                "bytearray() constructor length counts bytes past NUL",
                check_bytearray_constructor_length_counts_bytes_past_n
            ),
            (
                "bytes repeat is length-aware (#6749)",
                check_bytes_repeat_is_length_aware_6749
            ),
            (
                "bytes membership is length-aware (#6749)",
                check_bytes_membership_is_length_aware_6749
            ),
            (
                "bytes iteration yields int bytes (#6749)",
                check_bytes_iteration_yields_int_bytes_6749
            ),
            (
                "bytes truthiness is emptiness, not nullness (#6749)",
                check_bytes_truthiness_is_emptiness_not_nullness_6749
            ),
            (
                "bytes repr matches CPython b'...' (#6749)",
                check_bytes_repr_matches_cpython_b_6749
            ),
            (
                "bytes dict key is length-aware (#6749)",
                check_bytes_dict_key_is_length_aware_6749
            ),
            (
                "bytes ordering is lexicographic unsigned (#6749)",
                check_bytes_ordering_is_lexicographic_unsigned_6749
            ),
            (
                "bytes vs None comparison is null-safe (#6751)",
                check_bytes_vs_none_comparison_is_null_safe_6751
            ),
            (
                "builtin repr supports native bytes without demotion",
                check_builtin_repr_supports_native_bytes_without_demot
            ),
            (
                "string containment preserves embedded NUL boundaries",
                check_string_containment_preserves_embedded_nul_bounda
            )
        ]
    );
}


test "struct_pack.jac cases" {
    # ─── struct module: unpack / pack / calcsize ───
    def check_struct_unpack_u32_little_endian {
        (eng, _) = compile_native("struct_pack.jac");

        f = get_func(eng, "u_u32_le", ctypes.c_int64);
        assert f() == 1;
    }

    def check_struct_unpack_i32_little_endian_signed {
        (eng, _) = compile_native("struct_pack.jac");

        f = get_func(eng, "u_i32_le", ctypes.c_int64);
        assert f() == -1;
    }

    def check_struct_unpack_u32_big_endian {
        (eng, _) = compile_native("struct_pack.jac");

        f = get_func(eng, "u_u32_be", ctypes.c_int64);
        assert f() == 1;
    }

    def check_struct_unpack_i16_signed {
        (eng, _) = compile_native("struct_pack.jac");

        f = get_func(eng, "u_i16_le", ctypes.c_int64);
        assert f() == -2;
    }

    def check_struct_unpack_u16 {
        (eng, _) = compile_native("struct_pack.jac");

        f = get_func(eng, "u_u16_le", ctypes.c_int64);
        assert f() == 32768;
    }

    def check_struct_unpack_u8 {
        (eng, _) = compile_native("struct_pack.jac");

        f = get_func(eng, "u_u8", ctypes.c_int64);
        assert f() == 255;
    }

    def check_struct_unpack_i8_signed {
        (eng, _) = compile_native("struct_pack.jac");

        f = get_func(eng, "u_i8", ctypes.c_int64);
        assert f() == -1;
    }

    def check_struct_unpack_u64 {
        (eng, _) = compile_native("struct_pack.jac");

        f = get_func(eng, "u_u64_le", ctypes.c_int64);
        assert f() == 1;
    }

    def check_struct_unpack_two_shorts {
        (eng, _) = compile_native("struct_pack.jac");

        f = get_func(eng, "u_two_le", ctypes.c_int64);
        assert f() == 1002;
    }

    def check_struct_unpack_f32_via_pack_roundtrip {
        (eng, _) = compile_native("struct_pack.jac");

        f = get_func(eng, "u_f32", ctypes.c_double);
        assert abs(f() - 1.5) < 1e-9;
    }

    def check_struct_unpack_f64_via_pack_roundtrip {
        (eng, _) = compile_native("struct_pack.jac");

        f = get_func(eng, "u_f64", ctypes.c_double);
        assert abs(f() - 3.25) < 1e-12;
    }

    def check_struct_calcsize_mixed {
        (eng, _) = compile_native("struct_pack.jac");

        f = get_func(eng, "calcsize_mix", ctypes.c_int64);
        assert f() == 8;
    }

    def check_struct_calcsize_with_pad_byte {
        (eng, _) = compile_native("struct_pack.jac");

        f = get_func(eng, "calcsize_pad", ctypes.c_int64);
        assert f() == 4;
    }

    def check_struct_pack_unpack_u32_le_roundtrip {
        (eng, _) = compile_native("struct_pack.jac");

        f = get_func(eng, "pack_unpack_u32_le", ctypes.c_int64);
        assert f() == 305419896;
    }

    def check_struct_pack_unpack_u32_be_roundtrip {
        (eng, _) = compile_native("struct_pack.jac");

        f = get_func(eng, "pack_unpack_u32_be", ctypes.c_int64);
        assert f() == 305419896;
    }

    def check_struct_pack_multiple_values {
        (eng, _) = compile_native("struct_pack.jac");

        f = get_func(eng, "pack_multi", ctypes.c_int64);
        assert f() == 7009;
    }

    def check_struct_unpack_short_buffer_raises {
        (eng, _) = compile_native("struct_pack.jac");

        f = get_func(eng, "unpack_short_raises", ctypes.c_int64);
        assert f() == -1;
    }
    run_cases(
        [
            ("struct unpack u32 little-endian", check_struct_unpack_u32_little_endian),
            (
                "struct unpack i32 little-endian signed",
                check_struct_unpack_i32_little_endian_signed
            ),
            ("struct unpack u32 big-endian", check_struct_unpack_u32_big_endian),
            ("struct unpack i16 signed", check_struct_unpack_i16_signed),
            ("struct unpack u16", check_struct_unpack_u16),
            ("struct unpack u8", check_struct_unpack_u8),
            ("struct unpack i8 signed", check_struct_unpack_i8_signed),
            ("struct unpack u64", check_struct_unpack_u64),
            ("struct unpack two shorts", check_struct_unpack_two_shorts),
            (
                "struct unpack f32 via pack roundtrip",
                check_struct_unpack_f32_via_pack_roundtrip
            ),
            (
                "struct unpack f64 via pack roundtrip",
                check_struct_unpack_f64_via_pack_roundtrip
            ),
            ("struct calcsize mixed", check_struct_calcsize_mixed),
            ("struct calcsize with pad byte", check_struct_calcsize_with_pad_byte),
            (
                "struct pack unpack u32 le roundtrip",
                check_struct_pack_unpack_u32_le_roundtrip
            ),
            (
                "struct pack unpack u32 be roundtrip",
                check_struct_pack_unpack_u32_be_roundtrip
            ),
            ("struct pack multiple values", check_struct_pack_multiple_values),
            (
                "struct unpack short buffer raises",
                check_struct_unpack_short_buffer_raises
            )
        ]
    );
}


test "struct pack wrong arg count is a compile error" {
    import contextlib;
    import io;
    buf = io.StringIO();
    prog = JacProgram();
    with contextlib.redirect_stderr(buf) {
        ir = prog.compile(
            file_path=str(os.path.join(FIXTURES, "struct_bad_pack.jac")),
            options=native_force_opts()
        );
    }
    assert not prog.errors_had , (
        f"the bad struct.pack is owned by bad_pack(), which must demote to "
        f"a seam, got: {[str(e) for e in prog.errors_had]}"
    );
    assert ir.gen.native_layout is not None , "whole-module native compile aborted";
    assert "bad_pack" not in ir.gen.native_layout.functions , (
        "a struct.pack with the wrong argument count must demote its "
        "function out of the native layout, never pack uninitialized tail "
        "bytes"
    );
    assert "struct.pack" in buf.getvalue() , (
        f"the demotion reason must name struct.pack, got:\n{buf.getvalue()}"
    );
}

# ─── binary file read returns length-aware bytes ───
"""Write a small binary blob with embedded NULs and return its path."""
def _write_blob -> str {
    (fd, path) = tempfile.mkstemp(suffix=".bin");
    os.write(fd, b"\x78\x56\x34\x12\x00\x99\x00\x07");
    os.close(fd);
    return path;
}

test "binary_file.jac cases" {
    def check_binary_read_length_counts_embedded_nuls {
        (eng, _) = compile_native("binary_file.jac");

        f = get_sfunc(eng, "read_len", ctypes.c_int64, ctypes.c_char_p);
        path = _write_blob();
        try {
            assert f(path.encode("utf-8")) == 8;
        } finally {
            os.unlink(path);
        }
    }

    def check_binary_read_byte_after_nul {
        (eng, _) = compile_native("binary_file.jac");

        f = get_sfunc(eng, "byte_after_nul", ctypes.c_int64, ctypes.c_char_p);
        path = _write_blob();
        try {
            assert f(path.encode("utf-8")) == 153;
        } finally {
            os.unlink(path);
        }
    }

    def check_struct_unpack_from_binary_file_slice {
        (eng, _) = compile_native("binary_file.jac");

        f = get_sfunc(eng, "struct_from_file", ctypes.c_int64, ctypes.c_char_p);
        path = _write_blob();
        try {
            assert f(path.encode("utf-8")) == 305419896;
        } finally {
            os.unlink(path);
        }
    }

    def check_binary_read_via_context_manager {
        (eng, _) = compile_native("binary_file.jac");

        f = get_sfunc(eng, "read_with_ctx", ctypes.c_int64, ctypes.c_char_p);
        path = _write_blob();
        try {
            assert f(path.encode("utf-8")) == 8;
        } finally {
            os.unlink(path);
        }
    }
    def check_binary_readline_keeps_embedded_nul_length_aware {
        (eng, _) = compile_native("binary_file.jac");

        f = get_sfunc(eng, "first_line_len", ctypes.c_int64, ctypes.c_char_p);
        path = _write_line_blob();
        try {
            assert f(path.encode("utf-8")) == 5;
        } finally {
            os.unlink(path);
        }
    }

    def check_binary_readline_byte_after_nul {
        (eng, _) = compile_native("binary_file.jac");

        f = get_sfunc(
            eng, "first_line_byte_after_nul", ctypes.c_int64, ctypes.c_char_p
        );
        path = _write_line_blob();
        try {
            assert f(path.encode("utf-8")) == 67;
        } finally {
            os.unlink(path);
        }
    }
    run_cases(
        [
            (
                "binary read length counts embedded NULs",
                check_binary_read_length_counts_embedded_nuls
            ),
            ("binary read byte after NUL", check_binary_read_byte_after_nul),
            (
                "struct unpack from binary file slice",
                check_struct_unpack_from_binary_file_slice
            ),
            ("binary read via context manager", check_binary_read_via_context_manager),
            (
                "binary readline keeps embedded NUL (length-aware)",
                check_binary_readline_keeps_embedded_nul_length_aware
            ),
            ("binary readline byte after NUL", check_binary_readline_byte_after_nul)
        ]
    );
}


"""Write a blob whose first line has an embedded NUL before the newline."""
def _write_line_blob -> str {
    (fd, path) = tempfile.mkstemp(suffix=".bin");
    os.write(fd, b"AB\x00C\nXY");
    os.close(fd);
    return path;
}


test "reused object locals preserve narrowed string operations" {
    (eng, _) = compile_native("rebound_string.jac");
    assert get_func(eng, "rebound_string", ctypes.c_int64)() == 0;
}
