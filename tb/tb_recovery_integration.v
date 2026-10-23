`timescale 1ns / 1ps
`default_nettype none

module tb_recovery_integration;

    reg clk = 0;
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
    integer transfer_count;
    integer retry_count;
    integer success_count;
    integer failure_count;

    localparam [1:0] HEALTHY = 2'b00;
    localparam [1:0] SUSPECT = 2'b01;
    localparam [1:0] QUARANTINED = 2'b10;

    // =========================================================
    // CRC-8 GENERATOR
    // =========================================================

    crc8 crc_gen (
        .data_in(data_in),
        .crc_out(generated_crc)
    );

    assign packet_in = {data_in, generated_crc};

    // =========================================================
    // CRC-8 CHECKER
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
    // SIMULATED RECEIVER AND ACK/NACK RETURN PATH
    // =========================================================

    always @(negedge clk) begin
        if (rst) begin
            rx_valid = 0;
            rx_packet = 0;
            ack_to_sender = 0;
            nack_to_sender = 0;
        end
        else begin
            rx_valid = tx_valid && tx_ready;

            rx_packet = tx_packet;

            if (inject_error && rx_valid)
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
                transfer_count = transfer_count + 1;

            if (retry_event)
                retry_count = retry_count + 1;

            if (tx_success)
                success_count = success_count + 1;

            if (tx_failure)
                failure_count = failure_count + 1;

        end
    end

    // =========================================================
    // CHECK TASK
    // =========================================================

    task check;
        input condition;
        input [511:0] message;

        begin
            if (condition === 1'b1) begin
                $display("PASS: %0s", message);
            end
            else begin
                $display("FAIL: %0s", message);
                errors = errors + 1;
            end
        end
    endtask

    // =========================================================
    // RESET TASK
    // =========================================================

    task reset_system;
        begin
            @(negedge clk);

            rst = 1;
            send_req = 0;
            tx_ready = 0;
            inject_error = 0;
            drop_response = 0;
            probe_success = 0;
            probe_failure = 0;

            @(negedge clk);

            rst = 0;

            transfer_count = 0;
            retry_count = 0;
            success_count = 0;
            failure_count = 0;
        end
    endtask

    // =========================================================
    // PACKET SEND TASK
    // =========================================================

    task send_packet;
        input [47:0] data;

        begin
            @(negedge clk);

            data_in = data;
            send_req = 1;

            @(negedge clk);

            send_req = 0;
        end
    endtask

    // =========================================================
    // MAIN TEST SEQUENCE
    // =========================================================

    initial begin

        rst = 1;
        send_req = 0;
        data_in = 0;
        tx_ready = 0;
        inject_error = 0;
        drop_response = 0;
        probe_success = 0;
        probe_failure = 0;

        rx_valid = 0;
        rx_packet = 0;
        ack_to_sender = 0;
        nack_to_sender = 0;

        errors = 0;
        transfer_count = 0;
        retry_count = 0;
        success_count = 0;
        failure_count = 0;

        reset_system();

        // =====================================================
        // TEST 1: CLEAN PACKET DELIVERY
        // =====================================================

        $display("TEST 1: Clean packet delivery");

        tx_ready = 1;

        send_packet(48'h123456789ABC);

        repeat (12) @(negedge clk);

        check(
            success_count == 1,
            "Clean packet acknowledged"
        );

        check(
            retry_count == 0,
            "No retry for clean packet"
        );

        reset_system();

        // =====================================================
        // TEST 2: CORRUPTION AND RETRANSMISSION
        // =====================================================

        $display("TEST 2: Corruption and retry");

        tx_ready = 1;
        inject_error = 1;

        send_packet(48'hAABBCCDDEEFF);

        repeat (6) @(negedge clk);

        inject_error = 0;

        repeat (12) @(negedge clk);

        check(
            retry_count >= 1,
            "Corruption triggers retransmission"
        );

        check(
            success_count == 1,
            "Retry eventually succeeds"
        );

        reset_system();

        // =====================================================
        // TEST 3: LOST RESPONSE AND TIMEOUT
        // =====================================================

        $display("TEST 3: Lost response and timeout");

        tx_ready = 1;
        drop_response = 1;

        send_packet(48'h112233445566);

        repeat (7) @(negedge clk);

        drop_response = 0;

        repeat (15) @(negedge clk);

        check(
            retry_count >= 1,
            "Lost response causes timeout retry"
        );

        // =====================================================
        // FINAL VERIFICATION RESULT
        // =====================================================

        if (errors == 0) begin
            $display(
                "ALL RECOVERY INTEGRATION TESTS PASSED"
            );
        end
        else begin
            $display(
                "RECOVERY INTEGRATION TESTS FAILED: %0d",
                errors
            );

            $fatal(
                1,
                "Integration verification failed"
            );
        end

        $finish;
    end

    // =========================================================
    // SIMULATION WATCHDOG
    // =========================================================

    initial begin
        #5000;

        $display(
            "FAIL: Integration simulation timeout"
        );

        $fatal(1);
    end

endmodule

`default_nettype wire