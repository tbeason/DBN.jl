"""
    compare_all.jl

Comprehensive performance comparison of DBN implementations:
- Julia: DBN.jl (this package)
- Rust: Official Databento dbn CLI
- Python: databento-dbn package

This script runs benchmarks for all three implementations and generates
a comparison report showing relative performance.

Usage:
    julia --project=. benchmark/compare_all.jl [--data-dir DIR] [--runs N]

Requirements:
    - Rust dbn CLI: ~/dbn-workspace/dbn/target/release/dbn.exe
    - Python dbn: pip install ~/dbn-workspace/dbn/python/
"""

using DBN
using Printf
using Statistics
using Dates

# Configuration
const RUST_DBN_CLI = if Sys.iswindows()
    "C:/Users/tbeas/dbn-workspace/dbn/target/release/dbn.exe"
else
    joinpath(ENV["HOME"], "dbn-workspace/dbn/target/release/dbn")
end

const PYTHON_SCRIPT = "benchmark/compare_python.py"

"""
    benchmark_julia(file::String; runs=5)

Benchmark Julia DBN.jl read performance.
"""
function benchmark_julia(file::String; runs=5)
    # Warmup
    records = read_dbn(file)
    record_count = length(records)

    times = Float64[]
    for _ in 1:runs
        GC.gc()
        sleep(0.1)

        start_time = time_ns()
        records = read_dbn(file)
        elapsed = (time_ns() - start_time) / 1e9

        push!(times, elapsed)
    end

    return (
        records = record_count,
        mean_time = mean(times),
        std_time = std(times),
        throughput = record_count / mean(times)
    )
end

"""
    benchmark_rust(file::String; runs=5)

Benchmark Rust dbn CLI performance.
"""
function benchmark_rust(file::String; runs=5)
    if !isfile(RUST_DBN_CLI)
        return nothing
    end

    records = read_dbn(file)
    record_count = length(records)

    temp_out = tempname() * ".json"
    times = Float64[]

    for _ in 1:runs
        sleep(0.2)

        start_time = time_ns()
        run(pipeline(`$RUST_DBN_CLI $file --json --output $temp_out`,
                    stdout=devnull, stderr=devnull))
        elapsed = (time_ns() - start_time) / 1e9

        push!(times, elapsed)
        rm(temp_out, force=true)
    end

    return (
        records = record_count,
        mean_time = mean(times),
        std_time = std(times),
        throughput = record_count / mean(times)
    )
end

"""
    benchmark_python(file::String; runs=5)

Benchmark Python dbn package performance.
"""
function benchmark_python(file::String; runs=5)
    # Check if Python databento client is installed
    python_check = try
        read(`python3 -c "from databento import DBNStore"`, String)
        true
    catch
        false
    end

    if !python_check
        return nothing
    end

    # Run Python benchmark script for this file
    try
        # Create temporary Python script for single file
        temp_script = tempname() * ".py"
        write(temp_script, """
import sys
import time
import statistics
from databento import DBNStore

filepath = sys.argv[1]
runs = int(sys.argv[2])

# Get record count
record_count = 0
store = DBNStore.from_file(filepath)
for _ in store:
    record_count += 1

# Benchmark
times = []
for _ in range(runs):
    time.sleep(0.1)
    start = time.perf_counter()
    store = DBNStore.from_file(filepath)
    for _ in store:
        pass
    elapsed = time.perf_counter() - start
    times.append(elapsed)

mean_time = statistics.mean(times)
std_time = statistics.stdev(times) if len(times) > 1 else 0.0
throughput = record_count / mean_time

print(f"{record_count},{mean_time},{std_time},{throughput}")
""")

        output = read(`python3 $temp_script $file $runs`, String)
        rm(temp_script, force=true)

        # Parse output: records,mean_time,std_time,throughput
        parts = split(strip(output), ',')
        return (
            records = parse(Int, parts[1]),
            mean_time = parse(Float64, parts[2]),
            std_time = parse(Float64, parts[3]),
            throughput = parse(Float64, parts[4])
        )
    catch e
        @warn "Python benchmark failed" exception=e
        return nothing
    end
end

"""
    run_comparison(data_dir::String; runs=5)

Run comparison across all three implementations.
"""
function run_comparison(data_dir::String; runs=5)
    println("\n" * "="^80)
    println("  DBN Performance Comparison: Julia vs Rust vs Python")
    println("="^80)
    println()
    println("Data directory: $data_dir")
    println("Runs per test: $runs")
    println()

    # Check availability
    rust_available = isfile(RUST_DBN_CLI)
    python_available = try
        read(`python3 -c "from databento import DBNStore"`, String)
        true
    catch
        false
    end

    println("Implementation Status:")
    println("  Julia DBN.jl:  ✓ Available")
    println("  Rust dbn CLI:  ", rust_available ? "✓ Available" : "✗ Not found")
    println("  Python databento:  ", python_available ? "✓ Available" : "✗ Not installed")
    println()

    if !rust_available
        @warn "Rust dbn CLI not found at: $RUST_DBN_CLI"
    end
    if !python_available
        @warn "Python databento client not installed. Install with: pip install databento"
    end

    # Find test files
    test_files = filter(f -> endswith(f, ".dbn") && !endswith(f, ".zst"),
                       readdir(data_dir, join=true))

    if isempty(test_files)
        error("No test files found in $data_dir")
    end

    println("Found $(length(test_files)) test files\n")

    results = []

    for file in test_files
        filename = basename(file)
        filesize_mb = filesize(file) / 1024^2

        println("Testing: $filename ($(round(filesize_mb, digits=2)) MB)")
        println("-"^80)

        # Benchmark Julia
        print("  Julia DBN.jl:  ")
        flush(stdout)
        julia_result = benchmark_julia(file, runs=runs)
        julia_mrec_sec = julia_result.throughput / 1e6
        println(@sprintf("%.2f M rec/s (%.3f s ± %.3f s)",
                        julia_mrec_sec, julia_result.mean_time, julia_result.std_time))

        # Benchmark Rust
        rust_result = nothing
        if rust_available
            print("  Rust dbn CLI:  ")
            flush(stdout)
            try
                rust_result = benchmark_rust(file, runs=runs)
                rust_mrec_sec = rust_result.throughput / 1e6
                println(@sprintf("%.2f M rec/s (%.3f s ± %.3f s)",
                                rust_mrec_sec, rust_result.mean_time, rust_result.std_time))
            catch e
                println("ERROR")
                @warn "Rust benchmark failed" exception=e
            end
        end

        # Benchmark Python
        python_result = nothing
        if python_available
            print("  Python dbn:    ")
            flush(stdout)
            python_result = benchmark_python(file, runs=runs)
            if python_result !== nothing
                python_mrec_sec = python_result.throughput / 1e6
                println(@sprintf("%.2f M rec/s (%.3f s ± %.3f s)",
                                python_mrec_sec, python_result.mean_time, python_result.std_time))
            else
                println("ERROR")
            end
        end

        # Store results
        push!(results, (
            file = filename,
            records = julia_result.records,
            julia = julia_result,
            rust = rust_result,
            python = python_result
        ))

        println()
    end

    # Print comparison table
    print_comparison_table(results)

    return results
end

"""
    print_comparison_table(results)

Print a comprehensive comparison table.
"""
function print_comparison_table(results)
    println("\n" * "="^80)
    println("  PERFORMANCE COMPARISON")
    println("="^80)
    println()

    # Header
    println(@sprintf("%-25s %12s %12s %12s %12s %10s %10s",
                    "File", "Records", "Julia", "Rust", "Python",
                    "vs Rust", "vs Python"))
    println("-"^80)

    julia_vs_rust_ratios = Float64[]
    julia_vs_python_ratios = Float64[]

    for r in results
        julia_mrec = r.julia.throughput / 1e6

        rust_str = if r.rust !== nothing
            rust_mrec = r.rust.throughput / 1e6
            ratio = julia_mrec / rust_mrec
            push!(julia_vs_rust_ratios, ratio)
            @sprintf("%.2f M/s", rust_mrec)
        else
            "N/A"
        end

        python_str = if r.python !== nothing
            python_mrec = r.python.throughput / 1e6
            ratio = julia_mrec / python_mrec
            push!(julia_vs_python_ratios, ratio)
            @sprintf("%.2f M/s", python_mrec)
        else
            "N/A"
        end

        vs_rust_str = if r.rust !== nothing
            ratio = julia_mrec / (r.rust.throughput / 1e6)
            if ratio > 1.0
                @sprintf("%.2fx", ratio)
            else
                @sprintf("-%.2fx", 1.0/ratio)
            end
        else
            "N/A"
        end

        vs_python_str = if r.python !== nothing
            ratio = julia_mrec / (r.python.throughput / 1e6)
            if ratio > 1.0
                @sprintf("%.2fx", ratio)
            else
                @sprintf("-%.2fx", 1.0/ratio)
            end
        else
            "N/A"
        end

        println(@sprintf("%-25s %12s %12s %12s %12s %10s %10s",
                        r.file,
                        format_count(r.records),
                        @sprintf("%.2f M/s", julia_mrec),
                        rust_str,
                        python_str,
                        vs_rust_str,
                        vs_python_str))
    end

    println()

    # Print averages
    if !isempty(julia_vs_rust_ratios)
        avg_vs_rust = mean(julia_vs_rust_ratios)
        if avg_vs_rust > 1.0
            println(@sprintf("Average vs Rust: Julia is %.2fx faster", avg_vs_rust))
        else
            println(@sprintf("Average vs Rust: Rust is %.2fx faster", 1.0/avg_vs_rust))
        end
    end

    if !isempty(julia_vs_python_ratios)
        avg_vs_python = mean(julia_vs_python_ratios)
        if avg_vs_python > 1.0
            println(@sprintf("Average vs Python: Julia is %.2fx faster", avg_vs_python))
        else
            println(@sprintf("Average vs Python: Python is %.2fx faster", 1.0/avg_vs_python))
        end
    end

    println()
end

"""
    format_count(n)

Format number with comma separators.
"""
function format_count(n)
    str = string(n)
    result = ""
    for (i, c) in enumerate(reverse(str))
        if i > 1 && (i - 1) % 3 == 0
            result = "," * result
        end
        result = c * result
    end
    return result
end

# Main entry point
function main()
    args = ARGS

    data_dir = "benchmark/data"
    runs = 5

    i = 1
    while i <= length(args)
        if args[i] == "--data-dir"
            i += 1
            if i <= length(args)
                data_dir = args[i]
            end
        elseif args[i] == "--runs"
            i += 1
            if i <= length(args)
                runs = parse(Int, args[i])
            end
        end
        i += 1
    end

    run_comparison(data_dir, runs=runs)
end

# Run if executed as script
if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
