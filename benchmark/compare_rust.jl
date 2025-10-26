"""
    compare_rust.jl

Benchmark Julia DBN.jl performance against the official Rust implementation.

This script measures read throughput and compares:
- Julia: DBN.jl package (this implementation)
- Rust: Official Databento dbn CLI (~/dbn-workspace/dbn/target/release/dbn.exe)

Methodology:
- Use the same test files for both implementations
- Measure time to read and process all records
- Calculate records/second throughput
- Generate comparison report

Usage:
    julia --project=. benchmark/compare_rust.jl [--data-dir DIR]
"""

using DBN
using Printf
using Statistics
using Dates

# Path to Rust dbn CLI
const RUST_DBN_CLI = if Sys.iswindows()
    "C:/Users/tbeas/dbn-workspace/dbn/target/release/dbn.exe"
else
    joinpath(ENV["HOME"], "dbn-workspace/dbn/target/release/dbn")
end

"""
    benchmark_julia_read(file::String; runs=5)

Benchmark Julia DBN.jl read performance.
"""
function benchmark_julia_read(file::String; runs=5)
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
    benchmark_rust_read(file::String; runs=5)

Benchmark Rust dbn CLI read performance.

Strategy: Time how long it takes Rust to convert DBN to JSON (which requires reading all records).
"""
function benchmark_rust_read(file::String; runs=5)
    # Check if Rust CLI exists
    if !isfile(RUST_DBN_CLI)
        error("Rust dbn CLI not found at: $RUST_DBN_CLI")
    end

    # First, get record count by reading with Julia
    records = read_dbn(file)
    record_count = length(records)

    # Create temp output file
    temp_out = tempname() * ".json"

    times = Float64[]
    for _ in 1:runs
        # Clear OS file cache (best effort)
        if Sys.iswindows()
            # Windows: Just sleep to reduce caching effects
            sleep(0.2)
        else
            # Linux: Try to drop caches
            try
                run(`sync`)
            catch
            end
        end

        start_time = time_ns()
        # Run: dbn file.dbn --json --output temp.json
        # This forces Rust to read and decode all records
        run(pipeline(`$RUST_DBN_CLI $file --json --output $temp_out`,
                    stdout=devnull, stderr=devnull))
        elapsed = (time_ns() - start_time) / 1e9

        push!(times, elapsed)

        # Clean up temp file
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
    run_comparison(data_dir::String; runs=5)

Run comparison benchmarks between Julia and Rust.
"""
function run_comparison(data_dir::String; runs=5)
    println("\n" * "="^70)
    println("  DBN.jl vs Rust dbn - Performance Comparison")
    println("="^70)
    println()
    println("Data directory: $data_dir")
    println("Runs per test: $runs")
    println("Rust CLI: $RUST_DBN_CLI")
    println()

    # Find test files (only uncompressed for now, to compare pure read performance)
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
        println("-"^70)

        # Benchmark Julia
        print("  Julia DBN.jl:  ")
        flush(stdout)
        julia_result = benchmark_julia_read(file, runs=runs)
        julia_mrec_sec = julia_result.throughput / 1e6
        println(@sprintf("%.2f M rec/s (%.3f s ± %.3f s)",
                        julia_mrec_sec, julia_result.mean_time, julia_result.std_time))

        # Benchmark Rust
        print("  Rust dbn CLI:  ")
        flush(stdout)
        try
            rust_result = benchmark_rust_read(file, runs=runs)
            rust_mrec_sec = rust_result.throughput / 1e6
            println(@sprintf("%.2f M rec/s (%.3f s ± %.3f s)",
                            rust_mrec_sec, rust_result.mean_time, rust_result.std_time))

            # Calculate speedup
            speedup = julia_result.throughput / rust_result.throughput
            relative_str = if speedup > 1.0
                @sprintf("Julia is %.2fx faster", speedup)
            else
                @sprintf("Rust is %.2fx faster", 1.0/speedup)
            end

            println("  Comparison:    $relative_str")

            push!(results, (
                file = filename,
                records = julia_result.records,
                julia_mrec_sec = julia_mrec_sec,
                rust_mrec_sec = rust_mrec_sec,
                speedup = speedup
            ))
        catch e
            println("ERROR: $e")
            @warn "Failed to benchmark Rust on $filename" exception=e

            push!(results, (
                file = filename,
                records = julia_result.records,
                julia_mrec_sec = julia_mrec_sec,
                rust_mrec_sec = missing,
                speedup = missing
            ))
        end

        println()
    end

    # Print summary table
    print_summary(results)

    return results
end

"""
    print_summary(results)

Print a summary table of comparison results.
"""
function print_summary(results)
    println("\n" * "="^70)
    println("  SUMMARY")
    println("="^70)
    println()

    println(@sprintf("%-30s %12s %12s %12s %10s",
                    "File", "Records", "Julia", "Rust", "Speedup"))
    println("-"^70)

    for r in results
        speedup_str = if r.speedup === missing
            "N/A"
        elseif r.speedup > 1.0
            @sprintf("%.2fx", r.speedup)
        else
            @sprintf("-%.2fx", 1.0/r.speedup)
        end

        rust_str = r.rust_mrec_sec === missing ? "ERROR" : @sprintf("%.2f M/s", r.rust_mrec_sec)

        println(@sprintf("%-30s %12s %12s %12s %10s",
                        r.file,
                        format_count(r.records),
                        @sprintf("%.2f M/s", r.julia_mrec_sec),
                        rust_str,
                        speedup_str))
    end

    println()

    # Calculate average speedup (excluding errors)
    valid_speedups = filter(!ismissing, [r.speedup for r in results])
    if !isempty(valid_speedups)
        avg_speedup = mean(valid_speedups)
        if avg_speedup > 1.0
            println(@sprintf("Average: Julia is %.2fx faster than Rust", avg_speedup))
        else
            println(@sprintf("Average: Rust is %.2fx faster than Julia", 1.0/avg_speedup))
        end
    end
end

"""
    format_count(n)

Format a number with comma separators.
"""
function format_count(n)
    str = string(n)
    # Add commas
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

    # Parse arguments
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
