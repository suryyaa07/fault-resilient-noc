
`timescale 1ns / 1ps
`default_nettype none

module crc8_checker (
    input  wire [47:0] data_in,
    input  wire [7:0]  received_crc,
    output wire        crc_valid,
    output wire        crc_error
);

    wire [7:0] calculated_crc;

    crc8 crc_generator (
        .data_in(data_in),
        .crc_out(calculated_crc)
    );

    assign crc_valid = (calculated_crc == received_crc);
    assign crc_error = ~crc_valid;

endmodule

`default_nettype wire
