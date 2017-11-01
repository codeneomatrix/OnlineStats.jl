# http://www.jmlr.org/papers/volume11/ben-haim10a/ben-haim10a.pdf
"""
    IHistogram(b)

Incrementally build a histogram of `b` (not equally spaced) bins.  

# Example

    o = IHistogram(100)
    Series(randn(100_000), o)
"""
struct IHistogram <: OnlineStat{0, EqualWeight}
    value::Vector{Float64}
    counts::Vector{Int}
    buffer::Vector{Float64}
end
IHistogram(b::Integer) = IHistogram(fill(Inf, b), zeros(Int, b), zeros(b))

function fit!(o::IHistogram, y::Real, γ::Float64)
    i = searchsortedfirst(o.value, y)
    insert!(o.value, i, y)
    insert!(o.counts, i, 1)
    ind = find_min_diff(o)
    binmerge!(o, ind)
end

function binmerge!(o::IHistogram, i)
    k1 = o.counts[i]
    k2 = o.counts[i + 1] 
    q1 = o.value[i]
    q2 = o.value[i + 1]
    bottom = k1 + k2
    if bottom == 0
        o.value[i] = .5 * (o.value[i] + o.value[i + 1])
    elseif k2 == 0
        top = q1 * k1
        o.value[i] = top / bottom 
        o.counts[i] = bottom
    else
        top = (q1 * k1 + q2 * k2)
        o.value[i] = top / bottom 
        o.counts[i] = bottom
    end
    deleteat!(o.value, i + 1)
    deleteat!(o.counts, i + 1)
end

function find_min_diff(o::IHistogram)
    # find the index of the smallest difference v[i+1] - v[i]
    v = o.value
    @inbounds for i in eachindex(o.buffer)
        val = v[i + 1] - v[i]
        if isnan(val) || isinf(val)
            # If the difference is NaN = Inf - Inf or -Inf = Float64 - Inf
            # merge them to make way for actual values
            return i
        end
        o.buffer[i] = val
    end
    _, ind = findmin(o.buffer)
    return ind
end
