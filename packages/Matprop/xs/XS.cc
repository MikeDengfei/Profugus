//----------------------------------*-C++-*----------------------------------//
/*!
 * \file   Matprop/xs/XS.cc
 * \author Thomas M. Evans
 * \date   Wed Jan 29 15:27:36 2014
 * \brief  XS member definitions.
 * \note   Copyright (C) 2014 Oak Ridge National Laboratory, UT-Battelle, LLC.
 */
//---------------------------------------------------------------------------//

#include <algorithm>

#include "XS.hh"

namespace profugus
{

//---------------------------------------------------------------------------//
// CONSTRUCTOR
//---------------------------------------------------------------------------//
/*!
 * \brief Constructor.
 */
XS::XS()
    : d_pn(0)
    , d_Ng(1)
    , d_Nm(0)
{
}

//---------------------------------------------------------------------------//
// SET FUNCTIONS
//---------------------------------------------------------------------------//
/*!
 * \brief Set number of groups and Pn order that are stored.
 *
 * \param Pn_order anistropic scattering order (number of moments = Pn_order +
 * 1)
 *
 * \param num_groups number of energy groups
 *
 * All existing data is cleared in this call.
 */
void XS::set(int Pn_order,
             int num_groups)
{
    REQUIRE(Pn_order >= 0);
    REQUIRE(num_groups > 0);

    d_pn = Pn_order;
    d_Ng = num_groups;
    d_Nm = 0;

    // clear data
    d_totals.clear();
    d_scatter.clear();
    d_inst_totals.clear();
    d_inst_scat.clear();

    // resize totals
    d_totals.resize(END_XS_TYPES);
    d_inst_totals.resize(END_XS_TYPES);

    // resize scattering order vector
    d_scatter.resize(d_pn + 1);
    d_inst_scat.resize(d_pn + 1);

    // resize velocities
    d_v.size(d_Ng);
    d_bnds.size(d_Ng + 1);
}

//---------------------------------------------------------------------------//
/*!
 * \brief Set the group velocities.
 */
void XS::set_velocities(const OneDArray &velocities)
{
    REQUIRE(velocities.size() == d_Ng);
    REQUIRE(velocities.size() == d_v.length());

    for (int g = 0; g < d_Ng; ++g)
    {
        CHECK(velocities[g] >= 0.0);
        d_v[g] = velocities[g];
    }
}

//---------------------------------------------------------------------------//
/*!
 * \brief Set the group bounds.
 */
void XS::set_bounds(const OneDArray &bounds)
{
    REQUIRE(bounds.size() == d_Ng + 1);
    REQUIRE(bounds.size() == d_bnds.length());

    d_bnds[0] = bounds[0];
    for (int g = 1; g < d_Ng + 1; ++g)
    {
        CHECK(bounds[g] < bounds[g-1]);
        d_bnds[g] = bounds[g];
    }
}

//---------------------------------------------------------------------------//
/*!
 * \brief Add 1-D cross sections to the database.
 */
void XS::add(int              matid,
             int              type,
             const OneDArray &data)
{
    REQUIRE(data.size() == d_Ng);
    REQUIRE(type < END_XS_TYPES);
    REQUIRE(d_totals.size() == END_XS_TYPES);
    REQUIRE(d_inst_totals.size() == END_XS_TYPES);
    REQUIRE(!d_inst_totals[type].count(matid));

    // make a new denseVector to hold the data
    RCP_Vector v = Teuchos::rcp(
        new Vector(Teuchos::Copy, const_cast<double*>(data.getRawPtr()),
                   data.size()));

    // insert into hash table based on type
    d_totals[type].insert(Hash_Vector::value_type(matid, v));

    // indicate that this data has been inserted
    d_inst_totals[type].insert(matid);

    ENSURE(d_inst_totals[type].count(matid));
}

//---------------------------------------------------------------------------//
/*!
 * \brief Add scattering cross sections to the database.
 */
void XS::add(int              matid,
             int              pn,
             const TwoDArray &data)
{
    REQUIRE(data.getNumRows() == data.getNumCols());
    REQUIRE(data.getNumRows() == d_Ng);
    REQUIRE(pn <= d_pn);
    REQUIRE(d_scatter.size() == d_pn + 1);
    REQUIRE(!d_inst_scat[d_pn].count(matid));

    // make a new matrix to hold data
    RCP_Matrix m = Teuchos::rcp(new Matrix(d_Ng, d_Ng, true));
    Matrix    &s = *m;

    // the 2Darray is internally ROW-MAJOR, whereas Matrix is COLUMN-MAJOR, so
    // we have to do element-by-element copy
    for (int j = 0; j < d_Ng; ++j)
    {
        for (int i = 0; i < d_Ng; ++i)
        {
            s(i, j) = data(i, j);
        }
    }

    // insert into the hash table
    d_scatter[pn].insert(Hash_Matrix::value_type(matid, m));

    // indicate that this data has been inserted
    d_inst_scat[pn].insert(matid);

    ENSURE(d_inst_scat[pn].count(matid));
}

//---------------------------------------------------------------------------//
/*!
 * \brief Complete assignment.
 */
void XS::complete()
{
    // make null data for non-inserted data
    RCP_Vector vnull = Teuchos::rcp(new Vector(d_Ng, true));
    RCP_Matrix mnull = Teuchos::rcp(new Matrix(d_Ng, d_Ng, true));

    // iterate through inserted totals and add nulls for non-inserted data
    for (set_iter itr = d_inst_totals[TOTAL].begin();
         itr != d_inst_totals[TOTAL].end(); ++itr)
    {
        // get the inserted matid
        int matid = *itr;

        // add null data to fields that haven't been assigned
        for (int type = 1; type < END_XS_TYPES; ++type)
        {
            if (!d_inst_totals[type].count(matid))
            {
                d_totals[type].insert(Hash_Vector::value_type(matid, vnull));
            }
        }

        // add null data to scattering that haven't been assigned
        for (int n = 0; n < d_pn + 1; ++n)
        {
            if (!d_inst_scat[n].count(matid))
            {
                d_scatter[n].insert(Hash_Matrix::value_type(matid, mnull));
            }
        }
    }

    // store the size
    d_Nm = d_totals[TOTAL].size();

    // complete all hash-tables
    for (int type = 0; type < END_XS_TYPES; ++type)
    {
        d_totals[type].complete();
        ENSURE(d_totals[type].size() == d_Nm);
    }
    for (int n = 0; n < d_pn + 1; ++n)
    {
        d_scatter[n].complete();
        ENSURE(d_scatter[n].size() == d_Nm);
    }

    // clear work sets
    d_inst_totals.clear();
    d_inst_scat.clear();
}

//---------------------------------------------------------------------------//
/*!
 * \brief Get the material ids in the database.
 *
 * \param matids input/output vector that is resized to accomodate the stored
 * matids
 */
void XS::get_matids(Vec_Int &matids) const
{
    REQUIRE(d_totals[TOTAL].size() == d_Nm);

    // size the input vector
    matids.resize(d_Nm);

    Vec_Int::iterator id_itr = matids.begin();
    for (hash_iter mitr = d_totals[TOTAL].begin();
         mitr != d_totals[TOTAL].end(); ++mitr, ++id_itr)
    {
        *id_itr = mitr->first;
    }
}

} // end namespace profugus

//---------------------------------------------------------------------------//
//                 end of XS.cc
//---------------------------------------------------------------------------//
