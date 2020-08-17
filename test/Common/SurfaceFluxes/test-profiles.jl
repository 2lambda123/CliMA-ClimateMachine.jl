using Test
using ClimateMachine
using CLIMAParameters: AbstractEarthParameterSet
using ClimateMachine.SurfaceFluxes
using StaticArrays

using NCDatasets

struct EarthParameterSet <: AbstractEarthParameterSet end
const param_set = EarthParameterSet()

@testset "SurfaceFluxes - FMS Profiles" begin
    FT = Float64;

    ## Discretisation altitude z
    z      = [29.432779269303, 30.0497139076724, 31.6880000418153, 34.1873479240475]
    ## Pottemp at height z
    pt     = [268.559120403867, 269.799228886728, 277.443023238556, 295.79192777341]
    ## Surface Pottemp
    pt0    = [273.42369841804 , 272.551410044203, 278.638168565727, 298.133068766049]
    ## Roughness lengths
    z0     = [5.86144925739178e-05, 0.0001, 0.000641655193293549, 3.23383768877187e-05]
    zt     = [3.69403636275411e-05, 0.0001, 1.01735489109205e-05, 7.63933834969505e-05]
    zq     = [5.72575636226887e-05, 0.0001, 5.72575636226887e-05, 5.72575636226887e-05]
    ## Speed
    speed  = [2.9693638452068, 2.43308757772094, 5.69418282305367, 9.5608693754561]
    ## Scale velocity and moisture
    u_star =  [0.109462510724615, 0.0932942802513508, 0.223232887323184, 0.290918439028557]
    q_star =   [0.000110861442197537, 9.44983279664197e-05, 4.17643828631936e-05, 0.000133135421415819]
    # No explicit buoyancy terms in ClimateMachine
    #b_star =  [0.00690834676781433, 0.00428178089592372, 0.00121229800895103, 0.00262353784027441, -0.000570314880866852]

    for ii = 1:length(u_star)
        # Data at first interior node (x_ave)
        qt_ave = FT(0);
        z_ave = z[ii];
        thv_ave = pt[ii];
        u_ave = speed[ii];
        x_ave = [u_ave, thv_ave, qt_ave];

        ## Initial guesses for MO parameters
        LMO_init = eps(FT);
        u_star_init = FT(0.1);
        th_star_init = -FT(0.1);
        qt_star_init = -FT(1e-5);
        x_init = [LMO_init, u_star_init, th_star_init, qt_star_init];

        # Surface values for variables
        u_sfc = FT(0);
        thv_sfc = pt0[ii];
        qt_sfc = q_star[ii];
        z_sfc = FT(0);
        x_s = [u_sfc, thv_sfc, qt_sfc];

        # Dimensionless numbers
        dimless_num = [FT(1), FT(1/3), FT(1/3)]

        # Roughness
        z_rough = [z0[ii], zt[ii], zq[ii]]

        # Constants
        a  = FT(4.7);
        Δz = z[ii];

        # F_exchange
        F_exchange = [FT(0.01), -FT(0.01), -FT(0.000001)];

        ## Assuming surface fluxes are not given
        result = surface_conditions(
                    param_set,
                    x_init,
                    x_ave,
                    x_s,
                    z_rough,
                    F_exchange,
                    dimless_num,
                    thv_ave,
                    qt_ave,
                    Δz,
                    z_ave / 2,
                    a,
                 );
        x_star =result.x_star
        @test (abs((x_star[1] - u_star[ii])/u_star[ii])) <= FT(0.15)
    end
end
