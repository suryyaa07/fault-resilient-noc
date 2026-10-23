
# Fault-Resilient 4x4 Mesh NoC
## Hardware Interface Contract — Draft v0.1

Status: DRAFT — pending team approval  
Integration branch: integration/system

## 1. System Overview

The design targets a 4x4 mesh Network-on-Chip with:

- Five-port routers and input FIFOs
- Ready/valid flow control
- CRC-8 packet integrity checking
- ACK/NACK-based retransmission
- Link-health monitoring and quarantine
- Fault-aware BFS rerouting
- Probe-based link recovery

A complete mesh contains 16 routers and 24 undirected
neighbor connections, equivalent to 48 directed channels.

## 2. Packet Format — Implemented

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

## 3. Router Port Numbering — Implemented

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

## 4. Ready/Valid Handshake — Integration Tested

A transfer occurs on a rising clock edge when:

    valid && ready

The transmitting module must maintain valid and hold
packet data stable while valid is asserted and ready
is deasserted.

No packet may be removed from a FIFO solely because
valid is asserted.

Reset is named `rst` and is active high in the
currently implemented modules.

## 5. Receiver-to-Router Interface — Integration Tested

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

The current implementation uses deterministic XY
routing, input FIFOs, and arbitration.

Its output FIFO-pop control depends on the granted
input and the selected output's readiness.

The existing router does NOT expose a BFS next-hop
selection interface.

## 7. Link Health Interface — Unit Tested

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

## 8. BFS Integration — NOT YET IMPLEMENTED

The BFS manager must provide a next-hop decision for
a specified source/current router and destination,
accounting for unavailable connections.

A proposed interface is:

    route_request
    current_router_id[3:0]
    destination_router_id[3:0]
    next_hop_valid
    next_hop_port[2:0]
    route_unavailable

This is a PROPOSAL, not an existing module interface.

Proposed next-hop encodings:

    0 = North
    1 = South
    2 = East
    3 = West
    4 = Local

Before implementation, Rahul and Adwaith must agree on:

1. The actual BFS RTL module interface.
2. Whether routing is combinational or multi-cycle.
3. How router arbitration waits for a route result.
4. How route requests and results are associated.
5. How route availability updates are distributed.
6. How local-link quarantine affects output selection.
7. How no-route conditions are handled.
8. How deadlock and livelock risks are addressed.

The router must not forward using a stale BFS decision.

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

Completed local tests:

- Recovery module unit tests
- Receiver wrapper verification
- Protected-link verification
- Recovery-to-router integration:
  - Clean packet delivery
  - CRC corruption and retry
  - Lost ACK and duplicate suppression
  - Router output backpressure

Outstanding system tests:

- Multi-input router contention and fairness
- FIFO saturation and sustained backpressure
- BFS next-hop interface integration
- Alternative routing around quarantined links
- Full 4x4 mesh connectivity
- Simultaneous traffic and faults
- Deadlock/livelock analysis
- End-to-end delivery and recovery metrics

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
