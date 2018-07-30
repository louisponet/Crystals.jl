module Crystals
using Unitful
# using MicroLogging
using Markdown
export @u_str

export Crystal, is_fractional, volume, round!, are_compatible_lattices
export eachatom
export smith_normal_form
export gruber, niggly
export hart_forcade, is_periodic, to_fractional, to_cartesian, into_cell, origin_centered
export into_voronoi, supercell, cell_parameters
export point_group, inner_translations, is_primitive, primitive, space_group
export Lattices

# if Pkg.installed("Unitful") ≤ v"0.0.4"
#     function Base.inv{T<:Quantity}(x::StridedMatrix{T})
#         m = inv(ustrip.(x))
#         iq = eltype(m)
#         reinterpret(Quantity{iq, typeof(inv(dimension(T))), typeof(inv(unit(T)))}, m)
#     end
# end

module Constants
  const default_tolerance = 1e-8
end

include("Structures.jl")
using .Structures

include("CrystalAtoms.jl")
using .CrystalAtoms

include("SNF.jl")
using .SNF

include("utilities.jl")
using .Utilities

include("Gruber.jl")
using .Gruber

include("SpaceGroup.jl")
using .SpaceGroup

module Lattices
  using DocStringExtensions
  using Unitful
  import Crystals.Structures: Crystal

  @template DEFAULT =
    """
        $(SIGNATURES)

    $(DOCSTRING)
    """

  include("Bravais.jl")
  include("Binary.jl")
  include("A2BX4.jl")
end

""" setups docs, useful for docs and doctests """
function _doc_pages()
    Any["Home" => "index.md",
        "Basic Usage" => "basic.md",
        "Cartesian and Fractional Coordinates" => "cartesian.md",
        "API Catalogue" => "methods.md"]
end

end # module
# @doc readme("Crystals") -> Crystals
