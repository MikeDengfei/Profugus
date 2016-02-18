//----------------------------------*-C++-*----------------------------------//
/*!
 * \file   cuda_mc/Physics.pt.cu
 * \author Stuart Slattery
 * \brief  Physics template instantiations
 * \note   Copyright (C) 2015 Oak Ridge National Laboratory, UT-Battelle, LLC.
 */
//---------------------------------------------------------------------------//

#include "Physics.t.cuh"
#include "cuda_geometry/Mesh_Geometry.hh"

namespace cuda_profugus
{

template class Physics<Mesh_Geometry>;

} // end namespace profugus

//---------------------------------------------------------------------------//
//                 end of Physics.pt.cc
//---------------------------------------------------------------------------//
