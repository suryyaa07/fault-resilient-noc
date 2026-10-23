
`timescale 1ns / 1ps
`default_nettype none

module link_recovery_controller #(
    parameter integer SUSPECT_THRESHOLD = 2,
    parameter integer QUARANTINE_THRESHOLD = 4,
    parameter integer RECOVERY_THRESHOLD = 3
)(
    input  wire       clk,
    input  wire       rst,

    input  wire       rx_valid,
    input  wire       rx_crc_error,

    input  wire       tx_success,
    input  wire       tx_failure,

    input  wire       probe_success,
    input  wire       probe_failure,

    output reg        ack_out,
    output reg        nack_out,

    output wire       link_available,
    output wire       link_quarantined,
    output wire [1:0] health_state
);

    // Existing link-health module
    link_health_manager #(
        .SUSPECT_THRESHOLD(SUSPECT_THRESHOLD),
        .QUARANTINE_THRESHOLD(QUARANTINE_THRESHOLD),
        .RECOVERY_THRESHOLD(RECOVERY_THRESHOLD)
    ) health_manager (
        .clk(clk),
        .rst(rst),
        .success_event(tx_success),
        .failure_event(tx_failure),
        .probe_success(probe_success),
        .probe_failure(probe_failure),
        .health_state(health_state),
        .link_available(link_available),
        .link_quarantined(link_quarantined)
    );

    // Registered ACK/NACK response pulses
    always @(posedge clk) begin
        if (rst) begin
            ack_out  <= 1'b0;
            nack_out <= 1'b0;
        end
        else begin
            ack_out  <= rx_valid && !rx_crc_error;
            nack_out <= rx_valid && rx_crc_error;
        end
    end

endmodule

`default_nettype wire
