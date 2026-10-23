
`timescale 1ns / 1ps
`default_nettype none

module retransmission_manager #(
    parameter integer TIMEOUT_CYCLES = 16,
    parameter integer MAX_RETRIES = 3
)(
    input  wire        clk,
    input  wire        rst,
    input  wire        send_req,
    input  wire [55:0] packet_in,
    input  wire        ack,
    input  wire        nack,
    input  wire        tx_ready,

    output wire        tx_valid,
    output wire [55:0] tx_packet,
    output wire        busy,
    output reg         success,
    output reg         failure,
    output reg         retry_event
);

    localparam [1:0]
        IDLE     = 2'd0,
        SEND     = 2'd1,
        WAIT_ACK = 2'd2;

    reg [1:0] state;
    reg [55:0] saved_packet;

    integer retry_count;
    integer timeout_count;

    // Ready/valid source interface
    assign tx_valid  = (state == SEND) && !rst;
    assign tx_packet = saved_packet;
    assign busy      = (state != IDLE);

    wire tx_fire;
    assign tx_fire = tx_valid && tx_ready;

    initial begin
        if (TIMEOUT_CYCLES < 1 || MAX_RETRIES < 0)
            $error("Invalid retransmission parameters");
    end

    always @(posedge clk) begin
        if (rst) begin
            state         <= IDLE;
            saved_packet  <= 56'd0;
            retry_count   <= 0;
            timeout_count <= 0;
            success       <= 1'b0;
            failure       <= 1'b0;
            retry_event   <= 1'b0;
        end
        else begin
            success     <= 1'b0;
            failure     <= 1'b0;
            retry_event <= 1'b0;

            case (state)

                IDLE: begin
                    retry_count   <= 0;
                    timeout_count <= 0;

                    if (send_req) begin
                        saved_packet <= packet_in;
                        state        <= SEND;
                    end
                end

                SEND: begin
                    // Keep valid and packet stable until handshake.
                    if (tx_fire) begin
                        timeout_count <= 0;
                        state         <= WAIT_ACK;
                    end
                end

                WAIT_ACK: begin
                    // ACK takes precedence over NACK or timeout.
                    if (ack) begin
                        success <= 1'b1;
                        state   <= IDLE;
                    end
                    else if (nack ||
                             timeout_count >= TIMEOUT_CYCLES - 1) begin

                        if (retry_count < MAX_RETRIES) begin
                            retry_count   <= retry_count + 1;
                            retry_event   <= 1'b1;
                            timeout_count <= 0;
                            state         <= SEND;
                        end
                        else begin
                            failure <= 1'b1;
                            state   <= IDLE;
                        end
                    end
                    else begin
                        timeout_count <= timeout_count + 1;
                    end
                end

                default: begin
                    state <= IDLE;
                end

            endcase
        end
    end

endmodule

`default_nettype wire
