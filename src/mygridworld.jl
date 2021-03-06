# using StaticArrays, Parameters, POMDPs, Base
using POMDPModels, POMDPs
using StaticArrays, Parameters, Random, POMDPModelTools
const GWPos = SVector{2,Int}
# const max_reward = 10.0

"""
    MyGridWorld(;kwargs...)
Create a simple grid world MDP. Options are specified with keyword arguments.
# States and Actions
The states are represented by 2-element static vectors of integers. Typically any Julia `AbstractVector` e.g. `[x,y]` can also be used for arguments. Actions are the symbols `:up`, `:left`, `:down`, and `:right`.
# Keyword Arguments
- `size::Tuple{Int, Int}`: Number of cells in the x and y direction [default: `(10,10)`]
- `rewards::Dict`: Dictionary mapping cells to the reward in that cell, e.g. `Dict([1,2]=>10.0)`. Default reward for unlisted cells is 0.0
- `terminate_from::Set`: Set of cells from which the problem will terminate. Note that these states are not themselves terminal, but from these states, the next transition will be to a terminal state. [default: `Set(keys(rewards))`]
- `tprob::Float64`: Probability of a successful transition in the direction specified by the action. The remaining probability is divided between the other neighbors. [default: `0.7`]
- `discount::Float64`: Discount factor [default: `0.95`]
"""

function build_rewards(size::Tuple{Int, Int} , traversability_map::Array{Float64, 2}, terminal_pos::Tuple{Int, Int})
    rewards = Dict()
    nx = size[1]
    ny = size[2]
    for x in 1:nx, y in 1:ny
        if x == terminal_pos[1] && y == terminal_pos[2]
            rewards[GWPos(x, y)] = 1.0*nx*nx
        else
            rewards[GWPos(x, y)] = traversability_map[x, y]
        end
    end
    return rewards
end

@with_kw struct MyGridWorld <: MDP{GWPos, Symbol}
    size::Tuple{Int, Int}           = (10,10)
    #rewards::Dict{GWPos, Float64}   = Dict(GWPos(9,3)=>10.0)#Dict(GWPos(4,3)=>-10.0, GWPos(4,6)=>-5.0, GWPos(9,3)=>10.0, GWPos(8,8)=>3.0)
    #terminate_from::Set{GWPos}      = Set(keys(rewards))
    terminal_pos::Tuple{Int, Int} = (9, 3)
    terminate_from::Set{GWPos}      = Set([GWPos(terminal_pos[1], terminal_pos[2])])
    tprob::Float64                  = 0.7
    discount::Float64               = 0.95
    valid_map::Array{Float64, 2} = ones(size)
    traversability_map::Array{Float64, 2} = -0.1*ones(size)
    rewards = build_rewards(size, traversability_map, terminal_pos)

end




# States

function POMDPs.states(mdp::MyGridWorld)
    ss = vec(GWPos[GWPos(x, y) for x in 1:mdp.size[1], y in 1:mdp.size[2]])
    push!(ss, GWPos(-1,-1))
    return ss
end

function POMDPs.stateindex(mdp::MyGridWorld, s::AbstractVector{Int})
    if all(s.>0)
        return LinearIndices(mdp.size)[s...]
    else
        return prod(mdp.size) + 1 # TODO: Change
    end
end

struct GWUniform
    size::Tuple{Int, Int}
end
Base.rand(rng::AbstractRNG, d::GWUniform) = GWPos(rand(rng, 1:d.size[1]), rand(rng, 1:d.size[2]))
function POMDPs.pdf(d::GWUniform, s::GWPos)
    if all(1 .<= s[1] .<= d.size)
        return 1/prod(d.size)
    else
        return 0.0
    end
end
POMDPs.support(d::GWUniform) = (GWPos(x, y) for x in 1:d.size[1], y in 1:d.size[2])

POMDPs.initialstate(mdp::MyGridWorld) = GWUniform(mdp.size)

# Actions

POMDPs.actions(mdp::MyGridWorld) = (:up, :down, :left, :right)
Base.rand(rng::AbstractRNG, t::NTuple{L,Symbol}) where L = t[rand(rng, 1:length(t))] # don't know why this doesn't work out of the box


const dir = Dict(:up=>GWPos(0,1), :down=>GWPos(0,-1), :left=>GWPos(-1,0), :right=>GWPos(1,0))
const aind = Dict(:up=>1, :down=>2, :left=>3, :right=>4)

POMDPs.actionindex(mdp::MyGridWorld, a::Symbol) = aind[a]


# Transitions

POMDPs.isterminal(m::MyGridWorld, s::AbstractVector{Int}) = any(s.<0)

function POMDPs.transition(mdp::MyGridWorld, s::AbstractVector{Int}, a::Symbol)
    if s in mdp.terminate_from || isterminal(mdp, s)
        return Deterministic(GWPos(-1,-1))
    end

    destinations = MVector{length(actions(mdp))+1, GWPos}(undef)
    destinations[1] = s

    probs = @MVector(zeros(length(actions(mdp))+1))
    prob_stay = -mdp.traversability_map[s[1], s[2]]
    probs[1] = prob_stay
    for (i, act) in enumerate(actions(mdp))
        if act == a
            prob = 1 - prob_stay
        else
            prob = 0
            #prob = (1.0 - mdp.tprob)/(length(actions(mdp)) - 1) # probability of transitioning to another cell
        end

        dest = s + dir[act]
        destinations[i+1] = dest

        if !inbounds(mdp, dest) # hit an edge and come back
            probs[1] += prob
            destinations[i+1] = GWPos(-1, -1) # dest was out of bounds - this will have probability zero, but it should be a valid state
        else
            probs[i+1] += prob
        end
        # if act == a
        #     prob = mdp.tprob # probability of transitioning to the desired cell
        # else
        #     prob = (1.0 - mdp.tprob)/(length(actions(mdp)) - 1) # probability of transitioning to another cell
        # end
        #
        # dest = s + dir[act]
        # destinations[i+1] = dest
        #
        # if !inbounds(mdp, dest) # hit an edge and come back
        #     probs[1] += prob
        #     destinations[i+1] = GWPos(-1, -1) # dest was out of bounds - this will have probability zero, but it should be a valid state
        # else
        #     probs[i+1] += prob
        # end
    end
    #println(probs)
    return SparseCat(destinations, probs)
end

function inbounds(m::MyGridWorld, s::AbstractVector{Int})
    #return 1 <= s[1] <= m.size[1] && 1 <= s[2] <= m.size[2]
    if m.size[1] >= s[1] > 0 && m.size[2] >= s[2] > 0
        i = abs(s[2] - gw.size[1]) + 1
        j = s[1]
        return m.valid_map[i, j] > 0.0
    else
        return false
    end
end
# function inbounds(m::MyGridWorld, s::AbstractVector{Int})
#     #return 1 <= s[1] <= m.size[1] && 1 <= s[2] <= m.size[2]
#     if any(s .< 1) || any(s .> m.size)#s[1] > m.size[1] || s[2] > m.size[2]
#         return false
#     else
#         return m.valid_map[s[1], s[2]] > 0.0
#
#     end
# end

# Rewards

POMDPs.reward(mdp::MyGridWorld, s::AbstractVector{Int}) = get(mdp.rewards, s, 0.0)
POMDPs.reward(mdp::MyGridWorld, s::AbstractVector{Int}, a::Symbol) = reward(mdp, s)


# discount

POMDPs.discount(mdp::MyGridWorld) = mdp.discount

# Conversion
function POMDPs.convert_a(::Type{V}, a::Symbol, m::MyGridWorld) where {V<:AbstractArray}
    convert(V, [aind[a]])
end
function POMDPs.convert_a(::Type{Symbol}, vec::V, m::MyGridWorld) where {V<:AbstractArray}
    actions(m)[convert(Int, first(vec))]
end

# deprecated in POMDPs v0.9
POMDPs.initialstate_distribution(mdp::MyGridWorld) = GWUniform(mdp.size)
