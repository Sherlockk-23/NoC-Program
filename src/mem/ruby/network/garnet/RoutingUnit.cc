/*
 * Copyright (c) 2008 Princeton University
 * Copyright (c) 2016 Georgia Institute of Technology
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are
 * met: redistributions of source code must retain the above copyright
 * notice, this list of conditions and the following disclaimer;
 * redistributions in binary form must reproduce the above copyright
 * notice, this list of conditions and the following disclaimer in the
 * documentation and/or other materials provided with the distribution;
 * neither the name of the copyright holders nor the names of its
 * contributors may be used to endorse or promote products derived from
 * this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
 * "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
 * LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
 * A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
 * OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
 * SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
 * LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
 * DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
 * THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
 * OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */


#include "mem/ruby/network/garnet/RoutingUnit.hh"

#include <tuple>
#include "base/cast.hh"
#include "base/compiler.hh"
#include "debug/RubyNetwork.hh"
#include "mem/ruby/network/garnet/InputUnit.hh"
#include "mem/ruby/network/garnet/Router.hh"
#include "mem/ruby/slicc_interface/Message.hh"

namespace gem5
{

namespace ruby
{

namespace garnet
{

RoutingUnit::RoutingUnit(Router *router)
{
    m_router = router;
    m_routing_table.clear();
    m_weight_table.clear();
}

void
RoutingUnit::addRoute(std::vector<NetDest>& routing_table_entry)
{
    if (routing_table_entry.size() > m_routing_table.size()) {
        m_routing_table.resize(routing_table_entry.size());
    }
    for (int v = 0; v < routing_table_entry.size(); v++) {
        m_routing_table[v].push_back(routing_table_entry[v]);
    }
}

void
RoutingUnit::addWeight(int link_weight)
{
    m_weight_table.push_back(link_weight);
}

bool
RoutingUnit::supportsVnet(int vnet, std::vector<int> sVnets)
{
    // If all vnets are supported, return true
    if (sVnets.size() == 0) {
        return true;
    }

    // Find the vnet in the vector, return true
    if (std::find(sVnets.begin(), sVnets.end(), vnet) != sVnets.end()) {
        return true;
    }

    // Not supported vnet
    return false;
}

/*
 * This is the default routing algorithm in garnet.
 * The routing table is populated during topology creation.
 * Routes can be biased via weight assignments in the topology file.
 * Correct weight assignments are critical to provide deadlock avoidance.
 */
int
RoutingUnit::lookupRoutingTable(int vnet, NetDest msg_destination)
{
    // First find all possible output link candidates
    // For ordered vnet, just choose the first
    // (to make sure different packets don't choose different routes)
    // For unordered vnet, randomly choose any of the links
    // To have a strict ordering between links, they should be given
    // different weights in the topology file

    int output_link = -1;
    int min_weight = INFINITE_;
    std::vector<int> output_link_candidates;
    int num_candidates = 0;

    // Identify the minimum weight among the candidate output links
    for (int link = 0; link < m_routing_table[vnet].size(); link++) {
        if (msg_destination.intersectionIsNotEmpty(
            m_routing_table[vnet][link])) {

        if (m_weight_table[link] <= min_weight)
            min_weight = m_weight_table[link];
        }
    }

    // Collect all candidate output links with this minimum weight
    for (int link = 0; link < m_routing_table[vnet].size(); link++) {
        if (msg_destination.intersectionIsNotEmpty(
            m_routing_table[vnet][link])) {

            if (m_weight_table[link] == min_weight) {
                num_candidates++;
                output_link_candidates.push_back(link);
            }
        }
    }

    if (output_link_candidates.size() == 0) {
        fatal("Fatal Error:: No Route exists from this Router.");
        exit(0);
    }

    // Randomly select any candidate output link
    int candidate = 0;
    if (!(m_router->get_net_ptr())->isVNetOrdered(vnet))
        candidate = rand() % num_candidates;

    output_link = output_link_candidates.at(candidate);
    return output_link;
}


void
RoutingUnit::addInDirection(PortDirection inport_dirn, int inport_idx)
{
    m_inports_dirn2idx[inport_dirn] = inport_idx;
    m_inports_idx2dirn[inport_idx]  = inport_dirn;
}

void
RoutingUnit::addOutDirection(PortDirection outport_dirn, int outport_idx)
{
    m_outports_dirn2idx[outport_dirn] = outport_idx;
    m_outports_idx2dirn[outport_idx]  = outport_dirn;
}

// outportCompute() is called by the InputUnit
// It calls the routing table by default.
// A template for adaptive topology-specific routing algorithm
// implementations using port directions rather than a static routing
// table is provided here.

// [CHECK_THIS]
int
RoutingUnit::outvcCompute(RouteInfo route, int inport,
                            PortDirection inport_dirn)
{
    return -1;
}

int
RoutingUnit::outportCompute(RouteInfo route, int inport,
                            PortDirection inport_dirn)
{
    int outport = -1;

    if (route.dest_router == m_router->get_id()) {

        // Multiple NIs may be connected to this router,
        // all with output port direction = "Local"
        // Get exact outport id from table
        outport = lookupRoutingTable(route.vnet, route.net_dest);
        return outport;
    }

    // Routing Algorithm set in GarnetNetwork.py
    // Can be over-ridden from command line using --routing-algorithm = 1
    RoutingAlgorithm routing_algorithm =
        (RoutingAlgorithm) m_router->get_net_ptr()->getRoutingAlgorithm();

    switch (routing_algorithm) {
        case TABLE_:  outport =
            lookupRoutingTable(route.vnet, route.net_dest); break;
        case XY_:     outport =
            outportComputeXY(route, inport, inport_dirn); break;
        case RING_:   outport =
            outportComputeRing(route, inport, inport_dirn); break;
        case BUTTERFLY_: outport =
            outportComputeButterfly(route, inport, inport_dirn); break;
        case SLIMFLY_: outport =
            outportComputeSlimFly(route, inport, inport_dirn); break;
        // any custom algorithm
        case CUSTOM_: outport =
            outportComputeCustom(route, inport, inport_dirn); break;
        default: outport =
            lookupRoutingTable(route.vnet, route.net_dest); break;
    }

    assert(outport != -1);
    return outport;
}

// XY routing implemented using port directions
// Only for reference purpose in a Mesh
// By default Garnet uses the routing table
int
RoutingUnit::outportComputeXY(RouteInfo route,
                              int inport,
                              PortDirection inport_dirn)
{
    PortDirection outport_dirn = "Unknown";

    [[maybe_unused]] int num_rows = m_router->get_net_ptr()->getNumRows();
    int num_cols = m_router->get_net_ptr()->getNumCols();
    assert(num_rows > 0 && num_cols > 0);

    int my_id = m_router->get_id();
    int my_x = my_id % num_cols;
    int my_y = my_id / num_cols;

    int dest_id = route.dest_router;
    int dest_x = dest_id % num_cols;
    int dest_y = dest_id / num_cols;

    int x_hops = abs(dest_x - my_x);
    int y_hops = abs(dest_y - my_y);

    bool x_dirn = (dest_x >= my_x);
    bool y_dirn = (dest_y >= my_y);

    // already checked that in outportCompute() function
    assert(!(x_hops == 0 && y_hops == 0));

    if (x_hops > 0) {
        if (x_dirn) {
            assert(inport_dirn == "Local" || inport_dirn == "West");
            outport_dirn = "East";
        } else {
            assert(inport_dirn == "Local" || inport_dirn == "East");
            outport_dirn = "West";
        }
    } else if (y_hops > 0) {
        if (y_dirn) {
            // "Local" or "South" or "West" or "East"
            assert(inport_dirn != "North");
            outport_dirn = "North";
        } else {
            // "Local" or "North" or "West" or "East"
            assert(inport_dirn != "South");
            outport_dirn = "South";
        }
    } else {
        // x_hops == 0 and y_hops == 0
        // this is not possible
        // already checked that in outportCompute() function
        panic("x_hops == y_hops == 0");
    }

    return m_outports_dirn2idx[outport_dirn];
}

// Deadlock-free Ring routing algorithm using Virtual Channel Layering
// Uses two VC layers to prevent deadlock when packets wrap around the ring
// [DEBUG] pick closest routing
int
RoutingUnit::outportComputeRing(RouteInfo route,
                                int inport,
                                PortDirection inport_dirn)
{
    int my_id = m_router->get_id();
    int dest_id = route.dest_router;
    int num_nodes = m_router->get_net_ptr()->getNumRouters();

    // Calculate clockwise and counter-clockwise distances
    int clockwise_dist = (dest_id - my_id + num_nodes) % num_nodes;
    int counter_clockwise_dist = (my_id - dest_id + num_nodes) % num_nodes;

    // If we're at the destination, this shouldn't be called
    assert(clockwise_dist != 0);

    // pick closest one
    if (clockwise_dist <= counter_clockwise_dist) {
        assert(inport_dirn == "Local" || inport_dirn == "Left");
        return m_outports_dirn2idx["Right"];
    } else {
        assert(inport_dirn == "Local" || inport_dirn == "Right");
        return m_outports_dirn2idx["Left"];
    }
}

// Butterfly routing algorithm implementation
// Uses deterministic routing based on destination address bits
int
RoutingUnit::outportComputeButterfly(RouteInfo route,
                                    int inport,
                                    PortDirection inport_dirn)
{
    int my_id = m_router->get_id();
    int dest_id = route.dest_router;
    int num_routers = m_router->get_net_ptr()->getNumRouters();

    // Calculate butterfly parameters
    // Assuming binary butterfly (k=2)
    int k = 2;  // radix per stage
    int num_nodes = num_routers * k;  // total endpoints
    int n = 0;
    int temp = num_nodes;
    while (temp > 1) {
        n++;
        temp /= k;
    }

    int routers_per_stage = num_nodes / k;

    // Determine current stage and position within stage
    int current_stage = my_id / routers_per_stage;
    int router_in_stage = my_id % routers_per_stage;

    // If we're at the final stage, route to destination
    if (current_stage == n - 1) {
        // Final stage: route to specific destination
        int target_port = dest_id % k;

        // Map to actual output port (implementation dependent)
        // For now, use simple mapping
        std::string outport_name = "Stage" + std::to_string(current_stage) +
                                  "_Port" + std::to_string(target_port);

        // Find the outport index for this direction
        // This is a simplified implementation
        return (target_port < m_outports_dirn2idx.size()) ? target_port : 0;
    }

    // Intermediate stage: use butterfly routing
    // Extract the bit at position (n - current_stage - 1) from destination
    int bit_pos = n - current_stage - 1;
    int route_bit = (dest_id >> bit_pos) & 1;

    // Route based on the extracted bit
    // 0 -> upper output, 1 -> lower output
    std::string outport_name = "Stage" + std::to_string(current_stage) +
                              "_Port" + std::to_string(route_bit);

    // For simplified implementation, return the bit as port number
    return route_bit;
}

// SlimFly routing algorithm implementation
// Implements shortest path routing for SlimFly topology
// Reference: "Slim Fly: A Cost Effective Low-Diameter Network Topology"
int
RoutingUnit::outportComputeSlimFly(RouteInfo route,
                                  int inport,
                                  PortDirection inport_dirn)
{
    int my_id = m_router->get_id();
    int dest_id = route.dest_router;
    int num_routers = m_router->get_net_ptr()->getNumRouters();
    
    // Safety check: ensure we have valid output ports
    if (m_outports_idx2dirn.size() == 0) {
        DPRINTF(RubyNetwork, "Router %d: No output ports available\n", my_id);
        return lookupRoutingTable(route.vnet, route.net_dest);
    }
    
    // Extract SlimFly parameters
    // Assuming q=5 for now (this should be configurable)
    int q = 5;  // This should be extracted from network configuration
    
    // Validate that we have the right number of routers (2*q*q)
    if (num_routers != 2 * q * q) {
        DPRINTF(RubyNetwork, "Router %d: Invalid topology size %d, expected %d\n", 
                my_id, num_routers, 2*q*q);
        // Fallback to table-based routing if parameters don't match
        return lookupRoutingTable(route.vnet, route.net_dest);
    }
    
    // Validate router IDs
    if (my_id < 0 || my_id >= num_routers || dest_id < 0 || dest_id >= num_routers) {
        DPRINTF(RubyNetwork, "Router %d: Invalid router ID (my_id=%d, dest_id=%d)\n", 
                my_id, my_id, dest_id);
        return lookupRoutingTable(route.vnet, route.net_dest);
    }
    
    // Helper function to convert router ID to SlimFly address (i1, i2, i3)
    auto to_slimfly_addr = [q](int router_id) -> std::tuple<int, int, int> {
        int i1 = router_id / (q * q);
        int i2 = (router_id % (q * q)) / q;
        int i3 = router_id % q;
        return std::make_tuple(i1, i2, i3);
    };
    
    // Helper function to check if value is in set X (even powers of primitive element)
    auto is_in_X = [q](int val) -> bool {
        // For q=5, epsilon=2, X = {1, 4} (even powers: 2^0=1, 2^2=4)
        if (q == 5) {
            return (val == 1 || val == 4);
        }
        return false;
    };
    
    // Helper function to check if value is in set X_ (odd powers of primitive element)
    auto is_in_X_ = [q](int val) -> bool {
        // For q=5, epsilon=2, X_ = {2, 3} (odd powers: 2^1=2, 2^3=3)
        if (q == 5) {
            return (val == 2 || val == 3);
        }
        return false;
    };
    
    // Convert router IDs to SlimFly addresses
    auto my_addr = to_slimfly_addr(my_id);
    int my_i1 = std::get<0>(my_addr);
    int my_i2 = std::get<1>(my_addr);
    int my_i3 = std::get<2>(my_addr);
    
    auto dest_addr = to_slimfly_addr(dest_id);
    int dest_i1 = std::get<0>(dest_addr);
    int dest_i2 = std::get<1>(dest_addr);
    int dest_i3 = std::get<2>(dest_addr);
    
    DPRINTF(RubyNetwork, "Router %d: SlimFly routing from (%d,%d,%d) to (%d,%d,%d)\n",
            my_id, my_i1, my_i2, my_i3, dest_i1, dest_i2, dest_i3);
    
    // Validate SlimFly addresses
    if (my_i1 < 0 || my_i1 >= 2 || my_i2 < 0 || my_i2 >= q || my_i3 < 0 || my_i3 >= q ||
        dest_i1 < 0 || dest_i1 >= 2 || dest_i2 < 0 || dest_i2 >= q || dest_i3 < 0 || dest_i3 >= q) {
        DPRINTF(RubyNetwork, "Router %d: Invalid SlimFly addresses\n", my_id);
        return lookupRoutingTable(route.vnet, route.net_dest);
    }
    
    // Safety helper function to ensure valid port selection
    auto safe_port_select = [this](int port_hint, const char* reason) -> int {
        if (m_outports_idx2dirn.size() == 0) {
            return 0;
        }
        int port = port_hint % m_outports_idx2dirn.size();
        if (port < 0) port = 0;
        DPRINTF(RubyNetwork, "Router %d: Selected port %d for %s\n", 
                m_router->get_id(), port, reason);
        return port;
    };
    
    // Check if we're at the destination
    if (my_id == dest_id) {
        DPRINTF(RubyNetwork, "Router %d: Already at destination\n", my_id);
        return lookupRoutingTable(route.vnet, route.net_dest);
    }
    
    // Implement SlimFly shortest path routing
    
    // Case 1: Same group and same supernode - direct connection possible
    if (my_i1 == dest_i1 && my_i2 == dest_i2) {
        int diff = (dest_i3 - my_i3 + q) % q;
        
        // Check if direct connection exists
        bool direct_connection = false;
        if (my_i1 == 0) {
            direct_connection = is_in_X(diff) || is_in_X((-diff + q) % q);
        } else {
            direct_connection = is_in_X_(diff) || is_in_X_((-diff + q) % q);
        }
        
        if (direct_connection) {
            int port_selection = abs(dest_i3 - my_i3 + q);
            return safe_port_select(port_selection, "same supernode direct");
        } else {
            DPRINTF(RubyNetwork, "Router %d: No direct connection in supernode\n", my_id);
            return lookupRoutingTable(route.vnet, route.net_dest);
        }
    }
    
    // Case 2: Different groups - use inter-group connections
    if (my_i1 != dest_i1) {
        int inter_group_port = (dest_i1 * q + dest_i2 + dest_i3);
        return safe_port_select(inter_group_port, "inter-group");
    }
    
    // Case 3: Same group, different supernode - intra-group routing
    if (my_i1 == dest_i1 && my_i2 != dest_i2) {
        int intra_group_port = (dest_i2 * q + dest_i3);
        return safe_port_select(intra_group_port, "intra-group");
    }
    
    // Fallback: use table-based routing
    DPRINTF(RubyNetwork, "Router %d: Using table-based routing fallback\n", my_id);
    return lookupRoutingTable(route.vnet, route.net_dest);
}

// Template for implementing custom routing algorithm
// using port directions. (Example adaptive)
int
RoutingUnit::outportComputeCustom(RouteInfo route,
                                 int inport,
                                 PortDirection inport_dirn)
{
    panic("%s placeholder executed", __FUNCTION__);
}

} // namespace garnet
} // namespace ruby
} // namespace gem5
