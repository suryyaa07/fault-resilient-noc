
`timescale 1ns / 1ps
`default_nettype none

module tb_adapter_retransmission;

    reg clk = 1'b0;
    reg rst = 1'b1;

    reg router_valid = 1'b0;
    reg [55:0] router_packet = 56'd0;
    wire router_ready;

    reg ack = 1'b0;
    reg nack = 1'b0;
    reg tx_ready = 1'b1;
    reg link_available = 1'b1;

    wire send_req;
    wire [55:0] packet_in;
    wire tx_valid;
    wire [55:0] tx_packet;
    wire tx_busy;
    wire tx_success;
    wire tx_failure;
    wire retry_event;

    wire packet_success;
    wire packet_failure;
    wire [55:0] failed_packet;

    integer errors = 0;
    integer tx_count = 0;
    integer retry_count = 0;
    integer success_count = 0;
    integer failure_count = 0;

    localparam [55:0] PACKET_A =
        {4'd0,4'd5,8'h31,32'h11223344,8'h00};

    localparam [55:0] PACKET_B =
        {4'd1,4'd9,8'h32,32'h55667788,8'h00};

    router_recovery_adapter adapter (
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

    retransmission_manager #(
        .TIMEOUT_CYCLES(6),
        .MAX_RETRIES(2)
    ) transmitter (
        .clk(clk),
        .rst(rst),
        .send_req(send_req),
        .packet_in(packet_in),
        .ack(ack),
        .nack(nack),
        .tx_ready(tx_ready),
        .tx_valid(tx_valid),
        .tx_packet(tx_packet),
        .busy(tx_busy),
        .success(tx_success),
        .failure(tx_failure),
        .retry_event(retry_event)
    );

    always #5 clk = ~clk;

    always @(posedge clk) begin
        if (!rst) begin
            if (tx_valid && tx_ready)
                tx_count = tx_count + 1;
            if (retry_event)
                retry_count = retry_count + 1;
            if (packet_success)
                success_count = success_count + 1;
            if (packet_failure)
                failure_count = failure_count + 1;
        end
    end

    task check;
        input condition;
        input [8*100-1:0] message;
        begin
            if (condition !== 1'b1) begin
                $display("FAIL: %0s", message);
                errors = errors + 1;
            end else
                $display("PASS: %0s", message);
        end
    endtask

    task inject_packet;
        input [55:0] packet;
        integer wait_cycles;
        reg accepted;
        begin
            @(negedge clk);
            router_packet = packet;
            router_valid = 1'b1;
            accepted = 1'b0;
            wait_cycles = 0;

            while (!accepted && wait_cycles < 30) begin
                #1;
                if (router_ready === 1'b1) begin
                    @(posedge clk);
                    accepted = 1'b1;
                end else begin
                    @(negedge clk);
                    wait_cycles = wait_cycles + 1;
                end
            end

            @(negedge clk);
            router_valid = 1'b0;

            check(accepted, "Router packet accepted");
        end
    endtask

    initial begin
        $display("=== ADAPTER + RETRANSMISSION TEST ===");

        repeat (3) @(negedge clk);
        rst = 1'b0;

        // Scenario 1: Successful transmission.
        inject_packet(PACKET_A);

        wait (tx_valid === 1'b1);
        check(tx_packet === PACKET_A,
              "Correct packet loaded into transmitter");

        @(negedge clk);
        check(tx_busy === 1'b1,
              "Transmitter busy during transaction");
        check(router_ready === 1'b0,
              "Router blocked while transmitter busy");

        @(negedge clk);
        ack = 1'b1;
        @(negedge clk);
        ack = 1'b0;

        repeat (2) @(negedge clk);

        check(success_count == 1,
              "Successful packet acknowledged");
        check(tx_busy === 1'b0,
              "Transmitter returned to IDLE");

        // Scenario 2: NACK followed by successful retry.
        inject_packet(PACKET_B);

        wait (tx_valid === 1'b1);
        @(negedge clk);
        nack = 1'b1;
        @(negedge clk);
        nack = 1'b0;

        repeat (2) @(negedge clk);

        check(retry_count >= 1,
              "NACK caused retransmission");

        ack = 1'b1;
        @(negedge clk);
        ack = 1'b0;

        repeat (2) @(negedge clk);

        check(success_count == 2,
              "Retransmitted packet acknowledged");

        // Scenario 3: Retry exhaustion through timeouts.
        inject_packet(PACKET_A);

        // No ACK or NACK. Allow timeout and retries.
        repeat (40) @(negedge clk);

        check(failure_count == 1,
              "Retry exhaustion reported");
        check(failed_packet === PACKET_A,
              "Failed packet identity preserved");
        check(tx_busy === 1'b0,
              "Transmitter returned to IDLE after failure");

        // Scenario 4: Quarantine blocks new packets.
        link_available = 1'b0;
        router_valid = 1'b1;
        router_packet = PACKET_B;
        #1;

        check(router_ready === 1'b0,
              "Unavailable link blocks router");
        check(send_req === 1'b0,
              "Unavailable link blocks send request");

        router_valid = 1'b0;
        link_available = 1'b1;

        if (errors == 0)
            $display("ALL ADAPTER-RETRANSMISSION TESTS PASSED");
        else
            $display("ADAPTER-RETRANSMISSION FAILED: %0d errors",
                     errors);

        $finish;
    end

    initial begin
        #2000;
        $display("FAIL: Global watchdog timeout");
        $finish;
    end

endmodule

`default_nettype wire
