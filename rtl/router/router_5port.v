
`timescale 1ns/1ps

module router_5port #(
    parameter DATA_WIDTH = 56,
    parameter ROUTER_ID  = 0
)(
    input wire clk,
    input wire rst,

    input wire [DATA_WIDTH-1:0] north_in,
    input wire [DATA_WIDTH-1:0] south_in,
    input wire [DATA_WIDTH-1:0] east_in,
    input wire [DATA_WIDTH-1:0] west_in,
    input wire [DATA_WIDTH-1:0] local_in,

    input wire [4:0] in_valid,
    output wire [4:0] in_ready,

    output reg [DATA_WIDTH-1:0] north_out,
    output reg [DATA_WIDTH-1:0] south_out,
    output reg [DATA_WIDTH-1:0] east_out,
    output reg [DATA_WIDTH-1:0] west_out,
    output reg [DATA_WIDTH-1:0] local_out,

    output reg [4:0] out_valid,
    input wire [4:0] out_ready
);

    wire [DATA_WIDTH-1:0] inputs [0:4];
    wire [DATA_WIDTH-1:0] fifo_data [0:4];
    wire [4:0] fifo_empty, fifo_full;
    wire [4:0] fifo_request;
    wire [4:0] fifo_wr, fifo_rd;
    wire [DATA_WIDTH-1:0] selected_packet;

    reg [3:0] dest;
    reg [1:0] dest_x, dest_y;
    reg [1:0] here_x, here_y;
    reg [4:0] selected_out;
    wire [4:0] grant;
    wire advance;

    assign inputs[0] = north_in;
    assign inputs[1] = south_in;
    assign inputs[2] = east_in;
    assign inputs[3] = west_in;
    assign inputs[4] = local_in;

    genvar p;
    generate
        for (p = 0; p < 5; p = p + 1) begin : INPUT_FIFOS
            assign in_ready[p] = !fifo_full[p];
            assign fifo_wr[p] = in_valid[p] && in_ready[p];
            assign fifo_rd[p] = grant[p] && advance;

            input_fifo #(
                .DATA_WIDTH(DATA_WIDTH),
                .DEPTH(4)
            ) fifo_inst (
                .clk(clk),
                .rst(rst),
                .wr_en(fifo_wr[p]),
                .rd_en(fifo_rd[p]),
                .din(inputs[p]),
                .dout(fifo_data[p]),
                .full(fifo_full[p]),
                .empty(fifo_empty[p])
            );

            assign fifo_request[p] = !fifo_empty[p];
        end
    endgenerate

    assign selected_packet =
        grant[0] ? fifo_data[0] :
        grant[1] ? fifo_data[1] :
        grant[2] ? fifo_data[2] :
        grant[3] ? fifo_data[3] :
        grant[4] ? fifo_data[4] :
        {DATA_WIDTH{1'b0}};

    always @(*) begin
        here_x = ROUTER_ID % 4;
        here_y = ROUTER_ID / 4;

        dest = selected_packet[51:48];
        dest_x = dest % 4;
        dest_y = dest / 4;

        selected_out = 5'b00000;

        if (|grant) begin
            if (dest_x > here_x)
                selected_out[2] = 1'b1;
            else if (dest_x < here_x)
                selected_out[3] = 1'b1;
            else if (dest_y > here_y)
                selected_out[1] = 1'b1;
            else if (dest_y < here_y)
                selected_out[0] = 1'b1;
            else
                selected_out[4] = 1'b1;
        end

        north_out = 0;
        south_out = 0;
        east_out  = 0;
        west_out  = 0;
        local_out = 0;
        out_valid = 0;

        if (selected_out[0]) begin
            north_out = selected_packet;
            out_valid[0] = 1'b1;
        end else if (selected_out[1]) begin
            south_out = selected_packet;
            out_valid[1] = 1'b1;
        end else if (selected_out[2]) begin
            east_out = selected_packet;
            out_valid[2] = 1'b1;
        end else if (selected_out[3]) begin
            west_out = selected_packet;
            out_valid[3] = 1'b1;
        end else if (selected_out[4]) begin
            local_out = selected_packet;
            out_valid[4] = 1'b1;
        end
    end

    assign advance = |(selected_out & out_ready);

    arbiter #(
        .N(5)
    ) arbiter_inst (
        .clk(clk),
        .rst(rst),
        .request(fifo_request),
        .advance(advance),
        .grant(grant)
    );

endmodule
