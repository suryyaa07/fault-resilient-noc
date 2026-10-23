
`timescale 1ns / 1ps
`default_nettype none

module tb_crc8;

    reg  [47:0] data_in;
    wire [7:0]  crc_out;

    integer errors;

    crc8 dut (
        .data_in(data_in),
        .crc_out(crc_out)
    );

    // Independent reference CRC-8 calculation
    function [7:0] reference_crc;
        input [47:0] data;
        reg [7:0] remainder;
        reg feedback;
        integer i;
        begin
            remainder = 8'h00;

            for (i = 47; i >= 0; i = i - 1) begin
                feedback = remainder[7] ^ data[i];
                remainder = {remainder[6:0], 1'b0};

                if (feedback)
                    remainder = remainder ^ 8'h07;
            end

            reference_crc = remainder;
        end
    endfunction

    task check_packet;
        input [47:0] packet;
        reg [7:0] expected;
        begin
            data_in = packet;
            expected = reference_crc(packet);
            #10;

            if (crc_out !== expected) begin
                $display("FAIL: Data=%h Expected=%h Actual=%h",
                         packet, expected, crc_out);
                errors = errors + 1;
            end
            else begin
                $display("PASS: Data=%h CRC=%h",
                         packet, crc_out);
            end
        end
    endtask

    initial begin
        errors = 0;

        $display("Starting CRC-8 verification...");

        check_packet(48'h000000000000);
        // Independent CRC-8 test: ASCII "123456"
data_in = 48'h313233343536;
#10;

if (crc_out !== 8'hFD) begin
    $display("FAIL: Independent CRC test. Expected=FD Actual=%h", crc_out);
    errors = errors + 1;
end
else begin
    $display("PASS: Independent CRC test. CRC=FD");
end
        check_packet(48'hFFFFFFFFFFFF);
        check_packet(48'h123456789ABC);
        check_packet(48'hA5A5A5A5A5A5);
        check_packet(48'h000000000001);
        check_packet(48'h800000000000);

        if (errors == 0)
            $display("ALL CRC-8 TESTS PASSED");
        else
            $display("CRC-8 TEST FAILED: %0d errors", errors);

        $finish;
    end

endmodule

`default_nettype wire
