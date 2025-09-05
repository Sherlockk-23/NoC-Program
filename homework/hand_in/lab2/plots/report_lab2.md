## Task 1

The script is like
```
./build/NULL/gem5.opt \
configs/example/garnet_synth_traffic.py \
--network=garnet --num-cpus=$num_cpus \
--num-dirs=$num_dirs \
--topology=Mesh_XY --mesh-rows=$mesh_rows \
--inj-vnet=$inj_vnet --synthetic=$pattern \
--sim-cycles=$sim_cycles \
--injectionrate=$rate \
--global-frequency=$global_frequency \
```


 I plotted the latency and average hops against throughput for all kinds of traffic patterns. Some basic results are analysed as follow:

![](./plots/task1_injection_rate_latency.png)

### Latency v.s. Throughput for different patterns:

1. Zero-load latency differs from all kind of patterns. Pattern **neighbour** has the lowest zero-load latency, while pattern **transpose** has the highest.

2. As the injection rate increases, the latency increases slowly at first, then rises sharply after a certain point (the saturation point). The saturation point varies for different patterns. Pattern **neighbour** has the highest saturation point, while pattern **transpose** has the lowest.

3. The order of their saturation points from highest to lowest is almost the same to to order of their zero-load latency.

![](./plots/latency_components_analysis.png)


### Queueing v.s. Network Latency for different patterns:

1. For all patterns, when the injection rate is low, the network latency is larger than the queuing latency. Then, as the injection rate increases, both latency increases. As the network latency increases slowly,  the queuing latency increases extremely fast to be the main component of the overall latency.

2. As an exception, both latency of the **neighbour** pattern hardly increases, remaining low since the pattern hardly has to wait.

3. Network latency of all patterns are hard to be compared since they're all low. The order of their queuing latencies from highest to lowest is almost the same as the order of their overall latencies.

![](./plots/task1_hops_analysis.png)

### Average Hops v.s. Throughput for different patterns:

1. Basically, the average hops of all patterns remain constant as the injection rate increases. The average hops of pattern **neighbour** stays at $1$,  while that of pattern **uniform random** is the highest, at $5$.

2. As an exception, the average hops of **transpose** drop dramatically as it reaches saturate point. This may be because
many packets with long hops is blocked in the queue, and only those with short distance reached their destination successfully, leading to a drop in the ave hops count.

## Task2

The script is like:
```
./build/NULL/gem5.opt \
    configs/example/garnet_synth_traffic.py \
    --network=garnet --num-cpus=$num_cpus \
    --num-dirs=$num_dirs \
    --topology=Mesh_XY --mesh-rows=$mesh_rows \
    --inj-vnet=$inj_vnet --synthetic=$base_pattern \
    --sim-cycles=$sim_cycles \
    --injectionrate=$rate \
    --vcs-per-vnet=$vcs \
    --global-frequency=$global_frequency \
```

![](./plots/task2_vcs_effect.png)

![](./plots/task2_router_latency_effect.png)

![](./plots/task2_link_width_effect.png)

 I plotted the latency v.s. throughput for in different vcs-per-vnet, router-latency, link-width-bits and the same uniform-random pattern. Some basic results are analysed as follow:

1. **vcs-per-vnet**. Higher vcs-per-net simply means higher saturate point. Before reaching the saturate point, this hardly leads to changes in latency.

2. **router-latency**. Higher router-latency leads to higher overall latency.  It can also cause an advance ofthe saturate point, because that should delay the waitings in the network.

3. **link-width** This term works almost the same with vcs-per-vnet.


## Task3

### **network latency**
1. It consists of the queuing latency and network latency, which refer to packets' waiting time and transmission time, respectively.

2. At a low load, the network latency is the dominant factor in the overall latency, since there should be almost no queuing. As the load increases, the queuing latency increases quickly, surpassing the network latency.

3. With a wide linkwidth or large vc-per-net, the network latency is the dominant factor in the overall latency, since there should be almost no queuing. As the linkwidth or vc-per-net decreases, the queuing latency increases quickly, surpassing the network latency.

### **depth of input budder**
- buffers_per_data_vc = 4

- buffers_per_ctrl_vc = 1


### **default flow control**
Vitual Channel flow control.
