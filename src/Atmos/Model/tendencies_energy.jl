##### Energy tendencies

#####
##### First order fluxes
#####

function flux(::Advect{Energy}, m, state, aux, t, ts, direction)
    return (state.ρu / state.ρ) * state.ρe
end

function flux(::Pressure{Energy}, m, state, aux, t, ts, direction)
    return state.ρu / state.ρ * air_pressure(ts)
end

#####
##### First order fluxes
#####

struct ViscousProduction{PV <: Energy} <: TendencyDef{Flux{SecondOrder}, PV} end
function flux(
    ::ViscousProduction{Energy},
    m,
    state,
    aux,
    t,
    ts,
    diffusive,
    hyperdiff,
)
    ν, D_t, τ = turbulence_tensors(m, state, diffusive, aux, t)
    ν, D_t, τ = sponge_viscosity_modifier(m, m.viscoussponge, ν, D_t, τ, aux)
    return τ * state.ρu
end

struct EnthalpyProduction{PV <: Energy} <: TendencyDef{Flux{SecondOrder}, PV} end
function flux(
    ::EnthalpyProduction{Energy},
    m,
    state,
    aux,
    t,
    ts,
    diffusive,
    hyperdiff,
)
    ν, D_t, τ = turbulence_tensors(m, state, diffusive, aux, t)
    ν, D_t, τ = sponge_viscosity_modifier(m, m.viscoussponge, ν, D_t, τ, aux)
    d_h_tot = -D_t .* diffusive.∇h_tot
    return d_h_tot * state.ρ
end

#####
##### Sources
#####

function source(
    s::Subsidence{Energy},
    m,
    state,
    aux,
    t,
    ts,
    direction,
    diffusive,
)
    z = altitude(m, aux)
    w_sub = subsidence_velocity(s, z)
    k̂ = vertical_unit_vector(m, aux)
    return -state.ρ * w_sub * dot(k̂, diffusive.∇h_tot)
end
