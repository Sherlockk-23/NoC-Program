# Report for lab1

## Task 1 & 2

See Following Table , I iterated through the GlobalFrequency parameter and ran many experiments, which includes **Reception** and
**units of statistical variables**.


| GlobalFrequency     | packets\_injected (Count) | packets\_received (Count) | average\_packet\_queueing\_latency (Tick) | average\_packet\_network\_latency (Tick) | average\_packet\_latency (network + queueing) (Tick) | average\_hops (Count) | reception\_rate (packets/node/cycle) |
| :-------- | :------------------------ | :------------------------ | :---------------------------------------- | :--------------------------------------- | :--------------------------------------------------- | :-------------------- | :----------------------------------- |
| **1ps**   | 5                         | 2                         | 1000                                      | 3000                                     | 4000                                                 | 1.500000              | 0.000003                             |
| **5ps**   | 31                        | 26                        | 200                                       | 1296.153846                              | 1496.153846                                          | 4.961538              | 0.000041                             |
| **10ps**  | 68                        | 64                        | 100                                       | 669.531250                               | 769.531250                                           | 5.187500              | 0.000100                             |
| **50ps**  | 300                       | 295                       | 20                                        | 131.254237                               | 151.254237                                           | 5.050847              | 0.000461                             |
| **100ps** | 619                       | 618                       | 10                                        | 67.467638                                | 77.467638                                            | 5.237864              | 0.000966                             |
| **10GHz** | 619                       | 618                       | 10                                        | 67.467638                                | 77.467638                                            | 5.237864              | 0.000966                             |
| **5GHz**  | 1242                      | 1237                      | 6                                         | 40.738884                                | 46.738884                                            | 5.283751              | 0.001933                             |
| **2GHz**  | 3165                      | 3162                      | 2                                         | 13.557559                                | 15.557559                                            | 5.269450              | 0.004941                             |
| **1GHz**  | 6296                      | 6288                      | 2                                         | 13.557411                                | 15.557411                                            | 5.269084              | 0.009825                             |

The bash code for reception rate is
```
# Calculate reception rate: packets_received / num_cpus / sim_cycles
packets_received=$(grep "packets_received::total" m5out/stats.txt | awk '{print $2}')

if [ ! -z "$packets_received" ] && [ "$packets_received" != "0" ]; then
    # Use awk for floating point calculation since bc might not be available
    reception_rate=$(awk "BEGIN {printf \"%.6f\", $packets_received / ($num_cpus * $sim_cycles)}")
    echo "reception_rate = $reception_rate" >> network_stats.txt
else
    echo "reception_rate = 0.000000" >> network_stats.txt
fi

```

## Task 3:

### Input Parameter Options for `garnet_synth_traffic.py`

The main arguments for the `garnet_synth_traffic.py` are listed below.
| Option                | Description   | Default Value |  Where Defined |
|-----------------------|-------------------------------------------------------------------------------------------------| -----------------| ----------------- |
| `--synthetic`           | Type of synthetic traffic to generate. Options include `uniform_random`, `bit_complement`, `bit_reverse`, etc. | `uniform_random` | In `garnet_synth_traffic.py` |
| `--injectionrate`  and `--precision`    | Injection rate in packets per cycle per node. This is a floating-point value that specifies the probability that a packet is injected to a note at each cycle.  The precision defines its number of digits of precision after decimal, | `0.1` and `3` | In `garnet_synth_traffic.py` |
| `--inj-vnet`            | Virtual network to use for injection. Default is `0`. | `0` | In `garnet_synth_traffic.py` |
| `--sim-cycles`           | Number of simulation cycles to run. This is an integer value that specifies how long the simulation should run. | `1000` | In `garnet_synth_traffic.py` |
| `--num-packets-max` | Maximum number of packets to generate. This is an integer value that limits the total number of packets generated during the simulation. | `-1` | In `garnet_synth_traffic.py` |
| `--single-sender-id` and  `--single-dest-id`   | Only inject or dest from this sender. | `-1` | In `garnet_synth_traffic.py` |
| `--inj-vnet`        | Virtual network to use for injection.  | `-1` | In `garnet_synth_traffic.py` |
| `--router-latency`  | NNumber of pipeline stages in the garnet router. | `1` | In `Network.py` |
| `--link-latency` | Link latency in network. | `1` | In `Network.py` |
| `--link-width-bits` | Width of the links in bits. This is an integer value that specifies the width of the links in the network. | `128` | In `Network.py` |
| `--vcs-per-vnet` | Number of virtual channels per virtual network. This is an integer value that specifies how many virtual channels are available for each virtual network. | `2` | In `Network.py` |

### Unit of some parameters.
- **sim-cycles**: The unit is cycles. It represents the number of cycles the simulation will run.
- **router-latency** and **link-latency**: The unit is cycles. It represents how many cycles it takes for a packet to traverse through the router or link.
- Relationship between **Tick** and **Cycle**:
  A cycle is the minimum time unit in the simulation, while a tick can be defined to be a multiple of cycles, depending on the configuration of the simulation.
- **injectionrate**: The unit is packets per cycle per node. It represents the probability of a packet being injected into the network at each cycle.


### Where are the GarnetNetworkInterface and GarnetRouter defined?

- **GarnetNetworkInterface**: Defined in `src/mem/ruby/network/garnet/NetworkInterface.hh` and `NetworkInterface.cc`.
- **GarnetRouter**: Defined in `src/mem/ruby/network/garnet/Router.hh` and `Router.cc`.

### In which module(s) and packet handling occurs?
- **Packet Generation and Injection**:
  - Packets are generated in the `GarnetSyntheticTraffic::generatePkt()` function and `GarnetSyntheticTraffic::tick()`, and sent in `GarnetSyntheticTraffic::sendPkt()` function in `src/cpu/testers/garnet_synthetic_traffic/GarnetSyntheticTraffic.cc`. Then the packets are injected into the network through the `NetworkInterface::flitisizeMessage()` function.
- **Packet Buffering**:

  1. **Buffer in NetworkInterface**: The `NetworkInterface::flitisizeMessage()` converts messages to flits and buffers them in the `MessageBuffer` in NI.

  2. **Buffer in Routers**: Routers also maintain buffers for incoming and outgoing flits. In `InputUnit::wakeup()` function, a flit is buffered in the corresponding vc buffer. And in `CrossbarSwitch::wakeup()`, a flit well be transfer and buffered in the next outport buffer.


- **Packet Downstreaming**

  1. **Switch Allocator (`SwitchAllocator.cc`)**:
  Arbitrates for crossbar resources in SA_ stage

  2. **Virtual Channel Allocator (within SwitchAllocator)**: Allocates virtual channels in VA_ stage

  3. **Router (`Router.cc`)**: `Router::route_compute` - Pick an outport for certain flit according to the algorithm.

  4. **NetworkInterface (`NetworkInterface.cc`)**:
      - `NetworkInterface::scheduleOutputLink()` - Determines if flits can be sent to downstream routers
      - `NetworkInterface::wakeup()` - Checks for ready flits and credit availability

  5. **InputUnit::wakeup()**: Manages flit buffering and decide its outport and sometimes vc.

  6. **OutputUnit::has_free_vc()**: Check whether the flit can be sent to the downstream router by verifying virtual channel availability.
