
`timescale 1ns / 1ps
`default_nettype none

module tb_crc8_checker;

    reg  [47:0] data_in;
    reg  [7:0]  received_crc;
    wire        crc_valid;
    wire        crc_error;

    integer errors;

    crc8_checker dut (
        .data_in(data_in),
        .received_crc(received_crc),
        .crc_valid(crc_valid),
        .crc_error(crc_error)
    );

    task check_result;
        input [47:0] packet;
        input [7:0] crc;
        input expected_valid;
        begin
            data_in = packet;
            received_crc = crc;
            #10;

            if ((crc_valid !== expected_valid) ||
                (crc_error !== ~expected_valid)) begin

                $display("FAIL: Data=%h CRC=%h Valid=%b Error=%b",
                         packet, crc, crc_valid, crc_error);
                errors = errors + 1;
            end
            else begin
                $display("PASS: Data=%h CRC=%h Valid=%b Error=%b",
                         packet, crc, crc_valid, crc_error);
            end
        end
    endtask

    initial begin
        errors = 0;

        $display("Starting CRC-8 Checker Verification...");

        // Correct packet with matching CRC
        check_result(48'h313233343536, 8'hFD, 1'b1);

        // Corrupted data with original CRC
        check_result(48'h313233343537, 8'hFD, 1'b0);

        // Correct data with incorrect CRC
        check_result(48'h313233343536, 8'h00, 1'b0);

        // All-zero packet with correct CRC
        check_result(48'h000000000000, 8'h00, 1'b1);

        // All-ones packet with correct CRC
        check_result(48'hFFFFFFFFFFFF, 8'h48, 1'b1);

        // All-ones packet with incorrect CRC
        check_result(48'hFFFFFFFFFFFF, 8'h49, 1'b0);

        if (errors == 0)
            $display("ALL CRC-8 CHECKER TESTS PASSED");
        else
            $display("CRC-8 CHECKER TEST FAILED: %0d errors", errors);

        $finish;
    end

endmodule

`default_nettype wire
