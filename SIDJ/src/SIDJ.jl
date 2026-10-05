module SIDJ

# Stature identification: estimating living stature from skeletal
# measurements, and testing whether a known stature fits a skeleton, by
# regression on reference populations.

using Random
using Statistics
using Rmath

include("data.jl")         # reference groups and the samples drawn from them
include("regression.jl")   # a straight line fitted by least squares, and its intervals
include("estimate.jl")     # stature estimation: one model per set of measurements
include("associate.jl")    # stature association: does a known stature fit

export BoneTable, ReferenceGroup
export EstimationSample, AssociationSample, estimation_sample, association_sample
export LineFit, fit_line, prediction, bootstrap_prediction
export Model, Estimate, Association, estimate, associate, model_plot, association_plot
export available_measurements, BOOTSTRAP_BELOW, BOOTSTRAP_DRAWS, MIN_REFERENCE

end # module SIDJ
