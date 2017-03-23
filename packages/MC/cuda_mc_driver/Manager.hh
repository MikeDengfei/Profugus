//----------------------------------*-C++-*----------------------------------//
/*!
 * \file   cuda_mc_driver/Manager.hh
 * \author Thomas M>. Evans
 * \date   Wed Jun 18 11:21:16 2014
 * \brief  Manager class definition.
 * \note   Copyright (C) 2014 Oak Ridge National Laboratory, UT-Battelle, LLC.
 */
//---------------------------------------------------------------------------//

#ifndef cuda_mc_driver_Manager_hh
#define cuda_mc_driver_Manager_hh

#include <sstream>
#include <string>
#include <memory>

#include "comm/P_Stream.hh"
#include "cuda_mc/Fixed_Source_Solver.hh"
#include "cuda_mc/Keff_Solver.hh"
#include "mc/Global_RNG.hh"
#include "cuda_mc/Source_Transporter.hh"
#include "Problem_Builder.hh"
#include "Manager_Base.hh"

namespace cuda_mc
{

//===========================================================================//
/*!
 * \class Manager
 * \brief Manager class that drives the MC miniapp.
 */
//===========================================================================//

template <class Geometry_DMM>
class Manager : public Manager_Base
{
  private:
    // Typedefs.
    typedef Manager_Base                               Base;
    typedef typename Geometry_DMM::Geometry_t          Geom_t;
    typedef Problem_Builder<Geometry_DMM>              Prob_Builder;
    typedef typename Base::RCP_ParameterList           RCP_ParameterList;
    typedef typename Prob_Builder::SDP_Physics         SDP_Physics;
    typedef typename Prob_Builder::SDP_Geometry        SDP_Geometry;
    typedef typename Prob_Builder::SP_Geometry_DMM     SP_Geometry_DMM;
    typedef cuda_profugus::Solver<Geom_t>              Solver_t;
    typedef std::shared_ptr<Solver_t>                  SP_Solver;
    typedef cuda_profugus::Keff_Solver<Geom_t>         Keff_Solver_t;
    typedef std::shared_ptr<Keff_Solver_t>             SP_Keff_Solver;
    typedef cuda_profugus::Fixed_Source_Solver<Geom_t> Fixed_Source_Solver_t;
    typedef std::shared_ptr<Fixed_Source_Solver_t>     SP_Fixed_Source_Solver;
    typedef typename Solver_t::Tallier_t               Tallier_t;
    typedef typename Solver_t::SP_Tallier              SP_Tallier;
    typedef cuda_profugus::Source_Transporter<Geom_t>  Transporter_t;
    typedef std::shared_ptr<Transporter_t>             SP_Transporter;
    typedef profugus::Global_RNG::RNG_Control_t        RNG_Control_t;
    typedef std::shared_ptr<RNG_Control_t>             SP_RNG_Control;
    typedef cuda_profugus::Fission_Source<Geom_t>      Fission_Source_t;
    typedef std::shared_ptr<Fission_Source_t>          SP_Fission_Source;

    // >>> DATA

    // Problem database.
    RCP_ParameterList d_db;

    // Geometry memory manager.
    SP_Geometry_DMM d_geometry_dmm;

    // Geometry.
    SDP_Geometry d_geometry;

    // Physics.
    SDP_Physics d_physics;

    // Solvers.
    SP_Solver              d_solver;
    SP_Keff_Solver         d_keff_solver;
    SP_Fixed_Source_Solver d_fixed_solver;

    // Random number controller.
    SP_RNG_Control d_rnd_control;

  public:
    // Constructor.
    Manager();

    // Setup the problem.
    void setup(RCP_ParameterList master) override;

    // Solve the problem.
    void solve() override;

    // Output.
    void output() override;

  private:
    // >>> IMPLEMENTATION

    // Processor.
    int d_node, d_nodes;

    // Problem name.
    std::string d_problem_name;

    //! Output messages in a common format.
#define SCREEN_MSG(stream)                            \
    {                                                 \
        std::ostringstream m;                         \
        m << ">>> " << stream;                        \
        profugus::pcout << m.str() << profugus::endl; \
    }

};

} // end namespace cuda_mc

#endif // cuda_mc_driver_Manager_hh

//---------------------------------------------------------------------------//
//                 end of Manager.hh
//---------------------------------------------------------------------------//
