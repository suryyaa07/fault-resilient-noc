`timescale 1ns / 1ps

module mesh_bfs_congestion_tb;

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

// Build a symmetric, healthy 4x4 mesh.
        for (r = 0; r<16; r = r + 1) begin
            if (r / 4 > 0)
                link_up_map[r*4+NORTH] = 1'b1;
            if (r / 4<3)
                link_up_map[r*4+SOUTH] = 1'b1;
            if (r % 4<3)
                link_up_map[r*4+EAST] = 1'b1;
            if (r % 4 > 0)
                link_up_map[r*4+WEST] = 1'b1;
        end

        // Test 1: With zero congestion, the equal-cost tie selects EAST.
        #2;
        if (route_valid === 1'b1 && next_port === EAST) begin
            $display("PASS: Zero congestion selects EAST");
        end else begin
            $display("FAIL: Zero-congestion baseline, port=%0d valid=%b",
                     next_port, route_valid);
            failures = failures + 1;
        end

        // Test 2: Make the EAST link R0 <-> R1 highly congested.
        // The alternate SOUTH route should now be cheaper.
        congestion_map[0*8 + EAST*2 +: 2] = 2'd3;
        congestion_map[1*8 + WEST*2 +: 2] = 2'd3;

        #2;
        if (route_valid === 1'b1 && next_port === SOUTH) begin
            $display("PASS: Congestion changes route to SOUTH");
        end else begin
            $display("FAIL: Congestion rerouting, port=%0d valid=%b",
                     next_port, route_valid);
            failures = failures + 1;
        end

// Test 3: Disconnect all links.
        link_up_map = 64'b0;

        #2;

if (route_valid === 1'b0 &&
            destination_reached === 1'b0) begin
            $display("PASS: Disconnected network returns NO_ROUTE");
        end
        else begin
            $display("FAIL: NO_ROUTE test, valid=%b",
                     route_valid);
            failures = failures + 1;
        end

// Test 4: Local destination.
        current_router = 4'd5;
        dest_router = 4'd5;

        #2;

if (route_valid === 1'b1 &&
            destination_reached === 1'b1 &&
            next_port === LOCAL) begin
            $display("PASS: Local destination returns LOCAL");
        end
        else begin
            $display("FAIL: Local destination test");
            failures = failures + 1;
        end

$display("-------------------------------");
        $display("Total failures: %0d", failures);

if (failures == 0)
            $display("ALL CONGESTION TESTS PASSED");
        else
            $display("CONGESTION TESTS FAILED");

$finish;
    end

endmodule
