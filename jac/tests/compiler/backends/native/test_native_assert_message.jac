"""An assertion's message is what its error says, however the message is written.

`assert cond, "text"` raised with its text and where it failed, but a message
that was worked out (`"x must be positive: " + str(x)`, an f-string) was
dropped: the error said only `assertion failed at <file>:<line>`. A program
that reports what its own checks say (a validator naming the token nothing
grants, a test that prints the value it got) lost the message.
"""

import ctypes;
import os;
import re;
import tempfile;
import from pathlib { Path }
import from tests.support {
    compile_native,
    get_func,
    native_build,
    native_run,
    run_cases
}

glob RC_FIXTURE = str(
         Path(__file__).resolve().parent / "fixtures" / "rc_assert_message.jac"
     ),
     MALLOC_RE = re.compile(r"RC MALLOC\s+id=(\d+)\s.*\bop=(\S+)"),
     FREE_RE = re.compile(r"RC FREE\s+id=(\d+)\s");

def call_str(eng: any, name: str) -> bytes {
    return get_func(eng, name, ctypes.c_char_p)();
}

test "assert_message.jac cases" {
    def check_a_message_built_by_concatenation_is_carried_with {
        (eng, _) = compile_native("assert_message.jac");

        text = call_str(eng, "computed_message");
        assert text.startswith(b"x must be positive: -1 at ") , text;
        assert text.endswith(b"assert_message.jac:2") , text;
    }

    def check_a_message_that_is_an_f_string_is_carried_with_wh {
        (eng, _) = compile_native("assert_message.jac");

        text = call_str(eng, "formatted_message");
        assert text.startswith(b"too short: ab at ") , text;
        assert text.endswith(b"assert_message.jac:6") , text;
    }

    def check_a_literal_message_and_no_message_are_as_they_wer {
        (eng, _) = compile_native("assert_message.jac");

        literal = call_str(eng, "literal_message");
        assert literal.startswith(b"a literal at ")
            and literal.endswith(b"assert_message.jac:10") , literal;
        bare = call_str(eng, "bare_message");
        assert bare.startswith(b"assertion failed at ")
            and bare.endswith(b"assert_message.jac:14") , bare;
    }

    def check_a_message_is_not_worked_out_while_the_assertion {
        (eng, _) = compile_native("assert_message.jac");

        assert get_func(eng, "holding", ctypes.c_int64)() == 1;
        assert get_func(eng, "message_calls", ctypes.c_int64)() == 1;
    }

    def check_a_message_that_is_none_says_the_assertion_failed {
        (eng, _) = compile_native("assert_message.jac");

        text = call_str(eng, "none_message");
        assert text.startswith(b"assertion failed at ") , text;
        assert text.endswith(b"assert_message.jac:82") , text;
    }
    run_cases(
        [
            (
                "a message built by concatenation is carried, with where it failed",
                check_a_message_built_by_concatenation_is_carried_with
            ),
            (
                "a message that is an f-string is carried, with where it failed",
                check_a_message_that_is_an_f_string_is_carried_with_wh
            ),
            (
                "a literal message and no message are as they were",
                check_a_literal_message_and_no_message_are_as_they_wer
            ),
            (
                "a message is not worked out while the assertion holds",
                check_a_message_is_not_worked_out_while_the_assertion
            ),
            (
                "a message that is None says the assertion failed",
                check_a_message_that_is_none_says_the_assertion_failed
            )
        ]
    );
}


def check_message_freed(memory: str) {
    with tempfile.TemporaryDirectory() as tmp {
        out_bin = os.path.join(tmp, "rc_assert_message");
        native_build(RC_FIXTURE, out_bin, memory=memory, extra=["--debug"]);
        out = native_run(out_bin);
    }
    lines = out.splitlines();
    assert lines[-1] == "12" , lines[-1];
    allocated: dict[str, str] = {};
    freed: set[str] = set();
    for line in lines {
        malloc = MALLOC_RE.search(line);
        if malloc {
            allocated[malloc.group(1)] = malloc.group(2);
        }
        free = FREE_RE.search(line);
        if free {
            freed.add(free.group(1));
        }
    }
    assert "str_concat" in allocated.values() , out[-2000:];
    leaked = {
        aid: op
        for (aid, op) in allocated.items()
        if aid not in freed
    };
    assert not leaked , leaked;
}

test "a caught, sliced, or non-string message is freed cases" {
    def check_a_caught_sliced_or_non_string_message_is_freed_w {
        check_message_freed("rc");
    }

    def check_a_caught_sliced_or_non_string_message_is_freed_w_2 {
        check_message_freed("managed");
    }
    run_cases(
        [
            (
                "a caught, sliced, or non-string message is freed with reference counting",
                check_a_caught_sliced_or_non_string_message_is_freed_w
            ),
            (
                "a caught, sliced, or non-string message is freed with cycle collection",
                check_a_caught_sliced_or_non_string_message_is_freed_w_2
            )
        ]
    );
}
