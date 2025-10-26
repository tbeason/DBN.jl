"""
Comprehensive DBN performance comparison - all APIs

Usage: julia --project=. benchmark/compare_all_comprehensive.jl
"""

using DBN, Printf, Statistics

const RUST_CLI = Sys.iswindows() ? "C:/Users/tbeas/dbn-workspace/dbn/target/release/dbn.exe" : joinpath(ENV["HOME"], "dbn-workspace/dbn/target/release/dbn")

# Benchmark functions (module-level to avoid world age issues)

function bench_julia_flex(f, n)
    read_dbn(f); times = Float64[]
    for _ in 1:n; GC.gc(); sleep(0.1); t = time_ns(); read_dbn(f); push!(times, (time_ns()-t)/1e9); end
    (mean(times), length(read_dbn(f)))
end

function bench_julia_stream(f, n)
    for _ in DBNStream(f); end; times = Float64[]
    for _ in 1:n; GC.gc(); sleep(0.1); t = time_ns(); for _ in DBNStream(f); end; push!(times, (time_ns()-t)/1e9); end
    (mean(times), sum(1 for _ in DBNStream(f)))
end

function bench_julia_opt(f, n, schema)
    reader = schema == :trades ? read_trades : schema == :mbo ? read_mbo : nothing
    reader === nothing && return nothing
    reader(f); times = Float64[]
    for _ in 1:n; GC.gc(); sleep(0.1); t = time_ns(); reader(f); push!(times, (time_ns()-t)/1e9); end
    (mean(times), length(reader(f)))
end

function bench_julia_write(f, n)
    meta, recs = read_dbn_with_metadata(f); times = Float64[]
    for _ in 1:n; GC.gc(); sleep(0.1); tmp = tempname()*".dbn"; t = time_ns(); write_dbn(tmp, meta, recs); push!(times, (time_ns()-t)/1e9); rm(tmp, force=true); end
    (mean(times), length(recs))
end

function bench_python(f, n)
    try; read(`python3 -c "from databento import DBNStore"`, String); catch; return nothing; end
    script = tempname()*".py"
    write(script, """
import sys, time, statistics
from databento import DBNStore
f, n = sys.argv[1], int(sys.argv[2])
store = DBNStore.from_file(f)
cnt = sum(1 for _ in store)
times = []
for _ in range(n):
    time.sleep(0.1)
    t = time.perf_counter()
    for _ in DBNStore.from_file(f): pass
    times.append(time.perf_counter()-t)
print(f"{statistics.mean(times)},{cnt}")
""")
    try; out = read(`python3 $script $f $n`, String); rm(script); p = split(strip(out), ','); (parse(Float64, p[1]), parse(Int, p[2]))
    catch; rm(script, force=true); nothing; end
end

function bench_rust(f, n)
    !isfile(RUST_CLI) && return nothing
    cnt = length(read_dbn(f)); times = Float64[]
    for _ in 1:n; sleep(0.2); tmp = tempname()*".json"; t = time_ns(); run(pipeline(`$RUST_CLI $f --json --output $tmp`, stdout=devnull, stderr=devnull)); push!(times, (time_ns()-t)/1e9); rm(tmp, force=true); end
    (mean(times), cnt)
end

schema(f) = occursin("trades", f) ? :trades : occursin("mbo", f) ? :mbo : :unknown
fmt(t, c) = @sprintf("%.2f M/s", c/t/1e6)

function run_benchmarks(outfile, runs=5)
    io = open(outfile, "w")
    println(io, "="^80)
    println(io, "DBN.jl COMPREHENSIVE PERFORMANCE COMPARISON")
    println(io, "="^80); println(io)
    
    files = filter(f->endswith(f,".dbn")&&!endswith(f,".zst"), readdir("benchmark/data", join=true))
    key = ["trades.1m.dbn", "trades.10m.dbn", "mbo.1m.dbn", "trades.100k.dbn"]
    files = filter(f->any(k->occursin(k,f), key), files); sort!(files)
    
    for f in files
        fn = basename(f); sz = filesize(f)/1024^2; sch = schema(fn)
        println(io, "\n$fn ($(round(sz, digits=2)) MB)"); println(io, "-"^80)
        
        print("Testing $fn... "); flush(stdout)
        t, c = bench_julia_flex(f, runs); println(io, @sprintf("  %-30s %s", "Julia read_dbn()", fmt(t, c)))
        t, c = bench_julia_stream(f, runs); println(io, @sprintf("  %-30s %s", "Julia DBNStream()", fmt(t, c)))
        
        if sch in [:trades, :mbo] && c >= 100000
            r = bench_julia_opt(f, runs, sch)
            if r !== nothing; t, c = r; nm = sch==:trades ? "read_trades()" : "read_mbo()"
                println(io, @sprintf("  %-30s %s  (optimized)", "Julia $nm", fmt(t, c)))
            end
        end
        
        if c <= 1_000_000
            r = bench_julia_write(f, runs)
            if r !== nothing; t, c = r; println(io, @sprintf("  %-30s %s", "Julia write_dbn()", fmt(t, c))); end
        end
        
        r = bench_python(f, runs)
        if r !== nothing; t, c = r; println(io, @sprintf("  %-30s %s", "Python databento", fmt(t, c))); end
        
        r = bench_rust(f, runs)
        if r !== nothing; t, c = r; println(io, @sprintf("  %-30s %s", "Rust dbn CLI", fmt(t, c))); end
        
        println("✓")
    end
    
    println(io, "\n" * "="^80); println(io, "Benchmark complete"); println(io, "="^80)
    close(io); println("\nResults saved to: $outfile")
end

# Main
if abspath(PROGRAM_FILE) == @__FILE__
    outfile = length(ARGS) > 0 ? ARGS[1] : "benchmark/benchmark_results.txt"
    run_benchmarks(outfile, 5)
end
