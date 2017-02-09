//----------------------------------*-C++-*----------------------------------//
/*!
 * \file   cuda_mc/Source.pt.cu
 * \author Steven Hamilton
 * \date   Thu Nov 05 11:14:30 2015
 * \brief  Source template instantiations
 * \note   Copyright (C) 2015 Oak Ridge National Laboratory, UT-Battelle, LLC.
 */
//---------------------------------------------------------------------------//

#include "Source.t.cuh"
#include "cuda_geometry/Mesh_Geometry.hh"
#include "cuda_rtk/RTK_Geometry.cuh"

namespace cuda_mc
{

template class Source<cuda_profugus::Mesh_Geometry>;
template class Source<cuda_profugus::Core>;

} // end namespace cuda_mc

//---------------------------------------------------------------------------//
//                 end of Source.pt.cu
//---------------------------------------------------------------------------//
