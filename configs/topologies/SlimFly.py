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

from common import FileSystemConfig
from topologies.BaseTopology import SimpleTopology

# Creates a Slim Fly topology
# Reference: "Slim Fly: A Cost Effective Low-Diameter Network Topology"
# This implementation handles the case when delta = 1


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
        return 2  # fallback

    def _to_switch_id(self, addr, q):
        """Convert (i1, i2, i3) address to switch ID"""
        return addr[0] * q * q + addr[1] * q + addr[2]

    def _to_switch_addr(self, switch_id, q):
        """Convert switch ID to (i1, i2, i3) address"""
        i1 = switch_id // (q * q)
        i2 = (switch_id % (q * q)) // q
        i3 = switch_id % q
        return (i1, i2, i3)

    def _construct_slim_fly_graph(self, q):
        """Construct the Slim Fly topology graph"""
        delta = 1

        # Validate q parameter
        if (q - delta) % 4 != 0:
            raise Exception("q must satisfy (q-1) % 4 == 0 for delta=1")

        # Calculate topology parameters
        w = 0
        while True:
            if (4 * w + delta) == q:
                break
            w += 1

        k_ = (3 * q - delta) // 2
        p = int(math.ceil(k_ / 2.0))

        # Number of switches in the network
        num_switches = 2 * q * q

        # Find primitive element
        epsilon = self._find_primitive_element(q)

        # Create sets X and X_
        X = set()
        X_ = set()
        for i in range(q - 1):
            val = pow(epsilon, i, q)
            if i % 2 == 0:
                X.add(val)
            else:
                X_.add(val)

        # Create adjacency information
        adjacency = {}
        for switch_id in range(num_switches):
            adjacency[switch_id] = []

        # Add intra-group links
        for switch1 in range(num_switches):
            for switch2 in range(switch1 + 1, num_switches):
                addr1 = self._to_switch_addr(switch1, q)
                addr2 = self._to_switch_addr(switch2, q)

                # Intra-group links for group 0 (i1=0)
                if (
                    addr1[0] == 0
                    and addr2[0] == 0
                    and addr1[1] == addr2[1]
                    and (addr1[2] - addr2[2]) % q in X
                ):
                    adjacency[switch1].append(switch2)
                    adjacency[switch2].append(switch1)

                # Intra-group links for group 1 (i1=1)
                elif (
                    addr1[0] == 1
                    and addr2[0] == 1
                    and addr1[1] == addr2[1]
                    and (addr1[2] - addr2[2]) % q in X_
                ):
                    adjacency[switch1].append(switch2)
                    adjacency[switch2].append(switch1)

                # Inter-group links
                elif (
                    addr1[0] == 0
                    and addr2[0] == 1
                    and addr1[2] == (addr2[1] * addr1[1] + addr2[2]) % q
                ):
                    adjacency[switch1].append(switch2)
                    adjacency[switch2].append(switch1)

        return adjacency, num_switches

    def makeTopology(self, options, network, IntLink, ExtLink, Router):
        nodes = self.nodes

        # Get SlimFly parameter q from options (default to 5 if not specified)
        q = getattr(options, "slimfly_q", 5)

        # Validate q is a prime power (simplified check for small values)
        valid_q_values = [5, 7, 11, 13, 17]  # Prime numbers where (q-1)%4==0
        if q not in valid_q_values:
            print(f"Warning: q={q} may not be valid. Using q=5 instead.")
            q = 5

        # Construct SlimFly topology
        adjacency, num_switches = self._construct_slim_fly_graph(q)

        # Default values for link latency and router latency
        link_latency = options.link_latency
        router_latency = options.router_latency

        # Create routers
        routers = [
            Router(router_id=i, latency=router_latency)
            for i in range(num_switches)
        ]
        network.routers = routers

        # Calculate nodes per switch
        nodes_per_switch = len(nodes) // num_switches
        remainder_nodes = len(nodes) % num_switches

        # Connect nodes to switches
        ext_links = []
        link_count = 0
        node_index = 0

        for switch_id in range(num_switches):
            # Determine how many nodes to connect to this switch
            nodes_for_this_switch = nodes_per_switch
            if switch_id < remainder_nodes:
                nodes_for_this_switch += 1

            # Connect nodes to this switch
            for i in range(nodes_for_this_switch):
                if node_index < len(nodes):
                    ext_links.append(
                        ExtLink(
                            link_id=link_count,
                            ext_node=nodes[node_index],
                            int_node=routers[switch_id],
                            latency=link_latency,
                        )
                    )
                    link_count += 1
                    node_index += 1

        network.ext_links = ext_links

        # Create internal links based on SlimFly adjacency
        int_links = []

        for switch1 in range(num_switches):
            for switch2 in adjacency[switch1]:
                if switch1 < switch2:  # Avoid duplicate links
                    addr1 = self._to_switch_addr(switch1, q)
                    addr2 = self._to_switch_addr(switch2, q)

                    # Determine link weight based on connection type
                    if addr1[0] == addr2[0]:  # Intra-group link
                        weight = 1
                    else:  # Inter-group link
                        weight = 2

                    # Create bidirectional links
                    int_links.append(
                        IntLink(
                            link_id=link_count,
                            src_node=routers[switch1],
                            dst_node=routers[switch2],
                            latency=link_latency,
                            weight=weight,
                        )
                    )
                    link_count += 1

                    int_links.append(
                        IntLink(
                            link_id=link_count,
                            src_node=routers[switch2],
                            dst_node=routers[switch1],
                            latency=link_latency,
                            weight=weight,
                        )
                    )
                    link_count += 1

        network.int_links = int_links

        print(
            f"SlimFly topology created with q={q}, {num_switches} switches, {len(int_links)} links"
        )

    def registerTopology(self, options):
        """Register topology with filesystem"""
        # Get SlimFly parameter q
        q = getattr(options, "slimfly_q", 5)
        num_switches = 2 * q * q

        # Register nodes with filesystem
        for i in range(options.num_cpus):
            FileSystemConfig.register_node(
                [i], MemorySize(options.mem_size) // options.num_cpus, i
            )
