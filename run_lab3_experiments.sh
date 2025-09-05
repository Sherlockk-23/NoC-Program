#!/bin/bash

# Lab3实验脚本：拓扑与流控制分析
# 包含Ring拓扑、不同拓扑对比、Wormhole流控制实验

set -e  # 错误时退出

# 检查gem5是否已构建
if [ ! -f "build/NULL/gem5.opt" ]; then
    echo "错误: gem5未构建，请先运行 scons build/NULL/gem5.opt"
    exit 1
fi

# 创建结果目录
mkdir -p lab3_results/{ring_traffic,topology_comparison,wormhole_analysis}/data

echo "=========================================="
echo "         Lab3: 拓扑与流控制实验"
echo "=========================================="

# 基本参数
num_cpus=16
num_dirs=16
mesh_rows=4
sim_cycles=100000
injection_rates="0.01 0.02 0.05 0.1 0.15 0.2 0.25 0.3"
traffic_patterns="uniform_random tornado neighbor shuffle"
all_traffic_patterns="uniform_random tornado transpose neighbor shuffle"

# ==========================================
# Task 1: Ring拓扑下不同流量模式分析
# ==========================================
echo ""
echo "=== Task 1: Ring拓扑下不同流量模式分析 ==="

vcs_configs=(2 4)

for vcs in "${vcs_configs[@]}"; do
    echo ""
    echo "-- VCs per VNet: $vcs --"

    # 创建结果文件
    result_file="lab3_results/ring_traffic/data/ring_vcs${vcs}_results.txt"
    echo "# traffic_pattern injection_rate packets_injected packets_received avg_packet_latency avg_queueing_latency avg_network_latency avg_hops reception_rate" > "$result_file"

    for pattern in $all_traffic_patterns; do
        echo ""
        echo "  测试流量模式: $pattern"

        for rate in $injection_rates; do
            echo "    注入率: $rate"

            # 运行仿真
            ./build/NULL/gem5.opt \
            configs/example/garnet_synth_traffic.py \
            --network=garnet --num-cpus=$num_cpus \
            --num-dirs=$num_dirs \
            --topology=Ring \
            --routing-algorithm=2 \
            --vcs-per-vnet=$vcs \
            --inj-vnet=0 --synthetic=$pattern \
            --sim-cycles=$sim_cycles \
            --garnet-deadlock-threshold=$sim_cycles \
            --injectionrate=$rate \
            --global-frequency=10GHz \
            > lab3_results/ring_traffic/${pattern}_vcs${vcs}_${rate}.log 2>&1

            # 检查仿真是否成功
            if [ $? -eq 0 ]; then
                # 提取统计数据
                packets_injected=$(grep "packets_injected::total" m5out/stats.txt | awk '{print $2}')
                packets_received=$(grep "packets_received::total" m5out/stats.txt | awk '{print $2}')
                avg_packet_latency=$(grep "average_packet_latency" m5out/stats.txt | awk '{print $2}')
                avg_queueing_latency=$(grep "average_packet_queueing_latency" m5out/stats.txt | awk '{print $2}')
                avg_network_latency=$(grep "average_packet_network_latency" m5out/stats.txt | awk '{print $2}')
                avg_hops=$(grep "average_hops" m5out/stats.txt | awk '{print $2}')

                # 计算接收率
                if [ ! -z "$packets_received" ] && [ "$packets_received" != "0" ]; then
                    reception_rate=$(awk "BEGIN {printf \"%.6f\", $packets_received / ($num_cpus * $sim_cycles)}")

                    echo "      ✓ 完成 - 延迟: $avg_packet_latency cycles"

                    # 保存数据
                    echo "$pattern $rate $packets_injected $packets_received $avg_packet_latency $avg_queueing_latency $avg_network_latency $avg_hops $reception_rate" >> "$result_file"
                else
                    echo "      ✗ 失败 - 无包接收"
                fi
            else
                echo "      ✗ 仿真失败"
            fi
        done
    done
done

# ==========================================
# Task 2: 不同拓扑和路由算法对比
# ==========================================
echo ""
echo "=== Task 2: 不同拓扑和路由算法对比 ==="

# 拓扑配置
topologies=(
    "Mesh_XY 4 1 MeshXY"
    "Pt2Pt 0 0 Pt2Pt"
    "Crossbar 0 0 Crossbar"
    "Ring 0 0 RingTable"
    "Ring 0 2 RingAlgo"
)

for vcs in "${vcs_configs[@]}"; do
    echo ""
    echo "-- VCs per VNet: $vcs --"

    # 创建结果文件
    result_file="lab3_results/topology_comparison/data/topology_vcs${vcs}_results.txt"
    echo "# topology_config traffic_pattern injection_rate packets_injected packets_received avg_packet_latency avg_queueing_latency avg_network_latency avg_hops reception_rate" > "$result_file"

    for topo_config in "${topologies[@]}"; do
        read -r topology mesh_rows routing_algo config_name <<< "$topo_config"

        echo ""
        echo "  测试拓扑: $config_name"

        for pattern in $traffic_patterns; do
            echo "    流量模式: $pattern"

            for rate in $injection_rates; do
                echo "      注入率: $rate"

                # 构建命令
                cmd="./build/NULL/gem5.opt configs/example/garnet_synth_traffic.py"
                cmd+=" --network=garnet --num-cpus=$num_cpus --num-dirs=$num_dirs"
                cmd+=" --topology=$topology"

                if [ "$topology" == "Mesh_XY" ]; then
                    cmd+=" --mesh-rows=$mesh_rows"
                fi

                cmd+=" --routing-algorithm=$routing_algo"
                cmd+=" --vcs-per-vnet=$vcs"
                cmd+=" --inj-vnet=0 --synthetic=$pattern"
                cmd+=" --sim-cycles=$sim_cycles --injectionrate=$rate"
                cmd+=" --global-frequency=10GHz"
                cmd+=" --garnet-deadlock-threshold=$sim_cycles"

                # 运行仿真
                $cmd > lab3_results/topology_comparison/${config_name}_${pattern}_vcs${vcs}_${rate}.log 2>&1

                # 检查仿真是否成功
                if [ $? -eq 0 ]; then
                    # 提取统计数据
                    packets_injected=$(grep "packets_injected::total" m5out/stats.txt | awk '{print $2}')
                    packets_received=$(grep "packets_received::total" m5out/stats.txt | awk '{print $2}')
                    avg_packet_latency=$(grep "average_packet_latency" m5out/stats.txt | awk '{print $2}')
                    avg_queueing_latency=$(grep "average_packet_queueing_latency" m5out/stats.txt | awk '{print $2}')
                    avg_network_latency=$(grep "average_packet_network_latency" m5out/stats.txt | awk '{print $2}')
                    avg_hops=$(grep "average_hops" m5out/stats.txt | awk '{print $2}')

                    # 计算接收率
                    if [ ! -z "$packets_received" ] && [ "$packets_received" != "0" ]; then
                        reception_rate=$(awk "BEGIN {printf \"%.6f\", $packets_received / ($num_cpus * $sim_cycles)}")

                        echo "        ✓ 延迟: $avg_packet_latency cycles"

                        # 保存数据
                        echo "$config_name $pattern $rate $packets_injected $packets_received $avg_packet_latency $avg_queueing_latency $avg_network_latency $avg_hops $reception_rate" >> "$result_file"
                    else
                        echo "        ✗ 无包接收"
                    fi
                else
                    echo "        ✗ 仿真失败"
                fi
            done
        done
    done
done

# ==========================================
# Task 3: Wormhole流控制分析
# ==========================================
echo ""
echo "=== Task 3: Wormhole流控制分析 ==="

# Wormhole配置
wormhole_configs=(
    "1 1 VC1_1depth"
    "1 2 VC1_2depth"
    "2 1 VC2_1depth"
    "2 2 VC2_2depth"
)

# Wormhole兼容拓扑（排除Ring）
wormhole_topologies=(
    "Mesh_XY 4 1 MeshXY"
    "Pt2Pt 0 0 Pt2Pt"
    "Crossbar 0 0 Crossbar"
)


# for config in "${wormhole_configs[@]}"; do
# echo ""
# echo "-- Wormhole配置: $config_name --"

for config in "${wormhole_configs[@]}"; do
    # echo "${config}"
    read -r vcs depth config_name <<< "$config"

    echo ""
    echo "-- Wormhole配置: $config_name --"

    # 创建结果文件
    result_file="lab3_results/wormhole_analysis/data/wormhole_${config_name}_results.txt"
    echo "# topology_config traffic_pattern injection_rate packets_injected packets_received avg_packet_latency avg_queueing_latency avg_network_latency avg_hops reception_rate" > "$result_file"

    for topo_config in "${wormhole_topologies[@]}"; do
        read -r topology mesh_rows routing_algo topo_name <<< "$topo_config"

        echo ""
        echo "  测试拓扑: $topo_name"

        for pattern in $traffic_patterns; do
            echo "    流量模式: $pattern"

            for rate in $injection_rates; do
                echo "      注入率: $rate"

                # 构建命令
                cmd="./build/NULL/gem5.opt configs/example/garnet_synth_traffic.py"
                cmd+=" --network=garnet --num-cpus=$num_cpus --num-dirs=$num_dirs"
                cmd+=" --topology=$topology"

                if [ "$topology" == "Mesh_XY" ]; then
                    cmd+=" --mesh-rows=$mesh_rows"
                fi

                cmd+=" --routing-algorithm=$routing_algo"
                cmd+=" --vcs-per-vnet=$vcs"
                cmd+=" --wormhole=$depth"
                cmd+=" --inj-vnet=0 --synthetic=$pattern"
                cmd+=" --sim-cycles=$sim_cycles --injectionrate=$rate"
                cmd+=" --global-frequency=10GHz"
                cmd+=" --garnet-deadlock-threshold=$sim_cycles "

                # 运行仿真
                $cmd > lab3_results/wormhole_analysis/${topo_name}_${pattern}_${config_name}_${rate}.log 2>&1

                # 检查仿真是否成功
                if [ $? -eq 0 ]; then
                    # 提取统计数据
                    packets_injected=$(grep "packets_injected::total" m5out/stats.txt | awk '{print $2}')
                    packets_received=$(grep "packets_received::total" m5out/stats.txt | awk '{print $2}')
                    avg_packet_latency=$(grep "average_packet_latency" m5out/stats.txt | awk '{print $2}')
                    avg_queueing_latency=$(grep "average_packet_queueing_latency" m5out/stats.txt | awk '{print $2}')
                    avg_network_latency=$(grep "average_packet_network_latency" m5out/stats.txt | awk '{print $2}')
                    avg_hops=$(grep "average_hops" m5out/stats.txt | awk '{print $2}')

                    # 计算接收率
                    if [ ! -z "$packets_received" ] && [ "$packets_received" != "0" ]; then
                        reception_rate=$(awk "BEGIN {printf \"%.6f\", $packets_received / ($num_cpus * $sim_cycles)}")

                        echo "        ✓ 延迟: $avg_packet_latency cycles"

                        # 保存数据
                        echo "$topo_name $pattern $rate $packets_injected $packets_received $avg_packet_latency $avg_queueing_latency $avg_network_latency $avg_hops $reception_rate" >> "$result_file"
                    else

                        echo "        ✗ 无包接收"
                    fi
                else
                    echo "        ✗ 仿真失败"
                fi
            done
        done
    done
done

# # ==========================================
# # 生成实验总结
# # ==========================================
# echo ""
# echo "=== 生成实验总结 ==="

# cat > lab3_results/EXPERIMENT_SUMMARY.md << 'EOF'
# # Lab3实验总结

# ## 实验配置
# - 节点数: 16
# - 仿真周期: 100,000 cycles
# - 注入率范围: 0.01 - 0.3 packets/cycle/node
# - 流量模式: uniform_random, tornado, neighbor, shuffle (+ transpose for Ring)

# ## 实验任务

# ### Task 1: Ring拓扑流量模式分析
# - 拓扑: Ring (16节点)
# - 路由算法: Ring routing (算法2)
# - VCs配置: 1, 2
# - 流量模式: uniform_random, tornado, transpose, neighbor, shuffle

# ### Task 2: 拓扑和路由算法对比
# - 拓扑配置:
#   - Mesh_XY (4x4) + XY路由
#   - Pt2Pt + Table路由
#   - Crossbar + Table路由
#   - Ring + Table路由
#   - Ring + Ring路由
# - VCs配置: 1, 2
# - 流量模式: uniform_random, tornado, neighbor, shuffle

# ### Task 3: Wormhole流控制分析
# - 拓扑: Mesh_XY, Pt2Pt, Crossbar (排除Ring)
# - 配置组合:
#   - VC=1, Depth=1 (默认)
#   - VC=1, Depth=4
#   - VC=4, Depth=1
#   - VC=4, Depth=4 (Wormhole)
# - 流量模式: uniform_random, tornado, neighbor, shuffle

# ## 数据文件位置
# - Ring分析: lab3_results/ring_traffic/data/
# - 拓扑对比: lab3_results/topology_comparison/data/
# - Wormhole分析: lab3_results/wormhole_analysis/data/

# ## 下一步
# 运行分析脚本生成图表:
# ```bash
# python3 analyze_lab3_results.py
# ```
# EOF

# echo "实验总结已保存: lab3_results/EXPERIMENT_SUMMARY.md"

# echo ""
# echo "=========================================="
# echo "           Lab3实验完成!"
# echo "=========================================="
# echo ""
# echo "结果文件位置:"
# echo "- Task 1 数据: lab3_results/ring_traffic/data/"
# echo "- Task 2 数据: lab3_results/topology_comparison/data/"
# echo "- Task 3 数据: lab3_results/wormhole_analysis/data/"
# echo "- 实验总结: lab3_results/EXPERIMENT_SUMMARY.md"
# echo ""
# echo "运行分析脚本: python3 analyze_lab3_results.py"
# echo ""
