/*
 * Copyright (c) 2020 Inria
 * Copyright (c) 2016 Georgia Institute of Technology
 * Copyright (c) 2008 Princeton University
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


#include "mem/ruby/network/garnet/SwitchAllocator.hh"

#include "debug/RubyNetwork.hh"
#include "mem/ruby/network/garnet/GarnetNetwork.hh"
#include "mem/ruby/network/garnet/InputUnit.hh"
#include "mem/ruby/network/garnet/OutputUnit.hh"
#include "mem/ruby/network/garnet/Router.hh"

namespace gem5
{

namespace ruby
{

namespace garnet
{

SwitchAllocator::SwitchAllocator(Router *router)
    : Consumer(router)
{
    m_router = router;
    m_num_vcs = m_router->get_num_vcs();
    m_vc_per_vnet = m_router->get_vc_per_vnet();

    m_input_arbiter_activity = 0;
    m_output_arbiter_activity = 0;

    // Note: Ring topology check will be done in init() after network pointer is set
}

void
SwitchAllocator::init()
{
    m_num_inports = m_router->get_num_inports();
    m_num_outports = m_router->get_num_outports();
    m_round_robin_inport.resize(m_num_outports);
    m_round_robin_invc.resize(m_num_inports);
    m_port_requests.resize(m_num_inports);
    m_vc_winners.resize(m_num_inports);

    for (int i = 0; i < m_num_inports; i++) {
        m_round_robin_invc[i] = 0;
        m_port_requests[i] = -1;
        m_vc_winners[i] = -1;
    }

    for (int i = 0; i < m_num_outports; i++) {
        m_round_robin_inport[i] = 0;
    }
}

/*
 * The wakeup function of the SwitchAllocator performs a 2-stage
 * seperable switch allocation. At the end of the 2nd stage, a free
 * output VC is assigned to the winning flits of each output port.
 * There is no separate VCAllocator stage like the one in garnet1.0.
 * At the end of this function, the router is rescheduled to wakeup
 * next cycle for peforming SA for any flits ready next cycle.
 */

void
SwitchAllocator::wakeup()
{
    arbitrate_inports(); // First stage of allocation
    arbitrate_outports(); // Second stage of allocation

    clear_request_vector();
    check_for_wakeup();
}

/*
 * SA-I (or SA-i) loops through all input VCs at every input port,
 * and selects one in a round robin manner.
 *    - For HEAD/HEAD_TAIL flits only selects an input VC whose output port
 *     has at least one free output VC.
 *    - For BODY/TAIL flits, only selects an input VC that has credits
 *      in its output VC.
 * Places a request for the output port from this input VC.
 */

void
SwitchAllocator::arbitrate_inports()
{
    // Select a VC from each input in a round robin manner
    // Independent arbiter at each input port
    for (int inport = 0; inport < m_num_inports; inport++) {
        int invc = m_round_robin_invc[inport];

        for (int invc_iter = 0; invc_iter < m_num_vcs; invc_iter++) {
            auto input_unit = m_router->getInputUnit(inport);

            if (input_unit->need_stage(invc, SA_, curTick())) {
                // This flit is in SA stage

                int outport;
                // In wormhole mode, get outport from flit; in traditional mode, from VC
                bool is_wormhole = false;
                if (m_router->get_net_ptr() != nullptr) {
                    is_wormhole = m_router->is_wormhole_enabled();
                }
                if (is_wormhole) {
                    flit *t_flit = input_unit->peekTopFlit(invc);
                    outport = t_flit->get_outport();
                } else {
                    outport = input_unit->get_outport(invc);
                }

                // 最好在这之前决定 outvc, 即在 Input Unit 计算 outport 的时候一起算了
                // 不然这里一定是 -1 ?
                // 不一定！如果是非 head or tail，这里是提前决定了的！
                // 我糙尼玛的。
                int outvc = input_unit->get_outvc(invc);

                // check if the flit in this InputVC is allowed to be sent
                // send_allowed conditions described in that function.
                // 这里决定了一定有 free 的 outvc，也得改这个函数
                flit *t_flit = input_unit->peekTopFlit(invc);
                

                bool make_request =
                    send_allowed(inport, invc, outport, outvc, t_flit);

               
                DPRINTF(RubyNetwork, "still in SA stage for flit: %s\n", *t_flit);
                DPRINTF(RubyNetwork, "Send allowed for inport: %d, invc: %d, outport: %d, outvc: %d: %d\n",
                    inport, invc, outport, outvc, make_request);

                if (make_request) {
                    m_input_arbiter_activity++;
                    m_port_requests[inport] = outport;
                    m_vc_winners[inport] = invc;

                    break; // got one vc winner for this port
                }
            }

            invc++;
            if (invc >= m_num_vcs)
                invc = 0;
        }
    }
}

/*
 * SA-II (or SA-o) loops through all output ports,
 * and selects one input VC (that placed a request during SA-I)
 * as the winner for this output port in a round robin manner.
 *      - For HEAD/HEAD_TAIL flits, performs simplified outvc allocation.
 *        (i.e., select a free VC from the output port).
 *      - For BODY/TAIL flits, decrement a credit in the output vc.
 * The winning flit is read out from the input VC and sent to the
 * CrossbarSwitch.
 * An increment_credit signal is sent from the InputUnit
 * to the upstream router. For HEAD_TAIL/TAIL flits, is_free_signal in the
 * credit is set to true.
 */

void
SwitchAllocator::arbitrate_outports()
{
    // Now there are a set of input vc requests for output vcs.
    // Again do round robin arbitration on these requests
    // Independent arbiter at each output port


    for (int outport = 0; outport < m_num_outports; outport++) {
        int inport = m_round_robin_inport[outport];

        for (int inport_iter = 0; inport_iter < m_num_inports;
                 inport_iter++) {

            // inport has a request this cycle for outport
            if (m_port_requests[inport] == outport) {
                auto output_unit = m_router->getOutputUnit(outport);
                auto input_unit = m_router->getInputUnit(inport);

                // grant this outport to this inport
                int invc = m_vc_winners[inport];
                // 最好不进入 outvc == -1 的分支? 但是提前决定有点难写
                
                // remove flit from Input VC
                flit *t_flit = input_unit->getTopFlit(invc);

                int outvc = input_unit->get_outvc(invc);
                if (outvc == -1) {
                    // VC Allocation - select any free VC from outport
                    outvc = vc_allocate(outport, inport, invc, t_flit);
                    DPRINTF(RubyNetwork, "VC allocated for outport: %d, inport: %d, invc: %d: %d\n",
                            outport, inport, invc, outvc);
                }

                DPRINTF(RubyNetwork, "SwitchAllocator at Router %d "
                                     "granted outvc %d at outport %d "
                                     "to invc %d at inport %d to flit %s at "
                                     "cycle: %lld\n",
                        m_router->get_id(), outvc,
                        m_router->getPortDirectionName(
                            output_unit->get_direction()),
                        invc,
                        m_router->getPortDirectionName(
                            input_unit->get_direction()),
                            *t_flit,
                        m_router->curCycle());


                // Update outport field in the flit since this is
                // used by CrossbarSwitch code to send it out of
                // correct outport.
                // Note: post route compute in InputUnit,
                // outport is updated in VC, but not in flit
                t_flit->set_outport(outport);

                // set outvc (i.e., invc for next hop) in flit
                // (This was updated in VC by vc_allocate, but not in flit)
                t_flit->set_vc(outvc);

                // decrement credit in outvc
                output_unit->decrement_credit(outvc);

                // flit ready for Switch Traversal
                t_flit->advance_stage(ST_, curTick());
                m_router->grant_switch(inport, t_flit);
                m_output_arbiter_activity++;

                if ((t_flit->get_type() == TAIL_) ||
                    t_flit->get_type() == HEAD_TAIL_) {

                    bool is_wormhole = false;
                    if (m_router->get_net_ptr() != nullptr) {
                        is_wormhole = m_router->is_wormhole_enabled();
                    }

                    if (is_wormhole) {
                        // In wormhole mode, only free VC if buffer is completely empty
                        if (!(input_unit->isReady(invc, curTick()))) {
                            // Buffer is empty, can free VC
                            input_unit->set_vc_idle(invc, curTick());
                            input_unit->increment_credit(invc, true, curTick());
                        } else {
                            // Buffer still has flits, keep VC active
                            input_unit->increment_credit(invc, false, curTick());
                        }
                    } else {
                        // Traditional mode - This Input VC should now be empty
                        assert(!(input_unit->isReady(invc, curTick())));

                        // Free this VC
                        input_unit->set_vc_idle(invc, curTick());

                        // Send a credit back
                        // along with the information that this VC is now idle
                        input_unit->increment_credit(invc, true, curTick());
                    }
                } else {
                    // Send a credit back
                    // but do not indicate that the VC is idle
                    input_unit->increment_credit(invc, false, curTick());
                }

                // remove this request
                m_port_requests[inport] = -1;

                // Update Round Robin pointer
                m_round_robin_inport[outport] = inport + 1;
                if (m_round_robin_inport[outport] >= m_num_inports)
                    m_round_robin_inport[outport] = 0;

                // Update Round Robin pointer to the next VC
                // We do it here to keep it fair.
                // Only the VC which got switch traversal
                // is updated.
                m_round_robin_invc[inport] = invc + 1;
                if (m_round_robin_invc[inport] >= m_num_vcs)
                    m_round_robin_invc[inport] = 0;


                break; // got a input winner for this outport
            }

            inport++;
            if (inport >= m_num_inports)
                inport = 0;
        }
    }
}

/*
 * A flit can be sent only if
 * (1) there is at least one free output VC at the
 *     output port (for HEAD/HEAD_TAIL),
 *  or
 * (2) if there is at least one credit (i.e., buffer slot)
 *     within the VC for BODY/TAIL flits of multi-flit packets.
 * and
 * (3) pt-to-pt ordering is not violated in ordered vnets, i.e.,
 *     there should be no other flit in this input port
 *     within an ordered vnet
 *     that arrived before this flit and is requesting the same output port.
 */


// [TODO]: merge with send_allowed()
bool
SwitchAllocator::send_allowed(int inport, int invc, int outport, int outvc, flit *t_flit)
{
    // Check if outvc needed
    // Check if credit needed (for multi-flit packet)
    // Check if ordering violated (in ordered vnet)

    // int vnet = get_vnet(invc);
    // bool has_outvc = (outvc != -1);
    // bool has_credit = false;
    // // invc 0,2,4..., need change, vc_layer=1
    // // invc 1,3,5..., need change, vc_layer=0
    // // int vc_layer = (invc&1)^(needs_vc_layer_transition_ring(inport, invc, outport, m_router, m_vc_per_vnet) ? 1 : 0);
    // bool vc_layer = (invc&1)|(needs_vc_layer_transition_ring(inport, invc, outport, m_router, m_vc_per_vnet) ? 1 : 0);
    // int vc_offset = 2;

    int vnet = get_vnet(invc);
    bool has_outvc = (outvc != -1);
    bool has_credit = false;


    RoutingAlgorithm routing_algorithm =
        (RoutingAlgorithm) m_router->get_net_ptr()->getRoutingAlgorithm();

    bool use_val = m_router->get_net_ptr()->getVal();

    int vc_layer = calculate_vclayer(inport, invc, outport, m_router, m_vc_per_vnet, routing_algorithm, t_flit);
    DPRINTF(RubyNetwork, "Calculated vc_layer: %d for inport: %d, invc: %d, outport: %d, flit: %s\n",
            vc_layer, inport, invc, outport, *t_flit);
    int vc_offset = 2;
    if(routing_algorithm == RING_ || routing_algorithm == SLIMFLY_) {
        vc_offset = 2;
        if(use_val && (routing_algorithm == SLIMFLY_)) {
            vc_offset = 4;
        }
    } else {
        // assert(false);
        vc_layer=0; 
        vc_offset=1;
    }
    if(t_flit->get_route().dest_router == m_router->get_id()) {
        // to avoid vc_layer overflow when reach destination
        vc_layer=0; 
        vc_offset=1;
    }
    assert(vc_offset <= m_vc_per_vnet);
    assert(vc_layer < vc_offset);

    auto output_unit = m_router->getOutputUnit(outport);
    if (!has_outvc) {

        // needs outvc
        // this is only true for HEAD and HEAD_TAIL flits.
        bool hasFreeVCLayer = output_unit->has_free_vc_layer(vnet, vc_layer, vc_offset);
        DPRINTF(RubyNetwork, "Checking free VC layer for vnet: %d, vc_layer: %d, vc_offset: %d: %d\n",
                vnet, vc_layer, vc_offset, hasFreeVCLayer);
        if (hasFreeVCLayer) {

            has_outvc = true;

            // each VC has at least one buffer,
            // so no need for additional credit check
            has_credit = true;
        }
    } else {
        has_credit = output_unit->has_credit(outvc);
    }

    // cannot send if no outvc or no credit.
    if (!has_outvc || !has_credit)
        return false;


    // protocol ordering check
    if ((m_router->get_net_ptr())->isVNetOrdered(vnet)) {
        auto input_unit = m_router->getInputUnit(inport);

        // enqueue time of this flit
        Tick t_enqueue_time = input_unit->get_enqueue_time(invc);

        // check if any other flit is ready for SA and for same output port
        // and was enqueued before this flit
        int vc_base = vnet*m_vc_per_vnet;
        // for (int vc_offset = 0; vc_offset < m_vc_per_vnet; vc_offset++) {
        for (int temp_vc = vc_base + vc_layer; temp_vc < vc_base + m_vc_per_vnet; temp_vc += vc_offset) {
            if (input_unit->need_stage(temp_vc, SA_, curTick()) &&
               (input_unit->get_outport(temp_vc) == outport) &&
               (input_unit->get_enqueue_time(temp_vc) < t_enqueue_time)) {
                return false;
            }
        }
    }

    return true;
}



// [DEBUG] check this !

// Enhanced VC allocation for ring topology with deadlock prevention
// [TODO]: later, merge with vc_allocate()
int
SwitchAllocator::vc_allocate(int outport, int inport, int invc, flit *t_flit)
{

    int vnet = get_vnet(invc);
    bool has_credit = false;
    RoutingAlgorithm routing_algorithm =
        (RoutingAlgorithm) m_router->get_net_ptr()->getRoutingAlgorithm();

    bool use_val = m_router->get_net_ptr()->getVal();

    int vc_layer = calculate_vclayer(inport, invc, outport, m_router, m_vc_per_vnet, routing_algorithm, t_flit);
    
    int vc_offset = 2;
    if(routing_algorithm == RING_ || routing_algorithm == SLIMFLY_) {
        vc_offset = 2;
        if(use_val && (routing_algorithm == SLIMFLY_)) {
            vc_offset = 4;
        }
    } else {
        vc_layer=0; 
        vc_offset=1;
    }
    if(t_flit->get_route().dest_router == m_router->get_id()) {
        // to avoid vc_layer overflow when reach destination
        vc_layer=0; 
        vc_offset=1;
    }
    assert(vc_offset <= m_vc_per_vnet);
    assert(vc_layer < vc_offset);
    // Select VC from appropriate layer
    int outvc = m_router->getOutputUnit(outport)->select_free_vc_layer(vnet, vc_layer, vc_offset);

    assert(outvc != -1);

    m_router->getInputUnit(inport)->grant_outvc(invc, outvc);

    return outvc;
}

int SwitchAllocator::calculate_vclayer(int inport, int invc, int outport,
                                        Router* router, int vc_per_vnet,
                                        RoutingAlgorithm routing_algorithm,
                                         flit *t_flit)
{
    // Check if this is router 0 (dateline) and packet came from left (router num_nodes-1)
    int my_id = router->get_id();
    int num_routers = router->get_net_ptr()->getNumRouters();
    if (routing_algorithm == RING_) {
        if(invc & 1) {
            // invc is odd, vc_layer = 1
            return 1;
        } else {
            if (my_id == 0 ) {
                return 1;
            } else {
                return 0;
            }
        }
    }else if(routing_algorithm == SLIMFLY_){
        return t_flit->get_hops();
    }else {
        return 0;
    }
}



// Wakeup the router next cycle to perform SA again
// if there are flits ready.
void
SwitchAllocator::check_for_wakeup()
{
    Tick nextCycle = m_router->clockEdge(Cycles(1));

    if (m_router->alreadyScheduled(nextCycle)) {
        return;
    }

    for (int i = 0; i < m_num_inports; i++) {
        for (int j = 0; j < m_num_vcs; j++) {
            if (m_router->getInputUnit(i)->need_stage(j, SA_, nextCycle)) {
                m_router->schedule_wakeup(Cycles(1));
                return;
            }
        }
    }
}

int
SwitchAllocator::get_vnet(int invc)
{
    int vnet = invc/m_vc_per_vnet;
    assert(vnet < m_router->get_num_vnets());
    return vnet;
}


// Clear the request vector within the allocator at end of SA-II.
// Was populated by SA-I.
void
SwitchAllocator::clear_request_vector()
{
    std::fill(m_port_requests.begin(), m_port_requests.end(), -1);
}

void
SwitchAllocator::resetStats()
{
    m_input_arbiter_activity = 0;
    m_output_arbiter_activity = 0;
}

} // namespace garnet
} // namespace ruby
} // namespace gem5
