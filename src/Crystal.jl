module Crystals

using DataFrames: DataFrame, nrow, DataArray, ColumnIndex, index
using FixedSizeArrays: FixedVectorNoTuple


for s in 2:6
  local name = Symbol("Position$(s)D")
  local docstring = "Position for $s-dimensional crystals"
  local code = begin
    u = quote
      $docstring
      immutable $name{T <:Real} <: FixedVectorNoTuple{$s, T}
      end
    end
    for (i, symb) in enumerate([:x, :y, :z, :u, :v, :w][1:s])
      push!(u.args[4].args[3].args, :($symb::T))
    end
    u
  end
  eval(code)
end

" All acceptable types for positions "
typealias PositionTypes Union{
  Position2D, Position3D,
  Position4D, Position5D, Position6D
}

const MAX_POSITION_SIZE = maximum([length(u) for u in PositionTypes.types])
const MIN_POSITION_SIZE = minimum([length(u) for u in PositionTypes.types])
function positions_type(x::Vector)
  MIN_POSITION_SIZE ≤ length(x) ≤ MAX_POSITION_SIZE ||
    error("Incorrect column vector size")
  position_index = findfirst(u -> length(u) == length(x), PositionTypes.types)
  PositionTypes.types[position_index]{eltype(x)}
end

# Add conversion rules from arrays
for position_type in PositionTypes.types
  @eval begin
    function Base.convert{T <: Real}(::Type{Vector{$(position_type){T}}}, x::Matrix)
      size(x, 1) == $(length(position_type)) || error("Incompatible vector size")
      $(position_type){T}[$(position_type)(x[:, u]) for u in 1:size(x, 2)]
    end
  end
end

" Converts inputs to something a DataArray of Positions will understand "
function Positions(x::Matrix)
  MIN_POSITION_SIZE ≤ size(x, 1) ≤ MAX_POSITION_SIZE ||
    error("Incorrect column vector size")
  return convert(Vector{positions_type(x[:, 1])}, x)
end
Positions(x::DataArray) = x
function Positions(x::Vector)
  T = positions_type(x)::Type
  T[T(x)]
end

abstract AbstractCrystal

"""
Crystal structure

Holds all data necessary to define a crystal structure.
The cell and scale are held as fields.
The atomic properties, including the positions, are held in a DataFrame.
"""
type Crystal{T} <: AbstractCrystal
  """ Scale/unit of the positions and cell """
  scale::T
  """ Periodicity of the crystal structure """
  cell::Matrix{T}
  """ Atoms and atomic properties """
  atoms::DataFrame

  function Crystal(cell, scale, atoms::DataFrame)
    size(cell, 1) == size(cell, 2) || error("Cell matrix is not square")
    MIN_POSITION_SIZE ≤ size(cell, 1) ≤ MAX_POSITION_SIZE ||
      error("Incorrect column vector size")
    :position ∈ names(atoms) || nrow(atoms) == 0 ||
      error("Input Dataframe has atoms without positions")
    if nrow(atoms) == 0
      atoms[:position] = Vector{positions_type(cell[:, 1])}()
    else
      eltype(atoms[:position]) <: PositionTypes ||
        error("Positions do not have acceptable type")
      size(cell, 1) == length(eltype(atoms[:position])) ||
        error("Cell and position dimensionality do not match")
    end
    new(scale, cell, atoms)
  end
end

function Crystal(cell::Matrix, scale=1::Real; kwargs...)
  nkwargs = Tuple{Symbol, Any}[]
  for i in 1:length(kwargs)
    if kwargs[i][1] ≠ :position
      push!(nkwargs, kwargs[i])
      continue
    end
    position = Positions(kwargs[i][2])
    size(cell, 1) == length(eltype(position)) ||
      error("Dimensionality of cell and positions do not match")
    push!(nkwargs, (:position, position))
  end

  atoms = DataFrame(; nkwargs...)
  Crystal{eltype(cell)}(cell, scale, atoms)
end

function Crystal(cell::Matrix, columns::Vector{Any}, names::Vector{Symbol},
                 scale=1::Real)
  for (i, (value, name)) in enumerate(zip(columns[:], names[:]))
    name == :position || continue

    columns[i] = Positions(value)
    size(cell, 1) == length(eltype(columns[i])) ||
      error("Dimensionality of cell and positions do not match")
  end

  atoms = DataFrame(columns, names)
  Crystal{eltype(cell)}(cell, scale, atoms)
end

# Forwards all indexing to the DataFrame
""" Equivalent to `getindex(crystal.atoms, ...)` """
Base.getindex(crystal::Crystal, col::Any) = crystal.atoms[col]
Base.getindex(crystal::Crystal, col::Any, row::Any) = crystal.atoms[col, row]
Base.names(crystal::Crystal) = names(crystal.atoms)
""" Equivalent to `endof(crystal.atoms)` """
Base.endof(crystal::Crystal) = endof(crystal.atoms)
""" Equivalent to `size(crystal.atoms)` """
Base.size(crystal::Crystal) = size(crystal.atoms)
Base.size(crystal::Crystal, i) = size(crystal.atoms, i)
""" Equivalent to `ndims(crystal.atoms)` """
Base.ndims(crystal::Crystal) = ndims(crystal.atoms)

# Single column
Base.setindex!(crystal::Crystal, v::Crystal, col::Any) =
  setindex!(crystal.atoms, v.atoms, col)
Base.setindex!(crystal::Crystal, v::Matrix, col::Any) =
  setindex!(crystal.atoms, Positions(v), col)
Base.setindex!(crystal::Crystal, v::Any, col::Any) =
  setindex!(crystal.atoms, v, col)
Base.setindex!(crystal::Crystal, v::Crystal, row::Any, col::Any) =
  setindex!(crystal.atoms, v.atoms, row, col)
Base.setindex!(crystal::Crystal, v::Matrix, row::Any, col::Any) =
  setindex!(crystal.atoms, Positions(v), row, col)
Base.setindex!(crystal::Crystal, v::Any, row::Any, col::Any) =
  setindex!(crystal.atoms, v, row, col)

export Crystal, Positions

end # module
