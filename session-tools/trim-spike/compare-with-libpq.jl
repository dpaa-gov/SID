# Runs SID's reference queries through LibPQ and through the thin client, and compares every cell.
using LibPQ, Tables
include("PG.jl")
value(v) = "'" * replace(string(v), "\\" => "\\\\", "'" => "\\'") * "'"
conninfo = join(("host=" * value(ENV["DB_HOST"]), "port=" * value(get(ENV, "DB_PORT", "5432")), "dbname=" * value(ENV["DB_NAME"]),
    "user=" * value(ENV["DB_USER"]), "password=" * value(ENV["DB_PASS"]), "connect_timeout='10'", "options='-c statement_timeout=15000'"), " ")
old = LibPQ.Connection(conninfo; connect_timeout = 10)
new = PG.connect(conninfo)
same(a::Missing, b::Missing) = true
same(a, b::Missing) = false
same(a::Missing, b) = false
same(a::Bool, b::Bool) = a == b
same(a::AbstractString, b::String) = a == b
same(a::Number, b::Float64) = Float64(a) == b
cells = Ref(0); queries = Ref(0); differences = String[]
function check(label, sql)
    a = Tables.columntable(LibPQ.execute(old, sql))
    b = PG.query(new, sql)
    queries[] += 1
    String.(collect(keys(a))) == b.names || push!(differences, "$label: column names differ")
    for name in keys(a)
        column = getproperty(a, name)
        T = nonmissingtype(eltype(column))
        ours = T <: Bool ? PG.bools(b, String(name)) : T <: Number ? PG.floats(b, String(name)) : PG.strings(b, String(name))
        length(ours) == length(column) || (push!(differences, "$label.$name: $(length(ours)) rows, LibPQ $(length(column))"); continue)
        for i in eachindex(column)
            cells[] += 1
            same(column[i], ours[i]) || push!(differences, "$label.$name row $i: LibPQ $(repr(column[i])) ($(typeof(column[i]))), ours $(repr(ours[i]))")
        end
    end
    return a
end
check("groups", """
    SELECT DISTINCT i.collection || ' ' || i.ancestry || ' ' || i.sex AS group_label, i.collection, i.ancestry, i.sex
    FROM osteometry.individuals i INNER JOIN osteometry.collections c ON i.collection = c.collection
    WHERE c.stature_method = TRUE AND i.stature_method = TRUE ORDER BY i.collection, i.ancestry, i.sex""")
listed = check("measurements", "SELECT ards, bone, full_name, stature_method, utk2016 FROM osteometry.measurements ORDER BY bone, ards")
quoted(name) = "\"" * replace(name, "\"" => "\"\"") * "\""
bones = unique(listed.bone[i] for i in eachindex(listed.ards) if listed.stature_method[i] === true)
for bone in bones
    codes = [lowercase(listed.ards[i]) for i in eachindex(listed.ards) if listed.bone[i] == bone]
    columns = join(("b." * quoted(code) for code in codes), ", ")
    check(bone, """
        SELECT i.collection, i.ancestry, i.sex, i.accession, b.side, i.stature, $columns
        FROM osteometry.$(quoted(replace(lowercase(bone), " " => "_"))) b
        INNER JOIN osteometry.individuals i ON b.accession = i.accession
        INNER JOIN osteometry.collections c ON c.collection = i.collection
        WHERE i.stature_method = TRUE AND c.stature_method = TRUE ORDER BY i.accession, b.side""")
end
println(queries[], " queries (", join(bones, ", "), "), ", cells[], " cells compared, ", length(differences), " differences")
foreach(println, first(differences, 8))
# the errors SID tells apart
for (label, sql, test) in (("no such table", "SELECT 1 FROM osteometry.no_such_bone", PG.undefined_table), ("no such column", "SELECT no_such_column FROM osteometry.measurements", PG.undefined_column))
    try
        PG.query(new, sql); println(label, ": NOT refused")
    catch e
        println(label, ": ", e isa PG.Error && test(e) ? "recognised" : "NOT recognised", " -> ", sprint(showerror, e)[1:min(end, 90)])
    end
end
println("statement timeout in force: ", PG.strings(PG.query(new, "SHOW statement_timeout"), "statement_timeout")[1])
t = @elapsed try PG.query(new, "SELECT pg_sleep(20)") catch e; println("a 20 s query: ", sprint(showerror, e)[1:min(end, 80)]) end
println("  stopped after ", round(t; digits = 1), " s")
close(new); close(old)
t = @elapsed try PG.connect(replace(conninfo, r"host='[^']*'" => "host='10.255.255.1'")) catch e; println("unreachable host: ", first(sprint(showerror, e), 90)) end
println("  gave up after ", round(t; digits = 1), " s")
