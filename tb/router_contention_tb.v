
`timescale 1ns/1ps

module router_contention_tb;

    reg clk = 0;
    reg rst = 1;

    // Router inputs: North=0, South=1, East=2, West=3, Local=4
    reg [55:0] north_in = 0;
    reg [55:0] south_in = 0;
    reg [55:0] east_in  = 0;
    reg [55:0] west_in  = 0;
    reg [55:0] local_in = 0;

    reg [4:0] in_valid = 0;
    wire [4:0] in_ready;

    wire [55:0] north_out;
    wire [55:0] south_out;
    wire [55:0] east_out;
    wire [55:0] west_out;
    wire [55:0] local_out;

    wire [4:0] out_valid;
    reg [4:0] out_ready = 0;

    reg [8:0] seen_ids = 0;
    integer count_north = 0;
    integer count_south = 0;
    integer count_west  = 0;
    integer errors = 0;
    integer k;
    integer expected_source;
    integer accepted_count = 0;

    reg [3:0] source_id;
    reg [7:0] packet_id;

    router_5port #(
        .DATA_WIDTH(56),
        .ROUTER_ID(5)
    ) dut (
        .clk(clk),
        .rst(rst),

        .north_in(north_in),
        .south_in(south_in),
        .east_in(east_in),
        .west_in(west_in),
        .local_in(local_in),

        .in_valid(in_valid),
        .in_ready(in_ready),

        .north_out(north_out),
        .south_out(south_out),
        .east_out(east_out),
        .west_out(west_out),
        .local_out(local_out),

        .out_valid(out_valid),
        .out_ready(out_ready)
    );

    always #5 clk = ~clk;

    function [55:0] make_packet;
        input [3:0] src;
        input [7:0] pid;
        begin
            make_packet = {
                src,
                4'd6,                 // Destination router 6: east of router 5
                pid,
                32'hA5000000 + pid,
                8'h00
            };
        end
    endfunction

    // Observe only successful east-output transfers.
    always @(posedge clk) begin
        if (!rst && out_valid[2] && out_ready[2]) begin
            source_id = east_out[55:52];
            packet_id = east_out[47:40];

            if (east_out[51:48] !== 4'd6) begin
                $display("FAIL: Wrong destination");
                errors = errors + 1;
            end
            else if (packet_id > 8) begin
                $display("FAIL: Unexpected packet ID %0d", packet_id);
                errors = errors + 1;
            end
            else if (seen_ids[packet_id]) begin
                $display("FAIL: Duplicate packet ID %0d", packet_id);
                errors = errors + 1;
            end
            else begin
                seen_ids[packet_id] = 1'b1;
                accepted_count = accepted_count + 1;

                case (source_id)
                    4'd0: count_north = count_north + 1;
                    4'd1: count_south = count_south + 1;
                    4'd3: count_west  = count_west + 1;
                    default: begin
                        $display("FAIL: Unexpected source %0d", source_id);
                        errors = errors + 1;
                    end
                endcase

                // Expected round-robin sequence: North, South, West.
                case (accepted_count % 3)
                    1: expected_source = 0;
                    2: expected_source = 1;
                    0: expected_source = 3;
                endcase

                if (source_id != expected_source) begin
                    $display(
                        "FAIL: Transfer %0d came from source %0d; expected %0d",
                        accepted_count, source_id, expected_source
                    );
                    errors = errors + 1;
                end
                else begin
                    $display(
                        "PASS: Transfer %0d, source %0d, packet ID %0d",
                        accepted_count, source_id, packet_id
                    );
                end
            end
        end
    end

    initial begin
        $display("=== ROUTER CONTENTION / FAIRNESS TEST START ===");

        repeat (3) @(negedge clk);
        rst = 0;

        // Hold the output stalled while all three input FIFOs are filled.
        out_ready = 0;

        for (k = 0; k < 3; k = k + 1) begin
            @(negedge clk);

            north_in = make_packet(4'd0, k);
            south_in = make_packet(4'd1, k + 3);
            west_in  = make_packet(4'd3, k + 6);

            // Request North, South, and West input FIFOs simultaneously.
            in_valid = 5'b01011;

            @(posedge clk);
            if (!(in_ready[0] && in_ready[1] && in_ready[3])) begin
                $display("FAIL: An input was not ready during injection");
                errors = errors + 1;
            end
        end

        @(negedge clk);
        in_valid = 0;

        // Now allow all competing packets to use the east output.
        out_ready = 5'b00100;

        repeat (30) @(negedge clk);

        if (accepted_count != 9) begin
            $display("FAIL: Only %0d of 9 packets transferred", accepted_count);
            errors = errors + 1;
        end

        if (seen_ids !== 9'b111111111) begin
            $display("FAIL: Packet bitmap = %b", seen_ids);
            errors = errors + 1;
        end

        if (count_north != 3 || count_south != 3 || count_west != 3) begin
            $display(
                "FAIL: Counts N=%0d S=%0d W=%0d",
                count_north, count_south, count_west
            );
            errors = errors + 1;
        end

        if (errors == 0) begin
            $display("PASS: All 9 packets transferred exactly once");
            $display("PASS: North, South, and West each received 3 turns");
            $display("PASS: Round-robin order verified");
            $display("ALL ROUTER CONTENTION TESTS PASSED");
        end
        else begin
            $display("ROUTER CONTENTION TEST FAILED: %0d errors", errors);
        end

        $finish;
    end

    initial begin
        #2000;
        $display("FAIL: Simulation timeout");
        $finish;
    end

endmodule
