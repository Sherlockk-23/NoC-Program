# Copyright (c) 2025 Lab4 Project
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are
# met: redistributions of source code must retain the above copyright
# notice, this list of conditions and the following disclaimer;
# redistributions in binary form must reproduce the above copyright
# notice, this list of conditions and the following disclaimer in the
# documentation and/or other materials provided with the distribution;
# neither the name of the copyright holders nor the names of its
# contributors may be used to endorse or promote products derived from
# this software without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
# "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
# LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
# A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
# OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
# SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
# LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
# DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
# THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
# (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
# OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

import m5
from common import FileSystemConfig
from topologies.BaseTopology import SimpleTopology
from m5.objects import *
from m5.params import *


class FatTree(SimpleTopology):
    description = "FatTree"

    def __init__(self, controllers):
        self.nodes = controllers

    def makeTopology(self, options, network, IntLink, ExtLink, Router):
        nodes = self.nodes

        # FatTree parameters
        k = 4  # Default k=4
        if hasattr(options, 'fattree_k') and options.fattree_k > 0:
            k = options.fattree_k

        # Calculate number of components
        num_pods = k
        num_hosts = (k**3) // 4
        num_edge_switches = (k**2) // 2
        num_aggr_switches = (k**2) // 2
        num_core_switches = (k**2) // 4
        num_routers = num_edge_switches + num_aggr_switches + num_core_switches

        # Verify we have enough controllers
        if len(nodes) < num_hosts:
            m5.util.fatal("Not enough controllers for FatTree topology. "
                         f"Need at least {num_hosts} controllers, got {len(nodes)}")

        # Default values for link latency and router latency
        link_latency = options.link_latency
        router_latency = options.router_latency

        # Create routers
        routers = []
        
        # Edge routers (0 to num_edge_switches-1)
        for i in range(num_edge_switches):
            routers.append(Router(router_id=i, latency=router_latency))
        
        # Aggregation routers (num_edge_switches to num_edge_switches + num_aggr_switches - 1)
        for i in range(num_aggr_switches):
            router_id = num_edge_switches + i
            routers.append(Router(router_id=router_id, latency=router_latency))
        
        # Core routers (num_edge_switches + num_aggr_switches to total-1)
        for i in range(num_core_switches):
            router_id = num_edge_switches + num_aggr_switches + i
            routers.append(Router(router_id=router_id, latency=router_latency))

        network.routers = routers

        # Link counter for unique link IDs
        link_count = 0

        # Connect hosts to edge routers (External links)
        ext_links = []
        hosts_per_edge_switch = k // 2
        for i, node in enumerate(nodes[:num_hosts]):
            edge_router_id = i // hosts_per_edge_switch
            ext_links.append(
                ExtLink(
                    link_id=link_count,
                    ext_node=node,
                    int_node=routers[edge_router_id],
                    latency=link_latency,
                )
            )
            link_count += 1

        # Connect remaining nodes (if any) to edge router 0
        for i, node in enumerate(nodes[num_hosts:]):
            ext_links.append(
                ExtLink(
                    link_id=link_count,
                    ext_node=node,
                    int_node=routers[0],
                    latency=link_latency,
                )
            )
            link_count += 1

        network.ext_links = ext_links

        # Create internal links
        int_links = []

        # Connect edge switches to aggregation switches within each pod
        edge_switches_per_pod = k // 2
        aggr_switches_per_pod = k // 2

        for pod in range(num_pods):
            # Edge switches in this pod
            edge_start = pod * edge_switches_per_pod
            edge_end = edge_start + edge_switches_per_pod
            
            # Aggregation switches in this pod
            aggr_start = num_edge_switches + pod * aggr_switches_per_pod
            aggr_end = aggr_start + aggr_switches_per_pod

            # Connect each edge switch to each aggregation switch in the same pod
            for edge_idx in range(edge_start, edge_end):
                for aggr_idx in range(aggr_start, aggr_end):
                    # Edge to Aggregation
                    int_links.append(
                        IntLink(
                            link_id=link_count,
                            src_node=routers[edge_idx],
                            dst_node=routers[aggr_idx],
                            src_outport="Up",
                            dst_inport="Down",
                            latency=link_latency,
                            weight=1,
                        )
                    )
                    link_count += 1
                    
                    # Aggregation to Edge (bidirectional)
                    int_links.append(
                        IntLink(
                            link_id=link_count,
                            src_node=routers[aggr_idx],
                            dst_node=routers[edge_idx],
                            src_outport="Down",
                            dst_inport="Up",
                            latency=link_latency,
                            weight=1,
                        )
                    )
                    link_count += 1

        # Connect aggregation switches to core switches
        core_start = num_edge_switches + num_aggr_switches
        
        for pod in range(num_pods):
            aggr_start = num_edge_switches + pod * aggr_switches_per_pod
            aggr_end = aggr_start + aggr_switches_per_pod
            
            for aggr_idx in range(aggr_start, aggr_end):
                # Each aggregation switch connects to k/2 core switches
                # Distribute connections to ensure each core switch connects to each pod
                aggr_offset = aggr_idx - aggr_start
                core_start_for_aggr = core_start + aggr_offset * (k // 2)
                core_end_for_aggr = core_start_for_aggr + (k // 2)
                
                for core_idx in range(core_start_for_aggr, 
                                    min(core_end_for_aggr, core_start + num_core_switches)):
                    # Aggregation to Core
                    int_links.append(
                        IntLink(
                            link_id=link_count,
                            src_node=routers[aggr_idx],
                            dst_node=routers[core_idx],
                            src_outport="Up",
                            dst_inport="Down",
                            latency=link_latency,
                            weight=1,
                        )
                    )
                    link_count += 1
                    
                    # Core to Aggregation (bidirectional)
                    int_links.append(
                        IntLink(
                            link_id=link_count,
                            src_node=routers[core_idx],
                            dst_node=routers[aggr_idx],
                            src_outport="Down",
                            dst_inport="Up",
                            latency=link_latency,
                            weight=1,
                        )
                    )
                    link_count += 1

        network.int_links = int_links

        print(f"FatTree topology created:")
        print(f"  k = {k}")
        print(f"  {num_hosts} hosts")
        print(f"  {num_edge_switches} edge switches")
        print(f"  {num_aggr_switches} aggregation switches")  
        print(f"  {num_core_switches} core switches")
        print(f"  {len(int_links)} internal links")

    def registerTopology(self, options):
        # Register nodes with filesystem if needed
        if hasattr(options, 'num_cpus'):
            for i in range(options.num_cpus):
                FileSystemConfig.register_node(
                    [i], MemorySize(options.mem_size) // options.num_cpus, i
                )
