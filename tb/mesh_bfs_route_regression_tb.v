
`timescale 1ns / 1ps

module mesh_bfs_route_regression_tb;

    reg [3:0] current_router;
    reg [3:0] dest_router;
    reg [63:0] link_up_map;
    reg [127:0] congestion_map;

    wire [2:0] next_port;
    wire route_valid;
    wire destination_reached;

    integer r;
    integer failures;

    localparam NORTH = 0;
    localparam SOUTH = 1;
    localparam EAST  = 2;
    localparam WEST  = 3;
    localparam LOCAL = 4;

    mesh_bfs_route dut (
        .current_router(current_router),
        .dest_router(dest_router),
        .link_up_map(link_up_map),
        .congestion_map(congestion_map),
        .next_port(next_port),
        .route_valid(route_valid),
        .destination_reached(destination_reached)
    );

    initial begin
        failures = 0;
        current_router = 0;
        dest_router = 15;
        link_up_map = 0;
        congestion_map = 0;

        // Construct the healthy 4x4 mesh.
        for (r = 0; r < 16; r = r + 1) begin
            if ((r / 4) > 0)
                link_up_map[r*4 + NORTH] = 1'b1;
            if ((r / 4) < 3)
                link_up_map[r*4 + SOUTH] = 1'b1;
            if ((r % 4) < 3)
                link_up_map[r*4 + EAST] = 1'b1;
            if ((r % 4) > 0)
                link_up_map[r*4 + WEST] = 1'b1;
        end

        #2;

                // Test 1: healthy mesh.
        // With equal link costs, deterministic tie-breaking selects EAST.
        if (route_valid === 1'b1 && next_port === EAST) begin
            $display("PASS: Healthy mesh route starts EAST");
        end else begin
            $display("FAIL: Healthy mesh route");
            failures = failures + 1;
        end

        // Test 2: disable both ends of physical link R0-R4.
        link_up_map[0*4 + SOUTH] = 1'b0;
        link_up_map[4*4 + NORTH] = 1'b0;

        #2;

        if (route_valid === 1'b1 &&
            next_port === EAST &&
            destination_reached === 1'b0) begin
            $display("PASS: Failed link avoided; route starts EAST");
        end else begin
            $display("FAIL: Fault rerouting, port=%0d valid=%b",
                     next_port, route_valid);
            failures = failures + 1;
        end

        // Test 3: disconnect the entire mesh.
        link_up_map = 64'b0;

        #2;

        if (route_valid === 1'b0 &&
            destination_reached === 1'b0) begin
            $display("PASS: Disconnected destination returns NO_ROUTE");
        end else begin
            $display("FAIL: NO_ROUTE, valid=%b reached=%b",
                     route_valid, destination_reached);
            failures = failures + 1;
        end

        $display("-------------------------------");
        $display("Total failures: %0d", failures);

        if (failures == 0)
            $display("ALL REGRESSION TESTS PASSED");
        else
            $display("REGRESSION FAILED");

        $finish;
    end

endmodule
