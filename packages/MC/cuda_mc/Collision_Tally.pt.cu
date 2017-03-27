//----------------------------------*-C++-*----------------------------------//
/*!
 * \file   cuda_mc/Collision_Tally.pt.cu
 * \author Stuart Slattery
 * \brief  Collision_Tally template instantiations
 * \note   Copyright (C) 2015 Oak Ridge National Laboratory, UT-Battelle, LLC.
 */
//---------------------------------------------------------------------------//

#include "Collision_Tally.t.cuh"
#include "cuda_geometry/Mesh_Geometry.hh"
#include "cuda_rtk/RTK_Geometry.cuh"

namespace cuda_profugus
{

template class Collision_Tally<Mesh_Geometry>;
template class Collision_Tally<Core>;

} // end namespace profugus

//---------------------------------------------------------------------------//
//                 end of Collision_Tally.pt.cc
//---------------------------------------------------------------------------//
