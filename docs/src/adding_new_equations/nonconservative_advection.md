# Adding a new equation: nonconservative linear advection

If you want to use Trixi for your own research, you might be interested in
a new physics model that is not present in Trixi.jl. In this tutorial,
we will implement the nonconservative linear advection equation
```math
\partial_t u(t,x) + a(x) \partial_x u(t,x) = 0
```
in a periodic domain in one space dimension. In Trixi.jl, such a mathematical model
is encoded as a subtype of [`Trixi.AbstractEquations`](@ref).


## Basic setup

Let's start by creating a module (in the REPL, in a file, in a Jupyter notebook, ...).
That ensures that we can re-create `struct`s defined therein without having to
restart Julia.

```julia
# Define new physics
module NonconservativeLinearAdvection

using Trixi
using Trixi: AbstractEquations, get_node_vars
import Trixi: varnames, default_analysis_integrals, flux, max_abs_speed_naive,
              have_nonconservative_terms

# Since there is no native support for variable coefficients, we use two
# variables: one for the basic unknown `u` and another one for the coefficient `a`
struct NonconservativeLinearAdvectionEquation <: AbstractEquations{1 #= spatial dimension =#,
                                                                   2 #= two variables (u,a) =#}
end

varnames(::typeof(cons2cons), ::NonconservativeLinearAdvectionEquation) = ("scalar", "advectionvelocity")

default_analysis_integrals(::NonconservativeLinearAdvectionEquation) = ()


# The conservative part of the flux is zero
flux(u, orientation, equation::NonconservativeLinearAdvectionEquation) = zero(u)

# Calculate maximum wave speed for local Lax-Friedrichs-type dissipation
function max_abs_speed_naive(u_ll, u_rr, orientation::Integer, ::NonconservativeLinearAdvectionEquation)
  _, advectionvelocity_ll = u_ll
  _, advectionvelocity_rr = u_rr

  return max(abs(advectionvelocity_ll), abs(advectionvelocity_rr))
end


# We use nonconservative terms
have_nonconservative_terms(::NonconservativeLinearAdvectionEquation) = Val(true)

# This "nonconservative numerical flux" implements the nonconservative terms.
# In general, nonconservative terms can be written in the form
#   g(u) ∂ₓ h(u)
# Thus, a discrete difference approximation of this nonconservative term needs
# - `u mine`:  the value of `u` at the current position (for g(u))
# - `u_other`: the values of `u` in a neighborhood of the current position (for ∂ₓ h(u))
function flux_nonconservative(u_mine, u_other, orientation,
                              equations::NonconservativeLinearAdvectionEquation)
  _, advectionvelocity = u_mine
  scalar, _            = u_other

  return SVector(advectionvelocity * scalar, zero(scalar))
end

end # module
```

The implementation of nononservative terms uses a single "nonconservative flux"
function `flux_nonconservative`. It will basically be applied in a loop of the
form
```julia
du_m = sum(D[m, l] * flux_nonconservative(u[m], u[l], 1, equations)) # orientation 1: x
```
where `D` is the derivative matrix and `u` contains the nodal solution values.

Now, we can run a simple simulation using a DGSEM discretization. This code is
written outside of our new `module`.
```julia
# Create a simulation setup
import .NonconservativeLinearAdvection
using Trixi
using OrdinaryDiffEq

equation = NonconservativeLinearAdvection.NonconservativeLinearAdvectionEquation()

# You can derive the exact solution for this setup using the method of
# characteristics
function initial_condition_sine(x, t, equation::NonconservativeLinearAdvection.NonconservativeLinearAdvectionEquation)
  x0 = -2 * atan(sqrt(3) * tan(sqrt(3) / 2 * t - atan(tan(x[1] / 2) / sqrt(3))))
  scalar = sin(x0)
  advectionvelocity = 2 + cos(x[1])
  SVector(scalar, advectionvelocity)
end

# Create a uniform mesh in 1D in the interval [-π, π] with periodic boundaries
mesh = TreeMesh(-Float64(π), Float64(π), # min/max coordinates
                initial_refinement_level=4, n_cells_max=10^4)

# Create a DGSEM solver with polynomials of degree `polydeg`
# Remember to pass a tuple of the form `(conservative_flux, nonconservative_flux)`
# as `surface_flux` and `volume_flux` when working with nonconservative terms
volume_flux  = (flux_central, NonconservativeLinearAdvection.flux_nonconservative)
surface_flux = (flux_lax_friedrichs, NonconservativeLinearAdvection.flux_nonconservative)
solver = DGSEM(polydeg=3, surface_flux=surface_flux,
               volume_integral=VolumeIntegralFluxDifferencing(volume_flux))

# Setup the spatial semidiscretization containing all ingredients
semi = SemidiscretizationHyperbolic(mesh, equation, initial_condition_sine, solver)

# Create an ODE problem with given time span
tspan = (0.0, 1.0)
ode = semidiscretize(semi, tspan);

# Set up some standard callbacks summarizing the simulation setup and computing
# errors of the numerical solution
summary_callback = SummaryCallback()
analysis_callback = AnalysisCallback(semi, interval=50)
callbacks = CallbackSet(summary_callback, analysis_callback);

# OrdinaryDiffEq's `solve` method evolves the solution in time and executes
# the passed callbacks
sol = solve(ode, Tsit5(), abstol=1.0e-6, reltol=1.0e-6,
            save_everystep=false, callback=callbacks);

# Print the timer summary
summary_callback()

# Plot the numerical solution at the final time
using Plots: plot
plot(sol)
```

You should see a plot of the final solution that looks as follows.

![tutorial_nonconservative_advection](https://user-images.githubusercontent.com/12693098/124343365-1f9a9300-dbcb-11eb-93a5-0f75db2a99f8.png)

We can check whether everything fits together by refining the grid and comparing
the numerical errors. First, we look at the error using the grid resolution
above.
```julia
julia> analysis_callback(sol).l2 |> first
0.00029610274971929974
```

Next, we increase the grid resolution by one refinement level and run the
simulation again.
```julia
mesh = TreeMesh(-Float64(π), Float64(π), # min/max coordinates
                initial_refinement_level=5, n_cells_max=10^4)

semi = SemidiscretizationHyperbolic(mesh, equation, initial_condition_sine, solver)

tspan = (0.0, 1.0)
ode = semidiscretize(semi, tspan);

summary_callback = SummaryCallback()
analysis_callback = AnalysisCallback(semi, interval=50)
callbacks = CallbackSet(summary_callback, analysis_callback);

sol = solve(ode, Tsit5(), abstol=1.0e-6, reltol=1.0e-6,
            save_everystep=false, callback=callbacks);
summary_callback()
```

As expected, the new error is roughly reduced by a factor of 16, corresponding
to an experimental order of convergence of 4 (for polynomials of degree 3).
```julia
julia> analysis_callback(sol).l2 |> first
1.8602959063280523e-5

julia> 0.00029610274971929974 / 1.8602959063280523e-5
15.916970451424719
```


## Summary of the code

Here is the complete code that we used (without the callbacks since these
create a lot of unnecessary output in the doctests of this tutorial).

```jldoctest; output = false
# Define new physics
module NonconservativeLinearAdvection

using Trixi
using Trixi: AbstractEquations, get_node_vars
import Trixi: varnames, default_analysis_integrals, flux, max_abs_speed_naive,
              have_nonconservative_terms

# Since there is not yet native support for variable coefficients, we use two
# variables: one for the basic unknown `u` and another one for the coefficient `a`
struct NonconservativeLinearAdvectionEquation <: AbstractEquations{1 #= spatial dimension =#,
                                                                   2 #= two variables (u,a) =#}
end

varnames(::typeof(cons2cons), ::NonconservativeLinearAdvectionEquation) = ("scalar", "advectionvelocity")

default_analysis_integrals(::NonconservativeLinearAdvectionEquation) = ()


# The conservative part of the flux is zero
flux(u, orientation, equation::NonconservativeLinearAdvectionEquation) = zero(u)

# Calculate maximum wave speed for local Lax-Friedrichs-type dissipation
function max_abs_speed_naive(u_ll, u_rr, orientation::Integer, ::NonconservativeLinearAdvectionEquation)
  _, advectionvelocity_ll = u_ll
  _, advectionvelocity_rr = u_rr

  return max(abs(advectionvelocity_ll), abs(advectionvelocity_rr))
end


# We use nonconservative terms
have_nonconservative_terms(::NonconservativeLinearAdvectionEquation) = Val(true)

# This "nonconservative numerical flux" implements the nonconservative terms.
# In general, nonconservative terms can be written in the form
#   g(u) ∂ₓ h(u)
# Thus, a discrete difference approximation of this nonconservative term needs
# - `u mine`:  the value of `u` at the current position (for g(u))
# - `u_other`: the values of `u` in a neighborhood of the current position (for ∂ₓ h(u))
function flux_nonconservative(u_mine, u_other, orientation,
                              equations::NonconservativeLinearAdvectionEquation)
  _, advectionvelocity = u_mine
  scalar, _            = u_other

  return SVector(advectionvelocity * scalar, zero(scalar))
end

end # module



# Create a simulation setup
import .NonconservativeLinearAdvection
using Trixi
using OrdinaryDiffEq

equation = NonconservativeLinearAdvection.NonconservativeLinearAdvectionEquation()

# You can derive the exact solution for this setup using the method of
# characteristics
function initial_condition_sine(x, t, equation::NonconservativeLinearAdvection.NonconservativeLinearAdvectionEquation)
  x0 = -2 * atan(sqrt(3) * tan(sqrt(3) / 2 * t - atan(tan(x[1] / 2) / sqrt(3))))
  scalar = sin(x0)
  advectionvelocity = 2 + cos(x[1])
  SVector(scalar, advectionvelocity)
end

# Create a uniform mesh in 1D in the interval [-π, π] with periodic boundaries
mesh = TreeMesh(-Float64(π), Float64(π), # min/max coordinates
                initial_refinement_level=4, n_cells_max=10^4)

# Create a DGSEM solver with polynomials of degree `polydeg`
# Remember to pass a tuple of the form `(conservative_flux, nonconservative_flux)`
# as `surface_flux` and `volume_flux` when working with nonconservative terms
volume_flux  = (flux_central, NonconservativeLinearAdvection.flux_nonconservative)
surface_flux = (flux_lax_friedrichs, NonconservativeLinearAdvection.flux_nonconservative)
solver = DGSEM(polydeg=3, surface_flux=surface_flux,
               volume_integral=VolumeIntegralFluxDifferencing(volume_flux))

# Setup the spatial semidiscretization containing all ingredients
semi = SemidiscretizationHyperbolic(mesh, equation, initial_condition_sine, solver)

# Create an ODE problem with given time span
tspan = (0.0, 1.0)
ode = semidiscretize(semi, tspan);

# Set up some standard callbacks summarizing the simulation setup and computing
# errors of the numerical solution
summary_callback = SummaryCallback()
analysis_callback = AnalysisCallback(semi, interval=50)
callbacks = CallbackSet(summary_callback, analysis_callback);

# OrdinaryDiffEq's `solve` method evolves the solution in time and executes
# the passed callbacks
sol = solve(ode, Tsit5(), abstol=1.0e-6, reltol=1.0e-6,
            save_everystep=false);

# Plot the numerical solution at the final time
using Plots: plot
plot(sol)

# output

Plot{Plots.GRBackend() n=2}

```
