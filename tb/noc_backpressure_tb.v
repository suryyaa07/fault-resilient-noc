
`timescale 1ns/1ps

module noc_backpressure_tb;

    reg clk;
    reg rst;

    reg [15:0] local_valid;
    reg [16*56-1:0] local_packets;

    wire [15:0] local_ready;
    reg [15:0] delivered_ready;
    wire [15:0] delivered_valid;
    wire [16*56-1:0] delivered_packets;

    wire local0_ready;
    assign local0_ready = local_ready[0];

    reg [55:0] packets [0:7];
    reg [7:0] received;

    integer i;
    integer cycles;
    integer received_count;
    integer wait_count;
    integer monitor_i;
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

    always #5 clk = ~clk;

    // Monitor packet delivery to router 15.
    always @(posedge clk) begin
        if (!rst && delivered_valid[15] === 1'b1 && delivered_ready[15] === 1'b1) begin
            $display("Delivery observed at time %0t: %h",
                     $time, delivered_packets[15*56 +: 56]);

            for (monitor_i = 0; monitor_i < 8;
                 monitor_i = monitor_i + 1) begin

                if (delivered_packets[15*56 +: 56]
                    === packets[monitor_i]) begin

                    if (received[monitor_i] == 1'b0) begin
                        received[monitor_i] = 1'b1;
                        received_count = received_count + 1;

                        $display("PASS: Packet ID %0d delivered",
                                 monitor_i);
                    end
                end
            end
        end
    end

    initial begin
        clk = 1'b0;
        rst = 1'b1;
        local_valid = 16'b0;
        local_packets = {(16*56){1'b0}};
        delivered_ready = 16'hFFFF;

        received = 8'b0;
        received_count = 0;
        cycles = 0;
        wait_count = 0;
        accepted = 1'b0;

        // Initialize expected packets before monitoring deliveries.
        for (i = 0; i < 8; i = i + 1) begin
            packets[i] = {
                4'd0,
                4'd15,
                i[7:0],
                (32'hA5000000 + i),
                8'h00
            };
        end

        $display("==================================");
        $display("   BACKPRESSURE TEST START");
        $display("==================================");

        // Reset the NoC.
        repeat (4) @(negedge clk);
        rst = 1'b0;

        // Inject eight packets using valid-ready handshakes.
        for (i = 0; i < 8; i = i + 1) begin

            @(negedge clk);
            local_packets[0 +: 56] = packets[i];
            local_valid[0] = 1'b1;

            wait_count = 0;
            accepted = 1'b0;

            // Keep valid asserted until a rising edge accepts the packet.
            while ((accepted == 1'b0) && (wait_count < 100)) begin
                @(posedge clk);

                if (local0_ready === 1'b1) begin
                    accepted = 1'b1;
                    $display("Accepted packet ID %0d at time %0t",
                             i, $time);
                end else begin
                    wait_count = wait_count + 1;
                end
            end

            if (accepted == 1'b0) begin
                $display("ERROR: Timeout injecting packet ID %0d", i);
                $finish;
            end

            // Deassert valid on the falling edge.
            @(negedge clk);
            local_valid[0] = 1'b0;
        end

        // Give packets enough time to reach the destination.
        for (cycles = 0; cycles < 300; cycles = cycles + 1)
            @(posedge clk);

        @(negedge clk);

        $display("----------------------------------");
        $display("Packets received: %0d / 8", received_count);

        if (received_count == 8) begin
            $display("BACKPRESSURE TEST PASSED");
        end else begin
            $display("BACKPRESSURE TEST FAILED");

            for (i = 0; i < 8; i = i + 1) begin
                if (received[i] == 1'b0)
                    $display("Missing packet ID %0d", i);
            end
        end

        $display("----------------------------------");
        $finish;
    end

    // Prevent indefinite simulation.
    initial begin
        #10000;
        $display("ERROR: Simulation timed out.");
        $finish;
    end

endmodule
