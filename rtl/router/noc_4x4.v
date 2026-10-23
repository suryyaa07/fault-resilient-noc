
`timescale 1ns/1ps

module noc_4x4 #(
    parameter DATA_WIDTH = 56
)(
    input wire clk,
    input wire rst,

    input wire [15:0] local_valid,
    input wire [16*DATA_WIDTH-1:0] local_packets,

    // Local injection handshake
    output wire [15:0] local_ready,

    // Local delivery handshake
    output wire [15:0] delivered_valid,
    input wire [15:0] delivered_ready,
    output wire [16*DATA_WIDTH-1:0] delivered_packets
);

    // Router input and output packet buses.
    wire [DATA_WIDTH-1:0] north_in  [0:15];
    wire [DATA_WIDTH-1:0] south_in  [0:15];
    wire [DATA_WIDTH-1:0] east_in   [0:15];
    wire [DATA_WIDTH-1:0] west_in   [0:15];

    wire [DATA_WIDTH-1:0] north_out [0:15];
    wire [DATA_WIDTH-1:0] south_out [0:15];
    wire [DATA_WIDTH-1:0] east_out  [0:15];
    wire [DATA_WIDTH-1:0] west_out  [0:15];
    wire [DATA_WIDTH-1:0] local_out [0:15];

    // Port order: North=0, South=1, East=2, West=3, Local=4.
    wire [4:0] valid_in  [0:15];
    wire [4:0] ready_in  [0:15];
    wire [4:0] valid_out [0:15];
    wire [4:0] ready_out [0:15];

    // One-entry registered buffers for inter-router links.
    reg [DATA_WIDTH-1:0] link_n_data [0:15];
    reg [DATA_WIDTH-1:0] link_s_data [0:15];
    reg [DATA_WIDTH-1:0] link_e_data [0:15];
    reg [DATA_WIDTH-1:0] link_w_data [0:15];

    reg [15:0] link_n_valid;
    reg [15:0] link_s_valid;
    reg [15:0] link_e_valid;
    reg [15:0] link_w_valid;

    genvar r, c;

    generate
        for (r = 0; r < 4; r = r + 1) begin : ROW
            for (c = 0; c < 4; c = c + 1) begin : COL

                localparam ID = r*4 + c;

                // Incoming links
                if (r == 0) begin : NORTH_BOUNDARY
                    assign north_in[ID] = {DATA_WIDTH{1'b0}};
                    assign valid_in[ID][0] = 1'b0;
                end else begin : NORTH_LINK
                    assign north_in[ID] = link_s_data[ID-4];
                    assign valid_in[ID][0] = link_s_valid[ID-4];
                end

                if (r == 3) begin : SOUTH_BOUNDARY
                    assign south_in[ID] = {DATA_WIDTH{1'b0}};
                    assign valid_in[ID][1] = 1'b0;
                end else begin : SOUTH_LINK
                    assign south_in[ID] = link_n_data[ID+4];
                    assign valid_in[ID][1] = link_n_valid[ID+4];
                end

                if (c == 3) begin : EAST_BOUNDARY
                    assign east_in[ID] = {DATA_WIDTH{1'b0}};
                    assign valid_in[ID][2] = 1'b0;
                end else begin : EAST_LINK
                    assign east_in[ID] = link_w_data[ID+1];
                    assign valid_in[ID][2] = link_w_valid[ID+1];
                end

                if (c == 0) begin : WEST_BOUNDARY
                    assign west_in[ID] = {DATA_WIDTH{1'b0}};
                    assign valid_in[ID][3] = 1'b0;
                end else begin : WEST_LINK
                    assign west_in[ID] = link_e_data[ID-1];
                    assign valid_in[ID][3] = link_e_valid[ID-1];
                end

                // Local packet injection.
                assign valid_in[ID][4] = local_valid[ID];
                assign local_ready[ID] = ready_in[ID][4];

                // Inter-router output readiness.
                if (r == 0) begin : NORTH_READY_BOUNDARY
                    assign ready_out[ID][0] = 1'b0;
                end else begin : NORTH_READY_LINK
                    assign ready_out[ID][0] =
                        !link_n_valid[ID] || ready_in[ID-4][1];
                end

                if (r == 3) begin : SOUTH_READY_BOUNDARY
                    assign ready_out[ID][1] = 1'b0;
                end else begin : SOUTH_READY_LINK
                    assign ready_out[ID][1] =
                        !link_s_valid[ID] || ready_in[ID+4][0];
                end

                if (c == 3) begin : EAST_READY_BOUNDARY
                    assign ready_out[ID][2] = 1'b0;
                end else begin : EAST_READY_LINK
                    assign ready_out[ID][2] =
                        !link_e_valid[ID] || ready_in[ID+1][3];
                end

                if (c == 0) begin : WEST_READY_BOUNDARY
                    assign ready_out[ID][3] = 1'b0;
                end else begin : WEST_READY_LINK
                    assign ready_out[ID][3] =
                        !link_w_valid[ID] || ready_in[ID-1][2];
                end

                // NEW: Destination controls local delivery readiness.
                assign ready_out[ID][4] = delivered_ready[ID];

                // Router instance.
                router_5port #(
                    .DATA_WIDTH(DATA_WIDTH),
                    .ROUTER_ID(ID)
                ) router_inst (
                    .clk(clk),
                    .rst(rst),

                    .north_in(north_in[ID]),
                    .south_in(south_in[ID]),
                    .east_in(east_in[ID]),
                    .west_in(west_in[ID]),
                    .local_in(
                        local_packets[ID*DATA_WIDTH +: DATA_WIDTH]
                    ),

                    .in_valid(valid_in[ID]),
                    .in_ready(ready_in[ID]),

                    .north_out(north_out[ID]),
                    .south_out(south_out[ID]),
                    .east_out(east_out[ID]),
                    .west_out(west_out[ID]),
                    .local_out(local_out[ID]),

                    .out_valid(valid_out[ID]),
                    .out_ready(ready_out[ID])
                );

                // Local delivery outputs.
                assign delivered_packets[ID*DATA_WIDTH +: DATA_WIDTH]
                    = local_out[ID];

                assign delivered_valid[ID] = valid_out[ID][4];

                // Registered inter-router link-buffer updates.
                always @(posedge clk) begin
                    if (rst) begin
                        link_n_data[ID] <= {DATA_WIDTH{1'b0}};
                        link_s_data[ID] <= {DATA_WIDTH{1'b0}};
                        link_e_data[ID] <= {DATA_WIDTH{1'b0}};
                        link_w_data[ID] <= {DATA_WIDTH{1'b0}};

                        link_n_valid[ID] <= 1'b0;
                        link_s_valid[ID] <= 1'b0;
                        link_e_valid[ID] <= 1'b0;
                        link_w_valid[ID] <= 1'b0;
                    end else begin

                        if (ready_out[ID][0]) begin
                            link_n_valid[ID] <= valid_out[ID][0];
                            if (valid_out[ID][0])
                                link_n_data[ID] <= north_out[ID];
                        end

                        if (ready_out[ID][1]) begin
                            link_s_valid[ID] <= valid_out[ID][1];
                            if (valid_out[ID][1])
                                link_s_data[ID] <= south_out[ID];
                        end

                        if (ready_out[ID][2]) begin
                            link_e_valid[ID] <= valid_out[ID][2];
                            if (valid_out[ID][2])
                                link_e_data[ID] <= east_out[ID];
                        end

                        if (ready_out[ID][3]) begin
                            link_w_valid[ID] <= valid_out[ID][3];
                            if (valid_out[ID][3])
                                link_w_data[ID] <= west_out[ID];
                        end
                    end
                end

            end
        end
    endgenerate

endmodule
