"""
    nlsolve!(nlsolver::AbstractNLSolver, integrator)

Solve
```math
dt⋅f(tmp + γ⋅z, p, t + c⋅dt) = z
```
where `dt` is the step size and `γ` and `c` are constants, and return the solution `z`.
"""
function nlsolve!(nlsolver::AbstractNLSolver, integrator)
  preamble!(nlsolver, integrator)

  while get_status(nlsolver) === SlowConvergence
    # (possibly modify and) accept step
    apply_step!(nlsolver, integrator)

    # compute next iterate
    perform_step!(nlsolver, integrator)
  
    # check convergence and divergence criteria
    check_status!(nlsolver, integrator)
  end

  postamble!(nlsolver, integrator)
end

## default implementations for NLSolver

function preamble!(nlsolver::NLSolver, integrator)
  nlsolver.iter = 0
  if nlsolver.maxiters == 0
    nlsolver.status = MaxIterReached
    return
  end
  
  nlsolver.status = SlowConvergence
  nlsolver.η = initial_η(nlsolver, integrator)

  initialize_cache!(nlsolver.cache, nlsolver, integrator)

  nothing
end

initial_η(nlsolver::NLSolver, integrator) = nlsolver.η

initialize_cache!(nlcache, nlsolver::NLSolver, integrator) = nothing

apply_step!(nlsolver::NLSolver, integrator) = _apply_step!(nlsolver, integrator)

function _apply_step!(nlsolver::NLSolver{algType,iip}, integrator) where {algType,iip}
  if nlsolver.iter > 0
    if iip
      recursivecopy!(nlsolver.z, nlsolver.gz)
    else
      nlsolver.z = nlsolver.gz
    end
  end

  # update statistics
  nlsolver.iter += 1
  if has_destats(integrator)
    integrator.destats.nnonliniter += 1
  end

  nothing
end

function check_status!(nlsolver::NLSolver, integrator)
  nlsolver.status = check_status(nlsolver, integrator)
  nothing
end

function check_status(nlsolver::NLSolver, integrator)
  @unpack iter,maxiters,κ,fast_convergence_cutoff = nlsolver

  # compute norm of residuals and cache previous value
  iter > 1 && (ndzprev = nlsolver.ndz)
  ndz = norm_of_residuals(nlsolver, integrator)
  nlsolver.ndz = ndz

  # check for convergence
  if iter > 1
    Θ = ndz / ndzprev
    η = Θ / (1 - Θ)
    nlsolver.η = η
  else
    η = nlsolver.η
  end
  if iszero(ndz) || (η * ndz < κ && (iter > 1 || !iszero(integrator.success_iter)))
    if η < nlsolver.fast_convergence_cutoff
      return FastConvergence
    else
      return Convergence
    end
  end

  # check for divergence (not in initial step)
  if iter > 1
    # divergence
    if Θ > 1
      return Divergence
    end

    # very slow convergence
    if ndz * Θ^(maxiters - iter) > κ * (1 - Θ)
      return VerySlowConvergence
    end
  end

  # check number of iterations
  if iter >= maxiters
    return MaxItersReached
  end

  SlowConvergence
end  

function norm_of_residuals(nlsolver::NLSolver, integrator)
  @unpack t,opts = integrator
  @unpack z,gz = nlsolver

  atmp = calculate_residuals(z, gz, opts.abstol, opts.reltol, opts.internalnorm, t)
  opts.internalnorm(atmp, t)
end

function postamble!(nlsolver::NLSolver, integrator)
  fail_convergence = nlsolvefail(nlsolver)
  if fail_convergence && has_destats(integrator)
      integrator.destats.nnonlinconvfail += 1
  end
  integrator.force_stepfail = fail_convergence

  nlsolver.z
end