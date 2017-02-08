//---------------------------------*-C++-*-----------------------------------//
/*!
 * \file   MC/cuda_mc/Source_Provider.t.hh
 * \author Steven Hamilton
 * \date   Wed Apr 13 08:38:06 2016
 * \brief  Source_Provider template method definitions.
 * \note   Copyright (c) 2016 Oak Ridge National Laboratory, UT-Battelle, LLC.
 */
//---------------------------------------------------------------------------//

#ifndef MC_cuda_mc_Source_Provider_t_hh
#define MC_cuda_mc_Source_Provider_t_hh

#include "cuda_utils/Launch_Args.t.cuh"

#include "Source_Provider.cuh"
#include "Uniform_Source.cuh"
#include "Fission_Source.cuh"

namespace cuda_mc
{

//---------------------------------------------------------------------------//
// Functor to populate vector with particles from source
//---------------------------------------------------------------------------//
template <class Geometry, class Src_Type>
class Compute_Source
{
  public:

    typedef cuda_mc::RNG_State_t     RNG_State;
    typedef Particle<Geometry>       Particle_t;
    typedef def::size_type           size_type;

    Compute_Source( const Src_Type  source,
                    RNG_State      *rngs,
                    Particle_t     *particles,
                    const int      *indices,
                    size_type       num_particles)
        : d_source(source)
        , d_rngs(rngs)
        , d_particles(particles)
        , d_indices(indices)
        , d_num_particles(num_particles)
    {
    }

    __device__ void operator()( std::size_t tid ) const
    {
        DEVICE_REQUIRE(d_indices[tid] < d_num_particles);
        d_particles[d_indices[tid]] =
            d_source.get_particle(tid,&d_rngs[tid]);
        DEVICE_ENSURE( d_particles[tid].alive() );
    }

  private:

    const Src_Type  d_source;
    RNG_State      *d_rngs;
    Particle_t     *d_particles;
    const int      *d_indices;
    size_type       d_num_particles;
};
    

//---------------------------------------------------------------------------//
// Get starting particles from source
//---------------------------------------------------------------------------//
template <class Geometry>
void Source_Provider<Geometry>::get_particles(
    SP_Source source, SP_RNG_Control rng_control, 
    Particle_Vector &particles, const Index_Vector &indices) const
{
    // Get particle count and set up RNG, particles, source batching
    size_type Np = std::min(source->num_left(),indices.size());
    rng_control->initialize(Np);
    particles.resize(Np);
    source->begin_batch(Np);

    // Determine type of source
    typedef Uniform_Source_DMM<Geometry> Uni_Source_DMM;
    typedef Fission_Source_DMM<Geometry> Fisn_Source_DMM;
    std::shared_ptr<Uni_Source_DMM> uni_source_dmm;
    std::shared_ptr<Fisn_Source_DMM> fisn_source_dmm;
    uni_source_dmm  = std::dynamic_pointer_cast<Uni_Source_DMM>(source);
    fisn_source_dmm = std::dynamic_pointer_cast<Fisn_Source_DMM>(source);

    // Call to implementation for appropriate source type
    if( uni_source_dmm )
    {
        REQUIRE( !fisn_source_dmm );

        auto uni_source = uni_source_dmm->device_instance();

        get_particles_impl(uni_source,rng_control,particles,indices,Np);
    }
    else if( fisn_source_dmm )
    {
        REQUIRE( !uni_source_dmm );

        auto fisn_source = fisn_source_dmm->device_instance();

        get_particles_impl(fisn_source,rng_control,particles,indices,Np);
    }
    else
    {
        VALIDATE(false,"Unknown source type.");
    }

    // Update remaining particles in source
    source->end_batch(Np);
}

//---------------------------------------------------------------------------//
// Geometry-templated implementation
//---------------------------------------------------------------------------//
template <class Geometry>
template <class Src_Type>
void Source_Provider<Geometry>::get_particles_impl(
        Src_Type                   &source,
        SP_RNG_Control              rng_control,
        Particle_Vector             &particles,
        const Index_Vector          &indices,
        size_type                    Np) const
{
    // Build functor to populate vector
    auto &rngs = rng_control->get_states();
    Compute_Source<Geometry,Src_Type> f( source,
                                         rngs.data().get(),
                                         particles.data().get(),
                                         indices.data().get(),
                                         Np);

    // Launch kernel
    cuda::Launch_Args<cuda::arch::Device> launch_args;
    launch_args.set_num_elements(Np);

    cuda::parallel_launch( f, launch_args );

    cudaDeviceSynchronize();
}

//---------------------------------------------------------------------------//
} // end namespace cuda_mc

#endif // MC_cuda_mc_Source_Provider_t_hh

//---------------------------------------------------------------------------//
// end of MC/cuda_mc/Source_Provider.t.hh
//---------------------------------------------------------------------------//