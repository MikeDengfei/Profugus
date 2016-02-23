//----------------------------------*-C++-*----------------------------------//
/*!
 * \file   cuda_mc/Physics.pt.cu
 * \author Steven Hamilton
 * \date   Thu Nov 05 11:14:30 2015
 * \brief  Physics template instantiations
 * \note   Copyright (C) 2015 Oak Ridge National Laboratory, UT-Battelle, LLC.
 */
//---------------------------------------------------------------------------//

#include "Physics.t.hh"
#include "cuda_geometry/Mesh_Geometry.hh"

namespace cuda_mc
{

template class Physics<cuda_profugus::Mesh_Geometry>;

} // end namespace cuda_mc

//---------------------------------------------------------------------------//
//                 end of Physics.pt.cu
//---------------------------------------------------------------------------//