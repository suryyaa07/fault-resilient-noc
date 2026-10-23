`timescale 1ns / 1ps
`default_nettype none

module tb_link_recovery_controller;

    reg clk = 1'b0;
    always #5 clk = ~clk;

    reg rst;
    reg rx_valid;
    reg rx_crc_error;
    reg tx_success;
    reg tx_failure;
    reg probe_success;
    reg probe_failure;

    wire ack_out;
    wire nack_out;
    wire link_available;
    wire link_quarantined;
    wire [1:0] health_state;

    integer errors;

    localparam [1:0] HEALTHY     = 2'b00;
    localparam [1:0] SUSPECT     = 2'b01;
    localparam [1:0] QUARANTINED = 2'b10;

    link_recovery_controller #(
        .SUSPECT_THRESHOLD(2),
        .QUARANTINE_THRESHOLD(4),
        .RECOVERY_THRESHOLD(3)
    ) dut (
        .clk(clk),
        .rst(rst),
        .rx_valid(rx_valid),
        .rx_crc_error(rx_crc_error),
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

    task check_outputs;
        input [1:0] expected_state;
        input expected_ack;
        input expected_nack;
        input [511:0] message;
        begin
            if (health_state !== expected_state ||
                ack_out !== expected_ack ||
                nack_out !== expected_nack ||
                link_available !==
                    (expected_state != QUARANTINED) ||
                link_quarantined !==
                    (expected_state == QUARANTINED)) begin

                $display("FAIL: %0s", message);
                $display(" State=%b ACK=%b NACK=%b",
                         health_state, ack_out, nack_out);
                errors = errors + 1;
            end
            else begin
                $display("PASS: %0s", message);
            end
        end
    endtask

    // Apply inputs before rising edge and check
    // registered outputs after rising edge.
    task apply_cycle;
        input v;
        input crc_error;
        input success;
        input failure;
        input p_success;
        input p_failure;
        input [1:0] expected_state;
        input expected_ack;
        input expected_nack;
        input [511:0] message;
        begin
            @(negedge clk);

            rx_valid = v;
            rx_crc_error = crc_error;
            tx_success = success;
            tx_failure = failure;
            probe_success = p_success;
            probe_failure = p_failure;

            @(posedge clk);
            #1;

            check_outputs(
                expected_state,
                expected_ack,
                expected_nack,
                message
            );
        end
    endtask

    initial begin
        rst = 1'b1;
        rx_valid = 1'b0;
        rx_crc_error = 1'b0;
        tx_success = 1'b0;
        tx_failure = 1'b0;
        probe_success = 1'b0;
        probe_failure = 1'b0;
        errors = 0;

        @(posedge clk);
        #1;
        check_outputs(HEALTHY, 0, 0, "Reset state");

        @(negedge clk);
        rst = 1'b0;

        $display("TEST 1: Correct packet");

        apply_cycle(1,0,0,0,0,0,
                    HEALTHY,1,0,
                    "Correct CRC generates ACK");

        apply_cycle(0,0,0,0,0,0,
                    HEALTHY,0,0,
                    "ACK clears after one cycle");

        $display("TEST 2: Corrupted packet");

        apply_cycle(1,1,0,0,0,0,
                    HEALTHY,0,1,
                    "CRC error generates NACK");

        apply_cycle(0,0,0,0,0,0,
                    HEALTHY,0,0,
                    "NACK clears after one cycle");

        $display("TEST 3: Failure thresholds");

        apply_cycle(0,0,0,1,0,0,
                    HEALTHY,0,0,
                    "First failure remains HEALTHY");

        apply_cycle(0,0,0,1,0,0,
                    SUSPECT,0,0,
                    "Second failure enters SUSPECT");

        apply_cycle(0,0,1,0,0,0,
                    HEALTHY,0,0,
                    "Successful transmission restores HEALTHY");

        $display("TEST 4: Quarantine");

        apply_cycle(0,0,0,1,0,0,
                    HEALTHY,0,0,
                    "First consecutive failure");

        apply_cycle(0,0,0,1,0,0,
                    SUSPECT,0,0,
                    "Second consecutive failure");

        apply_cycle(0,0,0,1,0,0,
                    SUSPECT,0,0,
                    "Third consecutive failure");

        apply_cycle(0,0,0,1,0,0,
                    QUARANTINED,0,0,
                    "Fourth failure quarantines link");

        apply_cycle(0,0,1,0,0,0,
                    QUARANTINED,0,0,
                    "Normal success cannot clear quarantine");

        $display("TEST 5: Recovery probes");

        apply_cycle(0,0,0,0,1,0,
                    QUARANTINED,0,0,
                    "First recovery probe succeeds");

        apply_cycle(0,0,0,0,1,0,
                    QUARANTINED,0,0,
                    "Second recovery probe succeeds");

        apply_cycle(0,0,0,0,0,1,
                    QUARANTINED,0,0,
                    "Failed probe resets recovery progress");

        apply_cycle(0,0,0,0,1,0,
                    QUARANTINED,0,0,
                    "Recovery attempt restarts");

        apply_cycle(0,0,0,0,1,0,
                    QUARANTINED,0,0,
                    "Two successful probes insufficient");

        apply_cycle(0,0,0,0,1,0,
                    HEALTHY,0,0,
                    "Three successful probes restore HEALTHY");

        $display("TEST 6: Post-recovery operation");

        apply_cycle(1,0,0,0,0,0,
                    HEALTHY,1,0,
                    "ACK operates after recovery");

        apply_cycle(0,0,0,0,0,0,
                    HEALTHY,0,0,
                    "ACK pulse clears");

        if (errors == 0)
            $display("ALL LINK RECOVERY CONTROLLER TESTS PASSED");
        else
            $display("LINK RECOVERY CONTROLLER TESTS FAILED: %0d",
                     errors);

        $finish;
    end

    initial begin
        #2000;
        $display("FAIL: Simulation watchdog timeout");
        $fatal(1);
    end

endmodule

`default_nettype wire