
`timescale 1ns/1ps

module noc_4x4_tb;

    reg clk = 0;
    reg rst = 1;

    reg [15:0] local_valid = 0;
    reg [16*56-1:0] local_packets = 0;

    wire [15:0] local_ready;
    reg [15:0] delivered_ready = 16'hFFFF;
    wire [15:0] delivered_valid;
    wire [16*56-1:0] delivered_packets;

    reg [55:0] packet1, packet2, packet3;
    integer errors = 0;
    integer cycles;

    reg received1, received2;
    reg accepted_src0, accepted_src2;
    integer inject_cycles;

    noc_4x4 #(.DATA_WIDTH(56)) dut (
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

    task send_and_check;
        input integer src;
        input integer dst;
        input [55:0] packet;
        reg found;
        reg accepted;
        integer wait_cycles;
        begin
            found = 0;
            accepted = 0;
            wait_cycles = 0;

            @(negedge clk);
            local_packets[src*56 +: 56] = packet;
            local_valid[src] = 1'b1;

            while ((accepted == 0) && (wait_cycles < 30)) begin
                @(posedge clk);
                if (local_ready[src] === 1'b1)
                    accepted = 1;
                wait_cycles = wait_cycles + 1;
            end

            @(negedge clk);
            local_valid[src] = 1'b0;

            if (!accepted) begin
                $display("FAIL: Source router %0d did not accept packet", src);
                errors = errors + 1;
            end else begin
                for (cycles = 0; cycles < 30; cycles = cycles + 1) begin
                    @(negedge clk);
                    if (delivered_valid[dst] && delivered_ready[dst]) begin
                        if (delivered_packets[dst*56 +: 56] === packet)
                            $display("PASS: Packet reached router %0d", dst);
                        else begin
                            $display("FAIL: Data mismatch at router %0d", dst);
                            errors = errors + 1;
                        end
                        found = 1;
                        cycles = 30;
                    end
                end

                if (!found) begin
                    $display("FAIL: No packet received at router %0d", dst);
                    errors = errors + 1;
                end
            end

            repeat (2) @(negedge clk);
        end
    endtask

    initial begin
        $display("=== MULTI-PACKET NoC TEST START ===");

        repeat (3) @(negedge clk);
        rst = 0;

        packet1 = {4'd0, 4'd10, 8'h01, 32'h12345678, 8'h00};
        packet2 = {4'd2, 4'd3,  8'h02, 32'hABCDEF12, 8'h00};
        packet3 = {4'd0, 4'd10, 8'h03, 32'hDEADBEEF, 8'h00};

        // Preserve the original passing tests.
        send_and_check(0, 10, packet1);
        send_and_check(2, 3, packet2);

        // Inject concurrently and hold each valid until its handshake.
        accepted_src0 = 0;
        accepted_src2 = 0;
        inject_cycles = 0;

        @(negedge clk);
        local_packets[0*56 +: 56] = packet3;
        local_packets[2*56 +: 56] = packet2;
        local_valid[0] = 1'b1;
        local_valid[2] = 1'b1;

        while ((!accepted_src0 || !accepted_src2) && inject_cycles < 30) begin
            @(posedge clk);
            if (!accepted_src0 && local_ready[0] === 1'b1)
                accepted_src0 = 1;
            if (!accepted_src2 && local_ready[2] === 1'b1)
                accepted_src2 = 1;

            inject_cycles = inject_cycles + 1;
            @(negedge clk);
            if (accepted_src0) local_valid[0] = 1'b0;
            if (accepted_src2) local_valid[2] = 1'b0;
        end

        local_valid[0] = 1'b0;
        local_valid[2] = 1'b0;

        if (!accepted_src0 || !accepted_src2) begin
            $display("FAIL: Concurrent injection handshake timed out");
            errors = errors + 1;
        end

        received1 = 0;
        received2 = 0;

        for (cycles = 0; cycles < 40; cycles = cycles + 1) begin
            @(negedge clk);

            if (delivered_valid[10] &&
                delivered_packets[10*56 +: 56] === packet3)
                received1 = 1;

            if (delivered_valid[3] &&
                delivered_packets[3*56 +: 56] === packet2)
                received2 = 1;

            if (received1 && received2)
                cycles = 40;
        end

        if (received1)
            $display("PASS: Concurrent packet reached router 10");
        else begin
            $display("FAIL: Concurrent packet missing at router 10");
            errors = errors + 1;
        end

        if (received2)
            $display("PASS: Concurrent packet reached router 3");
        else begin
            $display("FAIL: Concurrent packet missing at router 3");
            errors = errors + 1;
        end

        if (errors == 0)
            $display("MULTI-PACKET TEST PASSED");
        else
            $display("MULTI-PACKET TEST FAILED: %0d errors", errors);

        $finish;
    end

endmodule
