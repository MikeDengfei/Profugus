//----------------------------------*-C++-*----------------------------------//
/*!
 * \file   cuda_mc/Keff_Tally.cuh
 * \author Steven Hamilton
 * \date   Wed May 14 13:29:40 2014
 * \brief  Keff_Tally class definition.
 * \note   Copyright (C) 2014 Oak Ridge National Laboratory, UT-Battelle, LLC.
 */
//---------------------------------------------------------------------------//

#ifndef cuda_mc_Keff_Tally_cuh
#define cuda_mc_Keff_Tally_cuh

#include <thrust/device_vector.h>

#include "utils/Definitions.hh"

#include "cuda_utils/Shared_Device_Ptr.hh"
#include "cuda_utils/Device_Memory_Manager.hh"
#include "Physics.cuh"
#include "Particle_Vector.cuh"

namespace cuda_mc
{

//===========================================================================//
/*!
 * \class Keff_Tally
 * \brief Use path length to estimate eigenvalue and variance
 *
 * Tally keff during KCode operation using path-length accumulators.
 */
/*!
 * \example mc/test/tstKeff_Tally.cc
 *
 * Test of Keff_Tally.
 */
//===========================================================================//

template <class Geometry>
class Keff_Tally
{
  public:

    typedef Physics<Geometry>           Physics_t;
    typedef Particle_Vector<Geometry>   Particle_Vector_t;

  private:
    // >>> DEVICE-SIDE DATA

    Physics_t *d_physics;

    double *d_thread_keff;

  public:
    // Kcode solver should construct this with initial keff estimate
    Keff_Tally(Physics_t *physics,
               double    *thread_keff)
        : d_physics(physics)
        , d_thread_keff(thread_keff)
    {
    }

    // >>> ON-DEVICE INTERFACE

    // Track particle and do tallying.
    __device__ void accumulate(double step, int pid,
                               const Particle_Vector_t *particles);

    // End history (null-op because we're only accumulating first moments)
    __device__ void end_history(){}
};

//===========================================================================//
/*!
 * \class Keff_Tally_DMM
 * \brief Device memory manager for Keff_Tally
 */
//===========================================================================//

template <class Geometry>
class Keff_Tally_DMM : public cuda::Device_Memory_Manager<Keff_Tally<Geometry>>
{
  public:
    typedef Physics<Geometry>                   Physics_t;
    typedef cuda::Shared_Device_Ptr<Physics_t>  SDP_Physics;

    //@{
    //! Misc typedefs.
    typedef def::Vec_Dbl    Vec_Dbl;
    typedef def::size_type  size_type;
    //@}

  private:

    // >>> HOST-SIDE DATA

    SDP_Physics d_physics;

    // Current cycle
    unsigned int d_cycle;

    //! Estimate of k-effective from this cycle
    // This should only be updated from host
    double d_keff_cycle;

    //! Store individual keff estimators over all (active + inactive) cycles
    Vec_Dbl d_all_keff;

    //! Accumulated first moment of keff for calculating average
    double d_keff_sum;

    //! Accumulated second moment of keff for calculating variance
    double d_keff_sum_sq;

    //! Thread-local data for tally
    thrust::device_vector<double> d_keff_data;

  public:
    // Kcode solver should construct this with initial keff estimate
    Keff_Tally_DMM(double keff_init, SDP_Physics physics);

    // Memory manager interface
    Keff_Tally<Geometry> device_instance()
    {
        Keff_Tally<Geometry> tally(d_physics.get_device_ptr(),
                                   d_keff_data.data().get());
        return tally;
    }

    // >>> ACCESSORS

    void finalize( int Np ) {}

    //! Access all keff estimators, both active and inactive
    const Vec_Dbl& all_keff() const { return d_all_keff; }

    //! Obtain keff estimate from this cycle
    double latest() const { return d_keff_cycle; }

    // Calculate average keff over active cycles
    double mean() const;

    // Calculate variance of average keff estimate over active cycles
    double variance() const;

    //! Number of cycles since resetting
    unsigned int cycle_count() const { return d_cycle; }

    // >>> ACCESSORS FOR TESTING

    //! Obtain first moment of keff (for testing purposes)
    double keff_sum() const { return d_keff_sum; }

    //! Obtain second moment of keff (for testing purposes)
    double keff_sum_sq() const { return d_keff_sum_sq; }

    // Begin active cycles in a kcode calculation.
    void begin_active_cycles();

    // Begin a new cycle in a kcode calculation.
    void begin_cycle(size_type num_particles);

    // End a cycle in a kcode calculation.
    void end_cycle(double num_particles);

    // Clear/re-initialize all tally values between solves.
    void reset();
};

} // end namespace cuda_mc

#include "Keff_Tally.i.cuh"

#endif // cuda_mc_Keff_Tally_cuh

//---------------------------------------------------------------------------//
//                 end of Keff_Tally.cuh
//---------------------------------------------------------------------------//
