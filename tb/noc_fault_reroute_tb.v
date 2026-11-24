`timescale 1ns/1ps

module noc_fault_reroute_tb;

    reg clk = 0;
    reg rst = 1;

    reg fault_enable = 1;
    reg [3:0] fault_router_a = 1;
    reg [3:0] fault_router_b = 2;

    reg [15:0] local_valid = 0;
    reg [16*56-1:0] local_packets = 0;
    wire [15:0] local_ready;

    wire [15:0] delivered_valid;
    reg [15:0] delivered_ready = 16'hFFFF;
    wire [16*56-1:0] delivered_packets;

    reg [55:0] packet;
    reg accepted = 0;
    reg received = 0;
    integer i;
    integer wait_count = 0;
    integer delivery_count = 0;

    noc_4x4 #(.DATA_WIDTH(56)) dut (
        .clk(clk),
        .rst(rst),
        .fault_enable(fault_enable),
        .fault_router_a(fault_router_a),
        .fault_router_b(fault_router_b),
        .local_valid(local_valid),
        .local_packets(local_packets),
        .local_ready(local_ready),
        .delivered_valid(delivered_valid),
        .delivered_ready(delivered_ready),
        .delivered_packets(delivered_packets)
    );

    always #5 clk = ~clk;

    // FAULT ROUTE TRACE: print successful directional transfers
    // for the packet injected by this testbench.
    genvar trace_r;
    generate
        for (trace_r = 0; trace_r < 16; trace_r = trace_r + 1) begin : ROUTE_TRACE
            always @(posedge clk) begin
                if (!rst) begin
                    if (dut.valid_out[trace_r][0] === 1'b1 &&
                        dut.ready_out[trace_r][0] === 1'b1 &&
                        dut.north_out[trace_r][51:48] == 4'd3 &&
                        dut.north_out[trace_r][39:8] == 32'h1234ABCD)
                        $display("ROUTE TRACE: Router %0d --NORTH--> Router %0d at %0t ns",
                                 trace_r, trace_r-4, $time);

                    if (dut.valid_out[trace_r][1] === 1'b1 &&
                        dut.ready_out[trace_r][1] === 1'b1 &&
                        dut.south_out[trace_r][51:48] == 4'd3 &&
                        dut.south_out[trace_r][39:8] == 32'h1234ABCD)
                        $display("ROUTE TRACE: Router %0d --SOUTH--> Router %0d at %0t ns",
                                 trace_r, trace_r+4, $time);

                    if (dut.valid_out[trace_r][2] === 1'b1 &&
                        dut.ready_out[trace_r][2] === 1'b1 &&
                        dut.east_out[trace_r][51:48] == 4'd3 &&
                        dut.east_out[trace_r][39:8] == 32'h1234ABCD)
                        $display("ROUTE TRACE: Router %0d --EAST--> Router %0d at %0t ns",
                                 trace_r, trace_r+1, $time);

                    if (dut.valid_out[trace_r][3] === 1'b1 &&
                        dut.ready_out[trace_r][3] === 1'b1 &&
                        dut.west_out[trace_r][51:48] == 4'd3 &&
                        dut.west_out[trace_r][39:8] == 32'h1234ABCD)
                        $display("ROUTE TRACE: Router %0d --WEST--> Router %0d at %0t ns",
                                 trace_r, trace_r-1, $time);
                end
            end
        end
    endgenerate

    initial begin
        $display("=== NOC FAULT REROUTING TEST ===");
        $display("Source: Router 0; Destination: Router 3");
        $display("Failed link: Router 1 <-> Router 2");

        packet = {4'd0, 4'd3, 8'hA5, 32'h1234ABCD, 8'h00};

        repeat (3) @(negedge clk);
        rst = 0;

        // Inject one packet at router 0 and hold valid until accepted.
        @(negedge clk);
        local_packets[0 +: 56] = packet;
        local_valid[0] = 1'b1;

        wait_count = 0;
        while ((accepted == 0) && (wait_count < 20)) begin
            @(posedge clk);
            if (local_ready[0] === 1'b1)
                accepted = 1;
            wait_count = wait_count + 1;
        end

        @(negedge clk);
        local_valid[0] = 1'b0;

        if (accepted == 0) begin
            $display("FAIL: Source router did not accept packet");
            $finish;
        end

        $display("PASS: Source router accepted packet");

        // Wait for delivery while the selected link remains faulty.
        for (i = 0; i < 100; i = i + 1) begin
            @(posedge clk);
            if (delivered_valid[3] && delivered_ready[3]) begin
                delivery_count = delivery_count + 1;
                if (delivered_packets[3*56 +: 56] === packet) begin
                    received = 1;
                    $display("PASS: Correct packet reached router 3");
                end else begin
                    $display("FAIL: Packet data mismatch");
                end
            end
        end

        if (received && delivery_count == 1) begin
            $display("PASS: Packet delivered exactly once with link 1-2 disabled");
            $display("ALL FAULT REROUTING TESTS PASSED");
        end else begin
            $display("FAIL: received=%0d deliveries=%0d",
                     received, delivery_count);
        end

        $finish;
    end

endmodule