//----------------------------------*-C++-*----------------------------------//
/*!
 * \file   cuda_mc/Solver.hh
 * \author Steven Hamilton
 * \date   Tue May 13 14:39:00 2014
 * \brief  Solver class definition.
 * \note   Copyright (C) 2014 Oak Ridge National Laboratory, UT-Battelle, LLC.
 */
//---------------------------------------------------------------------------//

#ifndef cuda_mc_Solver_hh
#define cuda_mc_Solver_hh

#include <memory>

#include "cuda_utils/Shared_Device_Ptr.hh"

namespace cuda_mc
{

// Forward declare Tallier
template <class Geom> class Tallier_DMM;

//===========================================================================//
/*!
 * \class Solver
 * \brief Base class for Monte Carlo top-level solvers.
 */
//===========================================================================//

template <class Geometry>
class Solver
{
  public:
    //@{
    //! Typedefs.
    typedef Geometry                            Geometry_t;
    typedef Tallier_DMM<Geometry_t>             Tallier_DMM_t;
    typedef std::shared_ptr<Tallier_DMM_t>      SP_Tallier_DMM;
    //@}

  protected:

    // >>> DATA

    // Tally contoller.
    SP_Tallier_DMM b_tallier;

  public:

    // Virtual destructor for polymorphism.
    virtual ~Solver(){}

    //! Solve the problem.
    virtual void solve() = 0;

    //! Call to reset the solver and tallies for another calculation.
    virtual void reset() = 0;

    //! Get tallies.
    SP_Tallier_DMM tallier() const { return b_tallier; }
};

} // end namespace cuda_mc

#endif // cuda_mc_Solver_hh

//---------------------------------------------------------------------------//
//                 end of Solver.hh
//---------------------------------------------------------------------------//
