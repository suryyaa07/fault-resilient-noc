
`timescale 1ns/1ps

module arbiter #(
    parameter N = 5
)(
    input wire clk,
    input wire rst,
    input wire [N-1:0] request,
    input wire advance,
    output reg [N-1:0] grant
);

    reg [$clog2(N)-1:0] priority_ptr;
    integer i;
    integer idx;
    reg found;

    always @(*) begin
        grant = {N{1'b0}};
        found = 1'b0;
        idx = 0;

        for (i = 0; i < N; i = i + 1) begin
            idx = (priority_ptr + i) % N;
            if (!found && request[idx]) begin
                grant[idx] = 1'b1;
                found = 1'b1;
            end
        end
    end

    always @(posedge clk) begin
        if (rst) begin
            priority_ptr <= 0;
        end else if (advance && |grant) begin
            priority_ptr <= (grant[0]) ? 1 % N :
                (grant[1]) ? 2 % N :
                (grant[2]) ? 3 % N :
                (grant[3]) ? 4 % N : 0;
        end
    end

endmodule
