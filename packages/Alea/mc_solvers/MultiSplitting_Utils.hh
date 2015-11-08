//----------------------------------*-C++-*----------------------------------//
/*!
 * \file   MultiSplitting_Utils.hh
 * \author Massimiliano Lupo Pasini
 * \brief  Objects type useful for the MultiSplitting techniques
 */
//---------------------------------------------------------------------------//

#ifndef mc_solver_MultiSplitting_Utils_hh
#define mc_solver_MultiSplitting_Utils_hh

#include "Teuchos_RCP.hpp"

namespace alea
{

struct splitting
{
    Teuchos::RCP<CRS_MATRIX> A;
    Teuchos::RCP<MV> b; 
    Teuchos::RCP<MV> E; 
};


}
#endif // mc_solver_MultiSplitting_Utils.hh
