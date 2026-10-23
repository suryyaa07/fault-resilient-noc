
`timescale 1ns / 1ps
`default_nettype none

module tb_link_rx_wrapper;

    reg clk = 1'b0;
    always #5 clk = ~clk;

    reg rst;
    reg link_valid;
    reg [55:0] link_packet;
    reg router_ready;

    wire link_ready;
    wire router_valid;
    wire [55:0] router_packet;
    wire ack_out;
    wire nack_out;

    integer errors = 0;
    integer link_accepts = 0;
    integer router_accepts = 0;
    integer ack_count = 0;
    integer nack_count = 0;

    reg [55:0] expected_packet;
    reg check_router_data;

    wire [7:0] generated_crc;
    reg [47:0] crc_data;

    crc8 crc_generator (
        .data_in(crc_data),
        .crc_out(generated_crc)
    );

    link_rx_wrapper dut (
        .clk(clk),
        .rst(rst),
        .link_valid(link_valid),
        .link_ready(link_ready),
        .link_packet(link_packet),
        .router_valid(router_valid),
        .router_ready(router_ready),
        .router_packet(router_packet),
        .ack_out(ack_out),
        .nack_out(nack_out)
    );

    // Handshakes are counted at the rising edge.
    // Registered ACK/NACK pulses are sampled after NBA updates.
    always @(posedge clk) begin
        if (rst) begin
            link_accepts = 0;
            router_accepts = 0;
            ack_count = 0;
            nack_count = 0;
        end
        else begin
            if (link_valid && link_ready)
                link_accepts = link_accepts + 1;

            if (router_valid && router_ready) begin
                router_accepts = router_accepts + 1;

                if (check_router_data &&
                    router_packet !== expected_packet) begin
                    $display("FAIL: Router received wrong packet");
                    errors = errors + 1;
                end
            end

            #1;

            if (ack_out)
                ack_count = ack_count + 1;

            if (nack_out)
                nack_count = nack_count + 1;
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
            link_valid = 0;
            link_packet = 0;
            router_ready = 0;
            check_router_data = 0;

            repeat (2) @(negedge clk);
            rst = 0;

            @(negedge clk);
        end
    endtask

    task make_packet;
        input [3:0] source_id;
        input [3:0] destination_id;
        input [7:0] packet_id;
        input [31:0] payload;
        output [55:0] packet;
        begin
            crc_data = {
                source_id,
                destination_id,
                packet_id,
                payload
            };
            #1;
            packet = {crc_data, generated_crc};
        end
    endtask

    task send_frame;
        input [55:0] packet;
        begin
            @(negedge clk);
            link_packet = packet;
            link_valid = 1;

            // Keep valid/data stable until accepted.
            @(posedge clk);
            while (link_ready !== 1'b1)
                @(posedge clk);

            @(negedge clk);
            link_valid = 0;
        end
    endtask

    reg [55:0] packet_a;
    reg [55:0] packet_b;
    reg [55:0] corrupt_packet;

    integer previous_acks;
    integer previous_nacks;
    integer previous_deliveries;

    initial begin
        rst = 1;
        link_valid = 0;
        link_packet = 0;
        router_ready = 0;
        crc_data = 0;
        expected_packet = 0;
        check_router_data = 0;

        make_packet(4'h1, 4'h7, 8'h21,
                    32'hDEADBEEF, packet_a);

        make_packet(4'h1, 4'h7, 8'h22,
                    32'hCAFEBABE, packet_b);

        corrupt_packet = packet_a;
        corrupt_packet[8] = ~corrupt_packet[8];

        // TEST 1: Valid packet acceptance
        reset_test();
        $display("TEST 1: VALID PACKET");

        expected_packet = packet_a;
        check_router_data = 1;
        router_ready = 0;

        send_frame(packet_a);

        check(router_valid === 1'b1,
              "Valid packet buffered");

        check(router_packet === packet_a,
              "Buffered packet unchanged");

        check(ack_count == 1,
              "Exactly one ACK generated");

        check(nack_count == 0,
              "No NACK generated");

        // TEST 2: Router backpressure
        $display("TEST 2: ROUTER BACKPRESSURE");

        repeat (4) @(negedge clk);

        check(router_valid === 1'b1,
              "VALID held while router stalled");

        check(router_packet === packet_a,
              "Packet stable while stalled");

        check(router_accepts == 0,
              "No router transfer during stall");

        // TEST 3: Full-buffer protection
        $display("TEST 3: BUFFER FULL");

        @(negedge clk);
        link_packet = packet_b;
        link_valid = 1;

        repeat (3) begin
            @(negedge clk);
            check(link_ready === 1'b0,
                  "New packet blocked while full");
        end

        link_valid = 0;

        check(ack_count == 1,
              "Blocked packet not ACKed");

        check(router_packet === packet_a,
              "Buffered packet not overwritten");

        // TEST 4: Deliver stored packet
        $display("TEST 4: ROUTER ACCEPTANCE");

        @(negedge clk);
        router_ready = 1;

        @(negedge clk);

        check(router_accepts == 1,
              "Exactly one router transfer");

        check(router_valid === 1'b0,
              "Buffer becomes empty");

        router_ready = 0;

        // TEST 5: CRC corruption
        $display("TEST 5: CRC REJECTION");

        previous_acks = ack_count;
        previous_nacks = nack_count;
        previous_deliveries = router_accepts;

        send_frame(corrupt_packet);

        check(nack_count == previous_nacks + 1,
              "Corrupt packet generates NACK");

        check(ack_count == previous_acks,
              "Corrupt packet not ACKed");

        check(router_accepts == previous_deliveries,
              "Corrupt packet not delivered");

        check(router_valid === 1'b0,
              "Corrupt packet not buffered");

        // TEST 6: Duplicate suppression
        $display("TEST 6: DUPLICATE SUPPRESSION");

        previous_acks = ack_count;
        previous_deliveries = router_accepts;

        send_frame(packet_a);

        check(ack_count == previous_acks + 1,
              "Duplicate generates ACK");

        check(router_valid === 1'b0,
              "Duplicate not buffered");

        check(router_accepts == previous_deliveries,
              "No duplicate router delivery");

        // TEST 7: Next transaction
        $display("TEST 7: NEW TRANSACTION");

        expected_packet = packet_b;
        previous_acks = ack_count;
        previous_deliveries = router_accepts;

        send_frame(packet_b);

        check(router_valid === 1'b1,
              "New packet accepted");

        check(ack_count == previous_acks + 1,
              "New packet ACKed");

        @(negedge clk);
        router_ready = 1;

        @(negedge clk);
        router_ready = 0;

        check(router_accepts == previous_deliveries + 1,
              "New packet delivered exactly once");

        // TEST 8: Reset clears state
        $display("TEST 8: RESET");

        reset_test();

        check(router_valid === 1'b0,
              "Buffer cleared by reset");

        check(ack_out === 1'b0,
              "ACK cleared by reset");

        check(nack_out === 1'b0,
              "NACK cleared by reset");

        expected_packet = packet_a;
        check_router_data = 1;

        send_frame(packet_a);

        check(router_valid === 1'b1,
              "Previous ID accepted after reset");

        check(ack_count == 1,
              "One ACK after reset");

        $display("----------------------------------------");
        $display("FINAL ERROR COUNT = %0d", errors);

        if (errors == 0)
            $display("ALL RECEIVER WRAPPER TESTS PASSED");
        else
            $fatal(1, "Receiver wrapper verification failed");

        $finish;
    end

    initial begin
        #10000;
        $fatal(1, "Receiver wrapper watchdog timeout");
    end

endmodule

`default_nettype wire
