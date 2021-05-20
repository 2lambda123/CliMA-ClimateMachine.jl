abstract type AbstractAdvection <: AbstractPhysicsComponent end

struct NonLinearAdvection <: AbstractAdvection end

struct ESDGLinearAdvection <: AbstractAdvection end
Base.@kwdef struct ESDGNonLinearAdvection{𝒯} <: AbstractAdvection
    eos::𝒯
end

@inline calc_advective_flux!(flux, ::Nothing, _...) = nothing
@inline calc_advective_flux!(flux, ::Nothing, _...) = nothing
@inline calc_advective_flux!(flux, ::AbstractAdvection, _...) = nothing

@inline function calc_advective_flux!(flux, ::NonLinearAdvection, state, aux, t)
    ρ  = state.ρ
    ρu = state.ρu
    ρθ = state.ρθ

    flux.ρ  += state.ρu
    flux.ρu += ρu ⊗ ρu / ρ
    flux.ρθ += ρu * ρθ / ρ

    return nothing
end

@inline function calc_flux!(flux, ::ESDGLinearAdvection, state, aux, t)
    ρu  = state.ρu
    ρᵣ  = aux.ref_state.ρ
    pᵣ  = aux.ref_state.p
    ρeᵣ = aux.ref_state.ρe

    flux.ρ += ρu
    #flux.ρu += -0
    flux.ρe += (ρeᵣ + pᵣ) / ρᵣ * ρu
    #flux.ρq += -0

    return nothing
end


@inline function calc_flux!(flux, advection::ESDGNonLinearAdvection, state, aux, t)
    ρ = state.ρ
    ρu = state.ρu
    ρe = state.ρe
    ρq = state.ρq
    eos = advection.eos
    ρ⁻¹ = 1 / ρ

    p = calc_pressure(eos, state, aux)

    flux.ρ  += ρu
    flux.ρu += ρ⁻¹ * ρu ⊗ ρu
    flux.ρe += ρ⁻¹ * ρu * (ρe + p)
    flux.ρq += ρ⁻¹ * ρu * ρq
    
    return nothing
end