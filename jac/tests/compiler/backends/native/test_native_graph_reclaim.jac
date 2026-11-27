"""Managed native nodes and edges are reclaimed once nothing refers to them.
A live edge row pins both endpoints and its edge object, so a connected
subgraph stays alive until it is disconnected or destroyed. Nodes and edges
used to be immortal, so a program that built and dropped graphs (a game
loading level after level) kept every node, edge and everything they held
for its whole run, even after destroying them."""

import ctypes;
import from tests.support { compile_native, get_func, run_cases }

glob fixture = "graph_reclaim.jac";

def call(name: str, *args: int) -> int {
    (engine, _) = compile_native(fixture);
    fn = get_func(engine, name, ctypes.c_int64, *[ctypes.c_int64 for _ in args]);
    return fn(*args);
}

test "a node never connected is freed with its last reference, and related cases" {
    def check_a_node_never_connected_is_freed_with_its_last_re {
        got = call("loose", 5);
        assert got == 5 , str(got);
    }

    def check_connected_nodes_stay_alive_while_the_graph_holds {
        got = call("held", 4);
        assert got == 10 , str(got);
    }

    def check_disconnecting_frees_a_target_and_edge_nothing_el {
        got = call("cut", 3);
        assert got == 33 , str(got);
    }

    def check_destroying_a_subgraph_reclaims_its_nodes_and_edg {
        got = call("destroy_tree", 3);
        assert got == 706 , str(got);
    }

    def check_a_walk_over_a_chain_visits_each_node_once_and_fr {
        got = call("tour", 5);
        assert got == 601 , str(got);
    }

    def check_a_reused_node_address_starts_with_a_clean_graph {
        got = call("reuse", 4);
        assert got == 4 , str(got);
    }

    def check_a_connected_subgraph_keeps_itself_alive_until_it {
        got = call("destroyed_tree", 5);
        assert got == 99 , str(got);
    }

    def check_destroying_a_subgraph_reclaims_its_nodes_and_edg_2 {
        got = call("teardown_tree", 5);
        assert got == 11010 , str(got);
    }

    def check_a_program_destroying_each_world_before_the_next {
        got = call("levels", 20);
        assert got == 1920100 , str(got);
    }
    run_cases(
        [
            (
                "a node never connected is freed with its last reference",
                check_a_node_never_connected_is_freed_with_its_last_re
            ),
            (
                "connected nodes stay alive while the graph holds them",
                check_connected_nodes_stay_alive_while_the_graph_holds
            ),
            (
                "disconnecting frees a target and edge nothing else refers to",
                check_disconnecting_frees_a_target_and_edge_nothing_el
            ),
            (
                "destroying a subgraph reclaims its nodes and edges",
                check_destroying_a_subgraph_reclaims_its_nodes_and_edg
            ),
            (
                "a walk over a chain visits each node once and frees nothing",
                check_a_walk_over_a_chain_visits_each_node_once_and_fr
            ),
            (
                "a reused node address starts with a clean graph entry",
                check_a_reused_node_address_starts_with_a_clean_graph
            ),
            (
                "a connected subgraph keeps itself alive until it is destroyed",
                check_a_connected_subgraph_keeps_itself_alive_until_it
            ),
            (
                "destroying a subgraph reclaims its nodes and edges",
                check_destroying_a_subgraph_reclaims_its_nodes_and_edg_2
            ),
            (
                "a program destroying each world before the next keeps only the current one",
                check_a_program_destroying_each_world_before_the_next
            )
        ]
    );
}


test "a variable keeps a disconnected node alive, and related cases" {
    def check_a_variable_keeps_a_disconnected_node_alive {
        got = call("kept_by_variable");
        assert got == 51 , str(got);
    }

    def check_a_walk_keeps_nodes_it_queued_alive_when_an_abili {
        got = call("walk_cut");
        assert got == 321 , str(got);
    }

    def check_edge_objects_read_back_from_the_graph_stay_valid {
        got = call("edges_held");
        assert got == 701 , str(got);
    }

    def check_an_edge_keeps_its_source_reachable_from_the_targ {
        got = call("backward_reach");
        assert got == 150 , str(got);
    }

    def check_a_node_two_parents_point_to_lives_until_both_edg {
        got = call("shared_child");
        assert got == 301 , str(got);
    }

    def check_graph_operations_release_temporary_nodes {
        got = call("temporaries_released");
        assert got == 11111 , str(got);
    }
    run_cases(
        [
            (
                "a variable keeps a disconnected node alive",
                check_a_variable_keeps_a_disconnected_node_alive
            ),
            (
                "a walk keeps nodes it queued alive when an ability cuts them loose",
                check_a_walk_keeps_nodes_it_queued_alive_when_an_abili
            ),
            (
                "edge objects read back from the graph stay valid while held",
                check_edge_objects_read_back_from_the_graph_stay_valid
            ),
            (
                "an edge keeps its source reachable from the target",
                check_an_edge_keeps_its_source_reachable_from_the_targ
            ),
            (
                "a node two parents point to lives until both edges are gone",
                check_a_node_two_parents_point_to_lives_until_both_edg
            ),
            (
                "graph operations release temporary nodes",
                check_graph_operations_release_temporary_nodes
            )
        ]
    );
}
