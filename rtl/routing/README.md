\# Routing Module Documentation



\## Algorithm



`mesh\_bfs\_route.v` implements congestion-aware weighted Dijkstra routing for a 4×4 mesh network. Despite the legacy `bfs` filename, the algorithm is Dijkstra, not breadth-first search (BFS).



Each physical link must be enabled at both endpoints.



The link cost is:



`cost = 1 + 2 × max(endpoint congestion scores)`



Each endpoint has a 2-bit congestion score from 0 to 3. The router selects a minimum-total-cost path and uses deterministic tie-breaking when multiple paths have equal cost.



\## Interface



Inputs:

\- `current\_router\[3:0]`: Current router ID.

\- `dest\_router\[3:0]`: Destination router ID.

\- `link\_up\_map\[63:0]`: Four directional link-status bits per router.

\- `congestion\_map\[127:0]`: Four 2-bit directional congestion scores per router.



Outputs:

\- `next\_port\[2:0]`: Selected first-hop direction.

\- `route\_valid`: Indicates whether a route exists or the destination is local.

\- `destination\_reached`: Indicates the current router is the destination.



Port encoding:

\- NORTH = 0

\- SOUTH = 1

\- EAST = 2

\- WEST = 3

\- LOCAL = 4



Router IDs use `router\_id = 4\*y + x`.



\## Verification



Testbenches are located in `tb/`. Run the available routing, fault, no-route, congestion, path, trace, and regression tests using the simulator supported by the project.



The path and trace testbenches may require a writable results directory. Configure output paths for the local environment before running them.



\## Integration limitation



This module produces a routing decision; it does not itself implement packet forwarding. Integration with the router datapath must consume `next\_port` and handle `route\_valid` and `destination\_reached` consistently.



The complete network must separately address deadlock freedom, routing-state updates, and packet-forwarding behavior.

