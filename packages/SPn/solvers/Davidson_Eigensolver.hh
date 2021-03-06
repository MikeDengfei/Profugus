//----------------------------------*-C++-*----------------------------------//
/*!
 * \file   SPn/solvers/Davidson_Eigensolver.hh
 * \author Thomas M. Evans, Steven Hamilton
 * \date   Fri Feb 21 14:41:41 2014
 * \brief  Davidson_Eigensolver class definition.
 * \note   Copyright (C) 2014 Oak Ridge National Laboratory, UT-Battelle, LLC.
 */
//---------------------------------------------------------------------------//

#ifndef SPn_solvers_Davidson_Eigensolver_hh
#define SPn_solvers_Davidson_Eigensolver_hh

#include "AnasaziGeneralizedDavidsonSolMgr.hpp"
#include "Epetra_MultiVector.h"
#include "Epetra_Operator.h"

#include "EigenvalueSolver.hh"

namespace profugus
{

//===========================================================================//
/*!
 * \class Davidson_Eigensolver
 * \brief Solve k-eigenvalue problem using Generalized Davidson solver
 */
/*!
 * \example solvers/test/tstDavidson_Eigensolver.cc
 *
 * Test of Davidson_Eigensolver.
 */
//===========================================================================//

template <class T>
class Davidson_Eigensolver : public EigenvalueSolver<T>
{
  public:
    //@{
    //! Typedefs.
    typedef typename T::MV                       MV;
    typedef typename T::OP                       OP;
    typedef Teuchos::RCP<OP>                     RCP_OP;
    typedef Teuchos::RCP<Teuchos::ParameterList> RCP_ParameterList;
    typedef Anasazi::MultiVecTraits<double,MV>   MultiVecTraits;
    typedef EigenvalueSolver<T>                  Base;
    //@}

    //! Constructor
    Davidson_Eigensolver( RCP_ParameterList db,
                          RCP_OP            LHS,
                          RCP_OP            RHS );

    //! Register preconditioner with solver
    void set_preconditioner( RCP_OP prec )
    {
        REQUIRE( prec != Teuchos::null );
        d_prec = prec;
    }

    //! Perform setup operations
    void setup();

    //! Solve eigenproblem
    void solve( double           &lambda,
                Teuchos::RCP<MV>  x );

  private:

    using Base::b_tolerance;
    using Base::b_converged;
    using Base::b_num_iters;
    using Base::b_verbosity;
    using Base::b_label;
    using Base::LOW;
    using Base::MEDIUM;
    using Base::HIGH;
    using Base::DEBUG;

    // Solver database
    RCP_ParameterList d_db;

    // Operators
    RCP_OP d_LHS;
    RCP_OP d_RHS;
    RCP_OP d_prec;
};

} // end namespace profugus

#endif // SPn_solvers_Davidson_Eigensolver_hh

//---------------------------------------------------------------------------//
//                 end of Davidson_Eigensolver.hh
//---------------------------------------------------------------------------//
