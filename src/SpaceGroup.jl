module SpaceGroup
using DocStringExtensions
export point_group, is_primitive, primitive, space_group

using LinearAlgebra
import Crystals.Constants: default_tolerance
import Crystals.Structures: Crystal, volume
import Crystals.Gruber: gruber
import Crystals.Utilities: into_voronoi, is_periodic, into_cell, is_unitful, to_fractional
import Crystals.Utilities: to_cartesian, to_same_kind
# using MicroLogging
using ArgCheck
import Unitful: ustrip, Quantity, unit
import CoordinateTransformations: AffineMap
import DataFrames: nrow, AbstractDataFrame, groupby

"""
    potential_equivalents(cell::AbstractMatrix; tolerance::Real=$(default_tolerance))

Figures out vectors in the lattice defined by the cell which have the same
lengths as the column vectors defining the cell. these new vectors are
potentially symmetrically equivalent.
"""
function potential_equivalents(cell::AbstractMatrix; tolerance::Real=default_tolerance)
    V = volume(cell)
    a0 = cell[:, 1]
    a1 = cell[:, 2]
    a2 = cell[:, 3]

    lengths = reduce(+, cell .* cell, dims=1)
    max_norm = mapreduce(i -> norm(cell[:, i]), max, 1:size(cell, 2), init=zero(eltype(cell)))

    n0 = ceil(Integer, max_norm * norm(cross(a1, a2)) / V)
    n1 = ceil(Integer, max_norm * norm(cross(a2, a0)) / V)
    n2 = ceil(Integer, max_norm * norm(cross(a0, a1)) / V)

    gvectors = Any[Array{eltype(cell), 1}[] for u in 1:length(lengths)]
    for i in -n0:n0, j in -n1:n1, k in -n2:n2
        g = cell * [i, j, k]
        glength = sum(g .* g)
        for (length, result) in zip(lengths, gvectors)
            ustrip(abs(length - glength)) < tolerance && push!(result, g)
        end
    end

    [hcat(gs...) for gs in gvectors]
end

"""
Finds and stores point group operations for a given lattice

A lattice is defined by a 3x3 matrix or cell.  Rotations are determined from
G-vector triplets with the same norm as the unit-cell vectors.

Implementation taken from [ENUM](http://enum.sourceforge.net/).
"""
function point_group(cell::AbstractMatrix{T};
                     tolerance::Real=default_tolerance) where T <: Number
    @assert size(cell, 1) == size(cell, 2)

    avecs, bvecs, cvecs = potential_equivalents(cell, tolerance=tolerance)
    result = Matrix{T}[Matrix{T}(I, size(cell))]

    identity = Matrix{T}(I, size(cell))
    invcell = inv(cell)
    for i in 1:size(avecs, 2), j in 1:size(bvecs, 2), k in 1:size(cvecs, 2)
        # (potential) rotation in cartesian coordinates
        rotation = hcat(avecs[:, i], bvecs[:, j], cvecs[:, k])
        # check operator is invertible
        ustrip(volume(rotation)) ≥ tolerance || continue

        # rotation in fractional coordinates
        rotation = rotation * invcell
        any(ustrip.(abs.(rotation .- identity)) .> tolerance) || continue

        # check matrix is a rotation
        if !all(ustrip.(abs.(rotation * transpose(rotation) .- identity)) .< tolerance)
            continue
        end

        # check rotation not in list
        index = findfirst(x -> all(ustrip.(abs.(x .- rotation)) .< tolerance), result)
        index ≠ nothing || push!(result, rotation)
    end
    result
end

function point_group(cell::AbstractMatrix{Quantity{T, D, U}};
                     tolerance::Real=default_tolerance) where {T, D, U}
    point_group(ustrip.(cell), tolerance=tolerance)
end

function inner_translations_impl(fractional::AbstractMatrix,
                                 cell::AbstractMatrix,
                                 species::AbstractVector;
                                 tolerance::Real=default_tolerance)
    @argcheck is_unitful(fractional) == Val{:unitless}()
    @argcheck length(species) == size(fractional, 2)
    @argcheck size(cell, 2) == size(fractional, 1)
    grubcell = gruber(cell)

    # find species with minimum number of atoms
    atom_index = find_min_species_index(species)
    atom_center = fractional[:, atom_index]
    atom_type = species[atom_index]

    translations = []
    for site ∈ eachindex(species)
        species[site] ≠ atom_type && continue

        translation = into_voronoi(fractional[:, site] - atom_center, grubcell)
        all(abs.(translation) .< tolerance) && continue

        is_mapping = true
        for mapping ∈ eachindex(species)
            pos = fractional[:, mapping] + translation
            found = false
            for mappee ∈ eachindex(species)
                species[mappee] ≠ species[mapping] && continue
                found = is_periodic(pos, fractional[:, mappee], grubcell;
                                    tolerance=tolerance)
                found && break
            end
            (!found) && (is_mapping = false; break)
        end
        is_mapping && push!(translations, into_voronoi(translation, grubcell))
    end
    length(translations) == 0 && return similar(fractional, (size(fractional, 1), 0))
    hcat(translations...)
end

""" Internal translations which leave a crystal unchanged """
function inner_translations(positions::AbstractMatrix,
                            cell::AbstractMatrix,
                            species::AbstractVector;
                            kwargs...)
    inner_translations_impl(to_fractional(positions, cell), cell, species; kwargs...)
end
function inner_translations(crystal::Crystal, cols::Union{Symbol, AbstractVector{Symbol}};
                            kwargs...)
    @assert nrow(crystal.properties) == nrow(crystal)
    inner_translations(crystal[:fractional],
                       crystal.cell,
                       species_ids(nrow(crystal), crystal.properties, cols);
                       kwargs...)
end
function inner_translations(crystal::Crystal; kwargs...)
    inner_translations(crystal, names(crystal.properties); kwargs...)
end


"""
    species_ids(properties::AbstractDataFrame, cols::Union{Symbol, AbstractVector{Symbol}})

Returns an array where each unique set of elements in the input columns corresponds to a
unique element in the output. This functions helps creates an array corresponding to atomic
species, where a species can be defined by more than one input columns.
"""
function species_ids(properties::AbstractDataFrame, cols::AbstractVector{Symbol})
    if length(cols) == 0
        return ones(Int64, nrow(properties))
    end
    props = copy(properties)
    row_ids_name = Symbol("row_" * prod((string(u) for u in names(properties))))
    props[row_ids_name] = 1:nrow(props)

    results = zeros(Int64, (nrow(props,)))
    for (i, group) in enumerate(groupby(props, cols))
        results[group[row_ids_name]] .= i
    end
    results
end

species_ids(properties::AbstractDataFrame, col::Symbol) = properties[col]

function species_ids(nrows::Integer,
                     properties::AbstractDataFrame,
                     cols::AbstractVector{Symbol})
    if length(cols) == 0
        Int64[1:nrows...]
    else
        species_ids(properties, cols)
    end
end
species_ids(::Integer, props::AbstractDataFrame, cols::Symbol) = species_ids(props, cols)

"""
    is_primitive(cartesian::AbstractMatrix, cell::AbstractMatrix, species::AbstractVector;
                 tolerance::Real=$(default_tolerance))
    is_primitive(crystal::Crystal, col::Union{Symbol, AbstractVector{Symbol}}; kwargs...)
    is_primitive(crystal::Crystal; kwargs...)

True if the crystal structure is primitive, e.g. not a supercell, e.g. not reducible to an
equivalent lattice with fewer atoms.
"""
is_primitive(args...; kwargs...) = size(inner_translations(args...; kwargs...), 2) == 0

""" Index to first instance of least represented species in crystal """
function find_min_species_index(species::AbstractVector)
    unique_species = unique(species)
    k = findmin([count(!iszero, species .== u) for u in unique(species)])[2]
    atom_type = unique_species[k]
    findfirst(isequal(atom_type), species)
end


"""
    primitive(crystal::Crystal; tolerance::Real=$(default_tolerance))

Computes the primitive cell of the input crystal. If the crystal is primitive,
it is returned as is, otherwise a new crystal is returned.
"""
function primitive(crystal::Crystal; kwargs...)
    primitive(crystal, names(crystal.properties); kwargs...)
end
function primitive(crystal::Crystal, cols::Union{Symbol, AbstractVector{Symbol}}; kwargs...)
    species = species_ids(nrow(crystal), crystal.properties, cols)
    new_cell, indices = primitive(crystal.cell, crystal[:position], species; kwargs...)
    incell = into_cell(crystal[indices, :cartesian], new_cell)
    positions = to_same_kind(incell, incell, new_cell)
    typeof(crystal)(new_cell, positions, crystal.properties[indices, :])
end
function primitive(cell::AbstractMatrix, positions::AbstractMatrix, species::AbstractVector;
                   kwargs...)
    primitive_impl(cell, to_cartesian(positions, cell), species; kwargs...)
end

function primitive_impl(cell::AbstractMatrix,
                        cartesian::AbstractMatrix,
                        species::AbstractVector;
                        tolerance::Real=default_tolerance)
    @argcheck size(cartesian, 2) == length(species)
    @argcheck size(cell, 2) == size(cartesian, 1)
    size(cartesian, 2) == 0 && return cell, Int64[1:length(species)...]

    grubcell = gruber(cell)
    trans = grubcell * inner_translations(inv(grubcell) * cartesian, grubcell, species;
                                          tolerance=tolerance)
    size(trans, 2) == 0 && return cell, Int64[1:length(species)...]

    # adds original translations.
    trans = hcat(trans, grubcell)

    # Looks for cell with smallest volume
    new_cell = deepcopy(grubcell)
    V = volume(new_cell)
    for i ∈ CartesianIndices(((ones(Int64, size(cell, 1)) * size(trans, 2))...,))
        issorted(i.I, lt=≤) || continue
        index = [i.I...]
        trial = trans[:, index]
        volume(trial) < 1e-12 * unit(V) && continue
        (volume(trial) > V - 3.0 * tolerance * unit(V)) && continue

        if det(ustrip.(trial)) < 0e0
            reverse!(index)
            trial = trans[:, index]
        end
        det(ustrip.(trial)) < 0e0 && error("Negative volume")

        int_cell = inv(trial) * cell
        all(abs.(int_cell - round.(Integer, int_cell) .< 1e-8)) || continue

        new_cell = trial
        V = volume(trial)
    end

    # Found the new cell with smallest volume (e.g. primivite)
    if V ≥ volume(grubcell) - tolerance * unit(V)
        error("Found translation but no primitive cell")
    end

    # now creates new lattice.
    indices = Int64[]
    @debug "Found gruber cell $(grubcell)"

    for site in 1:size(cartesian, 2)
        position = into_cell(cartesian[:, site], new_cell; tolerance=tolerance)
        k = findfirst(indices) do index
            species[site] == species[index] &&
            is_periodic(position, cartesian[:, index], new_cell, tolerance=tolerance)
        end
        if k == nothing
            push!(indices, site)
        end
    end

    length(species) % length(indices) ≠ 0 && error(
        "Nb of atoms in output not multiple of input: " *
        "$(length(species)) % $(length(indices)) ≠ 0"
    )

    abs(
        length(species) * volume(new_cell) - length(indices) * volume(cell)
       ) < tolerance * unit(volume(new_cell))|| error(
        "Size and volumes do not match: " *
        "abs($(length(species)) * $(volume(new_cell)) - $(length(indices)) *" *
        "$(volume(cell))) ≥ $(tolerance * unit(volume(new_cell)))"
    )
    new_cell, indices
end

""" Computes space-group operations """
function space_group_impl(cell::AbstractMatrix,
                          cartesian::AbstractMatrix,
                          species::AbstractVector;
                          tolerance::Real=default_tolerance)

    grubcell = gruber(cell, tolerance=tolerance)
    invcell = inv(grubcell)
    minsite = find_min_species_index(species)
    minspecies = species[minsite]
    minpos = cartesian[:, minsite]
    pg_ops = point_group(grubcell, tolerance=tolerance)

    # translations limited to those from one atom type to othe atom of same type
    translations = cartesian[:, species .==  minspecies]
    translations .-= translations[:, 1]
    translations = into_cell(translations, grubcell; tolerance=tolerance)

    result = AffineMap[]
    for pg in pg_ops
        for trial in 1:size(translations, 2)
            is_invariant = findfirst(eachindex(species)) do mapper
                position = pg * (cartesian[:, mapper] - minpos) + translations[:, trial]
                mappee = findfirst(eachindex(species)) do atom
                    species[mapper] == species[atom] &&
                    is_periodic(position, cartesian[:, atom] - minpos, grubcell;
                                tolerance=tolerance)
                end
                mappee == nothing
            end
            if is_invariant == nothing
                pos = pg * cartesian[:, minsite] - cartesian[:, minsite]
                translation = into_voronoi(translations[:, trial] - pos, grubcell)
                push!(result, AffineMap(pg, translation))
            end
        end
    end
    pure_symms = count(result) do op
      all(abs.(ustrip.(op(zeros(eltype(cartesian), size(translations, 1))))) .< 1e-8)
    end

    @info "Symmetry operations" total=length(result) pure=pure_symms
    [u for u in result]
end

"""
    $(SIGNATURES)

Computes the space-group operations of a crystal. By default, all atomic properties are
considered when determining whether atomic sites are related by symmetry. However, it is
possible to specify a subset of atomic properties. An empty subset of atomic properties
implies that all atoms sites are equivalent. It is also possible to specify an array of
integers, serving as labels for each atomic site.
"""
function space_group(crystal::Crystal; kwargs...)
    space_group(crystal, names(crystal.properties); kwargs...)
end
function space_group(crystal::Crystal, cols::Union{Symbol, AbstractVector{Symbol}};
                     kwargs...)
    species = species_ids(nrow(crystal), crystal.properties, cols)
    space_group(crystal.cell, crystal[:position], species; kwargs...)
end
function space_group(crystal::Crystal, species::AbstractVector{Int64}; kwargs...)
    @argcheck length(species) == nrow(crystal)
    space_group(crystal.cell, crystal[:position], species; kwargs...)
end
"""
    $(SIGNATURES)

    Computes the space-group of a crystal specified using standard Julia types.
"""
function space_group(cell::AbstractMatrix,
                     positions::AbstractMatrix,
                     species::AbstractVector;
                     kwargs...)
    space_group_impl(cell, to_cartesian(positions, cell), species; kwargs...)
end
end
