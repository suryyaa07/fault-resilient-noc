
`timescale 1ns / 1ps
`default_nettype none

module crc8 (
    input  wire [47:0] data_in,
    output reg  [7:0]  crc_out
);

    integer i;
    reg [7:0] crc;

    always @(*) begin
        crc = 8'h00;

        for (i = 47; i >= 0; i = i - 1) begin
            if (crc[7] ^ data_in[i])
                crc = (crc << 1) ^ 8'h07;
            else
                crc = crc << 1;
        end

        crc_out = crc;
    end

endmodule

`default_nettype wire
