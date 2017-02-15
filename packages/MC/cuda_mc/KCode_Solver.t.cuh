//----------------------------------*-C++-*----------------------------------//
/*!
 * \file   cuda_mc/KCode_Solver.t.cuh
 * \author Steven Hamilton
 * \date   Mon May 19 10:30:32 2014
 * \brief  KCode_Solver member definitions.
 * \note   Copyright (C) 2014 Oak Ridge National Laboratory, UT-Battelle, LLC.
 */
//---------------------------------------------------------------------------//

#ifndef cuda_mc_KCode_Solver_t_cuh
#define cuda_mc_KCode_Solver_t_cuh

#include "KCode_Solver.cuh"

#include <iostream>
#include <iomanip>

#include "harness/Diagnostics.hh"
#include "comm/global.hh"
#include "comm/Timing.hh"
#include "comm/Logger.hh"

namespace cuda_mc
{

//---------------------------------------------------------------------------//
// CONSTRUCTION
//---------------------------------------------------------------------------//
/*!
 * \brief Constructor.
 */
template <class Geometry>
KCode_Solver<Geometry>::KCode_Solver(RCP_Std_DB db)
    : d_db(db)
    , d_build_phase(CONSTRUCTED)
    , d_quiet(db->get("quiet", false))
{
    // set quiet off on work nodes
    if (profugus::node() != 0)
        d_quiet = true;

    ENSURE(d_build_phase == CONSTRUCTED);
}

//---------------------------------------------------------------------------//
/*!
 * \brief Set the underlying fixed-source transporter and fission source.
 */
template <class Geometry>
void KCode_Solver<Geometry>::set(SP_Source_Transporter transporter,
                                 SP_Fission_Source     source,
                                 SP_Tallier_DMM        tallier)
{
    REQUIRE(d_build_phase == CONSTRUCTED);
    REQUIRE(transporter);
    REQUIRE(source);
    REQUIRE(tallier);

    // assign the solver
    d_transporter = transporter;

    // assign the source
    d_source = source;

    // store the integrated cycle weight (const number of requested particles
    // per cycle)
    d_Np = static_cast<double>(d_source->Np());
    CHECK(d_Np > 0.0);

    d_batch_size = std::numeric_limits<size_type>::max();
    if (d_db->isType<int>("batch_size"))
    {
        d_batch_size = d_db->get<int>("batch_size");
    }
    else if (d_db->isType<size_type>("batch_size"))
    {
        d_batch_size = d_db->get<size_type>("batch_size");
    }
    else if (d_db->isParameter("batch_size"))
        VALIDATE(false,"Unrecognized type for parameter batch_size.");

    // Determine batching parameter for statistics
    d_cycles_per_batch = d_db->get<int>("cycles_per_batch",1);
    VALIDATE(d_cycles_per_batch>0,
        "Number of cycles per statistics batch must be positive.");

    // assign base class pointer
    b_tallier = tallier;

    // get initial k and build keff tally
    double init_keff = d_db->get("keff_init", 1.0);
    INSIST(init_keff >= 0., "Initial keff guess must be nonnegative.");
    d_keff_tally = std::make_shared<Keff_Tally_DMM_t>(
        init_keff, d_transporter->physics());

    // create our "disabled" (inactive cycle) tallier
    d_inactive_tallier = std::make_shared<Tallier_DMM_t>();
    d_inactive_tallier->set(d_transporter->geometry(), d_transporter->physics());

    // Build fission site vector
    d_host_sites = std::make_shared<Host_Fission_Sites>();
    d_dev_sites  = std::make_shared<Dev_Fission_Sites>();

    d_build_phase = ASSIGNED;

    ENSURE(b_tallier);
    ENSURE(d_inactive_tallier);
    ENSURE(d_keff_tally);
    ENSURE(d_transporter);
}

//---------------------------------------------------------------------------//
// INHERITED INTERFACE
//---------------------------------------------------------------------------//
/*!
 * \brief Solve the kcode problem.
 *
 * This runs the initialize/iterate/finalize process, and also prints user
 * output.
 */
template <class Geometry>
void KCode_Solver<Geometry>::solve()
{
    using std::endl; using std::cout;
    using std::setw; using std::fixed; using std::scientific;

    SCOPED_TIMER("MC::KCode_Solver.solve");

    // set cycle numbers
    const int num_total    = d_db->get("num_cycles",          50);
    const int num_inactive = d_db->get("num_inactive_cycles", 10);
    const int num_active   = num_total - num_inactive;

    INSIST(num_inactive > 0,
            "The number of  inactive keff cycles must be positive.");
    INSIST(num_total > num_inactive,
            "The number of keff cycles must be greater than the number"
            " of inactive cycles.");

    ENSURE(num_inactive + num_active == num_total);
    ENSURE(num_total > 0);

    // Preallocate diagnostics
    DIAGNOSTICS_ONE(vec_integers["np_fission"]      .reserve(num_total);)
    DIAGNOSTICS_TWO(vec_doubles ["local_np_fission"].reserve(num_total);)

    // Timers (some required, some optional)
    profugus::Timer cycle_timer;

    // Set up initial source etc.
    this->initialize();

    // Print column header
    if (!d_quiet)
    {
        cout << ">>> Beginning inactive cycles." << endl;
        cout << endl;
        cout << " Cycle  k_cycle   Time (s) " << endl;
    }

    // Solve inactive cycles
    for (int cycle = 0; cycle < num_inactive; ++cycle)
    {
        // Iterate and time
        cycle_timer.start();
        this->iterate();
        cycle_timer.stop();

        // Print diagnostic output
        if (!d_quiet)
        {
            cout.precision(6);
            cout.setf(std::ios::internal);

            cout << fixed      << setw(4) << cycle << "   "
                 << fixed      << setw(8) << d_keff_tally->latest() << "  "
                 << scientific << setw(9) << cycle_timer.TIMER_CLOCK()
                 << endl;
        }
    }

    // Prepare for active cycles
    CHECK(num_cycles() == num_inactive);
    this->begin_active_cycles();
    CHECK(num_cycles() == 0);

    // Print column header
    if (!d_quiet)
    {
        cout << endl;
        cout << ">>> Beginning active cycles." << endl;
        cout << endl;
        cout << " Cycle  k_cycle    k_avg    k_variance    Time (s) "
             << endl;
    }

    // Solve active cycles
    for (int cycle = 0; cycle < num_active; ++cycle)
    {
        // Iterate and time
        cycle_timer.start();
        this->iterate();
        cycle_timer.stop();

        // End batch in tallier at specified interval
        if (cycle % d_cycles_per_batch == 0)
            b_tallier->end_batch(d_cycles_per_batch*d_Np);

        // Print diagnostic output
        if (!d_quiet)
        {
            cout.precision(6);
            cout.setf(std::ios::internal);

            cout << fixed      << setw(4)  << cycle << "   "
                 << fixed      << setw(8)  << d_keff_tally->latest() << "  "
                 << fixed      << setw(8)  << d_keff_tally->mean() << "  "
                 << scientific << setw(11) << d_keff_tally->variance() << "  "
                 << scientific << setw(11) << cycle_timer.TIMER_CLOCK()
                 << endl;
        }
    }
    CHECK(num_cycles() == num_active);

    // End final batch for remaining odd cycles
    int extra_cycles = num_active % d_cycles_per_batch;
    if (extra_cycles > 0)
        b_tallier->end_batch(extra_cycles*d_Np);

    if (!d_quiet)
        cout << endl;

    profugus::global_barrier();

    // Finalize
    this->finalize();

    //ENSURE(b_tallier->is_finalized());
}

//---------------------------------------------------------------------------//
/*!
 * \brief Call to reset the solver and tallies for another kcode run
 */
template <class Geometry>
void KCode_Solver<Geometry>::reset()
{
    INSIST(d_build_phase == FINALIZED,
            "Reset may be called only after finalizing.");

    // Reset tallies
    b_tallier->reset();
    d_inactive_tallier->reset();

    d_build_phase = ASSIGNED;
}

//---------------------------------------------------------------------------//
// PUBLIC INTERFACE
//---------------------------------------------------------------------------//
/*!
 * \brief Initialize the k-eigenvalue problem.
 *
 * The initialize method adds the keffective tally to the active/inactive
 * talliers, builds the initial/fission source, and changes the tallier being
 * used.
 *
 * This last step allows user-added tallies (e.g. flux tallies) to be turned
 * off during the initial cycles, so that their biased distributions don't
 * contribute to the final (active-averaged) results.
 *
 * After this "swap", the keff tally (and potentially other diagnostic tallies
 * added to the 'inactive' tallier) are the only ones that will be called by the
 * transporter.
 */
template <class Geometry>
void KCode_Solver<Geometry>::initialize()
{
    INSIST(d_build_phase == ASSIGNED,
            "initialize must be called only after calling set()");

    // Add the keff tally to the ACTIVE cycle tallier and build it
    b_tallier->add_keff_tally(d_keff_tally);

    // Create tallier for inactive cycles
    // Currentely only keff tally is enabled
    d_inactive_tallier->add_keff_tally(d_keff_tally);

    d_transporter->set(d_inactive_tallier);

    // build the initial fission source
    if (d_source->is_initial_source())
    {
        d_source->build_initial_source();
    }

    d_build_phase = INACTIVE_SOLVE;

    ENSURE(d_keff_tally->cycle_count() == 0);
    ENSURE(d_build_phase == INACTIVE_SOLVE);
}

//---------------------------------------------------------------------------//
/*!
 * \brief Perform one k-eigenvalue cycle.
 */
template <class Geometry>
void KCode_Solver<Geometry>::iterate()
{
    REQUIRE(d_host_sites);
    REQUIRE(d_build_phase == INACTIVE_SOLVE || d_build_phase == ACTIVE_SOLVE);

    // store the number of source particles for this cycle
    DIAGNOSTICS_ONE(vec_integers["np_fission"].push_back(
                        d_source->total_num_to_transport()));
    DIAGNOSTICS_TWO(vec_integers["local_np_fission"].push_back(
                        d_source->num_to_transport()));

    // Allocate space for host fission sites
    // 20% above either the requested number of histories or the current
    // number of particles, whichever is larger
    double safety_factor = 1.2;
    size_type available_host_sites = safety_factor *
        std::max(d_source->Np()/profugus::nodes(),
                 d_source->num_to_transport());
    d_host_sites->resize(available_host_sites);

    // Allocate space for device fission sites
    // 20% above the batch size
    size_type this_batch_size = std::min(d_batch_size,
        d_source->num_to_transport());
    size_type available_dev_sites;
    if (d_batch_size == std::numeric_limits<size_type>::max())
    {
        available_dev_sites = available_host_sites;
    }
    else
    {
        available_dev_sites = safety_factor * this_batch_size;
    }
    d_dev_sites->resize(available_dev_sites);

    // initialize keff tally to the beginning of the cycle
    double latest_keff = d_keff_tally->latest();

    b_tallier->begin_cycle(this_batch_size);
    d_source->set_batch_size(this_batch_size);

    size_type num_sites = 0;

    while (d_source->num_left() > 0)
    {
        // set the solver to sample fission sites
        d_transporter->sample_fission_sites(d_dev_sites,latest_keff);

        // solve the fixed source problem using the transporter
        d_transporter->solve(d_source);

        // update fission site vector
        size_type num_sites_batch =
            d_transporter->num_sampled_fission_sites();

        if( num_sites_batch > available_dev_sites )
        {
            if( d_build_phase == INACTIVE_SOLVE )
            {
                profugus::log(profugus::WARNING) <<
                    "Not enough space allocated for fission sites on cycle " <<
                    num_cycles() << ". " << available_dev_sites <<
                    " were allocated but " << num_sites_batch
                    << " were required.";
            }
            else
            {
                INSIST(false,"Not enough space allocated for device fission "
                        "sites during active cycle.");
            }
        }

        num_sites_batch = std::min(num_sites_batch,available_dev_sites);

        if( num_sites+num_sites_batch > available_host_sites )
        {
            if( d_build_phase == INACTIVE_SOLVE )
            {
                profugus::log(profugus::WARNING) <<
                    "Not enough space allocated for fission sites on cycle " <<
                    num_cycles() << ". " << available_host_sites <<
                    " were allocated but " << num_sites
                    << " were required.";
            }
            else
            {
                INSIST(false,"Not enough space allocated for host fission sites "
                        "during active cycle");
            }
        }

        num_sites_batch = std::min(num_sites_batch,
            available_host_sites-num_sites);

        thrust::copy(d_dev_sites->begin(),d_dev_sites->begin()+num_sites_batch,
                     d_host_sites->begin()+num_sites);

        num_sites += num_sites_batch;
    }

    d_host_sites->resize(std::min(available_host_sites,num_sites));

    // do end-of-cycle tally processing including global sum Note: this is the
    // total *requested* number of particles, not the actual number of
    // histories. Each processor adjusts the particle weights so that the
    // total weight emitted, summed over all processors, is d_Np.
    b_tallier->end_cycle(d_Np);

    // build a new source from the fission site distribution
    d_source->build_source(d_host_sites);

    ENSURE(d_host_sites);
}

//---------------------------------------------------------------------------//
/*!
 * \brief Call to transition from inactive to active cycles
 *
 * This reinstates the original tallies and calls "finalize" on the inactive
 * tallies.
 */
template <class Geometry>
void KCode_Solver<Geometry>::begin_active_cycles()
{
    REQUIRE(d_inactive_tallier);
    REQUIRE(b_tallier);

    // Finalize the inactive tallier (will set the state to FINALIZED, but
    // shouldn't do anything else unless the user has explicitly added a tally
    // to it. This ensures that if the user has added, say, the same mesh
    // tally to both inactive and active cycles, they get an obvious "tally
    // was already finalized" error instead of a more subtle error (viz.,
    // being normalized to the *active* particle count instead of the *active
    // + inactive* particle count).
    d_inactive_tallier->finalize(num_cycles() * d_Np);

    // Tell all tallies to begin tallying active cycles
    b_tallier->begin_active_cycles();

    d_transporter->set(b_tallier);

    d_build_phase = ACTIVE_SOLVE;

    //ENSURE(d_inactive_tallier->is_finalized());
    ENSURE(num_cycles() == 0);
    ENSURE(d_build_phase == ACTIVE_SOLVE);
}

//---------------------------------------------------------------------------//
/*!
 * \brief Finalize the k-eigenvalue problem.
 *
 * This calls "finalize" on the active tallies, doing global sums,
 * redistributions, etc.
 */
template <class Geometry>
void KCode_Solver<Geometry>::finalize()
{
    INSIST(d_build_phase == ACTIVE_SOLVE,
            "Finalize can only be called after iterating with active cycles.");
    INSIST(num_cycles() > 0, "No active cycles were performed.");

    // Finalize tallies using global number particles
    //CHECK(!b_tallier->is_finalized());
    b_tallier->finalize(num_cycles() * d_Np);

    d_build_phase = FINALIZED;

    //ENSURE(b_tallier->is_finalized());
    ENSURE(d_build_phase == FINALIZED);
}

} // end namespace cuda_mc

#endif // cuda_mc_KCode_Solver_t_cuh

//---------------------------------------------------------------------------//
//                 end of KCode_Solver.t.cuh
//---------------------------------------------------------------------------//
