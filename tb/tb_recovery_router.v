
`timescale 1ns / 1ps
`default_nettype none

module tb_recovery_router;
reg tests_completed = 1'b0;

    reg clk = 1'b0;
    always #5 clk = ~clk;

    reg rst;
    reg send_req;
    reg [55:0] packet_in;
    reg inject_crc_error;
    reg drop_ack;
    reg [4:0] out_ready;

    wire tx_valid;
    wire tx_ready;
    wire [55:0] tx_packet;
    wire tx_busy;
    wire tx_success;
    wire tx_failure;
    wire retry_event;

    wire rx_link_ready;
    wire router_valid;
    wire [55:0] router_packet;
    wire ack_out;
    wire nack_out;

    wire [4:0] in_ready;
    wire [4:0] out_valid;

    wire [55:0] north_out;
    wire [55:0] south_out;
    wire [55:0] east_out;
    wire [55:0] west_out;
    wire [55:0] local_out;

    wire [55:0] link_packet;
    wire sender_ack;
    wire sender_nack;

    reg [47:0] crc_data;
    wire [7:0] generated_crc;

    reg [55:0] packet_a;
    reg [55:0] expected_packet;

    integer errors;
    integer link_transfers;
    integer router_input_transfers;
    integer router_output_transfers;
    integer retry_count;
    integer success_count;
    integer failure_count;

    // CRC-8 packet generation
    crc8 u_crc (
        .data_in(crc_data),
        .crc_out(generated_crc)
    );

    // Stop-and-wait transmitter
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

    // Fault injection on the protected link
    assign link_packet =
        tx_packet ^
        (inject_crc_error ? 56'h00000000000100 :
                            56'h00000000000000);

    assign tx_ready = rx_link_ready;

    assign sender_ack = ack_out && !drop_ack;
    assign sender_nack = nack_out;

    // CRC validation and receiver buffering
    link_rx_wrapper u_rx (
        .clk(clk),
        .rst(rst),
        .link_valid(tx_valid),
        .link_ready(rx_link_ready),
        .link_packet(link_packet),
        .router_valid(router_valid),
        .router_ready(in_ready[3]),
        .router_packet(router_packet),
        .ack_out(ack_out),
        .nack_out(nack_out)
    );

    // Rahul's actual five-port router
    router_5port #(
        .DATA_WIDTH(56),
        .ROUTER_ID(0)
    ) u_router (
        .clk(clk),
        .rst(rst),

        .north_in(56'd0),
        .south_in(56'd0),
        .east_in(56'd0),
        .west_in(router_packet),
        .local_in(56'd0),

        .in_valid({1'b0, router_valid, 3'b000}),
        .in_ready(in_ready),

        .north_out(north_out),
        .south_out(south_out),
        .east_out(east_out),
        .west_out(west_out),
        .local_out(local_out),

        .out_valid(out_valid),
        .out_ready(out_ready)
    );

    // Clock-edge handshake scoreboard
    always @(posedge clk) begin
        if (rst) begin
            link_transfers = 0;
            router_input_transfers = 0;
            router_output_transfers = 0;
            retry_count = 0;
            success_count = 0;
            failure_count = 0;
        end else begin

            if (tx_valid && tx_ready)
                link_transfers = link_transfers + 1;

            if (router_valid && in_ready[3]) begin
                router_input_transfers =
                    router_input_transfers + 1;

                if (router_packet !== expected_packet) begin
                    $display("FAIL: Router FIFO input data mismatch");
                    errors = errors + 1;
                end
            end

            if (out_valid[2] && out_ready[2]) begin
                router_output_transfers =
                    router_output_transfers + 1;

                if (east_out !== expected_packet) begin
                    $display("FAIL: Router East output data mismatch");
                    errors = errors + 1;
                end
            end

            if (|(out_valid & 5'b11011)) begin
                $display("FAIL: Unexpected output direction");
                errors = errors + 1;
            end

            // Allow registered pulses to update.
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
            packet_in = 0;
            out_ready = 0;
            inject_crc_error = 0;
            drop_ack = 0;

            repeat (3) @(negedge clk);
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

    task wait_for_completion;
        integer cycles;
        begin
            cycles = 0;

            // First allow sender activity to start.
            // launch_packet has already pulsed send_req.
            while ((tx_busy !== 1'b0) && cycles < 100) begin
                @(negedge clk);
                cycles = cycles + 1;
            end

            check(tx_busy === 1'b0,
                  "Transmitter returned to IDLE");

            repeat (5) @(negedge clk);
        end
    endtask

    initial begin
        rst = 1;
        send_req = 0;
        packet_in = 0;
        out_ready = 0;
        inject_crc_error = 0;
        drop_ack = 0;
        crc_data = 0;
        errors = 0;
        expected_packet = 0;

        // Destination router 1 is east of router 0.
        make_packet(4'h0, 4'h1, 8'h21,
                    32'hDEADBEEF, packet_a);

        expected_packet = packet_a;

        // TEST 1: Clean recovery-to-router delivery
        reset_test();
        $display("TEST 1: CLEAN ROUTER DELIVERY");

        out_ready = 5'b00100;

        launch_packet(packet_a);
        wait_for_completion();

        check(link_transfers == 1,
              "One protected-link transfer");
        check(router_input_transfers == 1,
              "One router FIFO insertion");
        check(router_output_transfers == 1,
              "One East output delivery");
        check(success_count == 1,
              "Transmission acknowledged");
        check(retry_count == 0,
              "No retransmission");

        // TEST 2: Corruption followed by retry
        reset_test();
        $display("TEST 2: CRC CORRUPTION");

        out_ready = 5'b00100;
        inject_crc_error = 1;

        launch_packet(packet_a);

        wait (retry_event === 1'b1);
        #1;
        inject_crc_error = 0;

        wait_for_completion();

        check(link_transfers == 2,
              "Two link transfers");
        check(router_input_transfers == 1,
              "Only valid packet enters router");
        check(router_output_transfers == 1,
              "Exactly one routed delivery");
        check(retry_count == 1,
              "Exactly one retry");
        check(success_count == 1,
              "Corruption recovered");

        // TEST 3: Lost ACK and duplicate suppression
        reset_test();
        $display("TEST 3: LOST ACK");

        out_ready = 5'b00100;
        drop_ack = 1;

        launch_packet(packet_a);

        wait (retry_event === 1'b1);
        #1;
        drop_ack = 0;

        wait_for_completion();

        check(link_transfers == 2,
              "Original plus retransmission");
        check(router_input_transfers == 1,
              "Duplicate blocked before router FIFO");
        check(router_output_transfers == 1,
              "No duplicate output delivery");
        check(retry_count == 1,
              "Exactly one retry");
        check(success_count == 1,
              "Lost ACK recovered");

        // TEST 4: Router output backpressure
        reset_test();
        $display("TEST 4: ROUTER OUTPUT BACKPRESSURE");

        out_ready = 5'b00000;

        launch_packet(packet_a);

        repeat (6) @(negedge clk);

        check(router_input_transfers == 1,
              "Packet accepted into router FIFO");
        check(router_output_transfers == 0,
              "No output handshake during stall");
        check(out_valid[2] === 1'b1,
              "East output VALID held during stall");
        check(east_out === packet_a,
              "East output data stable");

        out_ready = 5'b00100;

        wait_for_completion();

        check(router_input_transfers == 1,
              "No additional router insertion");
        check(router_output_transfers == 1,
              "Buffered packet forwarded once");
        check(success_count == 1,
              "Protected transfer acknowledged");

        $display("----------------------------------------");
        $display("FINAL ERROR COUNT = %0d", errors);

       if (errors == 0)
    $display("ALL RECOVERY-ROUTER TESTS PASSED");
else
    $fatal(1, "Recovery-router integration failed");

tests_completed = 1'b1;
$finish;
    end



initial begin
    #10000;
    if (!tests_completed)
        $fatal(1, "Recovery-router watchdog timeout");
end

endmodule

`default_nettype wire
