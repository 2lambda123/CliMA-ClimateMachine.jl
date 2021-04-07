#### Land sources
export PhaseChange, Precip, SoilRunoff
using Printf
function heaviside(x::FT) where {FT}
    if x >= FT(0)
        output = FT(1)
    else
        output = FT(0)
    end
    return output
end


abstract type LandSource{FT <: AbstractFloat} end

"""
    PhaseChange <: SoilSource
The function which computes the freeze/thaw source term for Richard's equation,
assuming the timescale is the maximum of the thermal timescale and the timestep.
"""
Base.@kwdef struct PhaseChange{FT} <: LandSource{FT}
    "Timestep"
    Δt::FT = FT(NaN)
    "Timescale for temperature changes"
    τLTE::FT = FT(NaN)
end


function land_source!(
    f::Function,
    land::LandModel,
    source::Vars,
    state::Vars,
    diffusive::Vars,
    aux::Vars,
    t::Real,
    direction,
)
    f(land, source, state, diffusive, aux, t, direction)
end

#TODO: precip docs
struct Precip{FT, F} <: LandSource{FT}
    precip::F

    function Precip{FT}(precip::F) where {FT, F}
        new{FT, F}(precip)
    end
end

function (p::Precip{FT})(x, y, t)  where {FT}
    FT(p.precip(x, y, t))
end

struct SoilRunoff{FT} <: LandSource{FT}
end

function land_source!(
    source_type::SoilRunoff{FT},
    land::LandModel,
    source::Vars,
    state::Vars,
    diffusive::Vars,
    aux::Vars,
    t::Real,
    direction,
) where {FT}
    bc = land.boundary_conditions.surface_bc.soil_water
    precip = bc.precip_model(t)
    # Assume that diffusive- is parallel or antiparallel to n^, since diff+ is
    # Then
    n̂ = diffusive.soil.water.K∇h/norm(diffusive.soil.water.K∇h)
    flux_vector = -diffusive.soil.water.K∇h
    precip_vector = n̂ * (0,0,precip)
    leftover = norm(precip_vector - flux_vector)
    source.river.area  += -leftover
                                      
end

function land_source!(
    source_type::Precip,
    land::LandModel,
    source::Vars,
    state::Vars,
    diffusive::Vars,
    aux::Vars,
    t::Real,
    direction,
)
    source.river.area += source_type(aux.x, aux.y, t)
end

function land_source!(
    source_type::PhaseChange,
    land::LandModel,
    source::Vars,
    state::Vars,
    diffusive::Vars,
    aux::Vars,
    t::Real,
    direction,
)
    FT = eltype(state)

    param_set = parameter_set(land)
    _ρliq = FT(ρ_cloud_liq(param_set))
    _ρice = FT(ρ_cloud_ice(param_set))
    _Tfreeze = FT(T_freeze(param_set))
    _LH_f0 = FT(LH_f0(param_set))
    _g = FT(grav(param_set))

    ϑ_l, θ_i = get_water_content(land.soil.water, aux, state, t)
    eff_porosity = land.soil.param_functions.porosity - θ_i
    θ_l = volumetric_liquid_fraction(ϑ_l, eff_porosity)
    T = get_temperature(land.soil.heat, aux, t)

    # The inverse matric potential is only defined for negative arguments.
    # This is calculated even when T > _Tfreeze, so to be safe,
    # take absolute value and then pick the sign to be negative.
    # But below, use heaviside function to only allow freezing in the
    # appropriate temperature range (T < _Tfreeze)
    ψ = -abs(_LH_f0 / _g / _Tfreeze * (T - _Tfreeze))
    hydraulics = land.soil.water.hydraulics
    θ_r = land.soil.param_functions.θ_r
    θstar =
        θ_r +
        (land.soil.param_functions.porosity - θ_r) *
        inverse_matric_potential(hydraulics, ψ)

    τft = max(source_type.Δt, source_type.τLTE)
    freeze_thaw =
        FT(1) / τft * (
            _ρliq *
            (θ_l - θstar) *
            heaviside(_Tfreeze - T) *
            heaviside(θ_l - θstar) - _ρice * θ_i * heaviside(T - _Tfreeze)
        )
    source.soil.water.ϑ_l -= freeze_thaw / _ρliq
    source.soil.water.θ_i += freeze_thaw / _ρice
end


# sources are applied additively

@generated function land_source!(
    stuple::Tuple,
    land::LandModel,
    source::Vars,
    state::Vars,
    diffusive::Vars,
    aux::Vars,
    t::Real,
    direction,
)
    N = fieldcount(stuple)
    return quote
        Base.Cartesian.@nexprs $N i -> land_source!(
            stuple[i],
            land,
            source,
            state,
            diffusive,
            aux,
            t,
            direction,
        )
        return nothing
    end
end
