
`timescale 1ns / 1ps
`default_nettype none

module link_rx_wrapper (
    input  wire        clk,
    input  wire        rst,

    // Protected incoming link
    input  wire        link_valid,
    output wire        link_ready,
    input  wire [55:0] link_packet,

    // Validated output to router
    output wire        router_valid,
    input  wire        router_ready,
    output wire [55:0] router_packet,

    // Registered link feedback
    output reg         ack_out,
    output reg         nack_out
);

    // One-entry packet buffer
    reg [55:0] buffer_packet;
    reg        buffer_valid;

    // Most recently accepted transaction identity
    reg        history_valid;
    reg [3:0]  last_source;
    reg [7:0]  last_packet_id;

    wire [7:0] calculated_crc;
    wire       crc_valid;
    wire       crc_error;

    wire       duplicate_packet;
    wire       link_fire;
    wire       router_fire;

    // CRC checker protects packet bits [55:8]
    crc8_checker crc_checker_inst (
        .data_in(link_packet[55:8]),
        .received_crc(link_packet[7:0]),
        .crc_valid(crc_valid),
        .crc_error(crc_error)
    );

    // Stop-and-wait duplicate identification.
    // Valid only under the agreed ID reuse/lifetime policy.
    assign duplicate_packet =
        history_valid &&
        (link_packet[55:52] == last_source) &&
        (link_packet[47:40] == last_packet_id);

    // CRC-invalid frames and recognized duplicates
    // can be consumed without occupying the data buffer.
    // A new valid frame requires an empty buffer.
    assign link_ready =
        !rst &&
        (crc_error || duplicate_packet || !buffer_valid);

    assign link_fire = link_valid && link_ready;

    // Output to Rahul's router
    assign router_valid  = buffer_valid && !rst;
    assign router_packet = buffer_packet;

    assign router_fire = router_valid && router_ready;

    always @(posedge clk) begin
        if (rst) begin
            buffer_packet <= 56'd0;
            buffer_valid  <= 1'b0;

            history_valid <= 1'b0;
            last_source   <= 4'd0;
            last_packet_id <= 8'd0;

            ack_out  <= 1'b0;
            nack_out <= 1'b0;
        end
        else begin

            // Feedback outputs are one-cycle pulses.
            ack_out  <= 1'b0;
            nack_out <= 1'b0;

            // Release packet after router handshake.
            if (router_fire)
                buffer_valid <= 1'b0;

            // Process one accepted incoming link frame.
            if (link_fire) begin

                // Corrupted frame: reject and NACK.
                if (crc_error) begin
                    nack_out <= 1'b1;
                end

                // Already accepted transaction:
                // ACK again, without router redelivery.
                else if (duplicate_packet) begin
                    ack_out <= 1'b1;
                end

                // New CRC-valid transaction:
                // retain packet before acknowledging.
                else if (!buffer_valid) begin
                    buffer_packet <= link_packet;
                    buffer_valid  <= 1'b1;

                    history_valid <= 1'b1;
                    last_source <= link_packet[55:52];
                    last_packet_id <= link_packet[47:40];

                    ack_out <= 1'b1;
                end
            end
        end
    end

endmodule

`default_nettype wire
