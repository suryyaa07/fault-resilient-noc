`timescale 1ns / 1ps

module mesh_bfs_trace_tb;

    reg [3:0] current_router;
    reg [3:0] dest_router;
    reg [63:0] link_up_map;
    reg [127:0] congestion_map;

    wire [2:0] next_port;
    wire route_valid;
    wire destination_reached;

    integer trace_file;
    integer cycle;
    integer r;
    integer d;
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

    function [55:0] port_name;
        input [2:0] port;
        begin
            case (port)
                3'd0: port_name = "NORTH";
                3'd1: port_name = "SOUTH";
                3'd2: port_name = "EAST";
                3'd3: port_name = "WEST";
                3'd4: port_name = "LOCAL";
                default: port_name = "INVALID";
            endcase
        end
    endfunction

    task log_event;
        input integer router_id;
        input integer destination_id;
        begin
            current_router = router_id;
            dest_router = destination_id;
            #2;

            if (route_valid !== 1'b1) begin
                $display(
                    "FAIL: No route from R%0d to R%0d",
                    router_id, destination_id
                );
                failures = failures + 1;
            end

            if (router_id == destination_id) begin
                if (destination_reached !== 1'b1 ||
                    next_port !== 3'd4) begin
                    $display(
                        "FAIL: Incorrect LOCAL result at R%0d",
                        router_id
                    );
                    failures = failures + 1;
                end
            end
            else begin
                if (destination_reached !== 1'b0) begin
                    $display(
                        "FAIL: Incorrect destination flag R%0d -> R%0d",
                        router_id, destination_id
                    );
                    failures = failures + 1;
                end

                if (next_port == 3'd4 ||
                    next_port > 3'd3) begin
                    $display(
                        "FAIL: Invalid directional port R%0d -> R%0d",
                        router_id, destination_id
                    );
                    failures = failures + 1;
                end
            end

            $fdisplay(trace_file, "%0d,%0d,%0d,%0s,%0d,%0d",
                cycle, router_id, destination_id,
                port_name(next_port), route_valid, 0);

            cycle = cycle + 1;
        end
    endtask

    initial begin
        failures = 0;
        cycle = 1;

        current_router = 0;
        dest_router = 0;
        link_up_map = 64'b0;
        congestion_map = 128'b0;

        trace_file = $fopen(
            "C:/NoC_Project/results/xsim_trace.csv", "w"
        );

        if (trace_file == 0) begin
            $display("ERROR: Could not open trace output file.");
            $finish;
        end

        $fdisplay(trace_file,
            "cycle,router_id,dest_id,next_port,route_valid,congestion");

        // Configure all valid in-grid directions as healthy.
        for (r = 0; r < 16; r = r + 1) begin
            if ((r / 4) > 0)
                link_up_map[r*4 + 0] = 1'b1;

            if ((r / 4) < 3)
                link_up_map[r*4 + 1] = 1'b1;

            if ((r % 4) < 3)
                link_up_map[r*4 + 2] = 1'b1;

            if ((r % 4) > 0)
                link_up_map[r*4 + 3] = 1'b1;
        end

        // Generate one decision for every source/destination pair.
        for (d = 0; d < 16; d = d + 1) begin
            for (r = 0; r < 16; r = r + 1) begin
                log_event(r, d);
            end
        end

        $fclose(trace_file);

        $display("--------------------------------");
        $display("Routing decisions recorded: %0d", cycle - 1);
        $display("Failed checks: %0d", failures);
        $display("--------------------------------");

        if (failures == 0)
            $display("PASS: All-pairs trace generation");
        else
            $display("FAIL: All-pairs trace generation");

        $finish;
    end

endmodule
