# Everything the browser needs to build and filter its dropdowns.

# Reference groups selected when the page opens (config/default_references.csv)
default_references(config::Config) =
    [row[1] for row in read_config_rows(joinpath(config.config_dir, "default_references.csv"))]

function build_meta(snapshot::ReferenceSnapshot, config::Config)
    labels = [g.label for g in snapshot.groups]
    wanted = Set(lowercase.(default_references(config)))
    groups = map(snapshot.groups) do group
        elements = [
            (element = bone, rows = length(table.accession), sides = sort(unique(table.side)),
             measurements = available_measurements(table))
            for bone in snapshot.bones for table in (get(group.bones, bone, nothing),) if table !== nothing
        ]
        (label = group.label, elements = elements)
    end
    return (
        version = config.version,
        loaded_at = string(snapshot.loaded_at) * "Z",
        default_references = [label for label in labels if lowercase(label) in wanted],
        groups = groups,
        bones = snapshot.bones,
        measurements = snapshot.measurements,
    )
end
