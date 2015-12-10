#-------------------------------------------------------# Type and Constructors
type NormalMix <: DistributionStat
    d::Dist.MixtureModel{Dist.Univariate, Dist.Continuous, Dist.Normal}    # MixtureModel
    s1::VecF             # mean of weights
    s2::VecF             # mean of (weights .* y)
    s3::VecF             # mean of (weights .* y .* y)
    n::Int64                        # number of observations
    weighting::LearningRate
end


function NormalMix(p::Integer, y::AVecF, wgt::LearningRate = LearningRate(r = .51); start = emstart(p, y, verbose = false))
    o = NormalMix(p, wgt, start = start)
    updatebatch!(o, y)
    o
end

function NormalMix(p::Integer, wgt::LearningRate = LearningRate(r = .51);
                   start = Dist.MixtureModel(map((u,v) -> Dist.Normal(u, v), randn(p), ones(p))))
    NormalMix(start, zeros(p), zeros(p), zeros(p), 0, wgt)
end

#------------------------------------------------------------------------# state
means(o::NormalMix) = means(o.d)
stds(o::NormalMix) = stds(o.d)

Dist.components(o::NormalMix) = Dist.components(o.d)
Dist.probs(o::NormalMix) = Dist.probs(o.d)


#---------------------------------------------------------------------# update!
function updatebatch!(o::NormalMix, y::AVecF)
    n = length(y)
    nc = length(Dist.components(o))
    π = Dist.probs(o)
    γ = weight(o)

    w = zeros(n, nc)
    for j = 1:nc, i = 1:n
        @inbounds w[i, j] = π[j] * Dist.pdf(Dist.components(o)[j], y[i])
    end
    w ./= sum(w, 2)
    s1 = vec(sum(w, 1))
    s2 = vec(sum(w .* y, 1))
    s3 = vec(sum(w .* y .* y, 1))
    smooth!(o.s1, s1, γ)
    smooth!(o.s2, s2, γ)
    smooth!(o.s3, s3, γ)

    π = o.s1
    π ./= sum(π)
    μ = o.s2 ./ o.s1
    σ = (o.s3 - (o.s2 .* o.s2 ./ o.s1)) ./ o.s1
    if any(σ .<= 0.) # reset standard deviations if one goes to 0
        σ = ones(nc)
    end

    o.d = Dist.MixtureModel(map((u,v) -> Dist.Normal(u, v), vec(μ), vec(sqrt(σ))), vec(π))
    o.n += n
    return
end


function update!(o::NormalMix, y::Float64)
    γ = weight(o)
    p = length(o.s1)

    w = zeros(p)
    for j in 1:p
        w[j] = Dist.pdf(o.d.components[j], y)
    end
    w /= sum(w)
    for j in 1:p
        o.s1[j] = smooth(o.s1[j], w[j], γ)
        o.s2[j] = smooth(o.s2[j], w[j] * y, γ)
        o.s3[j] = smooth(o.s3[j], w[j] * y * y, γ)
    end

    π = o.s1
    π ./= sum(π)
    μ = o.s2 ./ o.s1
    σ = (o.s3 - (o.s2 .* o.s2 ./ o.s1)) ./ o.s1
    if any(σ .<= 0.)
        σ = ones(p)
    end

    o.d = Dist.MixtureModel(map((u,v) -> Dist.Normal(u, v), vec(μ), vec(sqrt(σ))), vec(π))
    o.n += 1
    return
end


function Base.quantile(o::NormalMix, τ::Real; start = mean(o), maxit = 20, tol = .001)
    0 < τ < 1 || error("τ must be in (0, 1)")
    θ = start
    for i in 1:maxit
        θ += (τ - Dist.cdf(o, θ)) ./ Dist.pdf(o, θ)
        abs(Dist.cdf(o, θ) - τ) < tol && break
    end
    return θ
end