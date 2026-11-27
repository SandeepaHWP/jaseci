"""`jid` and bound endpoints over reclaimable native nodes and edges. The
graph kernel keeps a jid per live object, so the entry has to go wherever the
object's address is retired: a node or edge freed by its last reference, by a
disconnect, or with its region. Otherwise the next object allocated at that
address would answer with the dead one's id."""

import ctypes;
import from tests.support { compile_native, get_func, native_address, run_cases }

glob fixture = "graph_identity.jac";

def call(name: str, *args: int) -> int {
    (engine, _) = compile_native(fixture);
    fn = get_func(engine, name, ctypes.c_int64, *[ctypes.c_int64 for _ in args]);
    return fn(*args);
}

test "a node never connected takes its jid with it, and related cases" {
    def check_a_node_never_connected_takes_its_jid_with_it {
        got = call("loose_ids", 6);
        assert got == 6 , str(got);
    }

    def check_a_node_cut_loose_and_freed_takes_its_jid_with_it {
        got = call("cut_ids", 6);
        assert got == 6 , str(got);
    }

    def check_an_edge_freed_by_a_disconnect_takes_its_jid_with {
        got = call("edge_ids", 6);
        assert got == 6006 , str(got);
    }

    def check_an_edge_never_connected_takes_its_jid_with_it {
        got = call("loose_edge_ids", 6);
        assert got == 6 , str(got);
    }

    def check_a_bound_endpoint_holds_only_the_results_it_retur {
        got = call("endpoint_balance", 3);
        assert got == 270033 , str(got);
    }

    def check_a_region_s_nodes_and_edges_take_their_jids_with {
        got = call("region_ids", 6);
        assert got == 606 , str(got);
    }
    run_cases(
        [
            (
                "a node never connected takes its jid with it",
                check_a_node_never_connected_takes_its_jid_with_it
            ),
            (
                "a node cut loose and freed takes its jid with it",
                check_a_node_cut_loose_and_freed_takes_its_jid_with_it
            ),
            (
                "an edge freed by a disconnect takes its jid with it",
                check_an_edge_freed_by_a_disconnect_takes_its_jid_with
            ),
            (
                "an edge never connected takes its jid with it",
                check_an_edge_never_connected_takes_its_jid_with_it
            ),
            (
                "a bound endpoint holds only the results it returns",
                check_a_bound_endpoint_holds_only_the_results_it_retur
            ),
            (
                "a region's nodes and edges take their jids with the region",
                check_a_region_s_nodes_and_edges_take_their_jids_with
            )
        ]
    );
}


test "a jid stays with a held node and edge across a disconnect, and related cases" {
    def check_a_jid_stays_with_a_held_node_and_edge_across_a_d {
        got = call("stable_while_held");
        assert got == 110 , str(got);
    }

    def check_edges_a_bound_endpoint_returned_stay_valid_while {
        got = call("endpoint_edges_held");
        assert got == 701 , str(got);
    }

    def check_bound_endpoints_and_jid_release_temporary_operan {
        got = call("temporaries_released");
        assert got == 12311 , str(got);
    }
    run_cases(
        [
            (
                "a jid stays with a held node and edge across a disconnect",
                check_a_jid_stays_with_a_held_node_and_edge_across_a_d
            ),
            (
                "edges a bound endpoint returned stay valid while held",
                check_edges_a_bound_endpoint_returned_stay_valid_while
            ),
            (
                "bound endpoints and jid release temporary operands",
                check_bound_endpoints_and_jid_release_temporary_operan
            )
        ]
    );
}


test "a tuple or set endpoint is refused instead of being read as a list" {
    (engine, _) = compile_native("graph_identity_refused.jac");
    got = get_func(engine, "list_end", ctypes.c_int64)();
    assert got == 2 , str(got);
    assert native_address(engine, "tuple_end") == 0 , "tuple endpoint lowered";
    assert native_address(engine, "set_end") == 0 , "set endpoint lowered";
}
