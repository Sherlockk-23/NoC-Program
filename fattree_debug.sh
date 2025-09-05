# FatTree

./build/NULL/gem5.opt \
    --debug-flags=RubyNetwork \
    configs/example/garnet_synth_traffic.py \
    --network=garnet --num-cpus=16 \
    --num-dirs=16 \
    --topology=FatTree  --routing-algorithm=8 \
    --fattree-k=4 \
    --ada-type=1 \
    --vcs-per-vnet=4 \
    --inj-vnet=0 --synthetic=uniform_random \
    --sim-cycles=10000 \
    --injectionrate=0.2 \
    --global-frequency=10GHz \
    > debug.txt

echo > network_stats.txt
grep "packets_injected::total" m5out/stats.txt | sed 's/system.ruby.network.packets_injected::total\s*/packets_injected = /' >> network_stats.txt
grep "packets_received::total" m5out/stats.txt | sed 's/system.ruby.network.packets_received::total\s*/packets_received = /' >> network_stats.txt
grep "average_packet_queueing_latency" m5out/stats.txt | sed 's/system.ruby.network.average_packet_queueing_latency\s*/average_packet_queueing_latency = /' >> network_stats.txt
grep "average_packet_network_latency" m5out/stats.txt | sed 's/system.ruby.network.average_packet_network_latency\s*/average_packet_network_latency = /' >> network_stats.txt
grep "average_packet_latency" m5out/stats.txt | sed 's/system.ruby.network.average_packet_latency\s*/average_packet_latency = /' >> network_stats.txt
grep "average_hops" m5out/stats.txt | sed 's/system.ruby.network.average_hops\s*/average_hops = /' >> network_stats.txt

# Calculate reception rate: packets_received / num_cpus / sim_cycles
packets_received=$(grep "packets_received::total" m5out/stats.txt | awk '{print $2}')

if [ ! -z "$packets_received" ] && [ "$packets_received" != "0" ]; then
    # Use awk for floating point calculation since bc might not be available
    reception_rate=$(awk "BEGIN {printf \"%.6f\", $packets_received / ($num_cpus * $sim_cycles)}")
    echo "reception_rate = $reception_rate" >> network_stats.txt
else
    echo "reception_rate = 0.000000" >> network_stats.txt
fi
