
`timescale 1ns / 1ps
`default_nettype none

module tb_retransmission_manager;

    reg clk = 1'b0;
    always #5 clk = ~clk;

    reg rst;
    reg send_req;
    reg [55:0] packet_in;
    reg ack;
    reg nack;
    reg tx_ready;

    wire tx_valid;
    wire [55:0] tx_packet;
    wire busy;
    wire success;
    wire failure;
    wire retry_event;

    integer errors;
    integer transfers;
    integer retries;
    integer successes;
    integer failures;

    reg [55:0] expected_packet;

    retransmission_manager #(
        .TIMEOUT_CYCLES(5),
        .MAX_RETRIES(2)
    ) dut (
        .clk(clk),
        .rst(rst),
        .send_req(send_req),
        .packet_in(packet_in),
        .ack(ack),
        .nack(nack),
        .tx_ready(tx_ready),
        .tx_valid(tx_valid),
        .tx_packet(tx_packet),
        .busy(busy),
        .success(success),
        .failure(failure),
        .retry_event(retry_event)
    );

    // Monitor actual handshakes and output pulses.
    always @(posedge clk) begin
        if (!rst) begin
            if (tx_valid && tx_ready) begin
                transfers = transfers + 1;

                if (tx_packet !== expected_packet) begin
                    $display("FAIL: Transmitted packet mismatch");
                    errors = errors + 1;
                end
            end

            if (retry_event)
                retries = retries + 1;

            if (successes < 0)
                successes = 0;

            if (success)
                successes = successes + 1;

            if (failure)
                failures = failures + 1;
        end
    end

    task check;
        input condition;
        input [511:0] message;
        begin
            if (condition === 1'b1)
                $display("PASS: %0s", message);
            else begin
                $display("FAIL: %0s", message);
                errors = errors + 1;
            end
        end
    endtask

    task reset_dut;
        begin
            @(negedge clk);
            rst = 1'b1;
            send_req = 1'b0;
            ack = 1'b0;
            nack = 1'b0;
            tx_ready = 1'b0;
            packet_in = 56'd0;

            @(negedge clk);
            rst = 1'b0;

            transfers = 0;
            retries = 0;
            successes = 0;
            failures = 0;
        end
    endtask

    task start_packet;
        input [55:0] packet;
        begin
            @(negedge clk);
            expected_packet = packet;
            packet_in = packet;
            send_req = 1'b1;

            @(negedge clk);
            send_req = 1'b0;
        end
    endtask

    // Accept exactly one packet transfer.
    task accept_transfer;
        integer cycles;
        reg accepted;
        begin
            accepted = 1'b0;
            cycles = 0;

            @(negedge clk);
            tx_ready = 1'b1;

            while (!accepted && cycles < 20) begin
                @(posedge clk);
                if (tx_valid && tx_ready)
                    accepted = 1'b1;
                cycles = cycles + 1;
            end

            @(negedge clk);
            tx_ready = 1'b0;

            check(accepted, "Packet handshake completed");
        end
    endtask

    // Generate an ACK after a completed transfer.
    task send_ack;
        begin
            @(negedge clk);
            ack = 1'b1;

            @(posedge clk);
            #1;
            check(success, "ACK produces success pulse");

            @(negedge clk);
            ack = 1'b0;
        end
    endtask

    // Generate a NACK after a completed transfer.
    task send_nack;
        begin
            @(negedge clk);
            nack = 1'b1;

            @(posedge clk);
            #1;
            check(retry_event, "NACK produces retry event");

            @(negedge clk);
            nack = 1'b0;
        end
    endtask

    initial begin
        rst = 1'b1;
        send_req = 1'b0;
        ack = 1'b0;
        nack = 1'b0;
        tx_ready = 1'b0;
        packet_in = 56'd0;

        expected_packet = 56'd0;

        errors = 0;
        transfers = 0;
        retries = 0;
        successes = 0;
        failures = 0;

        // =========================================
        // TEST 1: Normal ACK
        // =========================================
        reset_dut();

        $display("TEST 1: Normal ACK");

        start_packet(56'h123456789ABCDE);
        accept_transfer();
        send_ack();

        @(negedge clk);
        check(!busy, "Manager returns to IDLE");
        check(transfers == 1, "Exactly one transfer");
        check(retries == 0, "No retransmissions");
        check(successes == 1, "Exactly one success");

        // =========================================
        // TEST 2: Backpressure
        // =========================================
        reset_dut();

        $display("TEST 2: Backpressure");

        start_packet(56'hAABBCCDDEEFF11);

        repeat (3) @(negedge clk);

        check(tx_valid, "TX valid held during backpressure");
        check(busy, "Manager remains busy");
        check(tx_packet == expected_packet,
              "Packet data preserved");
        check(transfers == 0, "No transfer before ready");

        accept_transfer();
        send_ack();

        @(negedge clk);
        check(transfers == 1, "One transfer after ready");

        // =========================================
        // TEST 3: NACK Retransmission
        // =========================================
        reset_dut();

        $display("TEST 3: NACK Retransmission");

        start_packet(56'h11112222333344);

        accept_transfer();
        send_nack();

        accept_transfer();
        send_ack();

        @(negedge clk);
        check(transfers == 2, "Original plus one retry");
        check(retries == 1, "Exactly one retry event");
        check(successes == 1, "ACK after retry succeeds");
        check(failures == 0, "No failure");

        // =========================================
        // TEST 4: Timeout Retransmission
        // =========================================
        reset_dut();

        $display("TEST 4: Timeout Retransmission");

        start_packet(56'h55556666777788);

        accept_transfer();

        // No ACK or NACK: allow timeout.
        repeat (7) @(negedge clk);

        check(retries == 1, "Timeout causes one retry");

        accept_transfer();
        send_ack();

        @(negedge clk);
        check(transfers == 2, "Packet retransmitted");
        check(successes == 1, "ACK after timeout succeeds");

        // =========================================
        // TEST 5: Retry Exhaustion
        // =========================================
        reset_dut();

        $display("TEST 5: Retry Exhaustion");

        start_packet(56'h9999AAAABBBBCC);

        accept_transfer();

        // First timeout
        repeat (7) @(negedge clk);
        accept_transfer();

        // Second timeout
        repeat (7) @(negedge clk);
        accept_transfer();

        // Final timeout: retry limit reached
        repeat (7) @(negedge clk);

        check(retries == 2, "Exactly two retries");
        check(transfers == 3, "Exactly three transmissions");
        check(failures == 1, "Failure reported once");
        check(successes == 0, "No false success");
        check(!busy, "Manager returns to IDLE");

        // =========================================
        // FINAL RESULT
        // =========================================
        if (errors == 0)
            $display("ALL RETRANSMISSION TESTS PASSED");
        else
            $display("RETRANSMISSION TESTS FAILED: %0d errors",
                     errors);

        $finish;
    end

    // Watchdog to prevent an infinite simulation.
    initial begin
        #5000;
        $display("FAIL: Simulation watchdog timeout");
        $finish;
    end

endmodule

`default_nettype wire
