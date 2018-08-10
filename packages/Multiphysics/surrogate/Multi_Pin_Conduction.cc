//---------------------------------*-C++-*-----------------------------------//
/*!
 * \file   MC/mc/Multi_Pin_Conduction.cc
 * \author Steven Hamilton
 * \date   Thu Aug 09 09:12:06 2018
 * \brief  Multi_Pin_Conduction class definitions.
 * \note   Copyright (c) 2018 Oak Ridge National Laboratory, UT-Battelle, LLC.
 */
//---------------------------------------------------------------------------//

#include "Multi_Pin_Conduction.hh"

#include "Utils/harness/Soft_Equivalence.hh"

namespace mc
{
//---------------------------------------------------------------------------//
// Constructor
//---------------------------------------------------------------------------//
Multi_Pin_Conduction::Multi_Pin_Conduction(
        SP_Assembly                 assembly,
        RCP_PL                      parameters,
        const std::vector<double>&  dz)
    : d_assembly(assembly)
{
    REQUIRE(d_assembly);

    d_Nz = dz.size();

    // Make pin solver
    d_pin_conduction = std::make_shared<Single_Pin_Conduction>(
        parameters, dz);
    d_pin_conduction->set_fuel_radius(d_assembly->fuel_radius());
    d_pin_conduction->set_clad_radius(d_assembly->clad_radius());

    double height = std::accumulate(dz.begin(), dz.end(), 0.0);
    CHECK(profugus::soft_equiv(height, d_assembly->height()));
}

//---------------------------------------------------------------------------//
// Solve for all pins
//---------------------------------------------------------------------------//
void Multi_Pin_Conduction::solve(
        const std::vector<double>& power,
        const std::vector<double>& channel_temp,
              std::vector<double>& fuel_temp)
{
    int Nx = d_assembly->num_pins_x();
    int Ny = d_assembly->num_pins_y();
    int N = Nx * Ny * d_Nz;

    REQUIRE(power.size() == N);
    REQUIRE(channel_temp.size() == N);
    REQUIRE(fuel_temp.size() == N);

    // Storage for single pin values
    std::vector<double> pin_power(d_Nz);
    std::vector<double> pin_channel_temp(d_Nz);
    std::vector<double> pin_fuel_temp(d_Nz);

    // Loop over pins
    for (int iy = 0; iy < Ny; ++iy)
    {
        for (int ix = 0; ix < Nx; ++ix)
        {
            // Copy assembly data into single-pin containers
            for (int iz = 0; iz < d_Nz; ++iz)
            {
                int assembly_idx = ix + Nx * (iy + Ny * iz);
                pin_power[iz] = power[assembly_idx];
                pin_channel_temp[iz] = channel_temp[assembly_idx];
            }

            if (d_assembly->pin_type(ix, iy) == Assembly_Model::FUEL)
            {
                // Solve conduction in pin
                d_pin_conduction->solve(
                    pin_power,
                    pin_channel_temp,
                    pin_fuel_temp);
            }
            else
            {
                for (int iz = 0; iz < d_Nz; ++iz)
                    CHECK(pin_power[iz] == 0);

                // "Fuel" temp is same as channel temp in guide tubes
                std::copy(pin_channel_temp.begin(),
                          pin_channel_temp.end(),
                          pin_fuel_temp.begin());
            }

            // Copy fuel temp data back to assembly container
            for (int iz = 0; iz < d_Nz; ++iz)
            {
                int assembly_idx = ix + Nx * (iy + Ny * iz);
                fuel_temp[assembly_idx] = pin_fuel_temp[iz];
            }
        }
    }
}

//---------------------------------------------------------------------------//
} // end namespace mc

//---------------------------------------------------------------------------//
// end of MC/mc/Multi_Pin_Conduction.cc
//---------------------------------------------------------------------------//
