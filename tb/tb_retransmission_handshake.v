
`timescale 1ns / 1ps
`default_nettype none

module tb_retransmission_handshake;

    reg clk = 0;
    always #5 clk = ~clk;

    reg rst, send_req, ack, nack, tx_ready;
    reg [55:0] packet_in;

    wire tx_valid, busy, success, failure, retry_event;
    wire [55:0] tx_packet;

    integer errors = 0;
    integer transfers = 0;
    integer retries = 0;
    integer successes = 0;
    integer failures = 0;

    localparam [55:0] TEST_PACKET = 56'h123456789ABCDE;

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

    // Count real rising-edge transfers and event pulses.
    always @(posedge clk) begin
        if (!rst) begin
            if (tx_valid && tx_ready)
                transfers = transfers + 1;
            if (success)
                successes = successes + 1;
            if (failure)
                failures = failures + 1;
            if (retry_event)
                retries = retries + 1;
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

    initial begin
        rst = 1;
        send_req = 0;
        ack = 0;
        nack = 0;
        tx_ready = 0;
        packet_in = 0;

        repeat (3) @(negedge clk);
        rst = 0;

        // TEST 1: Valid held while downstream is stalled.
        $display("TEST 1: BACKPRESSURE");

        @(negedge clk);
        packet_in = TEST_PACKET;
        send_req = 1;

        @(negedge clk);
        send_req = 0;

        repeat (4) begin
            check(tx_valid === 1'b1,
                  "VALID asserted during stall");
            check(tx_packet === TEST_PACKET,
                  "Packet stable during stall");
            check(transfers == 0,
                  "No transfer during stall");
            @(negedge clk);
        end

        // TEST 2: One handshake on readiness.
        $display("TEST 2: HANDSHAKE");

        tx_ready = 1;
        @(negedge clk);
        #1;

        check(transfers == 1,
              "Exactly one transfer");
        check(tx_valid === 1'b0,
              "VALID deasserted after handshake");

        tx_ready = 0;

        // TEST 3: ACK completes transaction.
        $display("TEST 3: ACK");

        
ack = 1;
@(negedge clk);
#1;
ack = 0;

// The DUT registers success at the preceding rising edge.
// Allow the following rising edge to sample that pulse
// in the testbench's event counter.
@(negedge clk);
#1;

check(successes == 1,
      "Exactly one success");

        check(failures == 0,
              "No terminal failure");
        check(!busy,
              "Manager returns to idle");

        if (errors == 0)
            $display("ALL HANDSHAKE TESTS PASSED");
        else
            $display("HANDSHAKE TESTS FAILED: %0d", errors);

        $finish;
    end

    initial begin
        #5000;
        $fatal(1, "Simulation watchdog timeout");
    end

endmodule

`default_nettype wire
