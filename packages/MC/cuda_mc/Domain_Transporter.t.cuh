//----------------------------------*-C++-*----------------------------------//
/*!
 * \file   cuda_mc/Domain_Transporter.t.hh
 * \author Stuart Slattery
 * \date   Mon May 12 12:02:13 2014
 * \brief  Domain_Transporter template member definitions.
 * \note   Copyright (C) 2014 Oak Ridge National Laboratory, UT-Battelle, LLC.
 */
//---------------------------------------------------------------------------//

#ifndef cuda_mc_Domain_Transporter_t_cuh
#define cuda_mc_Domain_Transporter_t_cuh

#include <cmath>

#include "utils/Constants.hh"
#include "comm/Timing.hh"
#include "cuda_utils/CudaDBC.hh"
#include "geometry/Definitions.hh"
#include "cuda_utils/Hardware.hh"
#include "Definitions.hh"
#include "Domain_Transporter.hh"

namespace cuda_profugus
{
//---------------------------------------------------------------------------//
// GLOBAL CUDA KERNELS
//---------------------------------------------------------------------------//
// Transport a particle one step.
template<class Geometry>
__global__ void take_step_kernel( const Geometry* geometry,
				  const Physics<Geometry>* physics,
				  const int num_particles,
				  Particle_Vector<Geometry>* particles )
{
    // Get the thread index.
    int idx = threadIdx.x + blockIdx.x * blockDim.x;
    int start_idx = particles->event_lower_bound( events::TAKE_STEP );

    if ( idx < num_particles )
    {
	// Get the particle index.
	int pidx = start_idx + idx;

	// Get the total cross section.
	double xs_tot = physics->total( physics::TOTAL,
					particles->matid(pidx),
					particles->group(pidx) );

	// Sample the distance to the next collision.
	double dist_col = (xs_tot > 0.0) 
			  ? particles->dist_mfp( pidx ) / xs_tot
			  : profugus::constants::huge;

	// Calculate distance to next geometry boundary
	double dist_bnd = 
            geometry->distance_to_boundary( particles->geo_state(pidx) );

        // Calculate the next step and event.
        events::Event event = (dist_bnd < dist_col) 
                              ? events::BOUNDARY : events::COLLISION;
        double step = (dist_bnd < dist_col) ? dist_bnd : dist_col;

	// Set the next event in the particle.
	particles->set_event( pidx, event );
	particles->set_step( pidx, step );

	// Update the mfp distance.
	particles->set_dist_mfp( 
	    pidx, particles->dist_mfp(pidx) - step * xs_tot );
    }
}				  

//---------------------------------------------------------------------------//
// Process a boundary.
template<class Geometry>
__global__ void process_boundary_kernel( const Geometry* geometry,
					 const int num_particles,
					 Particle_Vector<Geometry>* particles )
{
    // Get the thread index.
    int idx = threadIdx.x + blockIdx.x * blockDim.x;
    int start_idx = particles->event_lower_bound( events::BOUNDARY );

    if ( idx < num_particles )
    {
	// Get the particle index.
	int pidx = start_idx + idx;

	// move the particle to the surface.
	geometry->move_to_surface( particles->geo_state(pidx) );

	// get the in/out state of the particle
	auto state = geometry->boundary_state( particles->geo_state(pidx) );

	// process the boundary crossing
	switch( state )
	{
	    case profugus::geometry::OUTSIDE:

		// the particle has left the problem geometry. set the event
		// to escape and kill
		particles->kill( pidx );
		break;

	    case profugus::geometry::REFLECT:

		// the particle has hit a reflecting surface. the particle is
		// still alive and the boundary does not change
		geometry->reflect( particles->geo_state(pidx) );
		break;

	    case profugus::geometry::INSIDE:

		// otherwise the particle is at an internal geometry boundary;
		// update the material id of the region the particle has
		// entered and set the event to post-surface for variance
		// reduction. For now we have no post-surface VR so just take
		// the next step.
		particles->set_matid( 
		    pidx, geometry->matid(particles->geo_state(pidx)) );
                break;

	    default:
		CHECK(0);
	}
    }
}				  

//---------------------------------------------------------------------------//
// Move particles to the collision site.
template<class Geometry>
__global__ void move_to_collision_kernel( const Geometry* geometry,
					  const int num_particles,
					  Particle_Vector<Geometry>* particles )
{
    // Get the thread index.
    int idx = threadIdx.x + blockIdx.x * blockDim.x;
    int start_idx = particles->event_lower_bound( events::COLLISION );

    if ( idx < num_particles )
    {
	// Get the particle index.
	int pidx = start_idx + idx;

	// move the particle to the collision site
	geometry->move_to_point( particles->step(pidx), 
				 particles->geo_state(pidx) );

        // Reset distance to next collision
        particles->set_dist_mfp( pidx, -std::log(particles->ran(pidx)) );
    }
}				  

//---------------------------------------------------------------------------//
// Set surviving particles to take another step.
template<class Geometry>
__global__ void set_next_step_kernel(const events::Event event,
                                     const int num_particles,
                                     Particle_Vector<Geometry>* particles )
{
    // Get the thread index.
    int idx = threadIdx.x + blockIdx.x * blockDim.x;
    int start_idx = particles->event_lower_bound( event );

    if ( idx < num_particles )
    {
	// Get the particle index.
	int pidx = start_idx + idx;

        // Set survivors to take another step.
        if ( particles->alive(pidx) )
        {
            particles->set_event( pidx, events::TAKE_STEP );
        }
        // Otherwise they are dead.
        else
        {
            particles->set_event( pidx, events::DEAD );
        }
        
    }
}				  

//---------------------------------------------------------------------------//
// CONSTRUCTOR
//---------------------------------------------------------------------------//
/*!
 * \brief Constructor.
 */
template <class Geometry>
Domain_Transporter<Geometry>::Domain_Transporter()
    : d_sample_fission_sites(false)
    , d_keff(0.0)
{ /* ... */ }

//---------------------------------------------------------------------------//
// PUBLIC FUNCTIONS
//---------------------------------------------------------------------------//
/*!
 * \brief Set the geometry and physics classes.
 *
 * \param geometry
 * \param physics
 */
template <class Geometry>
void Domain_Transporter<Geometry>::set(const SDP_Geometry& geometry,
                                       const SDP_Physics&  physics)
{
    REQUIRE(geometry);
    REQUIRE(physics);

    d_geometry = geometry;
    d_physics  = physics;

    if (d_var_reduction)
    {
        d_var_reduction->set(d_geometry);
        d_var_reduction->set(d_physics);
    }
}

//---------------------------------------------------------------------------//
/*!
 * \brief Set the variance reduction.
 *
 * \param reduction
 */
template <class Geometry>
void Domain_Transporter<Geometry>::set(const SP_Variance_Reduction& reduction)
{
    REQUIRE(reduction);
    d_var_reduction = reduction;

    if (d_geometry)
        d_var_reduction->set(d_geometry);
    if (d_physics)
        d_var_reduction->set(d_physics);
}

//---------------------------------------------------------------------------//
/*!
 * \brief Set regular tallies.
 *
 * \param tallies
 */
template <class Geometry>
void Domain_Transporter<Geometry>::set(const SP_Tallier& tallies)
{
    REQUIRE(tallies);
    d_tallier = tallies;
}

//---------------------------------------------------------------------------//
/*!
 * \brief Set fission site sampling.
 *
 * \param fission_sites
 * \param keff
 */
template <class Geometry>
void Domain_Transporter<Geometry>::set(const SP_Fission_Sites& fission_sites,
                                       double keff)
{
    // assign the container
    d_fission_sites = fission_sites;

    // initialize the sampling flag
    d_sample_fission_sites = (nullptr != d_fission_sites);

    // assign current iterate of keff
    d_keff = keff;
}

//---------------------------------------------------------------------------//
/*!
 * \brief Transport a particle one step through the domain to either a
 * collision or a boundary.
 */
template <class Geometry>
void Domain_Transporter<Geometry>::transport_step(
    SDP_Particle_Vector &particles,
    SDP_Bank &bank)
{
    REQUIRE(d_geometry);
    REQUIRE(d_physics);

    SCOPED_TIMER("CUDA_MC::Domain_Transporter::transport_step");

    // get the particles that will take a step
    int num_particle =
        particles.get_host_ptr()->get_event_size( events::TAKE_STEP );
    
    // get CUDA launch parameters
    REQUIRE( cuda_utils::Hardware<cuda_utils::arch::Device>::have_acquired() );
    unsigned int threads_per_block = 
        cuda_utils::Hardware<cuda_utils::arch::Device>::default_block_size();
    unsigned int num_blocks = num_particle / threads_per_block;
    if ( num_particle % threads_per_block > 0 ) ++num_blocks;

    // move the particles a step
    take_step_kernel<<<num_blocks,threads_per_block,0,d_take_step_stream.handle()>>>(
        d_geometry.get_device_ptr(),
        d_physics.get_device_ptr(),
        num_particle,
        particles.get_device_ptr() );

    cudaStreamSynchronize(d_take_step_stream.handle());
}

//---------------------------------------------------------------------------//
/*!
 * \brief Post-process a tranpsort step
 */
template <class Geometry>
void Domain_Transporter<Geometry>::process_step(
    SDP_Particle_Vector &particles,
    SDP_Bank &bank)
{
    REQUIRE(d_tallier);

    SCOPED_TIMER("CUDA_MC::Domain_Transporter::process_step");

    // Do pathlength tallies. This call blocks on this thread so we tally
    // before moving on to boundaries and collisions.
    d_tallier->path_length( particles );

    // Process collisions
    process_collision( particles, bank );

    // Process boundaries
    process_boundary( particles, bank );

    cudaStreamSynchronize(d_collision_stream.handle());
    cudaStreamSynchronize(d_boundary_stream.handle());
}

//---------------------------------------------------------------------------//
/*
 * \brief Process particles that have hit a boundary.
 */
template <class Geometry>
void Domain_Transporter<Geometry>::process_boundary(
    SDP_Particle_Vector &particles,
    SDP_Bank     &bank)
{
    // get the particles that have hit a boundary
    int num_particle =
        particles.get_host_ptr()->get_event_size( events::BOUNDARY );
    
    // get CUDA launch parameters
    REQUIRE( cuda_utils::Hardware<cuda_utils::arch::Device>::have_acquired() );
    unsigned int threads_per_block = 
	cuda_utils::Hardware<cuda_utils::arch::Device>::default_block_size();
    unsigned int num_blocks = num_particle / threads_per_block;
    if ( num_particle % threads_per_block > 0 ) ++num_blocks;

    // process the boundary
    process_boundary_kernel<<<num_blocks,threads_per_block,0,d_boundary_stream.handle()>>>(
	d_geometry.get_device_ptr(),
	num_particle,
	particles.get_device_ptr() );

    // take any surviving particles and set them to take another step    
    set_next_step_kernel<<<num_blocks,threads_per_block,0,d_boundary_stream.handle()>>>(
        events::BOUNDARY,
	num_particle,
	particles.get_device_ptr() );
}

//---------------------------------------------------------------------------//
/*
 * \brief Process particles that have had a collision.
 */
template <class Geometry>
void Domain_Transporter<Geometry>::process_collision(
    SDP_Particle_Vector &particles,
    SDP_Bank     &bank)
{
    REQUIRE( d_physics );
    REQUIRE( d_geometry );
    REQUIRE( d_var_reduction );

    // get the particles that will have a collision
    int num_particle =
        particles.get_host_ptr()->get_event_size( events::COLLISION );
    
    // get CUDA launch parameters
    REQUIRE( cuda_utils::Hardware<cuda_utils::arch::Device>::have_acquired() );
    unsigned int threads_per_block = 
	cuda_utils::Hardware<cuda_utils::arch::Device>::default_block_size();
    unsigned int num_blocks = num_particle / threads_per_block;
    if ( num_particle % threads_per_block > 0 ) ++num_blocks;

    // Move particles to the collision site
    move_to_collision_kernel<<<num_blocks,threads_per_block,0,d_collision_stream.handle()>>>(
	d_geometry.get_device_ptr(),
	num_particle,
	particles.get_device_ptr() );

    // sample fission sites
    if (d_sample_fission_sites)
    {
        CHECK(d_fission_sites);
        CHECK(d_keff > 0.0);
        d_physics.get_host_ptr()->sample_fission_site(
            particles, *d_fission_sites, d_keff, d_collision_stream );
    }

    // process the collision
    d_physics.get_host_ptr()->collide(particles, d_collision_stream );

    // apply weight windows
    d_var_reduction->post_collision(particles, bank, d_collision_stream );

    // take any surviving particles and set them to take another step    
    set_next_step_kernel<<<num_blocks,threads_per_block,0,d_collision_stream.handle()>>>(
        events::COLLISION,
	num_particle,
	particles.get_device_ptr() );
}

//---------------------------------------------------------------------------//

} // end namespace cuda_profugus

#endif // cuda_mc_Domain_Transporter_t_cuh

//---------------------------------------------------------------------------//
//                 end of Domain_Transporter.t.hh
//---------------------------------------------------------------------------//
