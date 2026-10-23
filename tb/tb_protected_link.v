
`timescale 1ns / 1ps
`default_nettype none

module tb_protected_link;

    reg clk = 1'b0;
    always #5 clk = ~clk;

    reg rst;
    reg send_req;
    reg [55:0] packet_in;
    reg router_ready;
    reg drop_ack;
    reg inject_crc_error;

    wire tx_valid;
    wire tx_ready;
    wire [55:0] tx_packet;
    wire tx_busy;
    wire tx_success;
    wire tx_failure;
    wire retry_event;

    wire rx_link_valid;
    wire rx_link_ready;
    wire [55:0] rx_link_packet;

    wire router_valid;
    wire [55:0] router_packet;
    wire rx_ack;
    wire rx_nack;

    wire sender_ack;
    wire sender_nack;

    reg [47:0] crc_data;
    wire [7:0] generated_crc;

    integer errors;
    integer link_transfers;
    integer router_transfers;
    integer retry_count;
    integer success_count;
    integer failure_count;

    reg [55:0] expected_packet;

    // CRC generator
    crc8 u_crc (
        .data_in(crc_data),
        .crc_out(generated_crc)
    );

    // Transmitter
    retransmission_manager #(
        .TIMEOUT_CYCLES(12),
        .MAX_RETRIES(2)
    ) u_tx (
        .clk(clk),
        .rst(rst),
        .send_req(send_req),
        .packet_in(packet_in),
        .ack(sender_ack),
        .nack(sender_nack),
        .tx_ready(tx_ready),
        .tx_valid(tx_valid),
        .tx_packet(tx_packet),
        .busy(tx_busy),
        .success(tx_success),
        .failure(tx_failure),
        .retry_event(retry_event)
    );

    // Link fault injection
    assign rx_link_valid = tx_valid;
    assign rx_link_packet =
        tx_packet ^ (inject_crc_error ? 56'h00000000000100
                                      : 56'h00000000000000);

    assign tx_ready = rx_link_ready;

    // Receiver
    link_rx_wrapper u_rx (
        .clk(clk),
        .rst(rst),
        .link_valid(rx_link_valid),
        .link_ready(rx_link_ready),
        .link_packet(rx_link_packet),
        .router_valid(router_valid),
        .router_ready(router_ready),
        .router_packet(router_packet),
        .ack_out(rx_ack),
        .nack_out(rx_nack)
    );

    assign sender_ack = rx_ack && !drop_ack;
    assign sender_nack = rx_nack;

    // Count actual transfers.
    always @(posedge clk) begin
        if (rst) begin
            link_transfers = 0;
            router_transfers = 0;
            retry_count = 0;
            success_count = 0;
            failure_count = 0;
        end
        else begin
            if (tx_valid && tx_ready)
                link_transfers = link_transfers + 1;

            if (router_valid && router_ready) begin
                router_transfers = router_transfers + 1;

                if (router_packet !== expected_packet) begin
                    $display("FAIL: Router packet mismatch");
                    errors = errors + 1;
                end
            end

            #1;

            if (retry_event)
                retry_count = retry_count + 1;

            if (tx_success)
                success_count = success_count + 1;

            if (tx_failure)
                failure_count = failure_count + 1;
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

    task reset_test;
        begin
            @(negedge clk);
            rst = 1;
            send_req = 0;
            router_ready = 0;
            drop_ack = 0;
            inject_crc_error = 0;
            packet_in = 0;

            repeat (2) @(negedge clk);
            rst = 0;
            @(negedge clk);
        end
    endtask

    task make_packet;
        input [3:0] src;
        input [3:0] dst;
        input [7:0] id;
        input [31:0] payload;
        output [55:0] packet;
        begin
            crc_data = {src, dst, id, payload};
            #1;
            packet = {crc_data, generated_crc};
        end
    endtask

    task launch_packet;
        input [55:0] packet;
        begin
            @(negedge clk);
            packet_in = packet;
            send_req = 1;
            @(negedge clk);
            send_req = 0;
        end
    endtask

    task wait_for_idle;
        integer cycles;
        begin
            cycles = 0;
            while (tx_busy !== 1'b0 && cycles < 100) begin
                @(negedge clk);
                cycles = cycles + 1;
            end

            check(tx_busy === 1'b0,
                  "Transmitter returns to IDLE");

            repeat (3) @(negedge clk);
        end
    endtask

    reg [55:0] packet_a;

    initial begin
        rst = 1;
        send_req = 0;
        packet_in = 0;
        router_ready = 0;
        drop_ack = 0;
        inject_crc_error = 0;
        crc_data = 0;
        errors = 0;
        expected_packet = 0;

        make_packet(4'h1, 4'h7, 8'h21,
                    32'hDEADBEEF, packet_a);

        expected_packet = packet_a;

        // TEST 1: Normal delivery
        reset_test();
        $display("TEST 1: CLEAN DELIVERY");

        router_ready = 1;
        launch_packet(packet_a);
        wait_for_idle();

        check(link_transfers == 1,
              "One link transfer");
        check(router_transfers == 1,
              "One router delivery");
        check(success_count == 1,
              "One transaction success");
        check(retry_count == 0,
              "No retransmission");

        // TEST 2: CRC corruption and retry
        reset_test();
        $display("TEST 2: CRC CORRUPTION");

        router_ready = 1;
        inject_crc_error = 1;

        launch_packet(packet_a);

        // Wait until a retry is scheduled.
        wait (retry_event === 1'b1);
        #1;
        inject_crc_error = 0;

        wait_for_idle();

        check(link_transfers == 2,
              "Original plus retry");
        check(router_transfers == 1,
              "Only valid packet delivered");
        check(retry_count == 1,
              "Exactly one retry");
        check(success_count == 1,
              "Corruption recovered");

        // TEST 3: Lost ACK
        reset_test();
        $display("TEST 3: LOST ACK");

        router_ready = 1;
        drop_ack = 1;

        launch_packet(packet_a);

        // Restore ACK delivery when first retry is scheduled.
        wait (retry_event === 1'b1);
        #1;
        drop_ack = 0;

        wait_for_idle();

        check(link_transfers == 2,
              "Exactly two link transfers");
        check(router_transfers == 1,
              "Duplicate not delivered twice");
        check(retry_count == 1,
              "Exactly one retry");
        check(success_count == 1,
              "Lost ACK recovered");

        // TEST 4: Receiver backpressure
        reset_test();
        $display("TEST 4: ROUTER BACKPRESSURE");

        router_ready = 0;
        launch_packet(packet_a);

        repeat (5) @(negedge clk);

        check(router_valid === 1'b1,
              "Receiver buffers packet");
        check(router_packet === packet_a,
              "Packet stable during backpressure");

        router_ready = 1;
        wait_for_idle();

        check(router_transfers == 1,
              "Buffered packet delivered once");
        check(success_count == 1,
              "Transaction acknowledged");

        // TEST 5: Terminal failure
        reset_test();
        $display("TEST 5: TERMINAL FAILURE");

        router_ready = 1;
        drop_ack = 1;
        launch_packet(packet_a);
        wait_for_idle();

        check(link_transfers == 3,
              "Three link transfers");
        check(router_transfers == 1,
              "No duplicate delivery");
        check(retry_count == 2,
              "Two retries");
        check(success_count == 0,
              "No false success");
        check(failure_count == 1,
              "One terminal failure");

        $display("----------------------------------------");
        $display("FINAL ERROR COUNT = %0d", errors);

        if (errors == 0)
            $display("ALL PROTECTED LINK TESTS PASSED");
        else
            $fatal(1, "Protected link integration failed");

        $finish;
    end

    initial begin
        #10000;
        $fatal(1, "Protected link watchdog timeout");
    end

endmodule

`default_nettype wire
