
`timescale 1ns / 1ps
`default_nettype none

module router_recovery_adapter (
    input  wire        clk,
    input  wire        rst,

    // Input from Rahul's router
    input  wire        router_valid,
    output wire        router_ready,
    input  wire [55:0] router_packet,

    // Status from retransmission_manager
    input  wire        tx_busy,
    input  wire        tx_success,
    input  wire        tx_failure,

    // Link availability from link_health_manager
    input  wire        link_available,

    // Request to retransmission_manager
    output wire        send_req,
    output wire [55:0] packet_in,

    // Completion and failure reporting
    output wire        packet_success,
    output wire        packet_failure,
    output wire [55:0] failed_packet
);

    // Retain the identity of the accepted packet so that
    // an exhausted retransmission can be reported.
    reg [55:0] accepted_packet;

    // The transmitter accepts send_req only while IDLE.
    // tx_busy is low in that state.
    //
    // Do not accept new traffic during completion pulses.
    // This gives the completion event a separate cycle.
    wire can_accept;

    assign can_accept =
        !rst &&
        link_available &&
        !tx_busy &&
        !tx_success &&
        !tx_failure;

    // Router transfers only when the transmitter can
    // capture the same packet on the rising clock edge.
    assign router_ready = can_accept;

    // The manager and router observe this request on
    // the same rising edge.
    assign send_req = router_valid && can_accept;

    assign packet_in = router_packet;

    // Completion pulses originate in the transmitter.
    assign packet_success = tx_success;
    assign packet_failure = tx_failure;

    // Meaningful when packet_failure is asserted.
    assign failed_packet = accepted_packet;

    always @(posedge clk) begin
        if (rst) begin
            accepted_packet <= 56'd0;
        end
        else if (send_req) begin
            accepted_packet <= router_packet;
        end
    end

endmodule

`default_nettype wire
