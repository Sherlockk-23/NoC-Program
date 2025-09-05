# Report for Lab1 - Copilot Version

## Task 3: Answer the Questions

### Input Parameter Options for `garnet_synth_traffic.py`

Based on the source code analysis, the main arguments for the `garnet_synth_traffic.py` are listed below:

| Option                | Description   | Default Value |  Where Defined |
|-----------------------|-------------------------------------------------------------------------------------------------| -----------------| ----------------- |
| `--synthetic`           | Type of synthetic traffic to generate. Options include `uniform_random`, `tornado`, `bit_complement`, `bit_reverse`, `bit_rotation`, `neighbor`, `shuffle`, `transpose` | `uniform_random` | In `configs/example/garnet_synth_traffic.py` |
| `--injectionrate` (`-i`)     | Injection rate in packets per cycle per node. Takes decimal value between 0 to 1 (e.g., 0.225). Number of digits after decimal depends upon --precision.  | `0.1` | In `configs/example/garnet_synth_traffic.py` |
| `--precision`            | Number of digits of precision after decimal point for injection rate | `3` | In `configs/example/garnet_synth_traffic.py` |
| `--sim-cycles`           | Number of simulation cycles to run. This is an integer value that specifies how long the simulation should run. | `1000` | In `configs/example/garnet_synth_traffic.py` |
| `--num-packets-max` | Maximum number of packets to generate. This is an integer value that limits the total number of packets generated during the simulation. Set to -1 to disable. | `-1` | In `configs/example/garnet_synth_traffic.py` |
| `--single-sender-id`   | Only inject from this sender. Set to -1 to disable. | `-1` | In `configs/example/garnet_synth_traffic.py` |
| `--single-dest-id`     | Only send to this destination. Set to -1 to disable. | `-1` | In `configs/example/garnet_synth_traffic.py` |
| `--inj-vnet`        | Virtual network to use for injection. Only inject in this vnet (0, 1 or 2). 0 and 1 are 1-flit, 2 is 5-flit. Set to -1 to inject randomly in all vnets. | `-1` | In `configs/example/garnet_synth_traffic.py` |
| `--global-frequency` | Set the global frequency for the simulation. Default is 1ps, which is suitable for Garnet. | `1ps` | In `configs/example/garnet_synth_traffic.py` |
| `--router-latency`  | Number of pipeline stages in the garnet router. Has to be >= 1. Can be overridden on a per router basis in the topology file. | `1` | In `configs/network/Network.py` |
| `--link-latency` | Latency of each link in the simple/garnet networks. Has to be >= 1. Can be overridden on a per link basis in the topology file. | `1` | In `configs/network/Network.py` |
| `--link-width-bits` | Width of the links in bits. This is an integer value that specifies the width of the links in the network. | `128` | In `configs/network/Network.py` |
| `--vcs-per-vnet` | Number of virtual channels per virtual network inside garnet network. | `4` | In `configs/network/Network.py` |

### Units of Parameters

- **sim-cycles**: The unit is **cycles**. It represents the number of cycles the simulation will run.
- **router-latency** and **link-latency**: The unit is **cycles**. It represents how many cycles it takes for a packet to traverse through the router or link.
- **Relationship between Tick and Cycle**:
  - A **Tick** is the fundamental time unit in gem5, measured in picoseconds (ps) by default.
  - A **Cycle** is a higher-level time unit defined by the clock frequency.
  - Relationship: `Cycles = Ticks / Clock_Period_in_Ticks`
  - The conversion is handled by gem5's clock domains. For example, if global frequency is set to "1GHz", then 1 cycle = 1000 ticks (1000 ps).
- **injectionrate**: The unit is **packets per cycle per node**. It represents the probability of a packet being injected into the network at each cycle for each node.

### Where are GarnetNetworkInterface and GarnetRouter defined?

- **GarnetNetworkInterface**: Actually called `NetworkInterface` in the code
  - Header file: `src/mem/ruby/network/garnet/NetworkInterface.hh`
  - Implementation: `src/mem/ruby/network/garnet/NetworkInterface.cc`
- **GarnetRouter**: Called `Router` in the code
  - Header file: `src/mem/ruby/network/garnet/Router.hh`
  - Implementation: `src/mem/ruby/network/garnet/Router.cc`

### Packet Generation, Buffering, and Flow Control Modules

#### Packet Generation and Injection:
- **Module**: `GarnetSyntheticTraffic`
  - **Location**: `src/cpu/testers/garnet_synthetic_traffic/GarnetSyntheticTraffic.cc`
  - **Key Functions**:
    - `GarnetSyntheticTraffic::generatePkt()` - Generates packets according to traffic patterns
    - `GarnetSyntheticTraffic::tick()` - Main simulation loop that calls packet generation
  - **Process**: The synthetic traffic generator creates packets based on the specified traffic pattern (uniform_random, tornado, etc.) and injection rate, then sends them to the NetworkInterface.

#### Packet Buffering During Transmission:
Multiple modules handle packet buffering at different levels:

1. **NetworkInterface (`NetworkInterface.cc`)**:
   - **Input/Output Buffers**: Buffers packets between the processor and network
   - **Function**: `NetworkInterface::flitisizeMessage()` - Converts messages to flits and buffers them

2. **Router Components**:
   - **InputUnit**: `src/mem/ruby/network/garnet/InputUnit.hh/cc`
     - Contains `VirtualChannel` objects with `flitBuffer` for input buffering
   - **OutputUnit**: `src/mem/ruby/network/garnet/OutputUnit.hh/cc`
     - Contains output buffers for outgoing flits
   - **VirtualChannel**: `src/mem/ruby/network/garnet/VirtualChannel.hh/cc`
     - Individual VC buffers using `flitBuffer` class

3. **flitBuffer**: `src/mem/ruby/network/garnet/flitBuffer.hh/cc`
   - Low-level buffer implementation for storing flits

#### Flow Control and Downstream Decisions:
Multiple modules determine if packets can be sent downstream:

1. **Switch Allocator (`SwitchAllocator.cc`)**:
   - **Function**: Arbitrates for crossbar resources in SA_ stage
   - **Decision Logic**: Determines which flits can traverse the switch fabric

2. **Virtual Channel Allocator (within SwitchAllocator)**:
   - **Function**: Allocates virtual channels in VA_ stage
   - **Decision Logic**: Manages VC allocation for deadlock avoidance

3. **Router (`Router.cc`)**:
   - **Function**: `Router::wakeup()` - Coordinates overall router operation
   - **Decision Logic**: Manages the 5-stage pipeline (I_, VA_, SA_, ST_, LT_)

4. **NetworkInterface (`NetworkInterface.cc`)**:
   - **Functions**:
     - `NetworkInterface::scheduleOutputLink()` - Determines if flits can be sent to downstream routers
     - `NetworkInterface::wakeup()` - Checks for ready flits and credit availability
   - **Decision Logic**: Credit-based flow control with downstream routers

5. **Credit-based Flow Control**:
   - **CreditLink**: `src/mem/ruby/network/garnet/CreditLink.hh/cc`
   - **Function**: Manages upstream credit signals to prevent buffer overflow
   - **Decision Logic**: Downstream modules send credits back to upstream when buffers become available

## Summary

The Garnet network simulator implements a sophisticated packet injection, buffering, and flow control system:

- **Packet Generation**: Centralized in `GarnetSyntheticTraffic` with configurable traffic patterns
- **Multi-level Buffering**: From NetworkInterface down to individual VirtualChannel buffers
- **Distributed Flow Control**: Router pipeline stages, credit-based backpressure, and VC allocation work together to manage packet flow and prevent deadlocks

This modular design allows for realistic modeling of on-chip network behavior with precise control over traffic injection patterns and network parameters.
