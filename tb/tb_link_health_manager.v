`timescale 1ns / 1ps
`default_nettype none

module tb_link_health_manager;

    reg clk = 0;
    always #5 clk = ~clk;

    reg rst;
    reg success_event;
    reg failure_event;
    reg probe_success;
    reg probe_failure;

    wire [1:0] health_state;
    wire link_available;
    wire link_quarantined;

    integer errors;

    localparam [1:0] HEALTHY = 2'b00,
                     SUSPECT = 2'b01,
                     QUARANTINED = 2'b10;

    link_health_manager #(
        .SUSPECT_THRESHOLD(2),
        .QUARANTINE_THRESHOLD(4),
        .RECOVERY_THRESHOLD(3)
    ) dut (
        .clk(clk),
        .rst(rst),
        .success_event(success_event),
        .failure_event(failure_event),
        .probe_success(probe_success),
        .probe_failure(probe_failure),
        .health_state(health_state),
        .link_available(link_available),
        .link_quarantined(link_quarantined)
    );

    task check_state;
        input [1:0] expected;
        input [255:0] message;
        begin
            #1;
            if (health_state !== expected) begin
                $display("FAIL: %0s Expected=%b Actual=%b",
                         message, expected, health_state);
                errors = errors + 1;
            end
            else begin
                $display("PASS: %0s", message);
            end
        end
    endtask

    task send_failure;
        begin
            @(negedge clk);
            failure_event = 1;
            @(negedge clk);
            failure_event = 0;
        end
    endtask

    task send_success;
        begin
            @(negedge clk);
            success_event = 1;
            @(negedge clk);
            success_event = 0;
        end
    endtask

    task send_probe_success;
        begin
            @(negedge clk);
            probe_success = 1;
            @(negedge clk);
            probe_success = 0;
        end
    endtask

    task send_probe_failure;
        begin
            @(negedge clk);
            probe_failure = 1;
            @(negedge clk);
            probe_failure = 0;
        end
    endtask

    initial begin
        rst = 1;
        success_event = 0;
        failure_event = 0;
        probe_success = 0;
        probe_failure = 0;
        errors = 0;

        @(negedge clk);
        rst = 0;

        // TEST 1: Initial state
        check_state(HEALTHY, "Initial state HEALTHY");

        // TEST 2: First failure
        send_failure();
        check_state(HEALTHY, "One failure remains HEALTHY");

        // TEST 3: Second failure
        send_failure();
        check_state(SUSPECT, "Two failures enter SUSPECT");

        // TEST 4: Success resets failure streak
        send_success();
        check_state(HEALTHY, "Success restores HEALTHY");

        // TEST 5: Four consecutive failures
        send_failure();
        send_failure();
        check_state(SUSPECT, "Two failures enter SUSPECT");

        send_failure();
        send_failure();
        check_state(QUARANTINED,
                    "Four failures enter QUARANTINED");

        if (!link_available && link_quarantined)
            $display("PASS: Quarantined link unavailable");
        else begin
            $display("FAIL: Quarantine output incorrect");
            errors = errors + 1;
        end

        // TEST 6: Normal success cannot bypass quarantine
        send_success();
        check_state(QUARANTINED,
                    "Normal success cannot clear quarantine");

        // TEST 7: Probe failure resets recovery progress
        send_probe_success();
        send_probe_success();
        send_probe_failure();
        check_state(QUARANTINED,
                    "Probe failure keeps link quarantined");

        // TEST 8: Three consecutive successful probes
        send_probe_success();
        send_probe_success();
        check_state(QUARANTINED,
                    "Two probes insufficient for recovery");

        send_probe_success();
        check_state(HEALTHY,
                    "Three probes restore HEALTHY");

        if (link_available && !link_quarantined)
            $display("PASS: Recovered link available");
        else begin
            $display("FAIL: Recovery output incorrect");
            errors = errors + 1;
        end

        if (errors == 0)
            $display("ALL LINK HEALTH TESTS PASSED");
        else
            $display("LINK HEALTH TESTS FAILED: %0d errors",
                     errors);

        $finish;
    end

    initial begin
        #2000;
        $display("FAIL: Simulation watchdog timeout");
        $finish;
    end

endmodule

`default_nettype wire