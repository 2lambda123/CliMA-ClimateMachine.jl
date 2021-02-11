#### Conjugate Gradient solver

export ConjugateGradientAlgorithm

"""
    ConjugateGradientAlgorithm(;
        preconditioner::Union{PreconditioningAlgorithm, Nothing} = nothing,
        atol::Union{Real, Nothing} = nothing,
        rtol::Union{Real, Nothing} = nothing,
        maxiters::Union{Int, Nothing} = nothing,
    )

Constructor for a `ConjugateGradientAlgorithm`, which solves an equation of the
form `f(Q) = rhs`, where `f` is assumed to be a linear function of `Q` that can
be represented by a symmetric positive definite matrix with real coefficients.

# Keyword Arguments
- `preconditioner`: unused; defaults to NoPreconditioningAlgorithm
- `atol`: absolute tolerance; defaults to `eps(eltype(Q))`
- `rtol`: relative tolerance; defaults to `√eps(eltype(Q))`
- `maxiters`: maximum number of iterations; defaults to `length(Q)`
"""
struct ConjugateGradientAlgorithm <: KrylovAlgorithm
    preconditioner
    atol
    rtol
    maxiters
    function ConjugateGradientAlgorithm(;
        preconditioner::Union{PreconditioningAlgorithm, Nothing} = nothing,
        atol::Union{Real, Nothing} = nothing,
        rtol::Union{Real, Nothing} = nothing,
        maxiters::Union{Int, Nothing} = nothing,
    )
        @checkargs("be positive", arg -> arg > 0, atol, rtol, maxiters)
        return new(preconditioner, atol, rtol, maxiters)
    end
end

struct ConjugateGradientSolver{PT, FT, AT} <: IterativeSolver
    preconditioner::PT
    residual::AT
    z::AT               # preconditioner applied to residual
    p::AT               # descent direction
    Ap::AT              # linear operator applied to p
    α::FT               # descent weight
    ω0::FT              # aux
    ω1::FT              # aux
    atol::FT
    rtol::FT
    maxiters::Int
end

function IterativeSolver(
    algorithm::ConjugateGradientAlgorithm,
    Q,
    f!,
    rhs,
)
    check_krylov_args(Q, rhs)
    FT = eltype(Q)

    preconditioner = isnothing(algorithm.preconditioner) ? NoPreconditioningAlgorithm() :
        algorithm.preconditioner
    atol = isnothing(algorithm.atol) ? eps(FT) : FT(algorithm.atol)
    rtol = isnothing(algorithm.rtol) ? √eps(FT) : FT(algorithm.rtol)
    maxiters = isnothing(algorithm.maxiters) ? length(Q) : algorithm.maxiters

    return ConjugateGradientSolver(
        Preconditioner(preconditioner, Q, f!),
        similar(Q),
        similar(Q),
        similar(Q),
        similar(Q),
        FT(0.),
        FT(0.),
        FT(0.),
        atol,
        rtol,
        maxiters,
    )
end

atol(solver::ConjugateGradientSolver) = solver.atol
rtol(solver::ConjugateGradientSolver) = solver.rtol
maxiters(solver::ConjugateGradientSolver) = solver.maxiters

function residual!(
    solver::ConjugateGradientSolver,
    threshold,
    iters,
    Q,
    f!,
    rhs,
    args...;
)
    residual_norm = norm(solver.residual, weighted_norm)
    converged = check_convergence(residual_norm, threshold, iters)
    return residual_norm, converged
end

function initialize!(
    solver::ConjugateGradientSolver,
    threshold,
    iters,
    Q,
    f!,
    rhs,
    args...;
)
    # initialize residual
    residual = solver.residual
    f!(residual, Q, args...)
    residual .= rhs .- residual
    residual_norm, converged = residual!(solver, threshold, iters, Q, f!, rhs, args...)
    if !converged
        # TODO: Implement preconditioner with new pc interface
        # PCapply!(solver.preconditioner, solver.z, solver.residual, args...)
        solver.z .= solver.residual
        solver.p .= solver.z # temporary while preconditioning is unsupported
    end

    return residual_norm, converged
end

function doiteration!(
    solver::ConjugateGradientSolver,
    threshold,
    iters,
    Q,
    f!,
    rhs,
    args...;
)
    pc = solver.preconditioner
    r = solver.residual
    z = solver.z
    p = solver.p
    Ap = solver.Ap
    α = solver.α
    ω0 = solver.ω0
    ω0 = solver.ω1

    ω0 = dot(r, z)
    f!(Ap, p, args...)
    α = ω0 / dot(p, Ap)
    Q .+= α .* p
    r .= r .- α .* Ap
    residual_norm, converged = residual!(solver, threshold, iters, Q, f!, rhs, args...)
    if converged return converged, 1 end
    # TODO: Implement preconditioner with new pc interface
    # PCapply!(pc, z, r, args...)
    z .= r
    ω1 = dot(r, z)
    p .= z .+ (ω1 / ω0) .* p
    ω0 = ω1

    return false, 1
end
