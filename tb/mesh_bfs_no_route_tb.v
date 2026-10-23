
`timescale 1ns / 1ps

module mesh_bfs_no_route_tb;

    reg [3:0] current_router;
    reg [3:0] dest_router;
    reg [63:0] link_up_map;
    reg [127:0] congestion_map;

    wire [2:0] next_port;
    wire route_valid;
    wire destination_reached;

    integer failures;

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

        // Router 0 must reach router 15, but every link is down.
        current_router = 4'd0;
        dest_router = 4'd15;
        link_up_map = 64'b0;
        congestion_map = 128'b0;

        #2;

        if (route_valid !== 1'b0) begin
            $display("FAIL: Unreachable destination marked valid");
            failures = failures + 1;
        end
        else begin
            $display("PASS: Unreachable destination rejected");
        end

        if (destination_reached !== 1'b0) begin
            $display("FAIL: Destination falsely reported reached");
            failures = failures + 1;
        end
        else begin
            $display("PASS: Destination not falsely reported reached");
        end

        $display("NO_ROUTE test failures: %0d", failures);

        if (failures == 0)
            $display("PASS: NO_ROUTE test");
        else
            $display("FAIL: NO_ROUTE test");

        $finish;
    end

endmodule
