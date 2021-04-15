#######
# useful concepts for dispatch
#######

"""
Advection terms

right now really only non-linear or ::Nothing
"""
abstract type AdvectionTerm end
struct NonLinearAdvectionTerm <: AdvectionTerm end

"""
Turbulence Closures

ways to handle drag and diffusion and such
"""
abstract type TurbulenceClosure end

struct LinearDrag{T} <: TurbulenceClosure
    λ::T
end

struct ConstantViscosity{T} <: TurbulenceClosure
    μ::T
    ν::T
    κ::T
    function ConstantViscosity{T}(;
        μ = T(1e-6),   # m²/s
        ν = T(1e-6),   # m²/s
        κ = T(1e-6),   # m²/s
    ) where {T <: AbstractFloat}
        return new{T}(μ, ν, κ)
    end
end

"""
Forcings

ways to add body terms and sources
"""
abstract type Forcing end
abstract type CoriolisForce <: Forcing end

@inline calc_force!(state, ::Nothing, _...) = nothing

struct KinematicStress{T} <: Forcing
    τₒ::T
    function KinematicStress{T}(; τₒ = T(1e-4)) where {T <: AbstractFloat}
        return new{T}(τₒ)
    end
end

"""
Grouping structs
"""
abstract type AbstractModel end

Base.@kwdef struct SpatialModel{𝒜, ℬ, 𝒞, 𝒟, ℰ, ℱ} <: AbstractModel
    balance_law::𝒜
    physics::ℬ
    numerics::𝒞
    grid::𝒟
    boundary_conditions::ℰ
    parameters::ℱ
end

polynomialorders(model::SpatialModel) = convention(
    model.grid.resolution.polynomial_order,
    Val(ndims(model.grid.domain)),
)

abstract type ModelPhysics end

Base.@kwdef struct FluidPhysics{𝒪, 𝒜, 𝒟, 𝒞, ℬ, ℰ} <: ModelPhysics
    orientation::𝒪 = ClimateMachine.Orientations.FlatOrientation()
    advection::𝒜 = NonLinearAdvectionTerm()
    dissipation::𝒟 = nothing
    coriolis::𝒞 = nothing
    gravity::ℬ = nothing
    eos::ℰ = nothing
end

abstract type AbstractInitialValueProblem end

Base.@kwdef struct InitialValueProblem{𝒫, ℐ𝒱} <: AbstractInitialValueProblem
    params::𝒫 = nothing
    initial_conditions::ℐ𝒱 = nothing
end

abstract type AbstractSimulation end

struct Simulation{𝒜, ℬ, 𝒞, 𝒟, ℰ, ℱ} <: AbstractSimulation
    model::𝒜
    state::ℬ
    timestepper::𝒞
    initial_conditions::𝒟
    callbacks::ℰ
    time::ℱ
end

function Simulation(;
    model = nothing,
    state = nothing,
    timestepper = nothing,
    initial_conditions = nothing,
    callbacks = nothing,
    time = nothing,
)
    model = DGModel(model, initial_conditions = initial_conditions)

    FT = eltype(model.grid.vgeo)

    if state == nothing
        state = init_ode_state(model, FT(0); init_on_cpu = true)
    end
    # model = (discrete = dgmodel, spatial = model)
    return Simulation(
        model,
        state,
        timestepper,
        initial_conditions,
        callbacks,
        time,
    )
end

coordinates(simulation::Simulation) = coordinates(simulation.model.grid)
polynomialorders(simulation::Simulation) =
    polynomialorders(simulation.model.grid)

abstract type AbstractTimestepper end

Base.@kwdef struct TimeStepper{S, T} <: AbstractTimestepper
    method::S
    timestep::T
end