#!/bin/bash

# Lab2 自动化实验脚本
# 用于性能分析实验

# 创建结果目录
mkdir -p lab2_results
mkdir -p lab2_results/task1_traffic_patterns
mkdir -p lab2_results/task2_parameters
mkdir -p lab2_results/data

# 基本配置
num_cpus=64
sim_cycles=10000
num_dirs=64
mesh_rows=8
inj_vnet=0
global_frequency=1GHz

echo "=== Lab2 自动化实验开始 ==="
echo "开始时间: $(date)"

# ============================================================================
# Task 1: 不同流量模式的延迟-吞吐量曲线
# ============================================================================

echo ""
echo "=== Task 1: 测试不同流量模式 ==="

# 流量模式列表
traffic_patterns=("uniform_random" "shuffle" "transpose" "tornado" "neighbor")

# 注入率范围 (从0.01到0.5，步长递增)
injection_rates=("0.01" "0.02" "0.05" "0.1" "0.15" "0.2" "0.25" "0.3" "0.4" "0.5")

# 为每种流量模式创建数据文件
for pattern in "${traffic_patterns[@]}"; do
    echo "# injection_rate packets_injected packets_received avg_packet_latency avg_queueing_latency avg_network_latency avg_hops reception_rate" > lab2_results/data/${pattern}_results.txt
done

# 运行Task 1实验
for pattern in "${traffic_patterns[@]}"; do
    echo "正在测试流量模式: $pattern"


    for rate in "${injection_rates[@]}"; do
        echo "  注入率: $rate"

        # 运行仿真
        ./build/NULL/gem5.opt \
        configs/example/garnet_synth_traffic.py \
        --network=garnet --num-cpus=$num_cpus \
        --num-dirs=$num_dirs \
        --topology=Mesh_XY --mesh-rows=$mesh_rows \
        --inj-vnet=$inj_vnet --synthetic=$pattern \
        --sim-cycles=$sim_cycles \
        --injectionrate=$rate \
        --global-frequency=$global_frequency \
        > lab2_results/task1_traffic_patterns/${pattern}_${rate}.log 2>&1

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
            else
                reception_rate="0.000000"
            fi

            # 保存结果到数据文件
            echo "$rate $packets_injected $packets_received $avg_packet_latency $avg_queueing_latency $avg_network_latency $avg_hops $reception_rate" >> lab2_results/data/${pattern}_results.txt

            echo "    完成 - 延迟: $avg_packet_latency, 接收率: $reception_rate"
        else
            echo "    失败 - 仿真出错"
            echo "$rate - - - - - - -" >> lab2_results/data/${pattern}_results.txt
        fi
    done
done

# ============================================================================
# Task 2: 不同参数配置的影响
# ============================================================================

echo ""
echo "=== Task 2: 测试不同网络参数 ==="

# 使用uniform_random作为基准流量模式
base_pattern="uniform_random"
base_rates=("0.01" "0.02" "0.05" "0.1" "0.15" "0.2")

# 测试不同的vcs-per-vnet值 (避免过小的值)
echo "正在测试不同的vcs-per-vnet值..."
vcs_per_vnet_values=("1" "2" "4" "8" "16")
echo "# vcs_per_vnet injection_rate packets_injected packets_received avg_packet_latency avg_queueing_latency avg_network_latency avg_hops reception_rate" > lab2_results/data/vcs_per_vnet_results.txt

for vcs in "${vcs_per_vnet_values[@]}"; do
    echo "  测试vcs-per-vnet=$vcs"
    for rate in "${base_rates[@]}"; do
        echo "    注入率: $rate"

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
        > lab2_results/task2_parameters/vcs${vcs}_rate${rate}.log 2>&1

        if [ $? -eq 0 ]; then
            packets_injected=$(grep "packets_injected::total" m5out/stats.txt | awk '{print $2}')
            packets_received=$(grep "packets_received::total" m5out/stats.txt | awk '{print $2}')
            avg_packet_latency=$(grep "average_packet_latency" m5out/stats.txt | awk '{print $2}')
            avg_queueing_latency=$(grep "average_packet_queueing_latency" m5out/stats.txt | awk '{print $2}')
            avg_network_latency=$(grep "average_packet_network_latency" m5out/stats.txt | awk '{print $2}')
            avg_hops=$(grep "average_hops" m5out/stats.txt | awk '{print $2}')

            if [ ! -z "$packets_received" ] && [ "$packets_received" != "0" ]; then
                reception_rate=$(awk "BEGIN {printf \"%.6f\", $packets_received / ($num_cpus * $sim_cycles)}")
            else
                reception_rate="0.000000"
            fi

            echo "$vcs $rate $packets_injected $packets_received $avg_packet_latency $avg_queueing_latency $avg_network_latency $avg_hops $reception_rate" >> lab2_results/data/vcs_per_vnet_results.txt
        else
            echo "$vcs $rate - - - - - - -" >> lab2_results/data/vcs_per_vnet_results.txt
        fi
    done
done

# 测试不同的router-latency值
echo "正在测试不同的router-latency值..."
router_latency_values=("1" "2" "4" "8")
echo "# router_latency injection_rate packets_injected packets_received avg_packet_latency avg_queueing_latency avg_network_latency avg_hops reception_rate" > lab2_results/data/router_latency_results.txt

for latency in "${router_latency_values[@]}"; do
    echo "  测试router-latency=$latency"
    for rate in "${base_rates[@]}"; do
        echo "    注入率: $rate"

        ./build/NULL/gem5.opt \
        configs/example/garnet_synth_traffic.py \
        --network=garnet --num-cpus=$num_cpus \
        --num-dirs=$num_dirs \
        --topology=Mesh_XY --mesh-rows=$mesh_rows \
        --inj-vnet=$inj_vnet --synthetic=$base_pattern \
        --sim-cycles=$sim_cycles \
        --injectionrate=$rate \
        --router-latency=$latency \
        --global-frequency=$global_frequency \
        > lab2_results/task2_parameters/router_lat${latency}_rate${rate}.log 2>&1

        if [ $? -eq 0 ]; then
            packets_injected=$(grep "packets_injected::total" m5out/stats.txt | awk '{print $2}')
            packets_received=$(grep "packets_received::total" m5out/stats.txt | awk '{print $2}')
            avg_packet_latency=$(grep "average_packet_latency" m5out/stats.txt | awk '{print $2}')
            avg_queueing_latency=$(grep "average_packet_queueing_latency" m5out/stats.txt | awk '{print $2}')
            avg_network_latency=$(grep "average_packet_network_latency" m5out/stats.txt | awk '{print $2}')
            avg_hops=$(grep "average_hops" m5out/stats.txt | awk '{print $2}')

            if [ ! -z "$packets_received" ] && [ "$packets_received" != "0" ]; then
                reception_rate=$(awk "BEGIN {printf \"%.6f\", $packets_received / ($num_cpus * $sim_cycles)}")
            else
                reception_rate="0.000000"
            fi

            echo "$latency $rate $packets_injected $packets_received $avg_packet_latency $avg_queueing_latency $avg_network_latency $avg_hops $reception_rate" >> lab2_results/data/router_latency_results.txt
        else
            echo "$latency $rate - - - - - - -" >> lab2_results/data/router_latency_results.txt
        fi
    done
done

# 测试不同的link-width-bits值
echo "正在测试不同的link-width-bits值..."
link_width_values=("16" "32" "64" "128" "256")
echo "# link_width injection_rate packets_injected packets_received avg_packet_latency avg_queueing_latency avg_network_latency avg_hops reception_rate" > lab2_results/data/link_width_results.txt

for width in "${link_width_values[@]}"; do
    echo "  测试link-width-bits=$width"
    for rate in "${base_rates[@]}"; do
        echo "    注入率: $rate"

        ./build/NULL/gem5.opt \
        configs/example/garnet_synth_traffic.py \
        --network=garnet --num-cpus=$num_cpus \
        --num-dirs=$num_dirs \
        --topology=Mesh_XY --mesh-rows=$mesh_rows \
        --inj-vnet=$inj_vnet --synthetic=$base_pattern \
        --sim-cycles=$sim_cycles \
        --injectionrate=$rate \
        --link-width-bits=$width \
        --global-frequency=$global_frequency \
        > lab2_results/task2_parameters/link_width${width}_rate${rate}.log 2>&1

        if [ $? -eq 0 ]; then
            packets_injected=$(grep "packets_injected::total" m5out/stats.txt | awk '{print $2}')
            packets_received=$(grep "packets_received::total" m5out/stats.txt | awk '{print $2}')
            avg_packet_latency=$(grep "average_packet_latency" m5out/stats.txt | awk '{print $2}')
            avg_queueing_latency=$(grep "average_packet_queueing_latency" m5out/stats.txt | awk '{print $2}')
            avg_network_latency=$(grep "average_packet_network_latency" m5out/stats.txt | awk '{print $2}')
            avg_hops=$(grep "average_hops" m5out/stats.txt | awk '{print $2}')

            if [ ! -z "$packets_received" ] && [ "$packets_received" != "0" ]; then
                reception_rate=$(awk "BEGIN {printf \"%.6f\", $packets_received / ($num_cpus * $sim_cycles)}")
            else
                reception_rate="0.000000"
            fi

            echo "$width $rate $packets_injected $packets_received $avg_packet_latency $avg_queueing_latency $avg_network_latency $avg_hops $reception_rate" >> lab2_results/data/link_width_results.txt
        else
            echo "$width $rate - - - - - - -" >> lab2_results/data/link_width_results.txt
        fi
    done
done

# ============================================================================
# 生成总结报告
# ============================================================================

echo ""
echo "=== 生成实验总结 ==="

cat > lab2_results/experiment_summary.txt << EOF
Lab2 实验总结报告
生成时间: $(date)

实验配置:
- CPU数量: $num_cpus
- 仿真周期: $sim_cycles
- 网格大小: ${mesh_rows}x${mesh_rows}
- 拓扑: Mesh_XY
- 注入虚拟网络: $inj_vnet

Task 1: 流量模式测试
- 测试的流量模式: ${traffic_patterns[*]}
- 测试的注入率: ${injection_rates[*]}
- 结果文件: lab2_results/data/*_results.txt

Task 2: 参数影响测试
- vcs-per-vnet测试值: ${vcs_per_vnet_values[*]}
- router-latency测试值: ${router_latency_values[*]}
- link-width-bits测试值: ${link_width_values[*]}
- 基准流量模式: $base_pattern
- 基准注入率: ${base_rates[*]}

数据文件说明:
- 每行格式: [参数] injection_rate packets_injected packets_received avg_packet_latency avg_queueing_latency avg_network_latency avg_hops reception_rate
- 延迟单位: cycles
- 接收率: packets/(node*cycle)

使用Python脚本进行数据分析和画图:
1. 读取lab2_results/data/目录下的数据文件
2. 绘制延迟-吞吐量曲线
3. 分析不同参数的影响
EOF

echo ""
echo "=== 实验完成 ==="
echo "结束时间: $(date)"
echo ""
echo "结果保存在: lab2_results/"
echo "- 日志文件: lab2_results/task1_traffic_patterns/ 和 lab2_results/task2_parameters/"
echo "- 数据文件: lab2_results/data/"
echo "- 总结报告: lab2_results/experiment_summary.txt"
echo ""
echo "下一步: 使用Python或其他工具分析数据并绘制图表"
