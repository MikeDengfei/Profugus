//----------------------------------*-C++-*----------------------------------//
/*!
 * \file   cuda_geometry/Cartesian_Mesh.hh
 * \author Thomas M. Evans
 * \date   Mon Jul 21 16:55:00 2014
 * \brief  Cartesian_Mesh class definition.
 * \note   Copyright (C) 2014 Oak Ridge National Laboratory, UT-Battelle, LLC.
 */
//---------------------------------------------------------------------------//

#ifndef cuda_geometry_Cartesian_Mesh_hh
#define cuda_geometry_Cartesian_Mesh_hh

#include <math_constants.h>

#include <vector>
#include <thrust/device_vector.h>

#include "cuda_utils/CudaDBC.hh"
#include "cuda_utils/Definitions.hh"
#include "cuda_utils/Utility_Functions.hh"
#include "geometry/Definitions.hh"
#include "utils/Definitions.hh"

namespace cuda_profugus
{

//===========================================================================//
/*!
 * \class Cartesian_Mesh
 * \brief Common functionality for Cartesian meshes.
 *
 * Provides mesh-based functionality.
 */
/*!
 * \example geometry/test/tstCartesian_Mesh.cc
 *
 * Test of Cartesian_Mesh.
 */
//===========================================================================//

class Cartesian_Mesh
{
  public:
    //@{
    //! Mesh typedefs
    typedef int                           dim_type;
    typedef size_t                        size_type;
    typedef profugus::geometry::cell_type cell_type;
    typedef cuda_utils::Space_Vector      Space_Vector;
    typedef cuda_utils::Coordinates       Coordinates;
    typedef std::vector<double>           Vec_Dbl;
    //@}

  private:
    // >>> DATA

    // Cell edges.
    thrust::device_vector<double> d_x_edges_vec;
    thrust::device_vector<double> d_y_edges_vec;
    thrust::device_vector<double> d_z_edges_vec;

    // On-device pointers
    double *dd_x_edges;
    double *dd_y_edges;
    double *dd_z_edges;

    // Number of cells along each dimension
    int d_cells_x;
    int d_cells_y;
    int d_cells_z;

    // Total number of cells
    cell_type d_num_cells;

    // Dimensionality (always 3 for now)
    dim_type d_dimension;

    // Cell volumes
    thrust::device_vector<double> d_volumes_vec;

    // On-device pointer
    double *dd_volumes;

  public:

    // Construct from xyz edges.
    Cartesian_Mesh(const Vec_Dbl& x_edges, const Vec_Dbl& y_edges,
                   const Vec_Dbl& z_edges);

    // >>> ACCESSORS

    //! Get number of cells.
    __host__ __device__ cell_type num_cells() const { return d_num_cells; }

    //! Number of cells along an axis
    __host__ __device__ dim_type num_cells_along(dim_type d) const
    {
        DEVICE_REQUIRE( d>=0 && d<=3 );
        if( d == def::I )
            return d_cells_x;
        else if( d == def::J )
            return d_cells_y;
        else if( d == def::K )
            return d_cells_z;
        return -1;
    }

    //! Dimension of mesh.
    __host__ __device__ dim_type dimension() const { return d_dimension; }

    //! Return cell edges along a given direction.
    __device__ const double * edges(dim_type d) const
    {
        DEVICE_REQUIRE( d>=0 && d<=3 );
        if( d == def::I )
            return dd_x_edges;
        else if( d == def::J )
            return dd_y_edges;
        else if( d == def::K )
            return dd_z_edges;
        return 0;
    }

    // >>> INDEX CONVERSION

    // Convert cardinal index to (i,j) or (i,j,k).
    __host__ __device__ void cardinal(
        cell_type cell, dim_type& i, dim_type& j, dim_type& k) const
    {
        DEVICE_REQUIRE( cell < d_num_cells );
        k = cell / (d_cells_x * d_cells_y);
        DEVICE_ENSURE( k < d_cells_z );
        cell = cell % (d_cells_x * d_cells_y);
        j = cell / d_cells_x;
        DEVICE_ENSURE( j < d_cells_y );
        i = cell % d_cells_x;
        DEVICE_ENSURE( i < d_cells_x );
    }

    // Convert (i,j,k) to cell index
    __host__ __device__ inline bool index(dim_type   i,
                                          dim_type   j,
                                          dim_type   k,
                                          cell_type &cell) const
    {
        DEVICE_REQUIRE( i < d_cells_x );
        DEVICE_REQUIRE( j < d_cells_y );
        DEVICE_REQUIRE( k < d_cells_z );
        if( i < d_cells_x && j < d_cells_y && k < d_cells_z )
        {
            cell = i + d_cells_x * (j + d_cells_y * k);
            DEVICE_ENSURE( cell < d_num_cells );
            return true;
        }
        cell = static_cast<cell_type>(-1);
        return false;
    }

    // >>> VOLUME CALCULATION

    //! Get all volumes on host
    std::vector<double> volumes() const
    {
        DEVICE_REQUIRE( d_num_cells > 0 );
        std::vector<double> host_volumes(d_num_cells);
        cudaMemcpy( &host_volumes[0], dd_volumes, d_num_cells*sizeof(double),
                    cudaMemcpyDeviceToHost );
        return host_volumes;
    }

    //! Calculate volume from the global cell id
    __device__ inline double volume(cell_type global_cell) const
    {
        DEVICE_REQUIRE( global_cell < d_num_cells );
        return dd_volumes[global_cell];
    }

    // >>> SPATIAL LOCATION

    // Locate the positon's ijk coordinates with upper edges begin "inside"
    __device__ void find_upper(const Space_Vector &r, Coordinates &ijk ) const
    {
        using def::I; using def::J; using def::K;
        for (int dim : {I, J, K})
            ijk[dim] = find_upper(r[dim], dim);
    }

    // Locate a coordinate along a single axis
    __device__ dim_type find_upper(
        double r, dim_type axis) const
    {
        DEVICE_REQUIRE( 0 <= axis && axis < d_dimension );
        const double *edges_start;
        const double *edges_end;
        if( axis == def::I )
        {
            edges_start = dd_x_edges;
            edges_end   = dd_x_edges+d_cells_x+1;
        }
        if( axis == def::J )
        {
            edges_start = dd_y_edges;
            edges_end   = dd_y_edges+d_cells_y+1;
        }
        if( axis == def::K )
        {
            edges_start = dd_z_edges;
            edges_end   = dd_z_edges+d_cells_z+1;
        }
        return cuda::utility::lower_bound(edges_start,edges_end,r)
            - edges_start - 1;
    }

    //! Get lower corner of domain
    Space_Vector lower() const
    {
        Space_Vector xyz;

        cudaMemcpy(&xyz[def::I], dd_x_edges, sizeof(double),
                   cudaMemcpyDeviceToHost);
        cudaMemcpy(&xyz[def::J], dd_y_edges, sizeof(double),
                   cudaMemcpyDeviceToHost);
        cudaMemcpy(&xyz[def::K], dd_z_edges, sizeof(double),
                   cudaMemcpyDeviceToHost);

        return xyz;
    }

    //! Get high corner of domain
    Space_Vector upper() const
    {
        Space_Vector xyz;

        cudaMemcpy(&xyz[def::I], dd_x_edges+d_cells_x, sizeof(double),
                   cudaMemcpyDeviceToHost);
        cudaMemcpy(&xyz[def::J], dd_y_edges+d_cells_y, sizeof(double),
                   cudaMemcpyDeviceToHost);
        cudaMemcpy(&xyz[def::K], dd_z_edges+d_cells_z, sizeof(double),
                   cudaMemcpyDeviceToHost);

        return xyz;
    }

    //! Low corner of mesh in \e (i,j,k) direction.
    __device__ double low_corner(dim_type d) const
    {
        DEVICE_REQUIRE( d>=0 && d<=3 );
        if( d == def::I )
            return dd_x_edges[0];
        else if( d == def::J )
            return dd_y_edges[0];
        else if( d == def::K )
            return dd_z_edges[0];
        return CUDART_NAN;
    }

    //! High corner of mesh in \e (i,j,k) direction.
    __device__ double high_corner(dim_type d) const
    {
        DEVICE_REQUIRE( d>=0 && d<=3 );
        if( d == def::I )
            return dd_x_edges[d_cells_x];
        else if( d == def::J )
            return dd_y_edges[d_cells_y];
        else if( d == def::K )
            return dd_z_edges[d_cells_z];
        return CUDART_NAN;
    }
};

} // end namespace cuda_profugus


#endif // cuda_geometry_Cartesian_Mesh_hh

//---------------------------------------------------------------------------//
//                 end of Cartesian_Mesh.hh
//---------------------------------------------------------------------------//
