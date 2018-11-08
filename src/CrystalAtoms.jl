module CrystalAtoms
import Crystals.Structures: Crystal, position_for_crystal
export eachatom
import DataFrames
using LinearAlgebra
""" Wrapper around a row/atom in a Crystal for iteration """
struct CrystalAtom{PARENT <: Crystal}
    """ Parent crystal """
    parent::PARENT
    """ Index in parent """
    index::Int64
end

Base.getindex(a::CrystalAtom, c::Any) = getindex(a.parent, a.index, c)
Base.getindex(a::CrystalAtom, c::Symbol, d::Integer) = getindex(a.parent, a.index, c, d)
Base.setindex!(a::CrystalAtom, v::Any, c::Any) = setindex!(a.parent, v, a.index, c)
function Base.setindex!(atom::CrystalAtom, v::Any, c::Symbol, d::Integer)
    setindex!(atom.parent, v, atom.index, c, d)
end
Base.names(a::CrystalAtom) = names(a.parent)

""" Wraps crystal for iteration purposes """
struct AtomicIterator{PARENT <: Crystal}
    """ Parent crystal structure """
    parent::PARENT
end

""" Iterator over each atom in the crystal """
eachatom(crystal::Crystal) = AtomicIterator(crystal)
""" Iterator over each atom in the crystal """
DataFrames.eachrow(crystal::Crystal) = eachatom(crystal)

Base.iterate(itr::AtomicIterator, i::Integer=1) = i > length(itr.parent) ? nothing : (CrystalAtom(itr.parent, i), i + 1)
Base.size(itr::AtomicIterator) = (length(itr.parent), )

Base.length(itr::AtomicIterator) = size(itr.parent, 1)
Base.getindex(itr::AtomicIterator, i::Any) = CrystalAtom(itr.parent, i)
Base.eltype(::Type{AtomicIterator{T}}) where {T <: Crystal} = CrystalAtom{T}
end
