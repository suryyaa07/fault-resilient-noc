
`timescale 1ns / 1ps
`default_nettype none

module tb_retransmission_extended;

    reg clk = 1'b0;
    always #5 clk = ~clk;

    reg rst, send_req, ack, nack, tx_ready;
    reg [55:0] packet_in;

    wire tx_valid, busy, success, failure, retry_event;
    wire [55:0] tx_packet;

    integer errors;
    integer transfers;
    integer retries;
    integer successes;
    integer failures;

    localparam [55:0] PACKET_A = 56'h123456789ABCDE;
    localparam [55:0] PACKET_B = 56'hFEDCBA98765432;

    retransmission_manager #(
        .TIMEOUT_CYCLES(8),
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

    // Observe transfers at the actual handshake edge.
    // Observe registered events after their NBA updates.
    always @(posedge clk) begin
        if (rst) begin
            transfers = 0;
            retries = 0;
            successes = 0;
            failures = 0;
        end
        else begin
            if (tx_valid && tx_ready) begin
                transfers = transfers + 1;

                if (tx_packet !== PACKET_A) begin
                    $display("FAIL: Retransmitted packet changed");
                    errors = errors + 1;
                end
            end

            #1;

            if (retry_event)
                retries = retries + 1;

            if (success)
                successes = successes + 1;

            if (failure)
                failures = failures + 1;
        end
    end

    task check;
        input condition;
        input [511:0] description;
        begin
            if (condition === 1'b1)
                $display("PASS: %0s", description);
            else begin
                $display("FAIL: %0s", description);
                errors = errors + 1;
            end
        end
    endtask

    task reset_test;
        begin
            @(negedge clk);
            rst = 1;
            send_req = 0;
            ack = 0;
            nack = 0;
            tx_ready = 0;
            packet_in = 0;

            repeat (2) @(negedge clk);
            rst = 0;

            errors = 0;
        end
    endtask

    task launch_packet;
        begin
            @(negedge clk);
            packet_in = PACKET_A;
            send_req = 1;

            @(negedge clk);
            send_req = 0;

            // Change external input to ensure the saved copy is used.
            packet_in = PACKET_B;
        end
    endtask

    task wait_for_transfers;
        input integer target;
        integer count;
        begin
            count = 0;
            while (transfers < target && count < 100) begin
                @(negedge clk);
                count = count + 1;
            end

            check(transfers == target,
                  "Expected transfer count reached");
        end
    endtask

    task send_ack;
        begin
            @(negedge clk);
            ack = 1;

            @(negedge clk);
            ack = 0;
        end
    endtask

    task send_nack;
        begin
            @(negedge clk);
            nack = 1;

            @(negedge clk);
            nack = 0;
        end
    endtask

    initial begin
        rst = 1;
        send_req = 0;
        ack = 0;
        nack = 0;
        tx_ready = 0;
        packet_in = 0;
        errors = 0;
        transfers = 0;
        retries = 0;
        successes = 0;
        failures = 0;

        // TEST 1: NACK causes a retry.
        reset_test();
        $display("TEST 1: NACK RETRANSMISSION");

        launch_packet();
        tx_ready = 1;
        wait_for_transfers(1);

        send_nack();
        wait_for_transfers(2);

        send_ack();
        repeat (3) @(negedge clk);

        check(transfers == 2, "Exactly two transfers");
        check(retries == 1, "Exactly one retry");
        check(successes == 1, "Exactly one success");
        check(failures == 0, "No terminal failure");
        check(!busy, "Manager returns to IDLE");

        // TEST 2: Timeout causes a retry.
        reset_test();
        $display("TEST 2: TIMEOUT RETRANSMISSION");

        launch_packet();
        tx_ready = 1;
        wait_for_transfers(1);

        // Leave ACK and NACK low until timeout.
        wait_for_transfers(2);
        send_ack();
        repeat (3) @(negedge clk);

        check(transfers == 2, "Exactly two transfers");
        check(retries == 1, "Exactly one timeout retry");
        check(successes == 1, "Timeout recovery succeeds");
        check(failures == 0, "No terminal failure");

        // TEST 3: Retry exhaustion.
        reset_test();
        $display("TEST 3: RETRY EXHAUSTION");

        launch_packet();
        tx_ready = 1;

        // No ACK/NACK: allow all timeouts.
        repeat (40) @(negedge clk);

        check(transfers == 3, "Original plus two retries");
        check(retries == 2, "Exactly two retries");
        check(successes == 0, "No false success");
        check(failures == 1, "One terminal failure");
        check(!busy, "Manager returns to IDLE");

        $display("----------------------------------------");
        $display("FINAL ERROR COUNT = %0d", errors);

        if (errors == 0)
            $display("ALL EXTENDED RETRANSMISSION TESTS PASSED");
        else
            $fatal(1, "Extended retransmission tests failed");

        $finish;
    end

    initial begin
        #10000;
        $fatal(1, "Simulation watchdog timeout");
    end

endmodule

`default_nettype wire
