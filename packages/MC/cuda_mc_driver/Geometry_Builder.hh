//----------------------------------*-C++-*----------------------------------//
/*!
 * \file   cuda_mc_driver/Geometry_Builder.hh
 * \author Steven Hamilton
 * \date   Wed Nov 25 12:58:58 2015
 * \brief  Geometry_Builder class definition.
 * \note   Copyright (C) 2015 Oak Ridge National Laboratory, UT-Battelle, LLC.
 */
//---------------------------------------------------------------------------//

#ifndef cuda_mc_driver_Geometry_Builder_hh
#define cuda_mc_driver_Geometry_Builder_hh

#include <memory>
#include <unordered_map>

#include "cuda_geometry/Mesh_Geometry.hh"
#include "cuda_rtk/RTK_Geometry.cuh"

#include "cuda_utils/Shared_Device_Ptr.hh"

#include "Teuchos_RCP.hpp"
#include "Teuchos_ParameterList.hpp"
#include "Teuchos_Array.hpp"
#include "Teuchos_TwoDArray.hpp"

namespace cuda_mc
{

//===========================================================================//
/*!
 * \class Geometry_Builder
 * \brief Build profugus Geometry
 */
//===========================================================================//
template <class Geometry_DMM>
class Geometry_Builder
{
  public:

    typedef std::shared_ptr<Geometry_DMM>         SP_Geometry_DMM;
    typedef Teuchos::RCP<Teuchos::ParameterList>  RCP_ParameterList;

    Geometry_Builder()
    {
        VALIDATE(false,"Missing a specialization");
    }

    SP_Geometry_DMM build(RCP_ParameterList master);
};

// Specialization for Mesh_Geometry
template <>
class Geometry_Builder<cuda_profugus::Mesh_Geometry_DMM>
{
  public:

    typedef cuda_profugus::Mesh_Geometry_DMM        Geometry_DMM;
    typedef std::shared_ptr<Geometry_DMM>           SP_Geometry_DMM;
    typedef Teuchos::RCP<Teuchos::ParameterList>    RCP_ParameterList;
    typedef Teuchos::Array<int>                     OneDArray_int;
    typedef Teuchos::Array<double>                  OneDArray_dbl;

    SP_Geometry_DMM build(RCP_ParameterList master);
};

// Specialization for RTK_Geometry
template <>
class Geometry_Builder<cuda_profugus::Core_DMM>
{
  public:

    typedef cuda_profugus::Core_DMM                 Geometry_DMM;
    typedef std::shared_ptr<Geometry_DMM>           SP_Geometry_DMM;
    typedef Teuchos::RCP<Teuchos::ParameterList>    RCP_ParameterList;

    SP_Geometry_DMM build(RCP_ParameterList master);
};

} // end namespace cuda_mc

#endif // cuda_mc_driver_Geometry_Builder_hh

//---------------------------------------------------------------------------//
//                 end of Geometry_Builder.hh
//---------------------------------------------------------------------------//
