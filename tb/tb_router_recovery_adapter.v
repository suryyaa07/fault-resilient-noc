
`timescale 1ns / 1ps
`default_nettype none

module tb_router_recovery_adapter;

    reg clk = 1'b0;
    reg rst = 1'b1;

    reg         router_valid = 1'b0;
    reg [55:0]  router_packet = 56'd0;
    wire        router_ready;

    reg tx_busy = 1'b0;
    reg tx_success = 1'b0;
    reg tx_failure = 1'b0;
    reg link_available = 1'b1;

    wire        send_req;
    wire [55:0] packet_in;
    wire        packet_success;
    wire        packet_failure;
    wire [55:0] failed_packet;

    integer errors = 0;

    localparam [55:0] PACKET_A =
        {4'd0, 4'd5, 8'h21, 32'hAABBCCDD, 8'h00};

    localparam [55:0] PACKET_B =
        {4'd2, 4'd9, 8'h22, 32'h11223344, 8'h00};

    router_recovery_adapter dut (
        .clk(clk),
        .rst(rst),

        .router_valid(router_valid),
        .router_ready(router_ready),
        .router_packet(router_packet),

        .tx_busy(tx_busy),
        .tx_success(tx_success),
        .tx_failure(tx_failure),
        .link_available(link_available),

        .send_req(send_req),
        .packet_in(packet_in),

        .packet_success(packet_success),
        .packet_failure(packet_failure),
        .failed_packet(failed_packet)
    );

    always #5 clk = ~clk;

    task check;
        input condition;
        input [8*100-1:0] message;
        begin
            if (condition !== 1'b1) begin
                $display("FAIL: %0s", message);
                errors = errors + 1;
            end else begin
                $display("PASS: %0s", message);
            end
        end
    endtask

    initial begin
        $display("=== ROUTER-RECOVERY ADAPTER TEST ===");

        // Test 1: Reset blocks acceptance.
        router_valid = 1'b1;
        router_packet = PACKET_A;
        #1;

        check(router_ready === 1'b0,
              "Reset blocks router acceptance");
        check(send_req === 1'b0,
              "Reset blocks send request");

        @(negedge clk);
        rst = 1'b0;
        #1;

        // Test 2: Idle transmitter accepts a packet.
        check(router_ready === 1'b1,
              "Idle transmitter provides readiness");
        check(send_req === 1'b1,
              "Valid packet generates send request");
        check(packet_in === PACKET_A,
              "Packet forwarded correctly");

        @(posedge clk);
        #1;

        check(dut.accepted_packet === PACKET_A,
              "Accepted packet saved");

        @(negedge clk);
        router_valid = 1'b0;
        tx_busy = 1'b1;
        #1;

        // Test 3: Busy transmitter blocks another packet.
        router_valid = 1'b1;
        router_packet = PACKET_B;
        #1;

        check(router_ready === 1'b0,
              "Busy transmitter blocks router");
        check(send_req === 1'b0,
              "No send request while busy");

        @(negedge clk);
        router_valid = 1'b0;
        tx_busy = 1'b0;
        link_available = 1'b0;
        #1;

        // Test 4: Quarantined link blocks transmission.
        router_valid = 1'b1;
        #1;

        check(router_ready === 1'b0,
              "Quarantined link blocks router");
        check(send_req === 1'b0,
              "No request on unavailable link");

        @(negedge clk);
        router_valid = 1'b0;
        link_available = 1'b1;
        tx_success = 1'b1;
        #1;

        // Test 5: Completion pulse is reported.
        check(packet_success === 1'b1,
              "Success pulse forwarded");
        check(router_ready === 1'b0,
              "No acceptance during success pulse");

        @(negedge clk);
        tx_success = 1'b0;
        tx_failure = 1'b1;
        #1;

        // Test 6: Failure reports the saved packet.
        check(packet_failure === 1'b1,
              "Failure pulse forwarded");
        check(failed_packet === PACKET_A,
              "Correct failed packet reported");
        check(router_ready === 1'b0,
              "No acceptance during failure pulse");

        @(negedge clk);
        tx_failure = 1'b0;
        router_valid = 1'b1;
        router_packet = PACKET_B;
        #1;

        check(router_ready === 1'b1,
              "Adapter accepts next packet after completion");
        check(send_req === 1'b1,
              "Next packet generates request");

        @(posedge clk);
        #1;

        check(dut.accepted_packet === PACKET_B,
              "Next packet saved correctly");

        router_valid = 1'b0;

        if (errors == 0)
            $display("ALL ADAPTER TESTS PASSED");
        else
            $display("ADAPTER TESTS FAILED: %0d errors", errors);

        $finish;
    end

    initial begin
        #1000;
        $display("FAIL: Adapter testbench timeout");
        $finish;
    end

endmodule

`default_nettype wire
