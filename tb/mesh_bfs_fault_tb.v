`timescale 1ns / 1ps

module mesh_bfs_fault_tb;
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
        link_up_map = 64'b0;
        congestion_map = 128'b0;

        // Build a fully connected 4x4 mesh.
        for (r = 0; r < 16; r = r + 1) begin
            if ((r / 4) > 0)
                link_up_map[r*4 + NORTH] = 1'b1;
            if ((r / 4) < 3)
                link_up_map[r*4 + SOUTH] = 1'b1;
            if ((r % 4) < 3)
                link_up_map[r*4 + EAST] = 1'b1;
            if ((r % 4) > 0)
                link_up_map[r*4 + 3] = 1'b1;
        end

                // Test 1: Baseline route should start EAST.
        // With equal link costs, deterministic tie-breaking selects EAST.
        #2;
        if (route_valid !== 1'b1 || next_port !== EAST) begin
            $display("FAIL: Baseline route, port=%0d valid=%b",
                     next_port, route_valid);
            failures = failures + 1;
        end else begin
            $display("PASS: Baseline route starts EAST");
        end

        // Test 2: Disable physical link R0 <-> R4.
        // R0 SOUTH bit and R4 NORTH bit.
        link_up_map[1]  = 1'b0;
        link_up_map[16] = 1'b0;

        #2;
        if (route_valid !== 1'b1 ||
            next_port !== EAST ||
            destination_reached !== 1'b0) begin
            $display("FAIL: Fault route, port=%0d valid=%b reached=%b",
                     next_port, route_valid, destination_reached);
            failures = failures + 1;
        end else begin
            $display("PASS: Failed link avoided; route starts EAST");
        end

        $display("-------------------------------");
        $display("Fault test failures: %0d", failures);
        if (failures == 0)
            $display("PASS: Fault-routing test");
        else
            $display("FAIL: Fault-routing test");
        $display("-------------------------------");

        $finish;
    end
endmodule
