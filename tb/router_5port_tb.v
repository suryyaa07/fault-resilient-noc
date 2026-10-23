
`timescale 1ns/1ps

module router_5port_tb;

    reg clk = 0;
    reg rst = 1;

    reg [55:0] north_in = 0;
    reg [55:0] south_in = 0;
    reg [55:0] east_in  = 0;
    reg [55:0] west_in  = 0;
    reg [55:0] local_in = 0;

    reg [4:0] in_valid = 0;
    wire [4:0] in_ready;

    wire [55:0] north_out;
    wire [55:0] south_out;
    wire [55:0] east_out;
    wire [55:0] west_out;
    wire [55:0] local_out;

    wire [4:0] out_valid;
    reg [4:0] out_ready = 0;

    integer errors = 0;
    integer k;
    reg seen;

    router_5port #(
        .DATA_WIDTH(56),
        .ROUTER_ID(5)
    ) dut (
        .clk(clk),
        .rst(rst),
        .north_in(north_in),
        .south_in(south_in),
        .east_in(east_in),
        .west_in(west_in),
        .local_in(local_in),
        .in_valid(in_valid),
        .in_ready(in_ready),
        .north_out(north_out),
        .south_out(south_out),
        .east_out(east_out),
        .west_out(west_out),
        .local_out(local_out),
        .out_valid(out_valid),
        .out_ready(out_ready)
    );

    always #5 clk = ~clk;

    task check;
        input condition;
        input [8*100-1:0] message;
        begin
            if (condition !== 1'b1) begin
                $display("FAIL: %0s", message);
                errors = errors + 1;
            end else begin
                $display("PASS: %0s", message);
            end
        end
    endtask

    task send_and_check;
        input [55:0] packet;
        input [4:0] expected_port;
        input [8*30-1:0] test_name;
        begin
            // Inject one packet through the Local input.
            @(negedge clk);
            local_in = packet;
            in_valid = 5'b10000;
            out_ready = 0;

            while (in_ready[4] !== 1'b1)
                @(negedge clk);

            // Input transfer occurs on this rising edge.
            @(posedge clk);
            @(negedge clk);
            in_valid = 0;

            // Wait for the routed packet, with a timeout.
            seen = 0;
            for (k = 0; k < 20; k = k + 1) begin
                @(negedge clk);
                if (out_valid == expected_port)
                    seen = 1;
                if (seen)
                    k = 20;
            end

            check(seen, {test_name, ": output valid"});
            
            if (seen) begin
                case (expected_port)
                    5'b00001: check(north_out == packet,
                                     "North packet integrity");
                    5'b00010: check(south_out == packet,
                                     "South packet integrity");
                    5'b00100: check(east_out == packet,
                                     "East packet integrity");
                    5'b01000: check(west_out == packet,
                                     "West packet integrity");
                    5'b10000: check(local_out == packet,
                                     "Local packet integrity");
                endcase

                // Stall the selected output and verify stability.
                repeat (2) begin
                    @(negedge clk);
                    check(out_valid == expected_port,
                          "Valid held during backpressure");

                    case (expected_port)
                        5'b00001: check(north_out == packet,
                                         "North data stable");
                        5'b00010: check(south_out == packet,
                                         "South data stable");
                        5'b00100: check(east_out == packet,
                                         "East data stable");
                        5'b01000: check(west_out == packet,
                                         "West data stable");
                        5'b10000: check(local_out == packet,
                                         "Local data stable");
                    endcase
                end

                // Allow the receiver to accept the packet.
                out_ready = expected_port;
                @(posedge clk);
                @(negedge clk);
                out_ready = 0;
                #1;
                check(out_valid == 0, "Accepted packet dequeued");
            end
        end
    endtask

    initial begin
        $display("=== ROUTER READY/VALID REGRESSION START ===");

        repeat (2) @(negedge clk);
        rst = 0;

        // Router 5 is at (x=1,y=1).
        send_and_check(
            {4'd2,4'd6,8'h01,32'h12345678,8'h00},
            5'b00100, "Route East"
        );

        send_and_check(
            {4'd2,4'd4,8'h02,32'h12345678,8'h00},
            5'b01000, "Route West"
        );

        send_and_check(
            {4'd2,4'd9,8'h03,32'h12345678,8'h00},
            5'b00010, "Route South"
        );

        send_and_check(
            {4'd2,4'd1,8'h04,32'h12345678,8'h00},
            5'b00001, "Route North"
        );

        send_and_check(
            {4'd2,4'd5,8'h05,32'h12345678,8'h00},
            5'b10000, "Route Local"
        );

        if (errors == 0)
            $display("ALL ROUTER TESTS PASSED");
        else
            $display("ROUTER TESTS FAILED: %0d errors", errors);

        $finish;
    end

endmodule
