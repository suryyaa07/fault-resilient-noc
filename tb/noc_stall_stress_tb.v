
`timescale 1ns/1ps

module noc_stall_stress_tb;

    reg clk = 0;
    reg rst = 1;

    reg [15:0] local_valid = 0;
    reg [16*56-1:0] local_packets = 0;
    wire [15:0] local_ready;

    wire [15:0] delivered_valid;
    reg [15:0] delivered_ready = 16'hFFFF;
    wire [16*56-1:0] delivered_packets;

    reg [3:0] src [0:3];
    reg [3:0] dst [0:3];
    reg [55:0] pkt [0:3];
    integer count [0:3];
    integer i, k, cycles, errors;
    reg accepted;
    reg [15:0] seen_stalled;

    always #5 clk = ~clk;

    noc_4x4 #(.DATA_WIDTH(56)) dut (
        .clk(clk), .rst(rst),
        .local_valid(local_valid),
        .local_packets(local_packets),
        .local_ready(local_ready),
        .delivered_valid(delivered_valid),
        .delivered_ready(delivered_ready),
        .delivered_packets(delivered_packets)
    );

    // Count each packet only when its destination accepts it.
    always @(posedge clk) begin
        if (!rst) begin
            for (k = 0; k < 4; k = k + 1) begin
                if (delivered_valid[dst[k]] &&
                    delivered_ready[dst[k]] &&
                    delivered_packets[dst[k]*56 +: 56] === pkt[k])
                    count[k] = count[k] + 1;
            end
        end
    end

    initial begin
        $display("=== DESTINATION STALL STRESS TEST ===");
        errors = 0;
        seen_stalled = 0;

        src[0]=0; dst[0]=10;
        src[1]=1; dst[1]=11;
        src[2]=2; dst[2]=3;
        src[3]=4; dst[3]=15;

        for (i=0; i<4; i=i+1) begin
            pkt[i] = {src[i], dst[i],
                      (8'h50 + i[7:0]),
                      (32'hABCD0000 + i), 8'h00};
            count[i] = 0;
        end

        repeat (5) @(negedge clk);
        rst = 0;

        // Block destinations 10 and 3 before injecting traffic.
        delivered_ready[10] = 0;
        delivered_ready[3]  = 0;

        // Inject each packet once; hold valid until ready.
        for (i=0; i<4; i=i+1) begin
            accepted = 0;
            cycles = 0;

            @(negedge clk);
            local_packets[src[i]*56 +: 56] = pkt[i];
            local_valid[src[i]] = 1;

            while (!accepted && cycles < 20) begin
                @(posedge clk);
                if (local_ready[src[i]] === 1'b1)
                    accepted = 1;
                cycles = cycles + 1;
            end

            @(negedge clk);
            local_valid[src[i]] = 0;

            if (accepted)
                $display("PASS: Packet %0d accepted", i);
            else begin
                $display("FAIL: Packet %0d not accepted", i);
                errors = errors + 1;
            end
        end

        // Wait for blocked packets to appear at their outputs.
        repeat (30) @(negedge clk);

        if (delivered_valid[10] && !delivered_ready[10])
            seen_stalled[10] = 1;
        if (delivered_valid[3] && !delivered_ready[3])
            seen_stalled[3] = 1;

        if (seen_stalled[10])
            $display("PASS: Destination 10 holds a packet");
        else begin
            $display("FAIL: No packet observed held at destination 10");
            errors = errors + 1;
        end

        if (seen_stalled[3])
            $display("PASS: Destination 3 holds a packet");
        else begin
            $display("FAIL: No packet observed held at destination 3");
            errors = errors + 1;
        end

        // Release stalls.
        @(negedge clk);
        delivered_ready[10] = 1;
        delivered_ready[3]  = 1;

        repeat (100) @(posedge clk);
        @(negedge clk);

        for (i=0; i<4; i=i+1) begin
            $display("Packet %0d deliveries: %0d", i, count[i]);
            if (count[i] != 1)
                errors = errors + 1;
        end

        if (errors == 0)
            $display("ALL DESTINATION STALL TESTS PASSED");
        else
            $display("DESTINATION STALL TEST FAILED: %0d errors", errors);

        $finish;
    end

    initial begin
        #10000;
        $display("ERROR: Watchdog timeout");
        $finish;
    end

endmodule
