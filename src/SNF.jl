module SNF
using LinearAlgebra
import Unitful: Quantity, ustrip
export smith_normal_form

function choose_pivot!(left::AbstractMatrix{T}, smith::AbstractMatrix{T},
                       istep::Integer, index::Integer=1) where T <: Integer
  index > size(smith, 2) && return 0
  while all(smith[:, index] .== 0)
    index += 1
    index ≤ size(smith, 2) || return 0;
  end
  if smith[istep, index] == 0
    k = findfirst(x -> x ≠ 0, smith[:, index])
    left[istep, :], left[k, :] = deepcopy(left[k, :]), deepcopy(left[istep, :])
    smith[istep, :], smith[k, :] = deepcopy(smith[k, :]), deepcopy(smith[istep, :])
  end
  index
end

function improve_col_pivot!(left::AbstractMatrix{T}, smith::AbstractMatrix{T},
                            row::Integer, col::Integer) where T <: Integer
  @assert size(left, 1) == size(left, 2) == size(smith, 1) == size(smith, 2)
  for k in 1:size(smith, 1)
    smith[k, col] % smith[row, col] == 0 && continue

    β, σ, τ = gcdx(smith[row, col], smith[k, col])
    α = smith[row, col] / β
    γₒ = smith[k, col] / β

    Lp = Matrix{T}(I, size(left))
    Lp[row, [row, k]] = [σ, τ]
    Lp[k, [row, k]] = [-γₒ, α]

    left[:] = Lp * left
    smith[:] = Lp * smith
  end
end

function improve_row_pivot!(smith::AbstractMatrix{T}, right::AbstractMatrix{T},
                            row::Integer, col::Integer) where T <: Integer
  @assert size(right, 1) == size(right, 2) == size(smith, 1) == size(smith, 2)
  for k in 1:size(smith, 1)
    smith[row, k] % smith[row, col] == 0 && continue

    β, σ, τ = gcdx(smith[row, col], smith[row, k])
    α = smith[row, col] / β
    γ₀ = smith[row, k] / β

    Rp = Matrix{T}(I, size(right))
    Rp[[col, k], col] = [σ, τ]
    Rp[[col, k], k] = [-γ₀, α]

    right[:] = right * Rp
    smith[:] = smith * Rp
  end
end

function diagonalize_at_entry!(left::AbstractMatrix{T}, smith::AbstractMatrix{T},
                               right::AbstractMatrix{T}, row::Integer, col::Integer) where T <: Integer
  @assert size(right, 1) == size(right, 2) == size(smith, 1) == size(smith, 2)
  while count(!iszero, smith[:, col]) > 1 || count(!iszero, smith[row, :]) > 1
    improve_col_pivot!(left, smith, row, col)
    for i in 1:size(left, 2)
      i == row && continue
      smith[i, col] == 0 && continue
      β = smith[i, col] ÷ smith[row, col]
      left[i, :] -= left[row, :] * β
      smith[i, :] -= smith[row, :] * β
    end

    improve_row_pivot!(smith, right, row, col)
    for i in 1:size(left, 1)
      i == col && continue
      smith[row, i] == 0 && continue
      β = smith[row, i] ÷ smith[row, col]
      right[:, i] -= right[:, col] * β
      smith[:, i] -= smith[:, col] * β
    end
  end
end

function diagonalize_all_entries!(left::AbstractMatrix{T}, smith::AbstractMatrix{T}, right::AbstractMatrix{T}) where T <: Integer
  @assert size(smith, 1) == size(smith, 2)
  istep = 1
  col = choose_pivot!(left, smith, istep)
  while 0 < col ≤ size(smith, 2)
    diagonalize_at_entry!(left, smith, right, istep, col)

    istep += 1
    col += 1
    col = choose_pivot!(left, smith, istep, col)
  end
  return smith, left, right
end

function diagonalize_all_entries(smith::AbstractMatrix{T}) where T <: Integer
  smith = deepcopy(smith)
  d1, d2 = size(smith)
  left = Matrix{eltype(smith)}(I, d1, d1)
  right = Matrix{eltype(smith)}(I, d2, d2)
  diagonalize_all_entries!(left, smith, right)
  return smith, left, right
end

function move_zero_entries!(smith::AbstractMatrix{T}, right::AbstractMatrix{T}) where T <: Integer
  nonzero = findall(1:size(smith, 2)) do i; any(smith[:, i] .≠ 0) end
  length(nonzero) == size(smith, 2) && return
  for (i, j) in enumerate(nonzero)
    i == j && continue
    smith[:, i], smith[:, j] = deepcopy(smith[:, j]), deepcopy(smith[:, i])
    right[:, i], right[:, j] = deepcopy(right[:, j]), deepcopy(right[:, i])
  end
end

function make_divisible!(left::AbstractMatrix{T}, smith::AbstractMatrix{T}, right::Matrix{T}) where T <: Integer
  divides = x -> (smith[x, x] ≠ 0 && smith[x, x] % smith[x - 1, x - 1] ≠ 0)
  while (i = findfirst(divides, 2:size(smith, 2))) ≠ nothing
    (smith[i + 1, i + 1] == 0 || smith[i + 1, i + 1] % smith[i, i] == 0 ) && continue
    smith[:, i] += smith[:, i + 1]
    right[:, i] += right[:, i + 1]
    diagonalize_all_entries!(left, smith, right)
  end
end

function smith_normal_form(matrix::AbstractMatrix{T}) where T <: Integer
  smith, left, right = diagonalize_all_entries(matrix)
  move_zero_entries!(smith, right)
  make_divisible!(left, smith, right)
  left = convert(Matrix{T}, diagm(0 => [u ≥ 0 ? 1 : -1 for u in diag(smith)])) * left
  smith = abs.(smith)
  smith, left, right
end

function smith_normal_form(matrix::AbstractMatrix{Quantity{I, D, U}}) where {I <: Integer, U, D}
    s, l, r = smith_normal_form(ustrip.(matrix))
    s * unit(Quantity{I, U, D}), l, r
end

function smith_normal_form(matrix::AbstractMatrix{Quantity{BigInt, D, U}}) where {D, U}
    m = reshape([ustrip(u) for u in matrix], size(matrix))
    s, l, r = smith_normal_form(m)
    s2 = reshape([Quantity{BigInt, D, U}(u) for u in s], size(s))
    s2, l, r
end

end
