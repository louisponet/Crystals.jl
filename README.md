[![Build Status](https://travis-ci.org/mdavezac/Crystals.jl.svg?branch=master)](https://travis-ci.org/mdavezac/Crystals.jl)
[![](https://img.shields.io/badge/docs-stable-blue.svg)](https://mdavezac.github.io/Crystals.jl/latest)
[![Coverage Status](https://coveralls.io/repos/mdavezac/Crystals.jl/badge.svg)](https://coveralls.io/r/mdavezac/Crystals.jl)

# Crystals

The audience for this package should have a need or a want to play with relatively small
(DFT/GW scale) crystalline structure from an atomistic point of view. Its purpose is to
allow users to build and investigate crystal structures programmatically.

A `Crystal` declares an atomic crystalline structure, e.g an inifinite periodic
arrangement of atoms. The constructor takes at the very least an `n` by `n` array defining
the periodicity of the crystal, i.e. the crystal cell. The cell must have physical units
attached to it.

```julia
using Crystals
crystal = Crystal(Matrix(1.0I, 3, 3)u"nm")
@assert crystal.cell === [1 0 0; 0 1 0; 0 0 1]
```

However, it can also accept atomic positions and any other array of atomic
properties:

```julia
using Crystals
crystal = Crystal(Matrix(1.0I, 2, 2)u"km",
                  position=transpose([1 1; 2 3; 4 5])u"m",
                  species=["Al", "O", "O"],
                  label=[:+, :-, :-])
@assert crystal[:position] == transpose([1 1; 2 3; 4 5])u"m"
@assert crystal[:label] == [:+, :-, :-]
```

Note that the positions form an `n` by `N` array where `N` is the number of atoms. This is
the logical mathematical format when performing matrix operations on the positions.
However, from an input point of view, it is easier to think one atom at at time, rather than
one coordinate (and all atoms) at a time. Hence the transpose.Similarly, the input-cell is
given in matrix format, not in the vector column format of many DFT codes. Do look at the
tests and at the sample `Lattices` for other input formats.

Access to the crystal cell happens via `.` call, `crystal.cell`. Atomic properties can be
accessed and modified through the square bracket operator.

Several methods are available to manipulate the crystal more extensively (`supercell`,
`primitive`, `space_group`, `hart_forcade`, etc..).
