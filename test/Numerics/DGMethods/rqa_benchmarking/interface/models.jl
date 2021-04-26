using ClimateMachine.BalanceLaws

abstract type AbstractFluidModel <: BalanceLaw end

"""
    ModelSetup <: BalanceLaw
"""
struct ModelSetup{𝒯,𝒰,𝒱,𝒲,𝒳} <: AbstractFluidModel
    physics::𝒯
    boundary_conditions::𝒰
    initial_conditions::𝒱
    numerics::𝒲
    parameters::𝒳
end

function ModelSetup(;
    physics,
    boundary_conditions,
    initial_conditions,
    numerics,
    parameters,
)
    return ModelSetup(
        physics,
        unpack_boundary_conditions(boundary_conditions),
        initial_conditions,
        numerics,
        parameters,
    )
end

function unpack_boundary_conditions(bcs)
    # We need to repackage the boundary conditions to match the
    # boundary conditions interface of the Balance Law and DGModel
    boundaries = (:west, :east, :south, :north, :bottom, :top)
    repackaged_bcs = []

    for boundary in boundaries
        fields = get(bcs, boundary, nothing)
        new_bc = isnothing(fields) ? FluidBC() : FluidBC(fields...)
        push!(repackaged_bcs, new_bc)
    end

    return Tuple(repackaged_bcs)
end