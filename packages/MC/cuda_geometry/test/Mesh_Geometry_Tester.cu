//---------------------------------*-C++-*-----------------------------------//
/*!
 * \file   MC/cuda_geometry/test/Mesh_Geometry_Tester.cu
 * \author Steven Hamilton
 * \date   Mon Dec 14 13:28:26 2015
 * \brief  Mesh_Geometry_Tester class definitions.
 * \note   Copyright (c) 2015 Oak Ridge National Laboratory, UT-Battelle, LLC.
 */
//---------------------------------------------------------------------------//

#include "gtest/Gtest_Functions.hh"
#include "utils/View_Field.hh"
#include "cuda_utils/Definitions.hh"
#include "cuda_utils/CudaDBC.hh"

#include "../Mesh_Geometry.hh"
#include "Mesh_Geometry_Tester.hh"

typedef profugus::geometry::cell_type       cell_type;
typedef profugus::geometry::matid_type      matid_type;
typedef cuda_utils::Space_Vector            Point;
typedef cuda_utils::Coordinates             Coords;
typedef cuda_profugus::Mesh_Geometry        Mesh_Geometry;
typedef cuda_profugus::Mesh_Geometry_DMM    Mesh_Geometry_DMM;

// Compute the matid for particle at each specified spatial location
__global__ void compute_matids_kernel(Mesh_Geometry   mesh,
                                      int             num_points,
                                      const Point    *points,
                                      int            *matids)
{
    int tid = threadIdx.x + blockIdx.x * blockDim.x;
    if( tid < num_points )
    {
        // Create and initialize state on each thread
        // We're only testing matids so direction doesn't matter
        cuda_profugus::Mesh_State state;
        Point dir = {1.0, 0.0, 0.0};
        mesh.initialize(points[tid],dir,state);

        // Get matid
        matids[tid] = mesh.matid(state);
    }
}

// Compute the distance to boundary
__global__ void distance_kernel(Mesh_Geometry   mesh,
                                int             num_points,
                                const Point    *points,
                                        const Point    *dirs,
                                        double         *distances,
                                        Coords         *next_ijk)
{
    int tid = threadIdx.x + blockIdx.x * blockDim.x;
    if( tid < num_points )
    {
        // Create and initialize state on each thread
        cuda_profugus::Mesh_State state;
        mesh.initialize(points[tid],dirs[tid],state);

        distances[tid] = mesh.distance_to_boundary(state);
        next_ijk[tid] = state.next_ijk;
    }
}

// Compute the distance to boundary
__global__ void move_to_surf_kernel(Mesh_Geometry   mesh,
                                    int             num_points,
                                    const Point    *points,
                                    const Point    *dirs,
                                    Coords         *ijk)
{
    int tid = threadIdx.x + blockIdx.x * blockDim.x;
    if( tid < num_points )
    {
        // Create and initialize state on each thread
        cuda_profugus::Mesh_State state;
        mesh.initialize(points[tid],dirs[tid],state);

        mesh.distance_to_boundary(state);
        mesh.move_to_surface(state);
        ijk[tid] = state.ijk;
    }
}

// Compute the distance to boundary
__global__ void reflect_kernel(Mesh_Geometry   mesh,
                               int             num_points,
                               const Point    *points,
                               const Point    *dirs_in,
                               int            *reflected,
                               Point          *dirs_out,
                               Coords         *ijk_out,
                               int            *exit_face,
                               int            *refl_face)
{
    int tid = threadIdx.x + blockIdx.x * blockDim.x;
    if( tid < num_points )
    {
        // Create and initialize state on each thread
        cuda_profugus::Mesh_State state;
        mesh.initialize(points[tid],dirs_in[tid],state);

        // Move particle to boundary and reflect
        mesh.distance_to_boundary(state);
        mesh.move_to_surface(state);
        reflected[tid] = mesh.reflect(state);

        dirs_out[tid] = state.d_dir;
        ijk_out[tid]  = state.ijk;
        exit_face[tid] = state.exiting_face;
        refl_face[tid] = state.reflecting_face;
    }
}

namespace
{

// Build Mesh_Geometry
std::shared_ptr<Mesh_Geometry_DMM> get_mesh()
{
    std::vector<double> x_edges = {0.0, 0.1, 0.6, 0.9, 1.0};
    std::vector<double> y_edges = {-1.0, -0.6, 0.0};
    std::vector<double> z_edges = {2.0, 2.6, 3.4, 4.0};
    
    auto mesh = std::make_shared<Mesh_Geometry_DMM>(x_edges,y_edges,z_edges);
    return mesh;
}

}

//---------------------------------------------------------------------------//
// Compute volumes of specified cells
//---------------------------------------------------------------------------//
void Mesh_Geometry_Tester::test_volume()
{
    auto mesh = get_mesh();

    std::vector<cell_type> cells = {4, 1, 22, 11};
    int num_cells = cells.size();

    const auto& all_volumes = mesh->volumes();
    std::vector<double> cell_volumes(num_cells);

    for (int cellid = 0; cellid < num_cells; ++cellid)
        cell_volumes[cellid] = all_volumes[cells[cellid]];

    std::vector<double> expected_volumes = {0.1 * 0.6 * 0.6,
                                            0.5 * 0.4 * 0.6,
                                            0.3 * 0.6 * 0.6,
                                            0.1 * 0.4 * 0.8};

    EXPECT_VEC_SOFT_EQ( expected_volumes, cell_volumes );
}

//---------------------------------------------------------------------------//
// Compute matids of specified cells
//---------------------------------------------------------------------------//
void Mesh_Geometry_Tester::test_matid()
{
    auto mesh = get_mesh();

    std::vector<int> all_matids = {1, 3, 2, 0,
                                   3, 1, 4, 1,
                                   2, 5, 2, 1,
                                   0, 1, 2, 3,
                                   1, 2, 3, 4,
                                   2, 3, 4, 5};

    std::vector<Point> host_points = {{0.7,  -0.9,  2.1},
                                      {0.5,  -0.5,  2.5},
                                      {0.99, -0.01, 3.99},
                                      {0.05, -0.8,  2.4}};

    int num_points = host_points.size();
        
    // Set matids with mesh (host call)
    mesh->set_matids(all_matids);

    // Create memory on device
    thrust::device_vector<Point> device_points(host_points);
    thrust::device_vector<int> device_cell_matids(num_points);

    // Execute kernel
    compute_matids_kernel<<<1,num_points>>>(
             mesh->device_instance(),
             num_points,
             device_points.data().get(),
             device_cell_matids.data().get());

    REQUIRE( cudaGetLastError() == cudaSuccess );

    // Copy matids back to host
    std::vector<int> host_cell_matids(num_points);
    thrust::copy(device_cell_matids.begin(),device_cell_matids.end(),
                 host_cell_matids.begin());

    std::vector<int> expected_matids = {2, 1, 5, 1};

    EXPECT_VEC_EQ( expected_matids, host_cell_matids);
}

//---------------------------------------------------------------------------//
// Test distance to boundary
//---------------------------------------------------------------------------//
void Mesh_Geometry_Tester::test_dist_to_bdry()
{
    using def::I;  using def::J; using def::K;

    // Build mesh
    auto x_edges = {0.0, 0.10, 0.25, 0.30, 0.42};
    auto y_edges = {0.0, 0.20, 0.40, 0.50};
    auto z_edges = {-0.1, 0.0, 0.15, 0.50};
    auto mesh = std::make_shared<Mesh_Geometry_DMM>(x_edges,y_edges,z_edges);


    double sqrt_half = sqrt(0.5);
    std::vector<Point> host_points = {{0.01, 0.01, -0.01},
                                      {0.26, 0.35, -0.01}};
    std::vector<Point> host_dirs   = {{1.0,  0.0,   0.0},
                                      {sqrt_half, sqrt_half, 0.0}};

    int num_points = host_points.size();

    // Create memory on device
    thrust::device_vector<Point> device_points(host_points);
    thrust::device_vector<Point> device_dirs(host_dirs);
    thrust::device_vector<double> device_distances(num_points);
    thrust::device_vector<Coords> device_coords(num_points);

    // Execute kernel
    distance_kernel<<<1,num_points>>>(
             mesh->device_instance(),
             num_points,
             device_points.data().get(),
             device_dirs.data().get(),
             device_distances.data().get(),
             device_coords.data().get());

    REQUIRE( cudaGetLastError() == cudaSuccess );

    // Copy data back to host
    std::vector<double> host_distances(num_points);
    thrust::copy(device_distances.begin(),device_distances.end(),
                 host_distances.begin());
    std::vector<Coords> host_coords(num_points);
    thrust::copy(device_coords.begin(),device_coords.end(),
                 host_coords.begin());

    std::vector<double> expected_distances = {0.1 - 0.01, 0.04 / sqrt_half};
    std::vector<Coords> expected_coords = {{1, 0, 0}, {3, 1, 0}};

    EXPECT_VEC_SOFT_EQ(expected_distances, host_distances);
    EXPECT_EQ(expected_coords[0][I], host_coords[0][I]);
    EXPECT_EQ(expected_coords[0][J], host_coords[0][J]);
    EXPECT_EQ(expected_coords[0][K], host_coords[0][K]);
    EXPECT_EQ(expected_coords[1][I], host_coords[1][I]);
    EXPECT_EQ(expected_coords[1][J], host_coords[1][J]);
    EXPECT_EQ(expected_coords[1][K], host_coords[1][K]);
}

//---------------------------------------------------------------------------//
// Test move to surface
//---------------------------------------------------------------------------//
void Mesh_Geometry_Tester::test_move_to_surf()
{
    using def::I;  using def::J; using def::K;

    // Build mesh
    auto x_edges = {0.0, 0.10, 0.25, 0.30, 0.42};
    auto y_edges = {0.0, 0.20, 0.40, 0.50};
    auto z_edges = {-0.1, 0.0, 0.15, 0.50};
    auto mesh = std::make_shared<Mesh_Geometry_DMM>(x_edges,y_edges,z_edges);

    double sqrt_half = sqrt(0.5);
    std::vector<Point> host_points = {{0.01, 0.01, -0.01},
                                      {0.26, 0.35, -0.01}};
    std::vector<Point> host_dirs   = {{1.0,  0.0,   0.0},
                                      {sqrt_half, sqrt_half, 0.0}};

    int num_points = host_points.size();

    // Create memory on device
    thrust::device_vector<Point> device_points(host_points);
    thrust::device_vector<Point> device_dirs(host_dirs);
    thrust::device_vector<Coords> device_coords(num_points);

    // Execute kernel
    move_to_surf_kernel<<<1,num_points>>>(
             mesh->device_instance(),
             num_points,
             device_points.data().get(),
             device_dirs.data().get(),
             device_coords.data().get());

    REQUIRE( cudaGetLastError() == cudaSuccess );

    // Copy data back to host
    std::vector<Coords> host_coords(num_points);
    thrust::copy(device_coords.begin(),device_coords.end(),
                 host_coords.begin());

    std::vector<Coords> expected_coords = {{1, 0, 0}, {3, 1, 0}};

    EXPECT_EQ(expected_coords[0][I], host_coords[0][I]);
    EXPECT_EQ(expected_coords[0][J], host_coords[0][J]);
    EXPECT_EQ(expected_coords[0][K], host_coords[0][K]);
    EXPECT_EQ(expected_coords[1][I], host_coords[1][I]);
    EXPECT_EQ(expected_coords[1][J], host_coords[1][J]);
    EXPECT_EQ(expected_coords[1][K], host_coords[1][K]);
}

//---------------------------------------------------------------------------//
// Test reflection
//---------------------------------------------------------------------------//
void Mesh_Geometry_Tester::test_reflect()
{
    using def::I;  using def::J; using def::K;
    typedef cuda_profugus::Mesh_State Geo_State_t;

    // Build mesh
    auto x_edges = {0.0, 0.10, 0.25, 0.30, 0.42};
    auto y_edges = {0.0, 0.20, 0.40, 0.50};
    auto z_edges = {-0.1, 0.0, 0.15, 0.50};
    auto mesh = std::make_shared<Mesh_Geometry_DMM>(x_edges,y_edges,z_edges);

    std::vector<int> refl = {1, 0, 0, 0, 1, 1};
    mesh->set_reflecting(refl);

    std::vector<Point> host_points = {{0.05, 0.42, 0.10},
                                      {0.20, 0.45, 0.35}};
    std::vector<Point> host_dirs   = {{-4.0, 0.1, -0.5},
                                      {-1.0, 2.0, 1.0}};
    // Normalize directions
    double nrm = std::sqrt(host_dirs[0][I]*host_dirs[0][I] +
                           host_dirs[0][J]*host_dirs[0][J] +
                           host_dirs[0][K]*host_dirs[0][K]);
    host_dirs[0][I] /= nrm;
    host_dirs[0][J] /= nrm;
    host_dirs[0][K] /= nrm;

    nrm = std::sqrt(host_dirs[1][I]*host_dirs[1][I] +
                    host_dirs[1][J]*host_dirs[1][J] +
                    host_dirs[1][K]*host_dirs[1][K]);
    host_dirs[1][I] /= nrm;
    host_dirs[1][J] /= nrm;
    host_dirs[1][K] /= nrm;

    int num_points = host_points.size();

    // Create memory on device
    thrust::device_vector<Point> device_points(host_points);
    thrust::device_vector<Point> device_dirs_in(host_dirs);
    thrust::device_vector<Point>  device_dirs_out(num_points);
    thrust::device_vector<Coords> device_ijk_out(num_points);
    thrust::device_vector<int> device_exit_face(num_points);
    thrust::device_vector<int> device_refl_face(num_points);
    thrust::device_vector<int> device_reflected(num_points);

    // Execute kernel
    reflect_kernel<<<1,num_points>>>(
             mesh->device_instance(),
             num_points,
             device_points.data().get(),
             device_dirs_in.data().get(),
             device_reflected.data().get(),
             device_dirs_out.data().get(),
             device_ijk_out.data().get(),
             device_exit_face.data().get(),
             device_refl_face.data().get());

    REQUIRE( cudaGetLastError() == cudaSuccess );

    // Test reflected directions
    std::vector<Point> host_dirs_out(num_points);
    thrust::copy(device_dirs_out.begin(),device_dirs_out.end(),
                 host_dirs_out.begin());
    std::vector<Point> expected_dirs = {{-host_dirs[0][I],
                                         host_dirs[0][J],
                                         host_dirs[0][K]},
                                        {host_dirs[1][I],
                                         host_dirs[1][J],
                                         host_dirs[1][K]}};
    EXPECT_SOFT_EQ(expected_dirs[0][I], host_dirs_out[0][I]);
    EXPECT_SOFT_EQ(expected_dirs[0][J], host_dirs_out[0][J]);
    EXPECT_SOFT_EQ(expected_dirs[0][K], host_dirs_out[0][K]);
    EXPECT_SOFT_EQ(expected_dirs[1][I], host_dirs_out[1][I]);
    EXPECT_SOFT_EQ(expected_dirs[1][J], host_dirs_out[1][J]);
    EXPECT_SOFT_EQ(expected_dirs[1][K], host_dirs_out[1][K]);

    // Test reflected cell indices
    std::vector<Coords> host_ijk_out(num_points);
    thrust::copy(device_ijk_out.begin(),device_ijk_out.end(),
                 host_ijk_out.begin());
    std::vector<Coords> expected_ijk = {{0, 2, 1}, {1, 3, 2}};
    EXPECT_EQ(expected_ijk[0][I], host_ijk_out[0][I]);
    EXPECT_EQ(expected_ijk[0][J], host_ijk_out[0][J]);
    EXPECT_EQ(expected_ijk[0][K], host_ijk_out[0][K]);
    EXPECT_EQ(expected_ijk[1][I], host_ijk_out[1][I]);
    EXPECT_EQ(expected_ijk[1][J], host_ijk_out[1][J]);
    EXPECT_EQ(expected_ijk[1][K], host_ijk_out[1][K]);

    // Test reflected flag
    std::vector<int> host_reflected(num_points);
    thrust::copy(device_reflected.begin(),device_reflected.end(),
                 host_reflected.begin());
    std::vector<int> expected_reflected= {1, 0};
    EXPECT_VEC_EQ(expected_reflected, host_reflected);

    // Test exiting faces
    std::vector<int> host_exit_face(num_points);
    thrust::copy(device_exit_face.begin(),device_exit_face.end(),
                 host_exit_face.begin());
    std::vector<int> expected_exit_face = {Geo_State_t::MINUS_X,
                                           Geo_State_t::PLUS_Y};
    EXPECT_VEC_EQ(expected_exit_face, host_exit_face);

    // Test reflecting faces
    std::vector<int> host_refl_face(num_points);
    thrust::copy(device_refl_face.begin(),device_refl_face.end(),
                 host_refl_face.begin());
    std::vector<int> expected_refl_face = {Geo_State_t::MINUS_X,
                                           Geo_State_t::NONE};
    EXPECT_VEC_EQ(expected_refl_face, host_refl_face);
}

//---------------------------------------------------------------------------//
// Test reflection
//---------------------------------------------------------------------------//
void Mesh_Geometry_Tester::test_reflect()
{
    typedef cuda_profugus::Mesh_State Geo_State_t;

    // Build mesh
    auto x_edges = {0.0, 0.10, 0.25, 0.30, 0.42};
    auto y_edges = {0.0, 0.20, 0.40, 0.50};
    auto z_edges = {-0.1, 0.0, 0.15, 0.50};
    auto mesh = std::make_shared<Mesh_Geometry>(x_edges,y_edges,z_edges);

    std::vector<int> refl = {1, 0, 0, 0, 1, 1};
    mesh->set_reflecting(refl);

    std::vector<Point> host_points = {{0.05, 0.42, 0.10},
                                      {0.20, 0.45, 0.35}};
    std::vector<Point> host_dirs   = {{-4.0, 0.1, -0.5},
                                      {-1.0, 2.0, 1.0}};
    // Normalize directions
    double nrm = std::sqrt(host_dirs[0].x*host_dirs[0].x +
                           host_dirs[0].y*host_dirs[0].y +
                           host_dirs[0].z*host_dirs[0].z);
    host_dirs[0].x /= nrm;
    host_dirs[0].y /= nrm;
    host_dirs[0].z /= nrm;

    nrm = std::sqrt(host_dirs[1].x*host_dirs[1].x +
                    host_dirs[1].y*host_dirs[1].y +
                    host_dirs[1].z*host_dirs[1].z);
    host_dirs[1].x /= nrm;
    host_dirs[1].y /= nrm;
    host_dirs[1].z /= nrm;

    int num_points = host_points.size();

    // Create memory on device
    thrust::device_vector<Point> device_points(host_points);
    thrust::device_vector<Point> device_dirs_in(host_dirs);
    thrust::device_vector<Point>  device_dirs_out(num_points);
    thrust::device_vector<Coords> device_ijk_out(num_points);
    thrust::device_vector<int> device_exit_face(num_points);
    thrust::device_vector<int> device_refl_face(num_points);
    thrust::device_vector<int> device_reflected(num_points);

    // Execute kernel
    reflect_kernel<<<1,num_points>>>(
            *mesh,
             num_points,
             device_points.data().get(),
             device_dirs_in.data().get(),
             device_reflected.data().get(),
             device_dirs_out.data().get(),
             device_ijk_out.data().get(),
             device_exit_face.data().get(),
             device_refl_face.data().get());

    REQUIRE( cudaGetLastError() == cudaSuccess );

    // Test reflected directions
    std::vector<Point> host_dirs_out(num_points);
    thrust::copy(device_dirs_out.begin(),device_dirs_out.end(),
                 host_dirs_out.begin());
    std::vector<Point> expected_dirs = {{-host_dirs[0].x,
                                         host_dirs[0].y,
                                         host_dirs[0].z},
                                        {host_dirs[1].x,
                                         host_dirs[1].y,
                                         host_dirs[1].z}};
    EXPECT_SOFT_EQ(expected_dirs[0].x, host_dirs_out[0].x);
    EXPECT_SOFT_EQ(expected_dirs[0].y, host_dirs_out[0].y);
    EXPECT_SOFT_EQ(expected_dirs[0].z, host_dirs_out[0].z);
    EXPECT_SOFT_EQ(expected_dirs[1].x, host_dirs_out[1].x);
    EXPECT_SOFT_EQ(expected_dirs[1].y, host_dirs_out[1].y);
    EXPECT_SOFT_EQ(expected_dirs[1].z, host_dirs_out[1].z);

    // Test reflected cell indices
    std::vector<Coords> host_ijk_out(num_points);
    thrust::copy(device_ijk_out.begin(),device_ijk_out.end(),
                 host_ijk_out.begin());
    std::vector<Coords> expected_ijk = {{0, 2, 1}, {1, 3, 2}};
    EXPECT_EQ(expected_ijk[0].i, host_ijk_out[0].i);
    EXPECT_EQ(expected_ijk[0].j, host_ijk_out[0].j);
    EXPECT_EQ(expected_ijk[0].k, host_ijk_out[0].k);
    EXPECT_EQ(expected_ijk[1].i, host_ijk_out[1].i);
    EXPECT_EQ(expected_ijk[1].j, host_ijk_out[1].j);
    EXPECT_EQ(expected_ijk[1].k, host_ijk_out[1].k);

    // Test reflected flag
    std::vector<int> host_reflected(num_points);
    thrust::copy(device_reflected.begin(),device_reflected.end(),
                 host_reflected.begin());
    std::vector<int> expected_reflected= {1, 0};
    EXPECT_VEC_EQ(expected_reflected, host_reflected);

    // Test exiting faces
    std::vector<int> host_exit_face(num_points);
    thrust::copy(device_exit_face.begin(),device_exit_face.end(),
                 host_exit_face.begin());
    std::vector<int> expected_exit_face = {Geo_State_t::MINUS_X,
                                           Geo_State_t::PLUS_Y};
    EXPECT_VEC_EQ(expected_exit_face, host_exit_face);

    // Test reflecting faces
    std::vector<int> host_refl_face(num_points);
    thrust::copy(device_refl_face.begin(),device_refl_face.end(),
                 host_refl_face.begin());
    std::vector<int> expected_refl_face = {Geo_State_t::MINUS_X,
                                           Geo_State_t::NONE};
    EXPECT_VEC_EQ(expected_refl_face, host_refl_face);
}

//---------------------------------------------------------------------------//
// end of MC/cuda_geometry/test/Mesh_Geometry_Tester.cu
//---------------------------------------------------------------------------//
