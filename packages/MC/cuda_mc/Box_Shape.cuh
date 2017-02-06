//----------------------------------*-C++-*----------------------------------//
/*!
 * \file   cuda_mc/Box_Shape.cuh
 * \author Steven Hamilton
 * \date   Tuesday May 6 16:40:41 2014
 * \brief  Box_Shape class definition.
 * \note   Copyright (C) 2014 Oak Ridge National Laboratory, UT-Battelle, LLC.
 */
//---------------------------------------------------------------------------//

#ifndef cuda_mc_Box_Shape_cuh
#define cuda_mc_Box_Shape_cuh

#include <curand_kernel.h>

#include "utils/Definitions.hh"
#include "Definitions.hh"
#include "cuda_utils/Definitions.hh"
#include "cuda_utils/CudaDBC.hh"

namespace cuda_mc
{

//===========================================================================//
/*!
 * \class Box_Shape
 * \brief Box shape for MC geometric sampling.
 *
 * Does uniform sampling in an orthogonal box.  The sampling formulas for each
 * side of the box is:
 * \f[
   x = \Delta_{x}\xi_{1} + x_{o}
 * \f]
 * \f[
   y = \Delta_{y}\xi_{2} + y_{o}
 * \f]
 * \f[
   z = \Delta_{z}\xi_{3} + z_{o}
 * \f]
 */
//===========================================================================//

class Box_Shape
{
  public:
    //@{
    //! Base-class typedefs.
    typedef cuda_utils::Space_Vector Space_Vector;
    //@}

  private:
    // >>> DATA

    // Low corner of box.
    double d_lox, d_loy, d_loz;

    // Widths of box in each direction.
    double d_Dx, d_Dy, d_Dz;

  public:
    // Constructor.
    Box_Shape(double lox, double hix, double loy,
              double hiy, double loz, double hiz);

    // >>> ACCESSORS
    //! Return the low corner of the box.
    __device__ Space_Vector low_corner() const
    {
        return {d_lox, d_loy, d_loz};
    }

    //! Return the high corner of the box.
    __device__ inline Space_Vector high_corner() const
    {
        return {d_lox + d_Dx, d_loy + d_Dy, d_loz + d_Dz};
    }

    // >>> DERIVED INTERFACE
    //! Sample a point in the shape.
    __device__ Space_Vector sample(RNG_State_t *rng)
    {
        Space_Vector point =
           { d_Dx * curand_uniform_double(rng) + d_lox,
             d_Dy * curand_uniform_double(rng) + d_loy,
             d_Dz * curand_uniform_double(rng) + d_loz };
        DEVICE_ENSURE(is_point_inside(point));
        return point;
    }

    //! Return the volume.
    __device__ double volume() const { return d_Dx * d_Dy * d_Dz; }

    // Whether a point is on or inside this shape
    __device__ bool is_point_inside(const Space_Vector& x) const
    {
        using def::I; using def::J; using def::K;
        return (x[I] >= d_lox && x[I] <= d_lox + d_Dx) &&
               (x[J] >= d_loy && x[J] <= d_loy + d_Dy) &&
               (x[K] >= d_loz && x[K] <= d_loz + d_Dz);
    }

    // Get the bounding box
    __device__ void get_bbox( Space_Vector& low_corner,
                              Space_Vector& high_corner) const
    {
        using def::I; using def::J; using def::K;
        low_corner[I]  = d_lox;
        low_corner[J]  = d_loy;
        low_corner[K]  = d_loz;
        high_corner[I] = d_lox + d_Dx;
        high_corner[J] = d_loy + d_Dy;
        high_corner[K] = d_loz + d_Dz;
    }
    
};

} // end namespace cuda_mc

#endif // cuda_mc_Box_Shape_cuh

//---------------------------------------------------------------------------//
//                        end of cuda_mc/Box_Shape.cuh
//---------------------------------------------------------------------------//
