using MPI
using OrderedCollections
using StaticArrays
using Test
using Statistics
using DelimitedFiles

using CLIMAParameters
struct EarthParameterSet <: AbstractEarthParameterSet end
const param_set = EarthParameterSet()

using ClimateMachine
using ClimateMachine.Land
using ClimateMachine.Land.SnowModel
using ClimateMachine.Land.SnowModelParameterizations
using ClimateMachine.Mesh.Topologies
using ClimateMachine.Mesh.Grids
using ClimateMachine.DGMethods
using ClimateMachine.DGMethods.NumericalFluxes
using ClimateMachine.DGMethods: BalanceLaw, LocalGeometry
using ClimateMachine.MPIStateArrays
using ClimateMachine.GenericCallbacks
using ClimateMachine.ODESolvers
using ClimateMachine.VariableTemplates
using ClimateMachine.SingleStackUtils
using ClimateMachine.BalanceLaws:
    BalanceLaw, Prognostic, Auxiliary, Gradient, GradientFlux, vars_state
using ClimateMachine.ArtifactWrappers

#@testset "Snow Model" begin

    ClimateMachine.init()
    FT = Float64

    soil_water_model = PrescribedWaterModel()
    soil_heat_model = PrescribedTemperatureModel()
    soil_param_functions = nothing

    m_soil = SoilModel(soil_param_functions, soil_water_model, soil_heat_model)

    snow_parameters = SnowParameters{FT,FT,FT,FT}(0.05,100,1.0)
Q_surf = (t) -> eltype(t)(-9.0*sin(2.0*π/3600/24*t))
#Q_bott = (t) -> eltype(t)(-1.0*sin(2.0*π/3600/24*t))
forcing = PrescribedForcing(FT;Q_surf = Q_surf)
Tave_0 = FT(263.0)
l_0 = FT(0.0)
ρe_int0 = volumetric_internal_energy(Tave_0, snow_parameters.ρ_snow, l_0, param_set)
    ic = (aux) -> eltype(aux)(ρe_int0)
    m_snow = SingleLayerSnowModel{typeof(snow_parameters), typeof(forcing),typeof(ic)}(
        snow_parameters,
        forcing,
        ic
    )


    function init_land_model!(land, state, aux, localgeo, time)
        state.snow.ρe_int = land.snow.initial_ρe_int(aux)
    end

    sources = (FluxDivergence{FT}(),)

    m = LandModel(
        param_set,
        m_soil;
        snow = m_snow,
        source = sources,
        init_state_prognostic = init_land_model!,
    )

    N_poly = 1
    nelem_vert = 1

    # Specify the domain boundaries
    zmax = FT(1)
    zmin = FT(0)

    driver_config = ClimateMachine.SingleStackConfiguration(
        "LandModel",
        N_poly,
        nelem_vert,
        zmax,
        param_set,
        m;
        zmin = zmin,
        numerical_flux_first_order = CentralNumericalFluxFirstOrder(),
    )

    t0 = FT(0)
    timeend = FT(60 * 60 * 48)
    dt = FT(60*60)

    solver_config = ClimateMachine.SolverConfiguration(
        t0,
        timeend,
        driver_config,
        ode_dt = dt,
    )
    n_outputs = 30;
    
    every_x_simulation_time = ceil(Int, (timeend-t0) / n_outputs);
    
    # Create a place to store this output.
    state_types = (Prognostic(),)
    dons_arr = Dict[dict_of_nodal_states(solver_config, state_types; interp = true)]
    time_data = FT[0] # store time data
    
    callback = GenericCallbacks.EveryXSimulationTime(every_x_simulation_time) do
        dons = dict_of_nodal_states(solver_config, state_types; interp = true)
        push!(dons_arr, dons)
        push!(time_data, gettime(solver_config.solver))
        nothing
    end;
    
    # # Run the integration
    ClimateMachine.invoke!(solver_config; user_callbacks = (callback,));
    z = get_z(solver_config.dg.grid; rm_dupes = true);
N = length(dons_arr)
ρe_int = [dons_arr[k]["snow.ρe_int"][1] for k in 1:N]
T_ave = T_snow_ave.(ρe_int, Ref(0.0), Ref(100.0),Ref(param_set))
coeffs = compute_profile_coefficients.(Q_surf.(time_data), Ref(0.0), Ref(snow_parameters.z_snow), Ref(snow_parameters.ρ_snow), Ref(snow_parameters.κ_snow), ρe_int, Ref(param_set))
t_profs = get_temperature_profile.(Q_surf.(time_data), Ref(0.0), Ref(snow_parameters.z_snow), Ref(snow_parameters.ρ_snow), Ref(snow_parameters.κ_snow), ρe_int, Ref(param_set))
z = 0:0.01:1


function analytic(p, Q, a, tbar,z,t)
    κ = p.κ_snow
    ρ = p.ρ_snow
    z_snow = p.z_snow
    ν = 2.0*π/24/3600
    c_i = cp_i(param_set)
    ρc_snow = ρ*c_i # assumes no liquid
    D1 = (2*κ/ν/ρc_snow)^0.5
    Q1 = Q
    α = a+ κ/D1
    β = κ/D1
    θ  = ν*t-(z_snow-z)/D1
    mag = sqrt(α^2+β^2)
    δ = atan(α/mag, β/mag)
    
    temp = tbar - Q1/mag*sin(θ+δ)*exp(-(z_snow-z)/D1)
    return temp
end



anim = @animate for i ∈ 1:N
    plot(t_profs[i].(z),z, ylim = [0,1], xlim = [250,280], label = "prescribed")
    t = time_data[i]
    plot!(analytic.(Ref(snow_parameters), Ref(-9.0), Ref(0.0), Ref(mean(T_ave)),z,Ref(t)),z, label = "analytic")
end
gif(anim, "snow.gif", fps = 6)

#end
