
`timescale 1ns / 1ps

// Weighted adaptive routing for a 4x4 mesh.
//
// Router ID = 4*y + x.
// Ports: NORTH=0, SOUTH=1, EAST=2, WEST=3, LOCAL=4.
//
// link_up_map[r*4 +: 4]:
// bit 0 NORTH, bit 1 SOUTH, bit 2 EAST, bit 3 WEST.
//
// congestion_map[r*8 +: 8]:
// bits [1:0] NORTH, [3:2] SOUTH,
// bits [5:4] EAST,  [7:6] WEST.
//
// Each physical link must be enabled at both endpoints.
// Each endpoint has a 2-bit congestion score, 0 to 3.
// Link cost = 1 + 2*max(endpoint congestion scores).
//
// Dijkstra minimizes total cost. Equal-cost ties are
// deterministic according to router and port traversal order.
//
// Combinational bounded-search implementation.
// Congestion-aware route selection; not a deadlock-freedom
// guarantee for a complete packet-forwarding network.

module mesh_bfs_route (
    input  wire [3:0]   current_router,
    input  wire [3:0]   dest_router,
    input  wire [63:0]  link_up_map,
    input  wire [127:0] congestion_map,

    output reg  [2:0] next_port,
    output reg        route_valid,
    output reg        destination_reached
);

    localparam [2:0] NORTH = 3'd0;
    localparam [2:0] SOUTH = 3'd1;
    localparam [2:0] EAST  = 3'd2;
    localparam [2:0] WEST  = 3'd3;
    localparam [2:0] LOCAL = 3'd4;

    localparam integer INF = 1000000;

    integer i, d;
    integer node;
    integer neighbor;
    integer opposite;
    integer selected;
    integer best_dist;
    integer edge_score;
    integer score_a;
    integer score_b;
    integer candidate_dist;
    integer found;

    integer distance_cost [0:15];
    reg [3:0] parent [0:15];
    reg [2:0] parent_dir [0:15];
    reg [15:0] visited;

    reg [3:0] temp_router;
    reg [2:0] temp_dir;

    always @(*) begin
        next_port = LOCAL;
        route_valid = 1'b0;
        destination_reached = 1'b0;

        visited = 16'b0;
        node = 0;
        neighbor = 0;
        opposite = 0;
        selected = -1;
        best_dist = INF;
        edge_score = 0;
        score_a = 0;
        score_b = 0;
        candidate_dist = INF;
        found = 0;
        temp_router = 0;
        temp_dir = LOCAL;

        for (i = 0; i < 16; i = i + 1) begin
            distance_cost[i] = INF;
            parent[i] = 4'd0;
            parent_dir[i] = LOCAL;
        end

        if (current_router == dest_router) begin
            next_port = LOCAL;
            route_valid = 1'b1;
            destination_reached = 1'b1;
        end
        else begin
            distance_cost[current_router] = 0;

            // Dijkstra: select the lowest-cost unvisited router.
            for (i = 0; i < 16; i = i + 1) begin
                selected = -1;
                best_dist = INF;

                for (node = 0; node < 16; node = node + 1) begin
                    if (!visited[node] && distance_cost[node] < best_dist) begin
                        selected = node;
                        best_dist = distance_cost[node];
                    end
                end

                if (selected >= 0) begin
                    visited[selected] = 1'b1;

                    // Directions are visited in deterministic order:
                    // NORTH, SOUTH, EAST, WEST.
                    for (d = 0; d < 4; d = d + 1) begin
                        neighbor = selected;
                        opposite = 0;

                        case (d)
                            0: begin
                                neighbor = selected - 4;
                                opposite = 1;
                            end
                            1: begin
                                neighbor = selected + 4;
                                opposite = 0;
                            end
                            2: begin
                                neighbor = selected + 1;
                                opposite = 3;
                            end
                            3: begin
                                neighbor = selected - 1;
                                opposite = 2;
                            end
                        endcase

                        // Reject transitions outside the mesh.
                        if ((d == 0 && selected / 4 > 0) ||
                            (d == 1 && selected / 4 < 3) ||
                            (d == 2 && selected % 4 < 3) ||
                            (d == 3 && selected % 4 > 0)) begin

                            // Both endpoints must mark the link up.
                            if (link_up_map[selected*4+d] &&
                                link_up_map[neighbor*4+opposite]) begin

                                score_a =
                                    congestion_map[selected*8+d*2 +: 2];
                                score_b =
                                    congestion_map[neighbor*8+
                                                   opposite*2 +: 2];

                                if (score_a >= score_b)
                                    edge_score = score_a;
                                else
                                    edge_score = score_b;

                                candidate_dist =
                                    distance_cost[selected] + 1 + 2*edge_score;

                                if (candidate_dist < distance_cost[neighbor]) begin
                                    distance_cost[neighbor] = candidate_dist;
                                    parent[neighbor] = selected;
                                    parent_dir[neighbor] = d;
                                end
                            end
                        end
                    end
                end
            end

            // Reconstruct the first hop from destination to source.
            if (distance_cost[dest_router] < INF) begin
                temp_router = dest_router;

                for (i = 0; i < 16; i = i + 1) begin
                    if (temp_router != current_router && found == 0) begin
                        if (parent[temp_router] == current_router) begin
                            temp_dir = parent_dir[temp_router];
                            next_port = temp_dir;
                            found = 1;
                        end
                        else begin
                            temp_router = parent[temp_router];
                        end
                    end
                end

                if (found != 0)
                    route_valid = 1'b1;
            end
        end
    end

endmodule

