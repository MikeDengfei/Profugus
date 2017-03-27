//----------------------------------*-C++-*----------------------------------//
/*!
 * \file   cuda_mc/Particle_Vector.pt.cu
 * \author Stuart Slattery
 * \brief  Particle_Vector template instantiations
 * \note   Copyright (C) 2015 Oak Ridge National Laboratory, UT-Battelle, LLC.
 */
//---------------------------------------------------------------------------//

#include "Particle_Vector.t.cuh"
#include "cuda_geometry/Mesh_Geometry.hh"
#include "cuda_rtk/RTK_Geometry.cuh"

namespace cuda_profugus
{

template class Particle_Vector<Mesh_Geometry>;
template class Particle_Vector<Core>;

} // end namespace profugus

//---------------------------------------------------------------------------//
//                 end of Particle_Vector.pt.cc
//---------------------------------------------------------------------------//
