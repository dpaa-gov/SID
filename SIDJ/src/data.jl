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
# measurements, gathered from all of an individual's bones. Each measurement
# is taken from its own side (`sides`, one per code), so a left femur can sit
# beside a right tibia; a single side applies to them all.
# `group` is the position in `groups` of the group each row belongs to.
struct EstimationSample
    measurements::Vector{String}
    stature::Vector{Union{Missing, Float64}}
    values::Matrix{Union{Missing, Float64}}
    group::Vector{Int}
end

estimation_sample(groups::AbstractVector{ReferenceGroup}, side::AbstractString, codes::AbstractVector{<:AbstractString};
                  inches::Bool = false) = estimation_sample(groups, fill(String(side), length(codes)), codes; inches)

function estimation_sample(groups::AbstractVector{ReferenceGroup}, sides::AbstractVector{<:AbstractString},
                           codes::AbstractVector{<:AbstractString}; inches::Bool = false)
    length(sides) == length(codes) || throw(ArgumentError("one side is needed for each measurement"))
    wanted = unique(sides)
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
                table.side[i] in wanted || continue
                r = get!(row_of, table.accession[i]) do
                    push!(stature, missing)
                    push!(rows, fill!(Vector{Union{Missing, Float64}}(undef, length(codes)), missing))
                    push!(group, g)
                    length(rows)
                end
                ismissing(stature[r]) && (stature[r] = table.stature[i])
                for (k, j) in columns
                    sides[k] == table.side[i] && ismissing(rows[r][k]) && (rows[r][k] = table.values[i, j])
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

# One bone of a specimen: which bone, its side, and the measurements taken on it.
struct SpecimenBone
    bone::String
    side::String
    measurements::Vector{String}
end

# The individuals an association is fitted to: those with a stature and every
# measurement of every one of the specimen's bones, each bone on its own side,
# as the sum of all those measurements. For one bone that is every row of that
# bone on that side, in the order the reference data holds them.
struct AssociationSample
    measurements::Vector{String}
    stature::Vector{Float64}
    sum::Vector{Float64}
    group::Vector{Int}
end

# One bone's rows in one group, on its side, that have a stature and all of
# its measurements: whose they are, the stature and the measurements' sum
const BoneRows = @NamedTuple{accession::Vector{String}, stature::Vector{Float64}, sum::Vector{Float64}}

# Nothing where the group has no such bone, or the bone no such measurement
function bone_rows(reference::ReferenceGroup, part::SpecimenBone, inches::Bool)::Union{Nothing, BoneRows}
    table = get(reference.bones, part.bone, nothing)
    table === nothing && return nothing
    found = [findfirst(==(code), table.measurements) for code in part.measurements]
    any(isnothing, found) && return nothing
    columns = Int[j for j in found if j !== nothing]
    accession, stature, total = String[], Float64[], Float64[]
    for i in eachindex(table.accession)
        table.side[i] == part.side && !ismissing(table.stature[i]) || continue
        values = Float64[]
        for j in columns
            value = table.values[i, j]
            ismissing(value) || push!(values, value)
        end
        length(values) == length(columns) || continue # one of the measurements is missing
        push!(accession, table.accession[i])
        push!(stature, stature_in(table.stature[i], inches))
        push!(total, sum(values))
    end
    return (accession = accession, stature = stature, sum = total)
end

association_sample(groups::AbstractVector{ReferenceGroup}, bone::AbstractString, side::AbstractString,
                   codes::AbstractVector{<:AbstractString}; inches::Bool = false) =
    association_sample(groups, [SpecimenBone(String(bone), String(side), String.(codes))]; inches)

function association_sample(groups::AbstractVector{ReferenceGroup}, bones::AbstractVector{SpecimenBone}; inches::Bool = false)
    stature, total, group = Float64[], Float64[], Int[]
    codes = String[code for part in bones for code in part.measurements]
    for (g, reference) in enumerate(groups)
        parts = BoneRows[]
        for part in bones
            rows = bone_rows(reference, part, inches)
            rows === nothing && break
            push!(parts, rows)
        end
        # a group without one of the bones has nobody with them all
        !isempty(parts) && length(parts) == length(bones) || continue
        # The first bone's individuals, kept where every other bone has them
        # too. Several bones are joined by individual, so an individual is one
        # row whichever bone comes first: were the reference data to hold two
        # rows of theirs for a bone and side, the first is theirs, as it is in
        # estimation. Those with every bone are then some of those with each.
        # One bone alone is not joined: it is every row, as it has always been.
        others = Dict{String, Float64}[]
        for rows in parts[2:end]
            sums = Dict{String, Float64}()
            for (accession, value) in zip(rows.accession, rows.sum)
                get!(sums, accession, value)
            end
            push!(others, sums)
        end
        first = parts[1]
        seen = Set{String}()
        for i in eachindex(first.accession)
            accession = first.accession[i]
            if !isempty(others)
                accession in seen && continue
                push!(seen, accession)
            end
            all(other -> haskey(other, accession), others) || continue
            sum_of_all = first.sum[i]
            for other in others
                sum_of_all += other[accession]
            end
            push!(stature, first.stature[i])
            push!(total, sum_of_all)
            push!(group, g)
        end
    end
    return AssociationSample(codes, stature, total, group)
end
