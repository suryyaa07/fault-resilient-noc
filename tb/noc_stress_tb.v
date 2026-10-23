`timescale 1ns/1ps

module noc_stress_tb;

    reg clk;
    reg rst;

    reg [15:0] local_valid;
    reg [16*56-1:0] local_packets;
    wire [15:0] local_ready;

    wire [15:0] delivered_valid;
    reg [15:0] delivered_ready;
    wire [16*56-1:0] delivered_packets;

    reg [3:0] src [0:7];
    reg [3:0] dst [0:7];
    reg [55:0] packets [0:7];

    integer delivery_count [0:7];
    integer i;
    integer j;
    integer cycles;
    integer errors;
    reg accepted;

    noc_4x4 #(
        .DATA_WIDTH(56)
    ) dut (
        .clk(clk),
        .rst(rst),
        .local_valid(local_valid),
        .local_packets(local_packets),
        .local_ready(local_ready),
        .delivered_valid(delivered_valid),
        .delivered_ready(delivered_ready),
        .delivered_packets(delivered_packets)
    );

    // 10 ns clock
    initial clk = 0;
    always #5 clk = ~clk;

    // Count successful packet deliveries
    always @(posedge clk) begin
        if (!rst) begin
            for (integer k = 0; k < 8; k = k + 1) begin
                if (delivered_valid[dst[k]] &&
                    delivered_ready[dst[k]] &&
                    delivered_packets[dst[k]*56 +: 56] === packets[k]) begin

                    delivery_count[k] = delivery_count[k] + 1;

                    $display(
                        "OBSERVED: Packet %0d delivered at router %0d",
                        k, dst[k]
                    );
                end
            end
        end
    end

    initial begin
        $display("=== NOC MULTI-PACKET STRESS TEST START ===");

        rst = 1;
        local_valid = 16'b0;
        local_packets = {(16*56){1'b0}};
        delivered_ready = 16'hFFFF;
        errors = 0;

        // Packet sources and destinations
        src[0] = 0;  dst[0] = 10;
        src[1] = 1;  dst[1] = 11;
        src[2] = 2;  dst[2] = 3;
        src[3] = 4;  dst[3] = 15;
        src[4] = 8;  dst[4] = 2;
        src[5] = 12; dst[5] = 7;
        src[6] = 3;  dst[6] = 12;
        src[7] = 6;  dst[7] = 5;

        for (i = 0; i < 8; i = i + 1) begin
            packets[i] = {
    src[i],
    dst[i],
    (8'h40 + i[7:0]),
    (32'h12340000 + i),
    8'h00
};
            delivery_count[i] = 0;
        end

        // Reset
        repeat (5) @(negedge clk);
        rst = 0;
        repeat (2) @(negedge clk);

        // Inject each packet exactly once
        for (i = 0; i < 8; i = i + 1) begin
            accepted = 0;
            cycles = 0;

            @(negedge clk);
            local_packets[src[i]*56 +: 56] = packets[i];
            local_valid[src[i]] = 1'b1;

            // Wait for one valid/ready handshake
            while (!accepted && cycles < 20) begin
                @(posedge clk);

                if (local_ready[src[i]] === 1'b1)
                    accepted = 1;

                cycles = cycles + 1;
            end

            // Deassert valid on a falling edge
            @(negedge clk);
            local_valid[src[i]] = 1'b0;

            if (accepted)
                $display(
                    "PASS: Packet %0d accepted by router %0d",
                    i, src[i]
                );
            else begin
                $display(
                    "FAIL: Packet %0d was not accepted",
                    i
                );
                errors = errors + 1;
            end
        end

        // Allow packets to travel through the mesh
        repeat (150) @(posedge clk);
        @(negedge clk);

        $display("");
        $display("=== DELIVERY COUNTS ===");

        for (i = 0; i < 8; i = i + 1) begin
            $display(
                "Packet %0d: %0d deliveries (destination %0d)",
                i, delivery_count[i], dst[i]
            );

            if (delivery_count[i] == 1)
                $display("PASS: Packet %0d delivered exactly once", i);
            else begin
                $display(
                    "FAIL: Packet %0d delivered %0d times",
                    i, delivery_count[i]
                );
                errors = errors + 1;
            end
        end

        $display("");
        if (errors == 0)
            $display("ALL NOC STRESS TESTS PASSED");
        else
            $display("NOC STRESS TEST FAILED: %0d errors", errors);

        $finish;
    end

    // Watchdog prevents an accidental endless simulation
    initial begin
        #10000;
        $display("ERROR: Simulation watchdog timeout");
        $finish;
    end

endmodule