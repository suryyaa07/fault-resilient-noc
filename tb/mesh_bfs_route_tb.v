`timescale 1ns / 1ps

module mesh_bfs_route_tb;

    reg [3:0] current_router;
    reg [3:0] dest_router;
    reg [63:0] link_up_map;
    reg [127:0] congestion_map;

    wire [2:0] next_port;
    wire route_valid;
    wire destination_reached;

    localparam [2:0] NORTH = 3'd0;
    localparam [2:0] SOUTH = 3'd1;
    localparam [2:0] EAST  = 3'd2;
    localparam [2:0] WEST  = 3'd3;
    localparam [2:0] LOCAL = 3'd4;

    integer passed = 0;
    integer failed = 0;
    integer r;

    mesh_bfs_route dut (
        .current_router(current_router),
        .dest_router(dest_router),
        .link_up_map(link_up_map),
        .congestion_map(congestion_map),
        .next_port(next_port),
        .route_valid(route_valid),
        .destination_reached(destination_reached)
    );

    task check_result;
        input [8*40-1:0] test_name;
        input [2:0] expected_port;
        input expected_valid;
        input expected_reached;
        begin
            #1;
            if ((next_port === expected_port) &&
                (route_valid === expected_valid) &&
                (destination_reached === expected_reached)) begin
                $display("PASS: %0s", test_name);
                passed = passed + 1;
            end
            else begin
                $display("FAIL: %0s", test_name);
                $display("  expected port=%0d valid=%b reached=%b",
                         expected_port, expected_valid, expected_reached);
                $display("  actual   port=%0d valid=%b reached=%b",
                         next_port, route_valid, destination_reached);
                failed = failed + 1;
            end
        end
    endtask

    initial begin
        $display("Starting mesh_bfs_route tests...");

        // Start with all links unavailable.
        link_up_map = 64'b0;
        congestion_map = 128'b0;

        // Test 1: local delivery.
        current_router = 5;
        dest_router = 5;
        check_result("LOCAL destination", LOCAL, 1'b1, 1'b1);

        // Test 2: direct EAST link from router 0 to router 1.
        // Router 0 EAST is bit 2 of its four-bit slice.
        link_up_map = 64'b0;
        link_up_map[2] = 1'b1;
        link_up_map[4 + 3] = 1'b1; // Router 1 WEST
        current_router = 0;
        dest_router = 1;
        check_result("Direct EAST path", EAST, 1'b1, 1'b0);


        // Test 3: direct EAST is blocked, but a detour exists:
        // 0 -> 4 (SOUTH) -> 5 (EAST) -> 1 (NORTH).
        link_up_map = 64'b0;

        // Physical link 0 <-> 4 (SOUTH/NORTH).
        link_up_map[0*4 + 1] = 1'b1;
        link_up_map[4*4 + 0] = 1'b1;

        // Physical link 4 <-> 5 (EAST/WEST).
        link_up_map[4*4 + 2] = 1'b1;
        link_up_map[5*4 + 3] = 1'b1;

        // Physical link 5 <-> 1 (NORTH/SOUTH).
        link_up_map[5*4 + 0] = 1'b1;
        link_up_map[1*4 + 1] = 1'b1;

        // Direct link 0 <-> 1 remains disabled.
        current_router = 0;
        dest_router = 1;
        check_result("Detour around failed EAST", SOUTH, 1'b1, 1'b0);


        // Test 4: destination is disconnected.
        link_up_map = 64'b0;
        current_router = 0;
        dest_router = 15;
        check_result("Unreachable destination", LOCAL, 1'b0, 1'b0);

        // Test 5: a healthy path around a blocked direct route.
        // 0 -> 4 -> 8 -> 9 -> 10 -> 6 -> 2 -> 3
        // This checks that BFS can explore beyond one extra hop.
        link_up_map = 64'b0;
        link_up_map[0*4 + 1] = 1'b1; link_up_map[4*4 + 0] = 1'b1;
        link_up_map[4*4 + 1] = 1'b1; link_up_map[8*4 + 0] = 1'b1;
        link_up_map[8*4 + 2] = 1'b1; link_up_map[9*4 + 3] = 1'b1;
        link_up_map[9*4 + 2] = 1'b1; link_up_map[10*4 + 3] = 1'b1;
        link_up_map[10*4 + 0] = 1'b1; link_up_map[6*4 + 1] = 1'b1;
        link_up_map[6*4 + 0] = 1'b1; link_up_map[2*4 + 1] = 1'b1;
        link_up_map[2*4 + 2] = 1'b1; link_up_map[3*4 + 3] = 1'b1;
        current_router = 0;
        dest_router = 3;
        check_result("Longer reachable path", SOUTH, 1'b1, 1'b0);

        $display("--------------------------------");
        $display("Tests passed: %0d", passed);
        $display("Tests failed: %0d", failed);

        if (failed == 0)
            $display("ALL TESTS PASSED");
        else
            $display("SOME TESTS FAILED");

        $finish;
    end

endmodule
