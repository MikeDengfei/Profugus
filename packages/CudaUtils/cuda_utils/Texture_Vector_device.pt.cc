//----------------------------------*-C++-*----------------------------------//
/*!
 * \file   CudaUtils/cuda_utils/Texture_Vector_device.pt.cc
 * \author Seth R Johnson
 * \date   Fri Sep 20 10:08:43 2013
 * \brief  Texture_Vector member definitions.
 * \note   Copyright (C) 2013 Oak Ridge National Laboratory, UT-Battelle, LLC.
 */
//---------------------------------------------------------------------------//

#include "Texture_Vector_device.t.hh"

namespace cuda
{

typedef arch::Device Arch_t;

template class Texture_Vector<Arch_t,float>;
template class Texture_Vector<Arch_t,double>;
template class Texture_Vector<Arch_t,int>;

} // end namespace cuda

//---------------------------------------------------------------------------//
//                 end of Texture_Vector_device.pt.cc
//---------------------------------------------------------------------------//
