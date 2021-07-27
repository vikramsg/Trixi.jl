# By default, Julia/LLVM does not use fused multiply-add operations (FMAs).
# Since these FMAs can increase the performance of many numerical algorithms,
# we need to opt-in explicitly.
# See https://ranocha.de/blog/Optimizing_EC_Trixi for further details.
@muladd begin

function apply_smoothing!(u, mesh::StructuredMesh{1}, equations, dg::DGSEM, alpha, alpha_tmp, cache)
  # Diffuse alpha values by setting each alpha to at least 50% of neighboring elements' alpha
  # Copy alpha values such that smoothing is indpedenent of the element access order
  alpha_tmp .= alpha

  # Loop over elements, because there is no interface container
  for element in eachelement(dg,cache)
    # Get neighboring element ids
    left  = cache.elements.left_neighbors[1, element]

    # Apply smoothing
    alpha[left]     = max(alpha_tmp[left],    0.5 * alpha_tmp[element], alpha[left])
    alpha[element]  = max(alpha_tmp[element], 0.5 * alpha_tmp[left],    alpha[element])      
  end
  
end

end # @muladd
