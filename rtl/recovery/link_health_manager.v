
`timescale 1ns / 1ps
`default_nettype none

module link_health_manager #(
    parameter integer SUSPECT_THRESHOLD = 2,
    parameter integer QUARANTINE_THRESHOLD = 4,
    parameter integer RECOVERY_THRESHOLD = 3
)(
    input  wire       clk,
    input  wire       rst,
    input  wire       success_event,
    input  wire       failure_event,
    input  wire       probe_success,
    input  wire       probe_failure,

    output reg  [1:0] health_state,
    output wire       link_available,
    output wire       link_quarantined
);

    localparam [1:0] HEALTHY     = 2'b00,
                     SUSPECT     = 2'b01,
                     QUARANTINED = 2'b10;

    integer failure_count;
    integer recovery_count;

    assign link_available   = (health_state != QUARANTINED);
    assign link_quarantined = (health_state == QUARANTINED);

    always @(posedge clk) begin
        if (rst) begin
            health_state   <= HEALTHY;
            failure_count  <= 0;
            recovery_count <= 0;
        end
        else begin
            case (health_state)

                HEALTHY, SUSPECT: begin
                    recovery_count <= 0;

                    if (failure_event) begin
                        if (failure_count < QUARANTINE_THRESHOLD)
                            failure_count <= failure_count + 1;

                        if (failure_count + 1 >= QUARANTINE_THRESHOLD)
                            health_state <= QUARANTINED;
                        else if (failure_count + 1 >= SUSPECT_THRESHOLD)
                            health_state <= SUSPECT;
                    end
                    else if (success_event) begin
                        failure_count <= 0;
                        health_state <= HEALTHY;
                    end
                end

                QUARANTINED: begin
                    if (probe_failure) begin
                        recovery_count <= 0;
                    end
                    else if (probe_success) begin
                        if (recovery_count + 1 >= RECOVERY_THRESHOLD) begin
                            health_state <= HEALTHY;
                            failure_count <= 0;
                            recovery_count <= 0;
                        end
                        else begin
                            recovery_count <= recovery_count + 1;
                        end
                    end
                end

                default: begin
                    health_state <= HEALTHY;
                    failure_count <= 0;
                    recovery_count <= 0;
                end

            endcase
        end
    end

endmodule

`default_nettype wire
