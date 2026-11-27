"""`with Node entry` in a walker matched no node natively (it ran once, like
a bare `with entry`), and `Node`-typed collections compared nodes as
strings. The trigger now matches every node and `Node` lowers to an opaque
reference."""

import ctypes;
import from tests.support { compile_native, get_func, run_cases }

def call(name: str) -> int {
    (engine, _) = compile_native("node_trigger.jac");
    return get_func(engine, name, ctypes.c_int64)();
}

test "a Node-triggered walker ability runs at every node, and related cases" {
    def check_a_node_triggered_walker_ability_runs_at_every_no {
        got = call("sweep");
        assert got == 103 , str(got);
    }

    def check_nodes_held_as_node_keep_their_identity_in_collec {
        got = call("identity");
        assert got == 111111 , str(got);
    }
    run_cases(
        [
            (
                "a Node-triggered walker ability runs at every node",
                check_a_node_triggered_walker_ability_runs_at_every_no
            ),
            (
                "nodes held as Node keep their identity in collections",
                check_nodes_held_as_node_keep_their_identity_in_collec
            )
        ]
    );
}
