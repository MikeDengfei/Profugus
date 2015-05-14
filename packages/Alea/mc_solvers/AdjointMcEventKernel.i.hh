//----------------------------------*-C++-*----------------------------------//
/*!
 * \file   AdjointMcEventKernel.cc
 * \author Steven Hamilton
 * \brief  Perform single history of adjoint MC
 */
//---------------------------------------------------------------------------//

#ifndef mc_solver_AdjointMcEventKernel_i_hh
#define mc_solver_AdjointMcEventKernel_i_hh

#include <iterator>
#include <random>
#include <cmath>

#include "AdjointMcEventKernel.hh"
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
AdjointMcEventKernel::AdjointMcEventKernel(
        const MC_Data_View                  &mc_data,
        const const_scalar_view              coeffs,
        Teuchos::RCP<Teuchos::ParameterList> pl,
        generator_pool                       pool)
  : d_N(mc_data.offsets.size()-1)
  , d_mc_data(mc_data)
  , d_coeffs(coeffs)
  , d_start_cdf("start_cdf",d_N)
  , d_start_wt("start_wt",d_N)
  , d_rand_pool(pool)
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
    VALIDATE(!d_use_expected_value,
        "Expected value not available in event kernel yet.");

    // Power factor for initial probability distribution
    d_start_wt_factor = pl->get<SCALAR>("start_weight_factor",1.0);

    // Should we print anything to screen
    std::string verb = profugus::to_lower(pl->get("verbosity","low"));
    d_print = (verb == "high");
}

//---------------------------------------------------------------------------//
// Solve problem using Monte Carlo
//---------------------------------------------------------------------------//
void AdjointMcEventKernel::solve(const MV &x, MV &y)
{
    // Build initial probability and weight distributions
    build_initial_distribution(x);

    // Need to get Kokkos view directly, this is silly
    const scalar_view  y_device( "result",      d_N);
    const scalar_view  randoms(  "randoms",     d_num_histories);
    const History_Data hist_data(d_num_histories);

    // Build kernels
    InitHistory     init_history(randoms,d_start_cdf,d_start_wt,hist_data,
                                 d_mc_data);
    StateTransition transition(randoms,hist_data,d_mc_data);
    CollisionTally  coll_tally(hist_data,d_coeffs,y_device);

    // Create policy
    range_policy policy(0,d_num_histories);

    // Get initial state and tally
    Kokkos::fill_random(randoms,d_rand_pool,1.0);
    Kokkos::parallel_for(policy,init_history);
    Kokkos::parallel_for(policy,coll_tally);

    // Loop over history length (start at 1)
    for( int i=1; i<=d_max_history_length; ++i )
    {
        Kokkos::fill_random(randoms,d_rand_pool,1.0);
        Kokkos::parallel_for(policy,transition);
        Kokkos::parallel_for(policy,coll_tally);
    }

    // Copy data back to host
    Teuchos::ArrayRCP<SCALAR> y_data = y.getDataNonConst(0);
    const scalar_host_mirror y_mirror =
        Kokkos::create_mirror_view(y_device);
    Kokkos::deep_copy(y_mirror,y_device);

    // Apply scale factor
    SCALAR scale_factor = 1.0 / static_cast<SCALAR>(d_num_histories);
    for( LO i=0; i<d_N; ++i )
    {
        y_data[i] = scale_factor*y_mirror(i);
    }

    // Add rhs for expected value
    if( d_use_expected_value )
    {
        y.update(d_coeffs(0),x,1.0);
    }
}

//---------------------------------------------------------------------------//
// Build initial cdf and weights
//---------------------------------------------------------------------------//
void AdjointMcEventKernel::build_initial_distribution(const MV &x)
{
    // Build data on host, then explicitly copy to device
    // In future, convert this to a new Kernel to allow building
    //  distributions directly on device if x is allocated there
    scalar_host_mirror start_cdf_host = Kokkos::create_mirror_view(d_start_cdf);
    scalar_host_mirror start_wt_host  = Kokkos::create_mirror_view(d_start_wt);

    Teuchos::ArrayRCP<const SCALAR> x_data = x.getData(0);

    for( LO i=0; i<d_N; ++i )
    {
        start_cdf_host(i) =
            SCALAR_TRAITS::pow(SCALAR_TRAITS::magnitude(x_data[i]),
                               d_start_wt_factor);
    }
    SCALAR pdf_sum = std::accumulate(&start_cdf_host(0),&start_cdf_host(d_N-1)+1,0.0);
    ENSURE( pdf_sum > 0.0 );
    std::transform(&start_cdf_host(0),&start_cdf_host(d_N-1)+1,&start_cdf_host(0),
                   [pdf_sum](SCALAR x){return x/pdf_sum;});
    std::transform(x_data.begin(),x_data.end(),&start_cdf_host(0),
                   &start_wt_host(0),
                   [](SCALAR x, SCALAR y){return y==0.0 ? 0.0 : x/y;});
    std::partial_sum(&start_cdf_host(0),&start_cdf_host(d_N-1)+1,&start_cdf_host(0));

    Kokkos::deep_copy(d_start_cdf,start_cdf_host);
    Kokkos::deep_copy(d_start_wt, start_wt_host);
}


} // namespace alea

#endif // mc_solver_AdjointMcEventKernel_i_hh