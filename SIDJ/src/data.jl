# The data an analysis works on: reference measurements grouped by
# population, and the sample an analysis draws from the selected groups.

# One bone's rows for one reference group. `values` is rows × measurements;
# `stature` is each row's individual's living stature in centimetres.
struct BoneTable
    accession::Vector{String}
    side::Vector{String}
    stature::Vector{Union{Missing, Float64}}
    measurements::Vector{String}
    values::Matrix{Union{Missing, Float64}}
end

# A reference population (collection, ancestry, sex) and its bones by name.
struct ReferenceGroup
    label::String
    collection::String
    ancestry::String
    sex::String
    bones::Dict{String, BoneTable}
end

# Measurements with at least one value, in column order.
function available_measurements(table::BoneTable)
    return [code for (j, code) in enumerate(table.measurements)
            if any(!ismissing, view(table.values, :, j))]
end

const CM_PER_INCH = 2.54

stature_in(value, inches::Bool) = inches ? value / CM_PER_INCH : value

# Individuals of the selected groups, one row each: stature and the given
# measurements, gathered from all of an individual's bones on one side.
# `group` is the position in `groups` of the group each row belongs to.
struct EstimationSample
    measurements::Vector{String}
    stature::Vector{Union{Missing, Float64}}
    values::Matrix{Union{Missing, Float64}}
    group::Vector{Int}
end

function estimation_sample(groups::AbstractVector{ReferenceGroup}, side::AbstractString, codes::AbstractVector{<:AbstractString};
                           inches::Bool = false)
    stature = Union{Missing, Float64}[]
    rows = Vector{Union{Missing, Float64}}[]
    group = Int[]
    for (g, reference) in enumerate(groups)
        row_of = Dict{String, Int}() # an individual's row, by accession
        for bone in sort!(collect(keys(reference.bones)))
            table = reference.bones[bone]
            columns = [(k, j) for (k, code) in enumerate(codes)
                       for j in something(findfirst(==(code), table.measurements), 0) if j > 0]
            for i in eachindex(table.accession)
                table.side[i] == side || continue
                r = get!(row_of, table.accession[i]) do
                    push!(stature, missing)
                    push!(rows, fill!(Vector{Union{Missing, Float64}}(undef, length(codes)), missing))
                    push!(group, g)
                    length(rows)
                end
                ismissing(stature[r]) && (stature[r] = table.stature[i])
                for (k, j) in columns
                    ismissing(rows[r][k]) && (rows[r][k] = table.values[i, j])
                end
            end
        end
    end
    values = Matrix{Union{Missing, Float64}}(undef, length(rows), length(codes))
    for (r, row) in enumerate(rows)
        values[r, :] = row
    end
    return EstimationSample(String.(codes), [ismissing(s) ? s : stature_in(s, inches) for s in stature], values, group)
end

# One bone on one side: every row with a stature and all of the given
# measurements, as the sum of those measurements.
struct AssociationSample
    measurements::Vector{String}
    stature::Vector{Float64}
    sum::Vector{Float64}
    group::Vector{Int}
end

function association_sample(groups::AbstractVector{ReferenceGroup}, bone::AbstractString, side::AbstractString,
                            codes::AbstractVector{<:AbstractString}; inches::Bool = false)
    stature, total, group = Float64[], Float64[], Int[]
    for (g, reference) in enumerate(groups)
        table = get(reference.bones, bone, nothing)
        table === nothing && continue
        columns = [findfirst(==(code), table.measurements) for code in codes]
        any(isnothing, columns) && continue
        for i in eachindex(table.accession)
            table.side[i] == side && !ismissing(table.stature[i]) || continue
            values = [table.values[i, j] for j in columns]
            any(ismissing, values) && continue
            push!(stature, stature_in(table.stature[i], inches))
            push!(total, sum(values))
            push!(group, g)
        end
    end
    return AssociationSample(String.(codes), stature, total, group)
end
