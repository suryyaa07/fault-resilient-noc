`timescale 1ns/1ps

module noc_4x4 #(
    parameter DATA_WIDTH = 56
)(
    input wire clk,
    input wire rst,

    // Set fault_enable before packet injection.
    // Router IDs range from 0 to 15; IDs must be adjacent.
    input wire fault_enable,
    input wire [3:0] fault_router_a,
    input wire [3:0] fault_router_b,

    input wire [15:0] local_valid,
    input wire [16*DATA_WIDTH-1:0] local_packets,
    output wire [15:0] local_ready,

    output wire [15:0] delivered_valid,
    input wire [15:0] delivered_ready,
    output wire [16*DATA_WIDTH-1:0] delivered_packets
);

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

    reg [DATA_WIDTH-1:0] link_n_data [0:15];
    reg [DATA_WIDTH-1:0] link_s_data [0:15];
    reg [DATA_WIDTH-1:0] link_e_data [0:15];
    reg [DATA_WIDTH-1:0] link_w_data [0:15];

    reg [15:0] link_n_valid;
    reg [15:0] link_s_valid;
    reg [15:0] link_e_valid;
    reg [15:0] link_w_valid;

    // One link map per router. Each map uses the global 64-bit format:
    // bit [router_id*4 + direction], N=0, S=1, E=2, W=3.
    reg [63:0] router_link_up_map [0:15];
    reg [127:0] router_congestion_map [0:15];

    integer map_index;

    function link_is_faulted;
        input [3:0] a;
        input [3:0] b;
        input enable;
        input [3:0] fault_a;
        input [3:0] fault_b;
        begin
            link_is_faulted = 1'b0;
            if (enable == 1'b1) begin
                if (((a == fault_a) && (b == fault_b)) ||
                    ((a == fault_b) && (b == fault_a))) begin
                    link_is_faulted = 1'b1;
                end
            end
        end
    endfunction

    function [63:0] build_link_map;
    input enable;
    input [3:0] fault_a;
    input [3:0] fault_b;
    integer id;
    integer x;
    integer y;
    begin
        build_link_map = 64'b0;
        for (id = 0; id < 16; id = id + 1) begin
            x = id % 4;
            y = id / 4;

            if (y > 0 &&
                !link_is_faulted(id, id-4, enable, fault_a, fault_b))
                build_link_map[id*4+0] = 1'b1;

            if (y < 3 &&
                !link_is_faulted(id, id+4, enable, fault_a, fault_b))
                build_link_map[id*4+1] = 1'b1;

            if (x < 3 &&
                !link_is_faulted(id, id+1, enable, fault_a, fault_b))
                build_link_map[id*4+2] = 1'b1;

            if (x > 0 &&
                !link_is_faulted(id, id-1, enable, fault_a, fault_b))
                build_link_map[id*4+3] = 1'b1;
        end
    end
endfunction

    always @* begin
        for (map_index = 0; map_index < 16; map_index = map_index + 1) begin
            router_link_up_map[map_index] =
                build_link_map(fault_enable,
                               fault_router_a, fault_router_b);
            // Congestion feedback is not integrated yet.
            router_congestion_map[map_index] = 128'b0;
        end
    end

    genvar r, c;

    generate
        for (r = 0; r < 4; r = r + 1) begin : ROW
            for (c = 0; c < 4; c = c + 1) begin : COL

                localparam ID = r*4 + c;

                if (r == 0) begin : NORTH_BOUNDARY
                    assign north_in[ID] = {DATA_WIDTH{1'b0}};
                    assign valid_in[ID][0] = 1'b0;
                end else begin : NORTH_LINK
                    assign north_in[ID] = link_s_data[ID-4];
                    assign valid_in[ID][0] =
                        link_s_valid[ID-4] &
                        ~link_is_faulted(ID, ID-4, fault_enable,
                                         fault_router_a, fault_router_b);
                end

                if (r == 3) begin : SOUTH_BOUNDARY
                    assign south_in[ID] = {DATA_WIDTH{1'b0}};
                    assign valid_in[ID][1] = 1'b0;
                end else begin : SOUTH_LINK
                    assign south_in[ID] = link_n_data[ID+4];
                    assign valid_in[ID][1] =
                        link_n_valid[ID+4] &
                        ~link_is_faulted(ID, ID+4, fault_enable,
                                         fault_router_a, fault_router_b);
                end

                if (c == 3) begin : EAST_BOUNDARY
                    assign east_in[ID] = {DATA_WIDTH{1'b0}};
                    assign valid_in[ID][2] = 1'b0;
                end else begin : EAST_LINK
                    assign east_in[ID] = link_w_data[ID+1];
                    assign valid_in[ID][2] =
                        link_w_valid[ID+1] &
                        ~link_is_faulted(ID, ID+1, fault_enable,
                                         fault_router_a, fault_router_b);
                end

                if (c == 0) begin : WEST_BOUNDARY
                    assign west_in[ID] = {DATA_WIDTH{1'b0}};
                    assign valid_in[ID][3] = 1'b0;
                end else begin : WEST_LINK
                    assign west_in[ID] = link_e_data[ID-1];
                    assign valid_in[ID][3] =
                        link_e_valid[ID-1] &
                        ~link_is_faulted(ID, ID-1, fault_enable,
                                         fault_router_a, fault_router_b);
                end

                assign valid_in[ID][4] = local_valid[ID];
                assign local_ready[ID] = ready_in[ID][4];

                if (r == 0) begin : NORTH_READY_BOUNDARY
                    assign ready_out[ID][0] = 1'b0;
                end else begin : NORTH_READY_LINK
                    assign ready_out[ID][0] =
                        !link_is_faulted(ID, ID-4, fault_enable,
                                         fault_router_a, fault_router_b) &&
                        (!link_n_valid[ID] || ready_in[ID-4][1]);
                end

                if (r == 3) begin : SOUTH_READY_BOUNDARY
                    assign ready_out[ID][1] = 1'b0;
                end else begin : SOUTH_READY_LINK
                    assign ready_out[ID][1] =
                        !link_is_faulted(ID, ID+4, fault_enable,
                                         fault_router_a, fault_router_b) &&
                        (!link_s_valid[ID] || ready_in[ID+4][0]);
                end

                if (c == 3) begin : EAST_READY_BOUNDARY
                    assign ready_out[ID][2] = 1'b0;
                end else begin : EAST_READY_LINK
                    assign ready_out[ID][2] =
                        !link_is_faulted(ID, ID+1, fault_enable,
                                         fault_router_a, fault_router_b) &&
                        (!link_e_valid[ID] || ready_in[ID+1][3]);
                end

                if (c == 0) begin : WEST_READY_BOUNDARY
                    assign ready_out[ID][3] = 1'b0;
                end else begin : WEST_READY_LINK
                    assign ready_out[ID][3] =
                        !link_is_faulted(ID, ID-1, fault_enable,
                                         fault_router_a, fault_router_b) &&
                        (!link_w_valid[ID] || ready_in[ID-1][2]);
                end

                assign ready_out[ID][4] = delivered_ready[ID];

                router_5port #(
                    .DATA_WIDTH(DATA_WIDTH),
                    .ROUTER_ID(ID),
                    .ADAPTIVE_ROUTING(1)
                ) router_inst (
                    .clk(clk),
                    .rst(rst),
                    .adaptive_enable(fault_enable),
                    .link_up_map(router_link_up_map[ID]),
                    .congestion_map(router_congestion_map[ID]),

                    .north_in(north_in[ID]),
                    .south_in(south_in[ID]),
                    .east_in(east_in[ID]),
                    .west_in(west_in[ID]),
                    .local_in(local_packets[ID*DATA_WIDTH +: DATA_WIDTH]),

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

                assign delivered_packets[ID*DATA_WIDTH +: DATA_WIDTH] =
                    local_out[ID];
                assign delivered_valid[ID] = valid_out[ID][4];

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