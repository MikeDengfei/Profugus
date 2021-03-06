//----------------------------------*-C++-*----------------------------------//
/*!
 * \file   Alea/mc_solvers/AdjointMcParallelReduce.i.hh
 * \author Steven Hamilton
 * \brief  Perform single history of adjoint MC
 */
//---------------------------------------------------------------------------//

#ifndef Alea_mc_solvers_AdjointMcParallelReduce_i_hh
#define Alea_mc_solvers_AdjointMcParallelReduce_i_hh

#include <iterator>
#include <random>
#include <cmath>

#include "AdjointMcParallelReduce.hh"
#include "MC_Components.hh"
#include "utils/String_Functions.hh"
#include "harness/Warnings.hh"

namespace alea
{

//---------------------------------------------------------------------------//
/*!
 * \brief Constructor
 *
 * \param P Views into entries of probability matrix
 * \param W Views into entries of weight matrix
 * \param inds Views into nonzeros indices
 * \param offsets Starting indices for each matrix row
 * \param coeffs Polynomial coefficients
 * \param pl Problem parameters
 */
//---------------------------------------------------------------------------//
AdjointMcParallelReduce::AdjointMcParallelReduce(
        const MC_Data_View                  &mc_data,
        const const_scalar_view              coeffs,
        Teuchos::RCP<Teuchos::ParameterList> pl)
  : value_count(mc_data.offsets.size()-1)
  , d_mc_data(mc_data)
  , d_coeffs(coeffs)
  , d_start_cdf("start_cdf",value_count)
  , d_start_wt("start_wt",value_count)
  , d_rand_pool(pl->get("random_seed",31891))
  , d_max_history_length(d_coeffs.size()-1)
{
    d_num_histories = pl->get("num_histories",1000);

    // Determine type of tally
    std::string estimator = pl->get<std::string>("estimator",
                                                 "expected_value");
    VALIDATE(estimator == "collision" ||
             estimator == "expected_value",
             "Only collision and expected_value estimators are available.");
    d_use_expected_value = (estimator == "expected_value");

    // Power factor for initial probability distribution
    d_start_wt_factor = pl->get<SCALAR>("start_weight_factor",1.0);

    // Weight cutoff
    d_wt_cutoff = pl->get<SCALAR>("weight_cutoff",0.0);

    // Should we print anything to screen
    std::string verb = profugus::lower(pl->get("verbosity","low"));
    d_print = (verb == "high");
}

//---------------------------------------------------------------------------//
// Solve problem using Monte Carlo
//---------------------------------------------------------------------------//
void AdjointMcParallelReduce::solve(const MV &x, MV &y)
{
    range_policy policy(0,d_num_histories);

    // Build initial probability and weight distributions
    build_initial_distribution(x);

    // Need to get Kokkos view directly, this is silly
    Teuchos::ArrayRCP<SCALAR> y_data = y.getDataNonConst(0);
    const scalar_view y_device("result",value_count);
    const scalar_host_mirror y_mirror =
        Kokkos::create_mirror_view(y_device);

    // Execute functor
    Kokkos::parallel_reduce(policy,*this,y_mirror);

    // Apply scale factor
    SCALAR scale_factor = 1.0 / static_cast<SCALAR>(d_num_histories);
    for( LO i=0; i<value_count; ++i )
    {
        y_data[i] = scale_factor*y_mirror(i);
    }

    // Add rhs for expected value
    if( d_use_expected_value )
    {
        scalar_host_mirror coeffs_mirror =
            Kokkos::create_mirror_view(d_coeffs);
        Kokkos::deep_copy(coeffs_mirror,d_coeffs);
        y.update(coeffs_mirror(0),x,1.0);
    }
}


//---------------------------------------------------------------------------//
// Kokkos init
//---------------------------------------------------------------------------//
void AdjointMcParallelReduce::init( SCALAR *update ) const
{
    for( LO i=0; i<value_count; ++i )
    {
        update[i] = 0.0;
    }
}

//---------------------------------------------------------------------------//
/*!
 * \brief Perform adjoint Monte Carlo process
 */
//---------------------------------------------------------------------------//
void AdjointMcParallelReduce::operator()(const policy_member &member, SCALAR *y) const
{
    LO new_ind;
    LO state;
    const SCALAR * row_h;
    const SCALAR * row_cdf;
    const SCALAR * row_wts;
    const LO     * row_inds;
    int row_length;

    generator_type rand_gen = d_rand_pool.get_state();

    int histories_per_thread = 1;
    for( int ihist=0; ihist<histories_per_thread; ++ihist )
    {
        /*
        if( d_print )
        {
            printf("Getting new state on team %i, thread %i\n",
                    member.league_rank(),member.team_rank());
        }
        */

        // Get starting position and weight
        state = getNewState(&d_start_cdf(0),value_count,rand_gen);
        if( state == -1 )
            continue;

        if( std::abs(d_start_wt(state)) == 0.0 )
            continue;

        SCALAR weight = d_start_wt(state);
        SCALAR initial_weight = weight;

        if( d_print )
        {
            printf("Starting history in state %i with initial weight %6.2e\n",
                   state,initial_weight);
        }

        // Collision estimator starts tallying on zeroth order term
        // Expected value estimator gets this added explicitly at the end
        int stage = 0;
        if( d_use_expected_value )
            stage++;

        // Transport particle until done
        while(true)
        {
            // Get data and add to tally
            /*
            if( d_print )
            {
                printf("Getting new row on team %i, thread %i\n",
                       member.league_rank(),member.team_rank());
            }
            */
            getNewRow(state,row_h,row_cdf,row_wts,row_inds,row_length);
            /*
            if( d_print )
            {
                printf("Tallying contribution to state %i on team %i, thread %i\n",
                       state,member.league_rank(),member.team_rank());
            }
            */
            tallyContribution(state,d_coeffs(stage)*weight,
                              row_h,row_inds,row_length,y);

            /*
            if( d_print )
            {
                printf("Checking length cutoff on team %i, thread %i\n",
                       member.league_rank(),member.team_rank());
            }
            */
            if( stage >= d_max_history_length )
                break;

            if( std::abs(weight/initial_weight) < d_wt_cutoff )
                break;

            // Get new state index
            /*
            if( d_print )
            {
                printf("Getting new state on team %i, thread %i\n",
                       member.league_rank(),member.team_rank());
            }
            */
            new_ind = getNewState(row_cdf,row_length,rand_gen);
            if( new_ind == -1 )
                break;

            // Modify weight and update state
            weight *=  row_wts[new_ind];
            state   = row_inds[new_ind];
            stage++;

            if( d_print )
            {
                printf("Transitioning to state %i with new weight %6.2e",
                       state,weight);
            }

        } // while
    } // for ihist

    d_rand_pool.free_state(rand_gen);
}

//---------------------------------------------------------------------------//
// Kokkos join
//---------------------------------------------------------------------------//
void AdjointMcParallelReduce::join(      volatile SCALAR *update,
                           const volatile SCALAR *input) const
{
    for( LO i=0; i<value_count; ++i )
    {
        update[i] = update[i] + input[i];
    }
}

//---------------------------------------------------------------------------//
// PRIVATE FUNCTIONS
//---------------------------------------------------------------------------//

//---------------------------------------------------------------------------//
/*!
 * \brief Tally contribution into vector
 */
//---------------------------------------------------------------------------//
void AdjointMcParallelReduce::getNewRow( const LO        state,
                                 const SCALAR * &h_vals,
                                 const SCALAR * &p_vals,
                                 const SCALAR * &w_vals,
                                 const LO     * &inds,
                                       LO       &row_length ) const
{
    LO off     = d_mc_data.offsets(state);
    h_vals     = &d_mc_data.H(off);
    p_vals     = &d_mc_data.P(off);
    w_vals     = &d_mc_data.W(off);
    inds       = &d_mc_data.inds(off);
    row_length = d_mc_data.offsets(state+1)-off;
}

//---------------------------------------------------------------------------//
/*!
 * \brief Tally contribution into vector
 */
//---------------------------------------------------------------------------//
void AdjointMcParallelReduce::tallyContribution(
        const LO             state,
        const SCALAR         wt,
        const SCALAR * const h_vals,
        const LO     * const inds,
        const int            row_length,
              SCALAR * const y) const
{
    if( d_use_expected_value )
    {
        if( row_length > 0 )
        {
            y[inds[0]] += wt*h_vals[0];
            for( LO i=1; i<row_length; ++i )
            {
                // P is cdf, we want value of pdf
                y[inds[i]] += wt*h_vals[i];
            }
        }
    }
    else
    {
        y[state] += wt;
    }
}

//---------------------------------------------------------------------------//
/*!
 * \brief Get new state by sampling from cdf
 */
//---------------------------------------------------------------------------//
LO AdjointMcParallelReduce::getNewState(const SCALAR * const  cdf,
                                const LO              cdf_length,
                                      generator_type &gen) const
{
    // Generate random number
    SCALAR rand = Kokkos::rand<generator_type,SCALAR>::draw(gen);

    // Sample cdf to get new state
    // Use local lower_bound implementation, not std library version
    // This allows calling from device
    const SCALAR * const elem = lower_bound(cdf,cdf+cdf_length,rand);

    if( elem == cdf+cdf_length )
        return -1;

    return elem - cdf;
}

//---------------------------------------------------------------------------//
// Build initial cdf and weights
//---------------------------------------------------------------------------//
void AdjointMcParallelReduce::build_initial_distribution(const MV &x)
{
    // Build data on host, then explicitly copy to device
    // In future, convert this to a new Kernel to allow building
    //  distributions directly on device if x is allocated there
    scalar_host_mirror start_cdf_host = Kokkos::create_mirror_view(d_start_cdf);
    scalar_host_mirror start_wt_host  = Kokkos::create_mirror_view(d_start_wt);

    Teuchos::ArrayRCP<const SCALAR> x_data = x.getData(0);

    int N = value_count;

    for( LO i=0; i<N; ++i )
    {
        start_cdf_host(i) =
            SCALAR_TRAITS::pow(SCALAR_TRAITS::magnitude(x_data[i]),
                               d_start_wt_factor);
    }
    SCALAR pdf_sum = std::accumulate(&start_cdf_host(0),&start_cdf_host(N-1)+1,0.0);
    ENSURE( pdf_sum > 0.0 );
    std::transform(&start_cdf_host(0),&start_cdf_host(N-1)+1,&start_cdf_host(0),
                   [pdf_sum](SCALAR x){return x/pdf_sum;});
    std::transform(x_data.begin(),x_data.end(),&start_cdf_host(0),
                   &start_wt_host(0),
                   [](SCALAR x, SCALAR y){return y==0.0 ? 0.0 : x/y;});
    std::partial_sum(&start_cdf_host(0),&start_cdf_host(N-1)+1,&start_cdf_host(0));
    Kokkos::deep_copy(d_start_cdf,start_cdf_host);
    Kokkos::deep_copy(d_start_wt, start_wt_host);
}


} // namespace alea

#endif // Alea_mc_solvers_AdjointMcParallelReduce_i_hh
