
`timescale 1ns/1ps

module router_fifo_test_tb;

    reg clk = 0;
    reg rst = 1;

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

    integer i;
    integer errors = 0;
    integer received = 0;
    integer timeout_count;

    reg [3:0] seen = 0;
    reg [55:0] packet;

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
        input [7:0] pid;
        begin
            make_packet = {
                4'd0,
                4'd6,
                pid,
                32'h12340000 + pid,
                8'h00
            };
        end
    endfunction

    // Monitor packets accepted at the east output.
    always @(posedge clk) begin
        if (!rst && out_valid[2] && out_ready[2]) begin
            packet = east_out;

            if (packet[47:40] > 3) begin
                $display("FAIL: Unexpected packet ID %0d", packet[47:40]);
                errors = errors + 1;
            end
            else if (seen[packet[41:40]]) begin
                $display("FAIL: Duplicate packet ID %0d", packet[47:40]);
                errors = errors + 1;
            end
            else begin
                seen[packet[41:40]] = 1'b1;
                received = received + 1;
                $display("PASS: Packet ID %0d received", packet[47:40]);
            end
        end
    end

    initial begin
        $display("=== ROUTER FIFO SATURATION TEST START ===");

        repeat (3) @(negedge clk);
        rst = 0;

        // Block the east output so the input FIFO cannot drain.
        out_ready = 5'b00000;

        // Fill the North input FIFO with four packets.
        for (i = 0; i < 4; i = i + 1) begin
            @(negedge clk);
            north_in = make_packet(i);
            in_valid = 5'b00001;

            @(posedge clk);
            if (in_ready[0] !== 1'b1) begin
                $display("FAIL: FIFO unexpectedly not ready for packet %0d", i);
                errors = errors + 1;
            end
        end

        @(negedge clk);
        in_valid = 0;

        // Allow one extra clock for the fourth write to settle.
        @(negedge clk);

        if (in_ready[0] !== 1'b0) begin
            $display("FAIL: North input did not become full");
            errors = errors + 1;
        end
        else begin
            $display("PASS: North input FIFO is full after 4 packets");
        end

        // The full FIFO must not accept another packet.
        north_in = make_packet(4);
        in_valid = 5'b00001;

        @(posedge clk);
        if (in_ready[0] !== 1'b0) begin
            $display("FAIL: Full FIFO incorrectly advertised ready");
            errors = errors + 1;
        end
        else begin
            $display("PASS: Full FIFO applies backpressure");
        end

        @(negedge clk);
        in_valid = 0;

        // Release the output so queued packets can drain.
        out_ready = 5'b00100;

        timeout_count = 0;
        while (received < 4 && timeout_count < 50) begin
            @(negedge clk);
            timeout_count = timeout_count + 1;
        end

        if (received != 4) begin
            $display("FAIL: Received only %0d of 4 packets", received);
            errors = errors + 1;
        end

        // FIFO should accept data again after it drains.
        @(negedge clk);
        if (in_ready[0] !== 1'b1) begin
            $display("FAIL: FIFO did not become ready after draining");
            errors = errors + 1;
        end
        else begin
            $display("PASS: FIFO becomes ready after draining");
        end

        if (errors == 0 && received == 4 && seen == 4'b1111) begin
            $display("ALL ROUTER FIFO SATURATION TESTS PASSED");
        end
        else begin
            $display("FIFO SATURATION TEST FAILED: errors=%0d", errors);
        end

        $finish;
    end

    initial begin
        #2000;
        $display("FAIL: Simulation timeout");
        $finish;
    end

endmodule
