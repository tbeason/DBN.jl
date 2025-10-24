"""
    benchmarks.jl

Comprehensive benchmark suite using BenchmarkTools for detailed performance analysis.

This suite provides statistical distributions of performance metrics including
min/median/max times, memory allocations, and garbage collection overhead.
"""

using BenchmarkTools
using DBN
using DataFrames
using CSV
using Printf
using Dates

"""
    create_benchmark_suite(data_dir="benchmark/data")

Create a BenchmarkTools benchmark suite for DBN.jl operations.

The suite includes:
- Read operations (full and streaming)
- Write operations (to memory and disk)
- Compression operations
- Format conversion operations
- Price and timestamp utilities
"""
function create_benchmark_suite(data_dir="benchmark/data")
    suite = BenchmarkGroup()

    # Check if test data exists
    if !isdir(data_dir)
        @warn "Test data directory not found: $data_dir. Skipping file-based benchmarks."
        return suite
    end

    # Find test files of different sizes
    small_file = nothing
    medium_file = nothing
    large_file = nothing

    for file in readdir(data_dir, join=true)
        if contains(basename(file), "1k.dbn") && !endswith(file, ".zst")
            small_file = file
        elseif contains(basename(file), "100k.dbn") && !endswith(file, ".zst")
            medium_file = file
        elseif contains(basename(file), "1m.dbn") && !endswith(file, ".zst")
            large_file = file
        end
    end

    small_zst = isnothing(small_file) ? nothing : small_file * ".zst"
    medium_zst = isnothing(medium_file) ? nothing : medium_file * ".zst"

    # === READ BENCHMARKS ===
    suite["read"] = BenchmarkGroup()

    if !isnothing(small_file) && isfile(small_file)
        suite["read"]["small_uncompressed"] = @benchmarkable read_dbn($small_file)
    end

    if !isnothing(small_zst) && isfile(small_zst)
        suite["read"]["small_compressed"] = @benchmarkable read_dbn($small_zst)
    end

    if !isnothing(medium_file) && isfile(medium_file)
        suite["read"]["medium_uncompressed"] = @benchmarkable read_dbn($medium_file)
    end

    if !isnothing(medium_zst) && isfile(medium_zst)
        suite["read"]["medium_compressed"] = @benchmarkable read_dbn($medium_zst)
    end

    # === STREAMING BENCHMARKS ===
    suite["stream"] = BenchmarkGroup()

    if !isnothing(small_file) && isfile(small_file)
        suite["stream"]["small"] = @benchmarkable begin
            count = 0
            for record in DBNStream($small_file)
                count += 1
            end
            count
        end
    end

    if !isnothing(medium_file) && isfile(medium_file)
        suite["stream"]["medium"] = @benchmarkable begin
            count = 0
            for record in DBNStream($medium_file)
                count += 1
            end
            count
        end
    end

    # === WRITE BENCHMARKS ===
    suite["write"] = BenchmarkGroup()

    if !isnothing(small_file) && isfile(small_file)
        metadata, records = read_dbn_with_metadata(small_file)
        tmpfile = tempname()

        suite["write"]["small_uncompressed"] = @benchmarkable write_dbn($tmpfile, $metadata, $records) setup=(GC.gc()) teardown=(rm($tmpfile, force=true))

        tmpfile_zst = tmpfile * ".zst"
        suite["write"]["small_compressed"] = @benchmarkable write_dbn($tmpfile_zst, $metadata, $records) setup=(GC.gc()) teardown=(rm($tmpfile_zst, force=true))
    end

    if !isnothing(medium_file) && isfile(medium_file)
        metadata, records = read_dbn_with_metadata(medium_file)
        tmpfile = tempname()

        suite["write"]["medium_uncompressed"] = @benchmarkable write_dbn($tmpfile, $metadata, $records) setup=(GC.gc()) teardown=(rm($tmpfile, force=true))
    end

    # === CONVERSION BENCHMARKS ===
    suite["convert"] = BenchmarkGroup()

    if !isnothing(small_file) && isfile(small_file)
        tmpjson = tempname() * ".json"
        tmpcsv = tempname() * ".csv"

        suite["convert"]["to_json"] = @benchmarkable dbn_to_json($small_file, $tmpjson) setup=(GC.gc()) teardown=(rm($tmpjson, force=true))
        suite["convert"]["to_csv"] = @benchmarkable dbn_to_csv($small_file, $tmpcsv) setup=(GC.gc()) teardown=(rm($tmpcsv, force=true))
    end

    # === UTILITY BENCHMARKS ===
    suite["utils"] = BenchmarkGroup()

    # Price conversions
    suite["utils"]["float_to_price"] = @benchmarkable float_to_price(100.50)
    suite["utils"]["price_to_float"] = @benchmarkable price_to_float(1005000000)

    # Timestamp conversions
    dt = DateTime(2024, 1, 1, 9, 30)
    ts = datetime_to_ts(dt)
    suite["utils"]["datetime_to_ts"] = @benchmarkable datetime_to_ts($dt)
    suite["utils"]["ts_to_datetime"] = @benchmarkable ts_to_datetime($ts)

    return suite
end

"""
    run_benchmark_suite(data_dir="benchmark/data"; save_results=true)

Run the complete benchmark suite and optionally save results.

# Arguments
- `data_dir`: Directory containing test data files
- `save_results`: Whether to save results to CSV files (default: true)

# Returns
BenchmarkTools results object
"""
function run_benchmark_suite(data_dir="benchmark/data"; save_results=true)
    println("\n" * "="^70)
    println("DBN.jl BenchmarkTools Suite")
    println("="^70)
    println("\nCreating benchmark suite...")

    suite = create_benchmark_suite(data_dir)

    if isempty(suite)
        error("No benchmarks in suite. Check that test data exists in $data_dir")
    end

    println("Suite created with $(length(keys(suite))) groups")
    for group in keys(suite)
        println("  - $group: $(length(keys(suite[group]))) benchmarks")
    end

    println("\nRunning benchmarks (this may take several minutes)...")
    println("Started at: $(Dates.format(now(), "yyyy-mm-dd HH:MM:SS"))")

    results = run(suite, verbose=true)

    println("\nCompleted at: $(Dates.format(now(), "yyyy-mm-dd HH:MM:SS"))")

    # Print results
    print_benchmark_results(results)

    # Save results if requested
    if save_results
        timestamp = Dates.format(now(), "yyyymmdd_HHMMSS")
        csv_file = "benchmark/results_$(timestamp).csv"
        json_file = "benchmark/results_$(timestamp).json"

        save_results_to_csv(results, csv_file)
        println("\nResults saved to:")
        println("  - $csv_file")

        # Save raw BenchmarkTools results
        BenchmarkTools.save(json_file, results)
        println("  - $json_file")
    end

    return results
end

"""
    print_benchmark_results(results)

Pretty-print benchmark results in a readable format.
"""
function print_benchmark_results(results)
    println("\n\n" * "="^70)
    println("BENCHMARK RESULTS")
    println("="^70)

    for group_name in sort(collect(keys(results)))
        group = results[group_name]
        println("\n" * group_name * ":")
        println("─"^70)

        for bench_name in sort(collect(keys(group)))
            bench_result = group[bench_name]
            print_single_result(bench_name, bench_result)
        end
    end

    println("\n" * "="^70)
end

"""
    print_single_result(name, result)

Print a single benchmark result.
"""
function print_single_result(name, result)
    trial = minimum(result)

    @printf "  %-25s" name

    # Time
    time_ns = time(trial)
    if time_ns < 1_000
        @printf " %8.2f ns" time_ns
    elseif time_ns < 1_000_000
        @printf " %8.2f μs" (time_ns / 1_000)
    elseif time_ns < 1_000_000_000
        @printf " %8.2f ms" (time_ns / 1_000_000)
    else
        @printf " %8.2f s " (time_ns / 1_000_000_000)
    end

    # Memory
    mem_bytes = memory(trial)
    if mem_bytes < 1024
        @printf " %8d B" mem_bytes
    elseif mem_bytes < 1024^2
        @printf " %8.2f KB" (mem_bytes / 1024)
    elseif mem_bytes < 1024^3
        @printf " %8.2f MB" (mem_bytes / 1024^2)
    else
        @printf " %8.2f GB" (mem_bytes / 1024^3)
    end

    # Allocations
    @printf " %6d allocs" allocs(trial)

    println()
end

"""
    save_results_to_csv(results, filename)

Save benchmark results to a CSV file for further analysis.
"""
function save_results_to_csv(results, filename)
    rows = []

    for group_name in keys(results)
        group = results[group_name]
        for bench_name in keys(group)
            bench_result = group[bench_name]
            trial = minimum(bench_result)

            push!(rows, (
                group = String(group_name),
                benchmark = String(bench_name),
                min_time_ns = time(trial),
                median_time_ns = median(bench_result).time,
                mean_time_ns = mean(bench_result).time,
                max_time_ns = maximum(bench_result).time,
                memory_bytes = memory(trial),
                allocs = allocs(trial),
                gc_time_ns = gctime(trial)
            ))
        end
    end

    df = DataFrame(rows)

    # Add computed columns
    df.min_time_ms = df.min_time_ns ./ 1e6
    df.median_time_ms = df.median_time_ns ./ 1e6
    df.memory_mb = df.memory_bytes ./ 1024^2

    mkpath(dirname(filename))
    CSV.write(filename, df)
end

"""
    compare_benchmarks(file1::String, file2::String)

Compare two benchmark result files to track performance changes.

# Arguments
- `file1`: Path to first benchmark results JSON file (baseline)
- `file2`: Path to second benchmark results JSON file (current)
"""
function compare_benchmarks(file1::String, file2::String)
    baseline = BenchmarkTools.load(file1)[1]
    current = BenchmarkTools.load(file2)[1]

    println("\n" * "="^70)
    println("BENCHMARK COMPARISON")
    println("="^70)
    println("Baseline: $file1")
    println("Current:  $file2")
    println("="^70)

    judge_results = judge(current, baseline)

    println(judge_results)
end

# Run if executed as script
if abspath(PROGRAM_FILE) == @__FILE__
    data_dir = length(ARGS) >= 1 ? ARGS[1] : "benchmark/data"
    run_benchmark_suite(data_dir)
end
