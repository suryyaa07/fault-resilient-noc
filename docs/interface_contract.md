
# Fault-Resilient 4x4 Mesh NoC
## Hardware Interface Contract - Draft v0.1

Status: DRAFT - pending team approval  
Integration branch: integration/system

## 1. System Overview

The design targets a 4x4 mesh Network-on-Chip with:

- Five-port routers and input FIFOs
- Ready/valid flow control
- CRC-8 packet integrity checking
- ACK/NACK-based retransmission
- Link-health monitoring and quarantine
- Fault-aware adaptive routing using weighted Dijkstra
- Probe-based link recovery

A complete mesh contains 16 routers and 24 undirected
neighbor connections, equivalent to 48 directed channels.

## 2. Packet Format - Implemented

Packet width: 56 bits

| Bits | Field | Width |
|---|---|---|
| [55:52] | Source router ID | 4 |
| [51:48] | Destination router ID | 4 |
| [47:40] | Packet ID | 8 |
| [39:8] | Payload | 32 |
| [7:0] | CRC-8 | 8 |

CRC parameters used by the recovery implementation:

- Polynomial: 0x07
- Initial remainder: 0x00
- Processing order: MSB first
- Protected data: packet[55:8]

Packet IDs must not be reused while an older packet with
the same source and packet ID can still be retransmitted
or duplicated.

## 3. Router Port Numbering - Implemented

| Port number | Direction |
|---|---|
| 0 | North |
| 1 | South |
| 2 | East |
| 3 | West |
| 4 | Local |

For router ID `r`:

- x = r % 4
- y = r / 4

X increases eastward.
Y increases southward.

Valid router IDs: 0 through 15.

## 4. Ready/Valid Handshake - Integration Tested

A transfer occurs on a rising clock edge when:

    valid && ready

The transmitting module must maintain valid and hold
packet data stable while valid is asserted and ready
is deasserted.

No packet may be removed from a FIFO solely because
valid is asserted.

Reset is named `rst` and is active high in the
currently implemented modules.

## 5. Receiver-to-Router Interface - Integration Tested

Module: link_rx_wrapper

Protected-link input:

    link_valid
    link_ready
    link_packet[55:0]

Router-facing output:

    router_valid
    router_ready
    router_packet[55:0]

Feedback outputs:

    ack_out
    nack_out

The receiver validates CRC before accepting new packets.
It buffers an accepted packet and respects downstream
router backpressure.

Its duplicate-suppression mechanism uses packet identity
derived from source router ID and packet ID.

The receiver must not acknowledge a new packet unless
it has accepted or safely buffered that packet.

## 6. Router Interface — Implemented

Module: router_5port

Parameters:

    DATA_WIDTH = 56
    ROUTER_ID = 0
    ADAPTIVE_ROUTING = 0

The router has five input channels and five output channels:
North, South, East, West and Local.

Inputs:

    north_in[55:0]
    south_in[55:0]
    east_in[55:0]
    west_in[55:0]
    local_in[55:0]
    in_valid[4:0]
    out_ready[4:0]

Outputs:

    north_out[55:0]
    south_out[55:0]
    east_out[55:0]
    west_out[55:0]
    local_out[55:0]
    in_ready[4:0]
    out_valid[4:0]

The router supports input FIFOs, arbitration, deterministic XY routing
and optional adaptive routing.

The adaptive-routing interface includes:

    adaptive_enable
    link_up_map[63:0]
    congestion_map[127:0]

When ADAPTIVE_ROUTING is enabled and adaptive_enable is asserted,
the router uses the route selected by mesh_bfs_route.

When adaptive routing is disabled or adaptive_enable is deasserted,
the router uses deterministic XY routing.

If adaptive routing is enabled but no valid route is available,
the router does not fall back to XY routing.

The FIFO depth used by the current router implementation is 4.
## 7. Link Health Interface - Unit Tested

Module: link_health_manager

Event inputs:

    success_event
    failure_event
    probe_success
    probe_failure

Status outputs:

    health_state[1:0]
    link_available
    link_quarantined

The current RTL determines:

    link_available = (health_state != QUARANTINED)

    link_quarantined = (health_state == QUARANTINED)

The thresholds are parameterized.

Each directed channel must have an explicitly defined
health status and corresponding routing availability.

## 8. Adaptive Routing Interface — Implemented

RTL module: mesh_bfs_route

Source file: rtl/routing/mesh_bfs_route.v

Despite the historical filename, the current implementation uses
a weighted Dijkstra shortest-path algorithm, not BFS.

Inputs:

    current_router
    dest_router
    link_up_map
    congestion_map

Outputs:

    next_port
    route_valid
    destination_reached

The algorithm considers available links and endpoint congestion
when calculating a minimum-cost path.

The link cost is:

    1 + 2 * max(endpoint congestion scores)

The current router integration works as follows:

1. router_5port instantiates mesh_bfs_route when
   ADAPTIVE_ROUTING is enabled.
2. adaptive_enable selects adaptive routing instead of XY routing.
3. The 4x4 mesh instantiates routers with ADAPTIVE_ROUTING enabled.
4. The mesh passes its generated link-availability map to each router.
5. Configured fault injection can disable an adjacent mesh connection
   and allow the routing algorithm to select an alternative path.

The mesh currently supplies an all-zero congestion map.
Therefore, the routing module accepts congestion information, but
live congestion-aware routing is not active at the mesh level.

The mesh fault-injection mechanism is separate from the
link_health_manager. Quarantine status from the link-health manager
is not yet automatically connected to the mesh link-availability map.

The algorithm's shortest-path calculation does not, by itself,
guarantee deadlock freedom or livelock freedom.
## 9. Retransmission and ACK/NACK Limitations

The current protected-link recovery implements bounded
stop-and-wait retransmission.

ACK/NACK feedback does not carry an explicit packet ID
or transaction sequence number.

Therefore, handling delayed feedback across transaction
boundaries requires timing or protocol assumptions,
or an enhanced tagged-feedback interface.

Duplicate suppression also requires a packet-ID reuse
policy.

Full arbitrary-delay exactly-once delivery is NOT
claimed by the current implementation.

## 10. Verification Status

The repository contains testbenches covering the following areas:

- CRC-8 generation and checking
- Link-health state transitions and probe-based recovery
- Retransmission, timeout and retry exhaustion
- Protected-link and receiver-wrapper behaviour
- Recovery-to-router integration and backpressure
- Router FIFO and contention behaviour
- 4x4 mesh traffic and stress scenarios
- Adaptive routing, congestion inputs and fault-aware rerouting

The routing test suite includes checks for:

- Minimum-cost path selection
- Congestion-dependent route selection
- Disconnected networks and NO_ROUTE conditions
- Local-destination handling
- Fault-aware route selection

Previously executed routing verification reported passing congestion and standalone routing tests. Individual test results should not be interpreted as proof of complete end-to-end mesh correctness.

Remaining verification and integration work:

- Connect live congestion measurements to the mesh routing inputs.
- Connect link-health quarantine status to the mesh link-availability map.
- Verify simultaneous traffic with multiple concurrent link failures.
- Analyse deadlock and livelock behaviour.
- Measure end-to-end packet delivery, latency, throughput and recovery performance.
## 11. Team Ownership

Recovery RTL and protected-link behavior:
Surya

Router, FIFO, arbitration, and mesh integration:
Rahul

Fault-aware BFS routing:
Adwaith

Shared interface changes must be reviewed before
merging into the main branch.

## 12. Integration Rules

1. Preserve the existing passing recovery-to-router
   regression as a baseline.
2. Use separate feature branches for subsystem changes.
3. Integrate changes into integration/system first.
4. Do not push unverified changes directly to main.
5. Run relevant regressions after interface changes.
6. Document any packet format or handshake changes.
7. Do not claim full-mesh correctness based solely on
   individual module tests.

## 13. Pending Team Approvals

- [ ] Rahul confirms router and mesh interfaces.
- [ ] Adwaith confirms BFS inputs and outputs.
- [ ] Team agrees on routing request/result timing.
- [ ] Team agrees on per-directed-link health mapping.
- [ ] Team agrees on deadlock-handling strategy.
- [ ] Team approves the final integration interface.


