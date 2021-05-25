abstract type AbstractTerm{𝒯} end

struct PressureDivergence{𝒯} <: AbstractTerm{𝒯} end

@inline calc_component!(flux, ::Nothing, _...) = nothing
@inline calc_component!(flux, ::AbstractTerm, _...) = nothing

@inline function calc_component!(flux, ::PressureDivergence, state, aux, physics)
    eos = physics.eos
    parameters = physics.parameters
    
    p = calc_pressure(eos, state, aux, parameters)

    flux.ρu += p * I

    nothing
end