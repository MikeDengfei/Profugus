//----------------------------------*-C++-*----------------------------------//
/*!
 * \file   MC/mc/Source.hh
 * \author Thomas M. Evans
 * \date   Mon May 05 14:22:41 2014
 * \brief  Source class definition.
 * \note   Copyright (C) 2014 Oak Ridge National Laboratory, UT-Battelle, LLC.
 */
//---------------------------------------------------------------------------//

#ifndef MC_mc_Source_hh
#define MC_mc_Source_hh

#include <memory>
#include <cmath>

#include "utils/Definitions.hh"
#include "utils/Constants.hh"
#include "rng/RNG_Control.hh"
#include "Physics.hh"

namespace profugus
{

//===========================================================================//
/*!
 * \class Source
 * \brief Base class definition for Monte Carlo sources.
 */
//===========================================================================//

template <class Geometry>
class Source
{
  public:
    //@{
    //! Useful typedefs.
    typedef Geometry                            Geometry_t;
    typedef typename Geometry_t::Geo_State_t    Geo_State_t;
    typedef Physics<Geometry>                   Physics_t;
    typedef typename Physics_t::Particle_t      Particle_t;
    typedef typename Geometry_t::Space_Vector   Space_Vector;
    typedef RNG_Control                         RNG_Control_t;
    typedef RNG_Control_t::RNG_t                RNG_t;
    typedef def::size_type                      size_type;
    //@}

    //@{
    //! Smart pointers
    typedef std::shared_ptr<Geometry_t>    SP_Geometry;
    typedef std::shared_ptr<Physics_t>     SP_Physics;
    typedef std::shared_ptr<Particle_t>    SP_Particle;
    typedef std::shared_ptr<RNG_Control_t> SP_RNG_Control;
    //@}

  protected:
    // >>> DATA

    // Geometry and physics.
    SP_Geometry b_geometry;
    SP_Physics  b_physics;

    // Random number controller.
    SP_RNG_Control b_rng_control;

    // Sample isotropic angle.
    void sample_angle(Space_Vector &omega, RNG_t rng)
    {
        using def::X; using def::Y; using def::Z;

        omega[Z]        = 1.0 - 2.0 * rng.ran();
        double phi      = constants::two_pi * rng.ran();
        double sintheta = std::sqrt(1.0 - omega[Z] * omega[Z]);

        omega[X] = sintheta * std::cos(phi);
        omega[Y] = sintheta * std::sin(phi);
    }

    // Calculate random number offsets.
    void make_RNG();

    // Node ids.
    int b_node, b_nodes;

  public:
    // Constructor.
    Source(SP_Geometry    geometry,
           SP_Physics     physics,
           SP_RNG_Control rng_control);

    //! Virtual destructor.
    virtual ~Source() = 0;

    // >>> VIRTUAL PUBLIC INTERFACE

    //! Get a particle from the source.
    virtual SP_Particle get_particle() = 0;

    //! Whether the source has finished emitting all its particles.
    virtual bool empty() const = 0;

    //! Number of particles to transport in the source on the current domain.
    virtual size_type num_to_transport() const = 0;

    //! Total number of particles to transport in the entire problem/cycle.
    virtual size_type total_num_to_transport() const = 0;

    // >>> INHERITED INTERFACE

    //! Get the geometry.
    SP_Geometry geometry() const { return b_geometry; }

    //! Get the physics.
    SP_Physics physics() const { return b_physics; }

    //! Get the RNG controller.
    const RNG_Control_t& rng_control() const { return *b_rng_control; }

    //! Number of random number streams generated so far (inclusive).
    int num_streams() const { return d_rng_stream; }

  private:
    // >>> DATA

    // Offsets used for random number generator selection.
    int d_rng_stream;
};

} // end namespace profugus

#endif // MC_mc_Source_hh

//---------------------------------------------------------------------------//
//                 end of Source.hh
//---------------------------------------------------------------------------//
