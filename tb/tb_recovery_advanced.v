
`timescale 1ns / 1ps
`default_nettype none

module tb_recovery_advanced;

    reg clk = 1'b0;
    always #5 clk = ~clk;

    reg rst;
    reg send_req;
    reg [47:0] data_in;
    reg tx_ready;
    reg inject_error;
    reg drop_response;
    reg probe_success;
    reg probe_failure;

    wire [7:0] generated_crc;
    wire [55:0] packet_in;
    wire [55:0] tx_packet;
    wire tx_valid;
    wire busy;
    wire tx_success;
    wire tx_failure;
    wire retry_event;

    reg rx_valid;
    reg [55:0] rx_packet;

    wire crc_valid;
    wire crc_error;
    wire ack_out;
    wire nack_out;
    wire link_available;
    wire link_quarantined;
    wire [1:0] health_state;

    reg ack_to_sender;
    reg nack_to_sender;

    integer errors;
    integer transfers;
    integer retries;
    integer successes;
    integer failures;
    integer cycles;
    integer i;

    localparam [1:0] HEALTHY = 2'd0;
    localparam [1:0] SUSPECT = 2'd1;
    localparam [1:0] QUARANTINED = 2'd2;

    // =========================================================
    // CRC GENERATOR
    // =========================================================

    crc8 crc_gen (
        .data_in(data_in),
        .crc_out(generated_crc)
    );

    assign packet_in = {data_in, generated_crc};

    // =========================================================
    // CRC CHECKER
    // =========================================================

    crc8_checker checker (
        .data_in(rx_packet[55:8]),
        .received_crc(rx_packet[7:0]),
        .crc_valid(crc_valid),
        .crc_error(crc_error)
    );

    // =========================================================
    // RETRANSMISSION MANAGER
    // =========================================================

    retransmission_manager #(
        .TIMEOUT_CYCLES(8),
        .MAX_RETRIES(2)
    ) retransmitter (
        .clk(clk),
        .rst(rst),
        .send_req(send_req),
        .packet_in(packet_in),
        .ack(ack_to_sender),
        .nack(nack_to_sender),
        .tx_ready(tx_ready),
        .tx_valid(tx_valid),
        .tx_packet(tx_packet),
        .busy(busy),
        .success(tx_success),
        .failure(tx_failure),
        .retry_event(retry_event)
    );

    // =========================================================
    // LINK RECOVERY CONTROLLER
    // =========================================================

    link_recovery_controller #(
        .SUSPECT_THRESHOLD(2),
        .QUARANTINE_THRESHOLD(4),
        .RECOVERY_THRESHOLD(3)
    ) controller (
        .clk(clk),
        .rst(rst),
        .rx_valid(rx_valid),
        .rx_crc_error(crc_error),
        .tx_success(tx_success),
        .tx_failure(tx_failure),
        .probe_success(probe_success),
        .probe_failure(probe_failure),
        .ack_out(ack_out),
        .nack_out(nack_out),
        .link_available(link_available),
        .link_quarantined(link_quarantined),
        .health_state(health_state)
    );

    // =========================================================
    // SIMULATED LINK
    // =========================================================

    always @(negedge clk) begin
        if (rst) begin
            rx_valid = 1'b0;
            rx_packet = 56'd0;
            ack_to_sender = 1'b0;
            nack_to_sender = 1'b0;
        end
        else begin
            rx_valid = tx_valid && tx_ready;
            rx_packet = tx_packet;

            if (rx_valid && inject_error)
                rx_packet[8] = ~rx_packet[8];

            ack_to_sender = ack_out && !drop_response;
            nack_to_sender = nack_out && !drop_response;
        end
    end

    // =========================================================
    // EVENT COUNTERS
    // =========================================================

    always @(posedge clk) begin
        if (!rst) begin
            if (tx_valid && tx_ready)
                transfers = transfers + 1;

            #1;

            if (retry_event)
                retries = retries + 1;

            if (tx_success)
                successes = successes + 1;

            if (tx_failure)
                failures = failures + 1;
        end
    end

    // =========================================================
    // ASSERTION TASK
    // =========================================================

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

    // =========================================================
    // DIAGNOSTIC TASK
    // =========================================================

    task show_counters;
        input [511:0] test_name;
        begin
            $display("----------------------------------------");
            $display("DIAGNOSTICS: %0s", test_name);
            $display("Transfers = %0d", transfers);
            $display("Retries   = %0d", retries);
            $display("Successes = %0d", successes);
            $display("Failures  = %0d", failures);
            $display("Health    = %0d", health_state);
            $display("Busy      = %0b", busy);
            $display("----------------------------------------");
        end
    endtask

    // =========================================================
    // RESET TASK
    // =========================================================

    task reset_system;
        begin
            @(negedge clk);

            rst = 1'b1;
            send_req = 1'b0;
            tx_ready = 1'b0;
            inject_error = 1'b0;
            drop_response = 1'b0;
            probe_success = 1'b0;
            probe_failure = 1'b0;

            repeat (2) @(negedge clk);

            rst = 1'b0;

            transfers = 0;
            retries = 0;
            successes = 0;
            failures = 0;
        end
    endtask

    // =========================================================
    // SEND PACKET TASK
    // =========================================================

    task send_packet;
        input [47:0] payload;
        begin
            @(negedge clk);
            data_in = payload;
            send_req = 1'b1;

            @(negedge clk);
            send_req = 1'b0;
        end
    endtask

    // =========================================================
    // WAIT UNTIL TRANSACTION FINISHES
    // =========================================================

    task wait_idle;
        begin
            cycles = 0;

            while (busy && cycles < 100) begin
                @(negedge clk);
                cycles = cycles + 1;
            end

            repeat (3) @(negedge clk);

            check(!busy, "Manager returns to IDLE");
        end
    endtask

    // =========================================================
    // WAIT FOR FIRST RETRY
    // =========================================================

    task wait_first_retry;
        begin
            cycles = 0;

            while (retries < 1 && cycles < 100) begin
                @(negedge clk);
                cycles = cycles + 1;
            end

            check(retries >= 1, "First retry observed");
        end
    endtask

    // =========================================================
    // RECOVERY PROBE TASK
    // =========================================================

    task send_probe;
        begin
            @(negedge clk);
            probe_success = 1'b1;

            @(negedge clk);
            probe_success = 1'b0;
        end
    endtask

    // =========================================================
    // MAIN TEST SEQUENCE
    // =========================================================

    initial begin

        rst = 1'b1;
        send_req = 1'b0;
        data_in = 48'd0;
        tx_ready = 1'b0;
        inject_error = 1'b0;
        drop_response = 1'b0;
        probe_success = 1'b0;
        probe_failure = 1'b0;

        rx_valid = 1'b0;
        rx_packet = 56'd0;
        ack_to_sender = 1'b0;
        nack_to_sender = 1'b0;

        errors = 0;
        transfers = 0;
        retries = 0;
        successes = 0;
        failures = 0;
        cycles = 0;

        // =====================================================
        // TEST 1: CLEAN PACKET
        // =====================================================

        reset_system();

        $display("TEST 1: Exact clean-delivery counts");

        tx_ready = 1'b1;

        send_packet(48'h123456789ABC);

        wait_idle();

        show_counters("Clean delivery");

        check(transfers == 1, "Exactly one transfer");
        check(retries == 0, "No retries");
        check(successes == 1, "Exactly one success");
        check(failures == 0, "No failures");
        check(health_state == HEALTHY,
              "Link remains HEALTHY");

        // =====================================================
        // TEST 2: CORRUPTION AND RETRY
        // =====================================================

        reset_system();

        $display("TEST 2: Exact CRC-retry counts");

        tx_ready = 1'b1;
        inject_error = 1'b1;

        send_packet(48'hAABBCCDDEEFF);

        wait_first_retry();

        // Disable corruption before the retransmitted packet
        // is sampled by the simulated link.
        inject_error = 1'b0;

        wait_idle();

        show_counters("CRC corruption");

        check(transfers == 2,
              "Exactly two transmissions");
        check(retries == 1,
              "Exactly one retransmission");
        check(successes == 1,
              "Retry succeeds exactly once");
        check(failures == 0,
              "No terminal failure");

        // =====================================================
        // TEST 3: LOST RESPONSE
        // =====================================================

        reset_system();

        $display("TEST 3: Timeout and recovery");

        tx_ready = 1'b1;
        drop_response = 1'b1;

       
send_packet(48'h112233445566);

// Release the response drop as soon as the
// first retry is scheduled, before retry transfer.
wait (retry_event === 1'b1);
#1;
drop_response = 1'b0;

        wait_idle();

        show_counters("Timeout recovery");

        check(transfers == 2,
              "Timeout causes exactly two transfers");
        check(retries == 1,
              "Exactly one timeout retry");
        check(successes == 1,
              "Sender eventually succeeds");
        check(failures == 0,
              "No terminal failure");

        // =====================================================
        // TEST 4: RETRY EXHAUSTION
        // =====================================================

        reset_system();

        $display("TEST 4: Retry exhaustion");

        tx_ready = 1'b1;
        drop_response = 1'b1;

        send_packet(48'hFFEEDDCCBBAA);

        wait_idle();

        show_counters("Retry exhaustion");

        check(transfers == 3,
              "Original plus two retries");
        check(retries == 2,
              "Exactly two retries");
        check(successes == 0,
              "No false success");
        check(failures == 1,
              "Exactly one terminal failure");
        check(health_state == HEALTHY,
              "One failure remains HEALTHY");

        // =====================================================
        // TEST 5: LINK QUARANTINE
        // =====================================================

        reset_system();

        $display("TEST 5: Link quarantine");

        tx_ready = 1'b1;
        drop_response = 1'b1;

        for (i = 0; i < 4; i = i + 1) begin
            send_packet(48'h010203040506 + i);

            wait_idle();

            show_counters("Quarantine transaction");

            if (i == 1)
                check(health_state == SUSPECT,
                      "Two failures enter SUSPECT");

            if (i == 3)
                check(health_state == QUARANTINED,
                      "Four failures enter QUARANTINED");
        end

        check(failures == 4,
              "Four terminal failures counted");
        check(transfers == 12,
              "Twelve transmission attempts");
        check(retries == 8,
              "Eight retries");
        check(link_quarantined && !link_available,
              "Quarantined link unavailable");

        // =====================================================
        // TEST 6: PROBE RECOVERY
        // =====================================================

        $display("TEST 6: Probe-based recovery");

        send_probe();
        send_probe();

        check(health_state == QUARANTINED,
              "Two probes do not clear quarantine");

        send_probe();

        check(health_state == HEALTHY,
              "Three probes restore HEALTHY");

        check(link_available && !link_quarantined,
              "Recovered link available");

        // =====================================================
        // FINAL DIAGNOSTICS
        // =====================================================

        $display("========================================");
        $display("FINAL DIAGNOSTIC COUNTERS");
        $display("Transfers = %0d", transfers);
        $display("Retries   = %0d", retries);
        $display("Successes = %0d", successes);
        $display("Failures  = %0d", failures);
        $display("Errors    = %0d", errors);
        $display("========================================");

        // =====================================================
        // FINAL RESULT
        // =====================================================

        if (errors == 0) begin
            $display("ALL ADVANCED RECOVERY TESTS PASSED");
        end
        else begin
            $display(
                "ADVANCED RECOVERY TESTS FAILED: %0d errors",
                errors
            );
            $fatal(1, "Advanced verification failed");
        end

        $finish;
    end

    // =========================================================
    // SIMULATION WATCHDOG
    // =========================================================

    initial begin
        #10000;
        $fatal(1, "Advanced testbench watchdog timeout");
    end

endmodule

`default_nettype wire
