`timescale 1ns / 1ps

module mesh_bfs_path_tb;

    reg [3:0] current_router;
    reg [3:0] dest_router;
    reg [63:0] link_up_map;
    reg [127:0] congestion_map;

    wire [2:0] next_port;
    wire route_valid;
    wire destination_reached;

    integer r;
    integer step;
    integer failures;
    integer trace_file;
    integer next_router;
    reg [15:0] visited;

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
        step = 0;
        visited = 16'b0;
        current_router = 0;
        dest_router = 15;
        link_up_map = 64'b0;
        congestion_map = 128'b0;

        trace_file = $fopen(
            "C:/NoC_Project/results/fault_route_trace.csv", "w");

        if (trace_file == 0) begin
            $display("ERROR: Cannot open fault_route_trace.csv");
            $finish;
        end

        $fdisplay(trace_file,
            "step,router_id,dest_id,next_port,route_valid");

        // Build the healthy mesh.
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

        // Fail physical link R0 <-> R4.
        link_up_map[0*4 + SOUTH] = 1'b0;
        link_up_map[4*4 + NORTH] = 1'b0;

        // Walk the route one hop at a time.
        for (step = 0; step < 16; step = step + 1) begin
            #2;

            if (current_router == dest_router) begin
                $display("PASS: Destination R15 reached in %0d hops", step);
                step = 16;
            end
            else if (route_valid !== 1'b1) begin
                $display("FAIL: No route at R%0d", current_router);
                failures = failures + 1;
                step = 16;
            end
            else begin
                if (visited[current_router]) begin
                    $display("FAIL: Route loop at R%0d", current_router);
                    failures = failures + 1;
                    step = 16;
                end
                else begin
                    visited[current_router] = 1'b1;

                    $fdisplay(trace_file, "%0d,%0d,%0d,%0d,%0d",
                        step, current_router, dest_router,
                        next_port, route_valid);

                    $display("Step %0d: R%0d -> port %0d",
                        step, current_router, next_port);

                    next_router = current_router;

                    case (next_port)
                        NORTH: next_router = current_router - 4;
                        SOUTH: next_router = current_router + 4;
                        EAST:  next_router = current_router + 1;
                        WEST:  next_router = current_router - 1;
                        default: begin
                            $display("FAIL: Invalid port before destination");
                            failures = failures + 1;
                            step = 16;
                        end
                    endcase

                    // Check bounds and physical link availability.
                    if (step < 16) begin
                        if (next_router < 0 || next_router > 15) begin
                            $display("FAIL: Router out of bounds");
                            failures = failures + 1;
                            step = 16;
                        end
                        else begin
                            case (next_port)
                                NORTH: if (!link_up_map[current_router*4+NORTH])
                                    failures = failures + 1;
                                SOUTH: if (!link_up_map[current_router*4+SOUTH])
                                    failures = failures + 1;
                                EAST: if (!link_up_map[current_router*4+EAST])
                                    failures = failures + 1;
                                WEST: if (!link_up_map[current_router*4+WEST])
                                    failures = failures + 1;
                            endcase

                            current_router = next_router;
                        end
                    end
                end
            end
        end

        if (current_router != dest_router && failures == 0) begin
            $display("FAIL: Destination not reached within hop limit");
            failures = failures + 1;
        end

        $fclose(trace_file);

        $display("Fault path failures: %0d", failures);
        if (failures == 0)
            $display("PASS: Complete fault-route walk");
        else
            $display("FAIL: Complete fault-route walk");

        $finish;
    end

endmodule
