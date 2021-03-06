//----------------------------------*-C++-*----------------------------------//
/*!
 * \file   CudaUtils/test/Launch_Args_Kernel.hh
 * \author Stuart Slattery
 * \date   Tue Nov 24 14:09:29 2015
 * \brief
 * \note   Copyright (C) 2013 Oak Ridge National Laboratory, UT-Battelle, LLC.
 */
//---------------------------------------------------------------------------//

#ifndef CudaUtils_test_Launch_Args_Kernel_hh
#define CudaUtils_test_Launch_Args_Kernel_hh

#include "../cuda_utils/Device_Vector.hh"
#include "../cuda_utils/Host_Vector.hh"

//---------------------------------------------------------------------------//
// Launch_Args test functor.
template<typename Arch_T>
class Functor
{
  public:
    typedef cuda::Device_Vector<Arch_T,double> Device_Vector_t;
    typedef cuda::Host_Vector<double>          Host_Vector_t;

    Functor( const int data_size, const double value )
	: d_device_vec( data_size )
	, d_device_data( d_device_vec.data() )
    {
        Host_Vector_t host_vec(data_size,value);
        d_device_vec.assign( host_vec );
    }

    __host__ __device__ void operator()( const std::size_t idx )
    {
        d_device_data[idx] += static_cast<double>(idx);
    }

    void assign_data(Host_Vector_t &host_vec)
    {
        d_device_vec.to_host( host_vec );
    }

  private:
    Device_Vector_t d_device_vec;
    double* d_device_data;
};

#endif // CudaUtils_test_Launch_Args_Kernel_hh

//---------------------------------------------------------------------------//
//                        end of Launch_Args_Kernel.hh
//---------------------------------------------------------------------------//
