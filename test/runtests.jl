module CrystalTest
using Crystals
using Base.Test
using Unitful: @u_str
using FactCheck: @fact, facts, context, exitstatus, roughly,
                 exactly, @fact_throws, greater_than, not
using DataFrames: nrow, ncol, NA, DataArray, DataFrame, deleterows!, NA,
                  DataFrameRow, eachrow, @data

contains(x) = y -> x ∈ y
all_integers(x::Array, ε::AbstractFloat=1e-8) = all(abs(x - round(Integer, x)) .< ε)
all_integers(ε::AbstractFloat=1e-8) = y -> all_integers(y, ε)
is_subtype(x::Type) = y -> (y <: x)

# @testset "Positions" begin
#     include("Positions.jl")
# end
# @testset "Crystal" begin
#     include("Crystal.jl")
# end
# @testset "SNF" begin
#     include("SNF.jl")
# end
@testset "Utilities" begin
    include("utilities.jl")
end
# @testset "SpaceGroup" begin
#     include("SpaceGroup.jl")
# end
# @testset "Gruber" begin
#     include("Gruber.jl")
# end

exitstatus()
end
