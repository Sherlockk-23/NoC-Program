# Copyright (c) 2025
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

import math
from m5.params import *
from m5.objects import *
from m5.util.convert import *

from common import FileSystemConfig
from topologies.BaseTopology import SimpleTopology

# Creates a Slim Fly topology
# Reference: "Slim Fly: A Cost Effective Low-Diameter Network Topology"
# This implementation handles both delta = 1 and delta = 3 cases


class SlimFly(SimpleTopology):
    description = "SlimFly"

    def __init__(self, controllers):
        self.nodes = controllers

    def _is_primitive(self, a, q):
        """Check if 'a' is a primitive element in field F_q"""
        if a == 0 or a == 1:
            return False

        # Check if a^i mod q can generate all non-zero elements
        generated = set()
        power = 1
        for i in range(1, q):
            power = (power * a) % q
            generated.add(power)
            if power == 1 and i < q - 1:
                return False

        return len(generated) == q - 1

    def _find_primitive_element(self, q):
        """Find a primitive element in field F_q"""
        for e in range(2, q):
            if self._is_primitive(e, q):
                return e
        raise ValueError("Failed to find a primitive for q", q)

    def _generate_X(self, q, delta, p):
        """Generate X1 and X2 sets based on primitive element"""
        X1, X2 = set(), set()
        power = 1
        for i in range(0, q-1):
            if delta == 1:
                if i % 2 == 1:
                    X1.add(power)
                else:
                    X2.add(power)
            elif delta == 3:
                if i == (q-1)/2 or i == 0:
                    X1.add(power)
                    X2.add(power)
                elif i % 2 == 1:
                    if i < (q-1)/2:
                        X2.add(power)
                    else:
                        X1.add(power)
                else:
                    if i > (q-1)/2:
                        X2.add(power)
                    else:
                        X1.add(power)
            else:
                raise ValueError("delta can only be 1 or 3")

            power = (power * p) % q

        return X1, X2

    def _get_id(self, group, x, y, q):
        """Convert (group, x, y) to router ID"""
        return group * q * q + x * q + y

    def _get_coords(self, router_id, q):
        """Convert router ID to (group, x, y)"""
        group = router_id // (q * q)
        x = (router_id % (q * q)) // q
        y = router_id % q
        return group, x, y

    def _generate_adjacency(self, q, delta, X1, X2):
        """Generate adjacency matrix for SlimFly topology"""
        num_routers = 2 * q * q
        adj = [[0 for _ in range(num_routers)] for _ in range(num_routers)]

        # Group 0 intra-group connections
        for y1 in range(q):
            for y2 in range(q):
                if y1 != y2 and ((y1 - y2 + q) % q in X1):
                    for x in range(q):
                        router1 = self._get_id(0, x, y1, q)
                        router2 = self._get_id(0, x, y2, q)
                        adj[router1][router2] = 1

        # Group 1 intra-group connections
        for y1 in range(q):
            for y2 in range(q):
                if y1 != y2 and ((y1 - y2 + q) % q in X2):
                    for x in range(q):
                        router1 = self._get_id(1, x, y1, q)
                        router2 = self._get_id(1, x, y2, q)
                        adj[router1][router2] = 1

        # Inter-group connections
        for x in range(q):
            for y in range(q):
                for m in range(q):
                    for c in range(q):
                        if y == (m * x + c + q) % q:
                            router1 = self._get_id(0, x, y, q)
                            router2 = self._get_id(1, m, c, q)
                            adj[router1][router2] = 1
                            adj[router2][router1] = 1

        return adj

    def _floyd_warshall(self, adj):
        """Calculate shortest paths using Floyd-Warshall algorithm"""
        num_routers = len(adj)
        # Initialize distance matrix
        dist = []
        for i in range(num_routers):
            row = []
            for j in range(num_routers):
                if adj[i][j] == 1:
                    row.append(1)
                else:
                    row.append(float('inf'))
            dist.append(row)
        
        # Initialize next_hop matrix
        next_hop = [[0 for _ in range(num_routers)] for _ in range(num_routers)]

        # Initialize next_hop
        for i in range(num_routers):
            for j in range(num_routers):
                if i == j:
                    dist[i][j] = 0
                    next_hop[i][j] = i
                elif adj[i][j] == 1:
                    next_hop[i][j] = j

        # Floyd-Warshall
        for k in range(num_routers):
            for i in range(num_routers):
                for j in range(num_routers):
                    if dist[i][j] > dist[i][k] + dist[k][j]:
                        dist[i][j] = dist[i][k] + dist[k][j]
                        next_hop[i][j] = next_hop[i][k]

        return dist, next_hop

    def _create_outport_table(self, adj, next_hop, router_to_outport_map):
        """Create outport lookup table for routing"""
        num_routers = len(adj)
        outport_table = [[-1 for _ in range(num_routers)] for _ in range(num_routers)]

        for src in range(num_routers):
            for dest in range(num_routers):
                if src == dest:
                    outport_table[src][dest] = -1  # Local routing
                else:
                    next_router = next_hop[src][dest]
                    if next_router in router_to_outport_map[src]:
                        outport_table[src][dest] = router_to_outport_map[src][next_router]

        for src in range(num_routers):
            for dest in range(num_routers):
                if src == dest:
                    outport_table[src][dest] = -1  # Local routing
                else:
                    next_router = next_hop[src][dest]
                    if next_router in router_to_outport_map[src]:
                        outport_table[src][dest] = router_to_outport_map[src][next_router]

        # Flatten the 2D list to 1D list
        flattened = []
        for row in outport_table:
            flattened.extend(row)
        return flattened

    def _find_params(self, num_nodes):
        """Find SlimFly parameters from number of nodes"""
        q = int(math.sqrt(num_nodes / 2))
        if q * q * 2 != num_nodes or q < 3:
            raise ValueError(f"Number of nodes must be 2*q^2 with q>=3, got {num_nodes}")

        delta = q % 4
        if delta == 2:
            raise ValueError("q % 4 cannot be 2")

        return q, delta

    def makeTopology(self, options, network, IntLink, ExtLink, Router):
        nodes = self.nodes

        # Get SlimFly parameter q from options
        q = getattr(options, "slimfly_q", 5)
        
        # Validate q
        valid_q_values = [5, 7, 9, 11, 13, 17]  # Numbers where (q-1)%4==0 or (q-3)%4==0
        if q not in valid_q_values:
            print(f"Warning: q={q} may not be valid. Using q=5 instead.")
            q = 5

        num_routers = 2 * q * q
        delta = q % 4
        if delta == 2:
            delta = 1  # Fallback

        print(f"Creating SlimFly topology with q={q}, delta={delta}, {num_routers} routers")

        # Generate primitive element and X sets
        p = self._find_primitive_element(q)
        X1, X2 = self._generate_X(q, delta, p)

        print(f"Primitive element: {p}")
        print(f"X1: {sorted(X1)}")
        print(f"X2: {sorted(X2)}")

        # Generate adjacency matrix
        adj = self._generate_adjacency(q, delta, X1, X2)

        # Calculate shortest paths
        dist, next_hop = self._floyd_warshall(adj)
        # Calculate maximum distance
        max_dist = 0
        for row in dist:
            for d in row:
                if d != float('inf') and d > max_dist:
                    max_dist = d
        print(f"Maximum distance: {max_dist}")

        # Create routers
        routers = [
            Router(router_id=i, latency=options.router_latency)
            for i in range(num_routers)
        ]
        network.routers = routers

        # Connect nodes to routers
        ext_links = []
        link_count = 0
        nodes_per_router = len(nodes) // num_routers
        remainder_nodes = len(nodes) % num_routers
        
        outport_count = [0] * num_routers

        node_index = 0
        for router_id in range(num_routers):
            nodes_for_router = nodes_per_router
            if router_id < remainder_nodes:
                nodes_for_router += 1

            for i in range(nodes_for_router):
                if node_index < len(nodes):
                    ext_links.append(
                        ExtLink(
                            link_id=link_count,
                            ext_node=nodes[node_index],
                            int_node=routers[router_id],
                            latency=options.link_latency,
                        )
                    )
                    link_count += 1
                    node_index += 1
                    outport_count[router_id] += 1

        network.ext_links = ext_links

        # Create internal links and build outport mapping
        int_links = []
        router_to_outport_map = [dict() for _ in range(num_routers)]

        for src in range(num_routers):
            for dest in range(num_routers):
                if adj[src][dest] == 1:
                    # Create link
                    int_links.append(
                        IntLink(
                            link_id=link_count,
                            src_node=routers[src],
                            dst_node=routers[dest],
                            latency=options.link_latency,
                            weight=1,
                        )
                    )
                    
                    # Record outport mapping
                    router_to_outport_map[src][dest] = outport_count[src]
                    outport_count[src] += 1
                    link_count += 1

        network.int_links = int_links

        # Create outport lookup table
        outport_table = self._create_outport_table(adj, next_hop, router_to_outport_map)

        # Convert X sets to binary arrays
        X1_binary = [1 if i in X1 else 0 for i in range(q)]
        X2_binary = [1 if i in X2 else 0 for i in range(q)]

        # Set SlimFly information in network
        network.slimfly_q = q
        network.slimfly_X1 = X1_binary
        network.slimfly_X2 = X2_binary
        network.slimfly_outport_table = outport_table

        print(f"SlimFly topology created: {len(int_links)} internal links")
        print(f"Outport table size: {len(outport_table)}")

    def registerTopology(self, options):
        """Register topology with filesystem"""
        q = getattr(options, "slimfly_q", 5)
        
        for i in range(options.num_cpus):
            FileSystemConfig.register_node(
                [i], MemorySize(options.mem_size) // options.num_cpus, i
            )
