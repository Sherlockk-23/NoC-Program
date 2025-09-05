#!/bin/bash

# Lab4实验脚本：FatTree和SlimFly拓扑性能分析
# 包含自适应路由、死锁避免、多种流量模式测试

set -e  # 错误时退出

# 检查gem5是否已构建
if [ ! -f "build/NULL/gem5.opt" ]; then
    echo "错误: gem5未构建，请先运行 scons build/NULL/gem5.opt"
    exit 1
fi

# 创建结果目录
mkdir -p lab4_results/{fattree,slimfly}/data

echo "=========================================="
echo "         Lab4: 高级拓扑路由实验"
echo "=========================================="

# 基本参数
num_cpus=16
num_dirs=16
sim_cycles=50000
injection_rates="0.01 0.02 0.05 0.1 0.15 0.2 0.25 0.3 0.4 0.5 0.6 0.7 0.8"

# 流量模式定义
traffic_patterns=(
    # "uniform_random"
    # "tornado"
    # "shuffle"
    # "single_sender"     # --single-sender-id=3
    "single_dest"    # --single-dest-id=9
    # "single_pair"       # --single-sender-id=3 --single-dest-id=9
)

# ==========================================
# Task 1: FatTree 拓扑实验
# ==========================================
echo ""
echo "=== Task 1: FatTree 拓扑性能分析 ==="

# FatTree 配置
fattree_configs=(
    "4 0"   # k=4, ada-type=0 (非自适应)
    "4 1"   # k=4, ada-type=1 (自适应)
)

fattree_vcs_configs=(1 2 4 8)

for config in "${fattree_configs[@]}"; do
    read -r k ada_type <<< "$config"

    echo ""
    echo "-- FatTree k=$k, ada-type=$ada_type --"

    # 创建结果文件
    result_file="lab4_results/fattree/data/fattree_k${k}_ada${ada_type}_results.txt"
    echo "# vcs_per_vnet traffic_pattern injection_rate packets_injected packets_received avg_packet_latency avg_queueing_latency avg_network_latency avg_hops reception_rate" > "$result_file"

    for vcs in "${fattree_vcs_configs[@]}"; do
        echo ""
        echo "  VCs per VNet: $vcs"

        for pattern_info in "${traffic_patterns[@]}"; do
            echo "    流量模式: $pattern_info"

            for rate in $injection_rates; do
                echo "      注入率: $rate"

                # 构建基础命令
                cmd="./build/NULL/gem5.opt configs/example/garnet_synth_traffic.py"
                cmd+=" --network=garnet --num-cpus=$num_cpus --num-dirs=$num_dirs"
                cmd+=" --topology=FatTree --fattree-k=$k"
                cmd+=" --routing-algorithm=8"  # FATTREE_NON_ADAPTIVE
                cmd+=" --ada-type=$ada_type"
                cmd+=" --vcs-per-vnet=$vcs"
                cmd+=" --sim-cycles=$sim_cycles --injectionrate=$rate"
                cmd+=" --global-frequency=10GHz"
                cmd+=" --garnet-deadlock-threshold=$sim_cycles"

                # 根据流量模式添加特定参数
                case $pattern_info in
                    "uniform_random")
                        cmd+=" --inj-vnet=0 --synthetic=uniform_random"
                        ;;
                    "tornado")
                        cmd+=" --inj-vnet=0 --synthetic=tornado"
                        ;;
                    "shuffle")
                        cmd+=" --inj-vnet=0 --synthetic=shuffle"
                        ;;
                    "single_sender")
                        cmd+=" --inj-vnet=0 --synthetic=uniform_random"
                        cmd+=" --single-sender-id=3"
                        ;;
                    "single_dest")
                        cmd+=" --inj-vnet=0 --synthetic=uniform_random"
                        cmd+=" --single-dest-id=9"
                        ;;
                    "single_pair")
                        cmd+=" --inj-vnet=0 --synthetic=uniform_random"
                        cmd+=" --single-sender-id=3 --single-dest-id=9"
                        ;;
                esac

                # 运行仿真
                $cmd > lab4_results/fattree/fattree_k${k}_ada${ada_type}_${pattern_info}_vcs${vcs}_${rate}.log 2>&1

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
                        echo "$vcs $pattern_info $rate $packets_injected $packets_received $avg_packet_latency $avg_queueing_latency $avg_network_latency $avg_hops $reception_rate" >> "$result_file"
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
# Task 2: SlimFly 拓扑实验
# ==========================================
echo ""
echo "=== Task 2: SlimFly 拓扑性能分析 ==="

# SlimFly 配置 - 根据约束条件设计
slimfly_configs=(
    "false 0 2"   # no-deadlock=false, ada-type=0, min_vcs=2
    "false 1 4"   # no-deadlock=false, ada-type=1, min_vcs=4
    "false 2 4"   # no-deadlock=false, ada-type=2, min_vcs=4
    "true 0 2"    # no-deadlock=true, ada-type=0, min_vcs=2
    "true 1 4"    # no-deadlock=true, ada-type=1, min_vcs=4
    "true 2 4"    # no-deadlock=true, ada-type=2, min_vcs=4
)

for config in "${slimfly_configs[@]}"; do
    read -r no_deadlock ada_type min_vcs <<< "$config"

    echo ""
    echo "-- SlimFly no-deadlock=$no_deadlock, ada-type=$ada_type --"

    # 创建结果文件
    result_file="lab4_results/slimfly/data/slimfly_nodeadlock${no_deadlock}_ada${ada_type}_results.txt"
    echo "# vcs_per_vnet traffic_pattern injection_rate packets_injected packets_received avg_packet_latency avg_queueing_latency avg_network_latency avg_hops reception_rate" > "$result_file"

    # 根据约束条件设置VCs配置
    if [ "$min_vcs" == "2" ]; then
        vcs_configs=(2 4 8)
    else
        vcs_configs=(4 8)
    fi

    for vcs in "${vcs_configs[@]}"; do
        echo ""
        echo "  VCs per VNet: $vcs"

        for pattern_info in "${traffic_patterns[@]}"; do
            echo "    流量模式: $pattern_info"

            for rate in $injection_rates; do
                echo "      注入率: $rate"

                # 构建基础命令
                cmd="./build/NULL/gem5.opt configs/example/garnet_synth_traffic.py"
                cmd+=" --network=garnet --num-cpus=$num_cpus --num-dirs=$num_dirs"
                cmd+=" --topology=SlimFly --slimfly-q=5"
                cmd+=" --routing-algorithm=4"  # SLIMFLY
                cmd+=" --ada-type=$ada_type"
                cmd+=" --vcs-per-vnet=$vcs"
                cmd+=" --sim-cycles=$sim_cycles --injectionrate=$rate"
                cmd+=" --global-frequency=10GHz"
                cmd+=" --garnet-deadlock-threshold=$sim_cycles"

                # 添加 no-deadlock 参数
                if [ "$no_deadlock" == "true" ]; then
                    cmd+=" --no-deadlock"
                fi

                # 根据流量模式添加特定参数
                case $pattern_info in
                    "uniform_random")
                        cmd+=" --inj-vnet=0 --synthetic=uniform_random"
                        ;;
                    "tornado")
                        cmd+=" --inj-vnet=0 --synthetic=tornado"
                        ;;
                    "shuffle")
                        cmd+=" --inj-vnet=0 --synthetic=shuffle"
                        ;;
                    "single_sender")
                        cmd+=" --inj-vnet=0 --synthetic=uniform_random"
                        cmd+=" --single-sender-id=3"
                        ;;
                    "single_dest")
                        cmd+=" --inj-vnet=0 --synthetic=uniform_random"
                        cmd+=" --single-dest-id=9"
                        ;;
                    "single_pair")
                        cmd+=" --inj-vnet=0 --synthetic=uniform_random"
                        cmd+=" --single-sender-id=3 --single-dest-id=9"
                        ;;
                esac

                # 运行仿真
                $cmd > lab4_results/slimfly/slimfly_nodeadlock${no_deadlock}_ada${ada_type}_${pattern_info}_vcs${vcs}_${rate}.log 2>&1

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
                        echo "$vcs $pattern_info $rate $packets_injected $packets_received $avg_packet_latency $avg_queueing_latency $avg_network_latency $avg_hops $reception_rate" >> "$result_file"
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
# 生成实验总结
# ==========================================
echo ""
echo "=== 生成实验总结 ==="

cat > lab4_results/EXPERIMENT_SUMMARY.md << 'EOF'
# Lab4实验总结

## 实验配置
- 节点数: 16
- 仿真周期: 50,000 cycles
- 注入率范围: 0.01 - 0.3 packets/cycle/node

## 流量模式
1. uniform_random: 均匀随机流量
2. tornado: 龙卷风流量模式
3. shuffle: 洗牌流量模式
4. single_sender: 单发送者流量 (sender_id=3)
5. single_pair: 单对通信 (sender_id=3, dest_id=9)

## 实验任务

### Task 1: FatTree 拓扑分析
- 拓扑: FatTree (k=4)
- 路由算法: FatTree 非自适应路由
- Ada-type: 0 (非自适应), 1 (自适应)
- VCs配置: 1, 2, 4, 8 (无最小VC要求)

### Task 2: SlimFly 拓扑分析
- 拓扑: SlimFly (q=5)
- 路由算法: SlimFly 路由
- No-deadlock: true/false
- Ada-type: 0, 1, 2
- VCs约束:
  - no-deadlock, ada-type=0: VCs ≥ 2
  - no-deadlock, ada-type=1,2: VCs ≥ 4

## 数据文件位置
- FatTree分析: lab4_results/fattree/data/
- SlimFly分析: lab4_results/slimfly/data/

## 下一步
运行分析脚本生成图表:
```bash
python3 analyze_lab4_results.py
```
EOF

echo "实验总结已保存: lab4_results/EXPERIMENT_SUMMARY.md"

echo ""
echo "=========================================="
echo "           Lab4实验完成!"
echo "=========================================="
echo ""
echo "结果文件位置:"
echo "- FatTree 数据: lab4_results/fattree/data/"
echo "- SlimFly 数据: lab4_results/slimfly/data/"
echo "- 实验总结: lab4_results/EXPERIMENT_SUMMARY.md"
echo ""
echo "运行分析脚本: python3 analyze_lab4_results.py"
echo ""
