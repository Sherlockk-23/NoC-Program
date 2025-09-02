# Copyright (c) 2025 Custom Implementation
# Butterfly topology for gem5 Garnet network

import math
from m5.params import *
from m5.objects import *
from m5.util import fatal

from common import FileSystemConfig
from topologies.BaseTopology import SimpleTopology


class Butterfly(SimpleTopology):
    description = "Butterfly"

    def __init__(self, controllers):
        self.nodes = controllers

    # Creates a Butterfly topology
    # k-ary n-fly butterfly network
    def makeTopology(self, options, network, IntLink, ExtLink, Router):
        nodes = self.nodes

        # Butterfly parameters
        # For k-ary n-fly: k=radix per stage, n=number of stages
        num_nodes = options.num_cpus

        # Calculate butterfly parameters
        # For simplicity, use 2-ary n-fly (binary butterfly)
        k = 2  # radix (2 for binary butterfly)
        n = int(math.log2(num_nodes))  # number of stages

        if num_nodes != (k**n):
            fatal("Butterfly topology requires num_cpus to be power of 2")

        # Total routers = n * (num_nodes / k) + 1 final stage
        # Each stage has num_nodes/k routers, plus final connection stage
        routers_per_stage = num_nodes // k
        total_stages = n + 1  # n stages + 1 destination stage
        num_routers = n * routers_per_stage

        link_latency = options.link_latency
        router_latency = options.router_latency

        # Create routers
        routers = []
        for stage in range(n):
            for router_in_stage in range(routers_per_stage):
                router_id = stage * routers_per_stage + router_in_stage
                router = Router(router_id=router_id, latency=router_latency)
                routers.append(router)

        network.routers = routers

        # Connect nodes to first stage routers
        ext_links = []
        link_count = 0

        # Connect each node to appropriate first-stage router
        for (i, node) in enumerate(nodes):
            first_stage_router = i // k
            ext_links.append(
                ExtLink(
                    link_id=link_count,
                    ext_node=node,
                    int_node=routers[first_stage_router],
                    latency=link_latency,
                )
            )
            link_count += 1

        network.ext_links = ext_links

        # Create internal links between stages
        int_links = []

        for stage in range(n - 1):  # Connect stage to stage+1
            for src_router_idx in range(routers_per_stage):
                src_router_id = stage * routers_per_stage + src_router_idx
                src_router = routers[src_router_id]

                # Butterfly connection pattern
                for output_port in range(k):
                    # Calculate destination router in next stage
                    dst_router_idx = self.butterfly_destination(
                        src_router_idx,
                        output_port,
                        stage,
                        k,
                        routers_per_stage,
                    )
                    dst_router_id = (
                        stage + 1
                    ) * routers_per_stage + dst_router_idx
                    dst_router = routers[dst_router_id]

                    int_links.append(
                        IntLink(
                            link_id=link_count,
                            src_node=src_router,
                            dst_node=dst_router,
                            src_outport=f"Stage{stage}_Port{output_port}",
                            dst_inport=f"FromStage{stage}",
                            latency=link_latency,
                        )
                    )
                    link_count += 1

        network.int_links = int_links

    def butterfly_destination(
        self, src_router, output_port, stage, k, routers_per_stage
    ):
        """
        Calculate butterfly connection pattern
        For binary butterfly: perfect shuffle connection
        """
        # Binary butterfly perfect shuffle pattern
        if k == 2:
            # For stage s, router r, output port p:
            # destination = (r shifted by 1 bit) XOR (p << (n-stage-1))
            bit_pos = stage
            dest = src_router
            if output_port == 1:
                dest = dest ^ (1 << bit_pos)
            return dest % routers_per_stage
        else:
            # General k-ary butterfly pattern
            # More complex implementation needed for k > 2
            return (src_router * k + output_port) % routers_per_stage

    # Register nodes with filesystem
    def registerTopology(self, options):
        for i in range(options.num_cpus):
            FileSystemConfig.register_node(
                [i], MemorySize(options.mem_size) // options.num_cpus, i
            )
