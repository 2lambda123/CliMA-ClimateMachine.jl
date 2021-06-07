### Reference state
using DocStringExtensions
using Thermodynamics.TemperatureProfiles
export ReferenceState, NoReferenceState, HydrostaticState
const TD = Thermodynamics
using CLIMAParameters.Planet: R_d, MSLP, cp_d, grav, T_surf_ref, T_min_ref
using ..DGMethods: fvm_balance!
using ..Mesh.Grids: polynomialorders

"""
    ReferenceState

Hydrostatic reference state, for example, used as initial
condition or for linearization.
"""
abstract type ReferenceState end

vars_state(m::ReferenceState, ::AbstractStateType, FT) = @vars()

"""
    NoReferenceState <: ReferenceState

No reference state used
"""
struct NoReferenceState <: ReferenceState end

"""
    HydrostaticState{P,T} <: ReferenceState

A hydrostatic state specified by a virtual
temperature profile and relative humidity.

By default, this is a dry hydrostatic reference
state.
"""
struct HydrostaticState{P, FT} <: ReferenceState
    virtual_temperature_profile::P
    relative_humidity::FT
    subtract_off::Bool
end
"""
    HydrostaticState(
        virtual_temperature_profile,
        relative_humidity = 0;
        subtract_off = true,
    )

Construct a `HydrostaticState` given virtual temperature profile and
relative humidity. The keyword argument `subtract_off` controls
whether the constructed state is subtracted off in the prognostic
momentum equation to remove hydrostatic contribution.
"""
function HydrostaticState(
    virtual_temperature_profile::TemperatureProfile{FT},
    relative_humidity = FT(0);
    subtract_off = true,
) where {FT}
    return HydrostaticState{typeof(virtual_temperature_profile), FT}(
        virtual_temperature_profile,
        relative_humidity,
        subtract_off,
    )
end

# TODO: change `ρe` to `energy` to support `θModel`
# TODO: Make `moisture` sub-component, so that moisture components are optional
vars_state(m::HydrostaticState, ::Auxiliary, FT) =
    @vars(ρ::FT, p::FT, T::FT, ρe::FT, ρq_tot::FT, ρq_liq::FT, ρq_ice::FT)

function ref_state_init_pρ!(
    atmos::AtmosModel,
    aux::Vars,
    tmp::Vars,
    geom::LocalGeometry,
)
    param_set = parameter_set(atmos)
    z = altitude(atmos, aux)
    ref_state = reference_state(atmos)
    T_virt, p = ref_state.virtual_temperature_profile(param_set, z)
    aux.ref_state.p = p
    aux.ref_state.ρ = p / (T_virt * R_d(param_set))
end

function ref_state_init_density_from_pressure!(
    atmos::AtmosModel,
    aux::Vars,
    tmp::Vars,
    geom::LocalGeometry,
) where {P, F}
    k = vertical_unit_vector(atmos, aux)
    ∇Φ = ∇gravitational_potential(atmos, aux)
    # density computation from pressure ρ = -1/g*dpdz
    ρ = -k' * tmp.∇p / (k' * ∇Φ)
    aux.ref_state.ρ = ρ
end

function ref_state_finalize_init!(
    atmos::AtmosModel,
    aux::Vars,
    tmp::Vars,
    geom::LocalGeometry,
)
    FT = eltype(aux)
    param_set = parameter_set(atmos)
    ρ = aux.ref_state.ρ
    p = aux.ref_state.p
    T_virt = p / (ρ * FT(R_d(param_set)))

    ref_state = reference_state(atmos)
    RH = ref_state.relative_humidity
    phase_type = PhaseEquil
    (T, q_pt) = TD.temperature_and_humidity_given_TᵥρRH(
        param_set,
        T_virt,
        ρ,
        RH,
        phase_type,
    )

    # Update temperature to be exactly consistent with
    # p, ρ, and q_pt
    if moisture_model(atmos) isa DryModel
        ts = PhaseDry_ρp(param_set, ρ, p)
    else
        ts = PhaseEquil_ρpq(param_set, ρ, p, q_pt.tot)
    end
    T = air_temperature(ts)
    q_pt = PhasePartition(ts)
    q_tot = q_pt.tot
    q_liq = q_pt.liq
    q_ice = q_pt.ice

    aux.ref_state.ρq_tot = ρ * q_tot
    aux.ref_state.ρq_liq = ρ * q_liq
    aux.ref_state.ρq_ice = ρ * q_ice
    aux.ref_state.T = T
    e_kin = FT(0)
    e_pot = gravitational_potential(atmos.orientation, aux)
    aux.ref_state.ρe = ρ * total_energy(e_kin, e_pot, ts)
end

atmos_init_aux!(::AtmosModel, ::ReferenceState, _...) = nothing
function atmos_init_aux!(
    atmos::AtmosModel,
    ::HydrostaticState,
    state_auxiliary::MPIStateArray,
    grid,
    direction,
)
    # Step 1: initialize both ρ and p
    init_state_auxiliary!(
        atmos,
        ref_state_init_pρ!,
        state_auxiliary,
        grid,
        direction,
    )

    # Step 2: correct ρ from p to satisfy discrete hydrostic balance
    vertical_fvm = polynomialorders(grid)[end] == 0

    if vertical_fvm
        # Vertical finite volume scheme
        # pᵢ - pᵢ₊₁ =  g ρᵢ₊₁ Δzᵢ₊₁/2 + g ρᵢ Δzᵢ/2
        fvm_balance!(fvm_balance_init!, atmos, state_auxiliary, grid)
    else
        ref_state = reference_state(atmos)
        ∇p = ∇reference_pressure(ref_state, state_auxiliary, grid)
        init_state_auxiliary!(
            atmos,
            ref_state_init_density_from_pressure!,
            state_auxiliary,
            grid,
            direction;
            state_temporary = ∇p,
        )
    end

    init_state_auxiliary!(
        atmos,
        ref_state_finalize_init!,
        state_auxiliary,
        grid,
        direction,
    )
end

using ..MPIStateArrays: vars
using ..DGMethods: init_ode_state
using ..DGMethods.NumericalFluxes:
    CentralNumericalFluxFirstOrder,
    CentralNumericalFluxSecondOrder,
    CentralNumericalFluxGradient


"""
    PressureGradientModel

A mini balance law that is used to take the gradient of reference
pressure. The gradient is computed as ∇ ⋅(pI) and the calculation
uses the balance law interface to be numerically consistent with
the way this gradient is computed in the dynamics.
"""
struct PressureGradientModel <: BalanceLaw end
vars_state(::PressureGradientModel, ::Auxiliary, T) = @vars(p::T)
vars_state(::PressureGradientModel, ::Prognostic, T) = @vars(∇p::SVector{3, T})
vars_state(::PressureGradientModel, ::Gradient, T) = @vars()
vars_state(::PressureGradientModel, ::GradientFlux, T) = @vars()
function init_state_auxiliary!(
    m::PressureGradientModel,
    state_auxiliary::MPIStateArray,
    grid,
    direction,
) end
function init_state_prognostic!(
    ::PressureGradientModel,
    state::Vars,
    aux::Vars,
    localgeo,
    t,
) end
function flux_first_order!(
    ::PressureGradientModel,
    flux::Grad,
    state::Vars,
    auxstate::Vars,
    t::Real,
    direction,
)
    flux.∇p -= auxstate.p * I
end
flux_second_order!(::PressureGradientModel, _...) = nothing
source!(::PressureGradientModel, _...) = nothing

boundary_conditions(::PressureGradientModel) = ntuple(i -> nothing, 6)
boundary_state!(nf, ::Nothing, ::PressureGradientModel, _...) = nothing

∇reference_pressure(::NoReferenceState, state_auxiliary, grid) = nothing
function ∇reference_pressure(::ReferenceState, state_auxiliary, grid)
    FT = eltype(state_auxiliary)
    ∇p = similar(state_auxiliary; vars = @vars(∇p::SVector{3, FT}), nstate = 3)

    grad_model = PressureGradientModel()
    # Note that the choice of numerical fluxes doesn't matter
    # for taking the gradient of a continuous field
    grad_dg = DGModel(
        grad_model,
        grid,
        CentralNumericalFluxFirstOrder(),
        CentralNumericalFluxSecondOrder(),
        CentralNumericalFluxGradient(),
    )

    # initialize p
    ix_p = varsindex(vars(state_auxiliary), :ref_state, :p)
    grad_dg.state_auxiliary.data .= state_auxiliary.data[:, ix_p, :]

    # FIXME: this isn't used but needs to be passed in
    gradQ = init_ode_state(grad_dg, FT(0))

    grad_dg(∇p, gradQ, nothing, FT(0))
    return ∇p
end

function fvm_balance_init!(
    atmos::AtmosModel,
    aux_top::Vars,
    aux::Vars,
    Δz::MArray{Tuple{2}, FT},
) where {FT}
    param_set = parameter_set(atmos)
    _grav::FT = grav(param_set)
    _R_d::FT = R_d(param_set)

    ref = aux.ref_state
    topref = aux_top.ref_state

    T_virt = ref.p / (_R_d * ref.ρ)
    top_T_virt = topref.p / (_R_d * topref.ρ)

    topref.ρ =
        ref.ρ * (_R_d * T_virt - _grav * Δz[1] / 2) /
        (_R_d * top_T_virt + _grav * Δz[2] / 2)
    topref.p = _R_d * topref.ρ * top_T_virt
end
