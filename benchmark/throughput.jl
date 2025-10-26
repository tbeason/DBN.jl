"""
    throughput.jl

Measure throughput (records/second) for DBN.jl read and write operations.

This script provides simple, interpretable performance metrics focused on
throughput rather than detailed timing distributions.
"""

using DBN
using Statistics
using Printf
using Dates

"""
    benchmark_read_throughput(file::String; runs=5, warmup=1)

Measure read throughput for a DBN file.

# Arguments
- `file`: Path to the DBN file to benchmark
- `runs`: Number of benchmark runs (default: 5)
- `warmup`: Number of warmup runs to run before benchmarking (default: 1)

# Returns
Named tuple with:
- `file`: Filename
- `records`: Number of records
- `mean_time_s`: Mean time in seconds
- `std_time_s`: Standard deviation of time
- `throughput_recs_per_sec`: Mean throughput in records/second
- `throughput_mrecs_per_sec`: Mean throughput in million records/second
- `file_size_mb`: File size in megabytes
- `bandwidth_mbps`: Read bandwidth in MB/s
"""
function benchmark_read_throughput(file::String; runs=5, warmup=1)
    # Warmup runs
    for _ in 1:warmup
        records = read_dbn(file)
    end

    times = Float64[]
    record_count = 0

    for i in 1:runs
        GC.gc()  # Force garbage collection before each run
        sleep(0.1)  # Small pause to settle

        start_time = time_ns()
        records = read_dbn(file)
        elapsed = (time_ns() - start_time) / 1e9  # Convert to seconds

        push!(times, elapsed)
        record_count = length(records)
    end

    mean_time = mean(times)
    std_time = std(times)
    throughput = record_count / mean_time
    file_size_mb = filesize(file) / 1024^2
    bandwidth = file_size_mb / mean_time

    return (
        file = basename(file),
        records = record_count,
        mean_time_s = mean_time,
        std_time_s = std_time,
        throughput_recs_per_sec = throughput,
        throughput_mrecs_per_sec = throughput / 1e6,
        file_size_mb = file_size_mb,
        bandwidth_mbps = bandwidth
    )
end

"""
    benchmark_write_throughput(records, metadata, output_file; runs=5, warmup=1)

Measure write throughput for DBN records.

# Arguments
- `records`: Vector of records to write
- `metadata`: Metadata for the DBN file
- `output_file`: Path where the file will be written (will be deleted after each run)
- `runs`: Number of benchmark runs
- `warmup`: Number of warmup runs

# Returns
Named tuple with performance metrics
"""
function benchmark_write_throughput(records, metadata, output_file; runs=5, warmup=1)
    # Warmup runs
    for _ in 1:warmup
        write_dbn(output_file, metadata, records)
        rm(output_file, force=true)
    end

    times = Float64[]
    file_sizes = Float64[]

    for i in 1:runs
        GC.gc()
        sleep(0.1)

        start_time = time_ns()
        write_dbn(output_file, metadata, records)
        elapsed = (time_ns() - start_time) / 1e9

        push!(times, elapsed)
        push!(file_sizes, filesize(output_file) / 1024^2)
        rm(output_file, force=true)
    end

    mean_time = mean(times)
    std_time = std(times)
    throughput = length(records) / mean_time
    mean_file_size = mean(file_sizes)
    bandwidth = mean_file_size / mean_time

    return (
        records = length(records),
        mean_time_s = mean_time,
        std_time_s = std_time,
        throughput_recs_per_sec = throughput,
        throughput_mrecs_per_sec = throughput / 1e6,
        file_size_mb = mean_file_size,
        bandwidth_mbps = bandwidth
    )
end

"""
    benchmark_streaming_throughput(file::String; runs=5, warmup=1)

Measure streaming read throughput using DBNStream.

# Arguments
- `file`: Path to the DBN file to benchmark
- `runs`: Number of benchmark runs
- `warmup`: Number of warmup runs

# Returns
Named tuple with performance metrics
"""
function benchmark_streaming_throughput(file::String; runs=5, warmup=1)
    # Warmup runs
    for _ in 1:warmup
        count = 0
        for record in DBNStream(file)
            count += 1
        end
    end

    times = Float64[]
    record_count = 0

    for i in 1:runs
        GC.gc()
        sleep(0.1)

        start_time = time_ns()
        count = 0
        for record in DBNStream(file)
            count += 1
        end
        elapsed = (time_ns() - start_time) / 1e9

        push!(times, elapsed)
        record_count = count
    end

    mean_time = mean(times)
    std_time = std(times)
    throughput = record_count / mean_time
    file_size_mb = filesize(file) / 1024^2
    bandwidth = file_size_mb / mean_time

    return (
        file = basename(file),
        records = record_count,
        mean_time_s = mean_time,
        std_time_s = std_time,
        throughput_recs_per_sec = throughput,
        throughput_mrecs_per_sec = throughput / 1e6,
        file_size_mb = file_size_mb,
        bandwidth_mbps = bandwidth
    )
end

"""
    print_throughput_result(label::String, result)

Pretty-print throughput benchmark results.
"""
function print_throughput_result(label::String, result)
    println("\n" * "="^70)
    println("$label")
    println("="^70)

    if haskey(result, :file)
        @printf "File:                   %s\n" result.file
    end

    @printf "Records:                %s\n" format_number(result.records)
    @printf "Mean Time:              %.4f ± %.4f seconds\n" result.mean_time_s result.std_time_s

    if haskey(result, :file_size_mb)
        @printf "File Size:              %.2f MB\n" result.file_size_mb
    end

    println("\n" * "-"^70)
    println("Throughput:")
    @printf "  %.2f records/second\n" result.throughput_recs_per_sec
    @printf "  %.2f thousand records/second\n" (result.throughput_recs_per_sec / 1e3)
    @printf "  %.4f million records/second\n" result.throughput_mrecs_per_sec

    if haskey(result, :bandwidth_mbps)
        @printf "\nBandwidth:              %.2f MB/s\n" result.bandwidth_mbps
    end

    println("="^70)
end

"""
    format_number(n::Integer)

Format large integers with thousand separators.
"""
function format_number(n::Integer)
    s = string(n)
    len = length(s)
    result = ""

    for (i, c) in enumerate(s)
        result *= c
        if (len - i) % 3 == 0 && i != len
            result *= ","
        end
    end

    return result
end

"""
    run_throughput_benchmarks(data_dir="benchmark/data")

Run comprehensive throughput benchmarks on all test files.
"""
function run_throughput_benchmarks(data_dir="benchmark/data"; runs=5)
    if !isdir(data_dir)
        error("Data directory not found: $data_dir. Run generate_test_data.jl first.")
    end

    println("\n" * "█"^70)
    println("█" * " "^68 * "█")
    println("█" * "  DBN.jl THROUGHPUT BENCHMARK SUITE" * " "^32 * "█")
    println("█" * " "^68 * "█")
    println("█"^70)
    println("\nBenchmark runs per test: $runs")
    println("Data directory: $data_dir")
    println("\nStarted at: $(Dates.format(now(), "yyyy-mm-dd HH:MM:SS"))")

    # Find all test files
    test_files = filter(f -> endswith(f, ".dbn") || endswith(f, ".dbn.zst"), readdir(data_dir, join=true))
    sort!(test_files)

    if isempty(test_files)
        error("No test files found in $data_dir")
    end

    println("\nFound $(length(test_files)) test files")

    # Track results for summary
    all_results = []

    for file in test_files
        println("\n\n" * "▼"^70)
        println("Testing: $(basename(file))")
        println("▼"^70)

        try
            # Read throughput
            println("\n[1/3] Benchmarking full read (read_dbn)...")
            read_result = benchmark_read_throughput(file, runs=runs)
            print_throughput_result("READ THROUGHPUT - $(basename(file))", read_result)
            push!(all_results, ("read", basename(file), read_result))

            # Streaming throughput
            println("\n[2/3] Benchmarking streaming read (DBNStream)...")
            stream_result = benchmark_streaming_throughput(file, runs=runs)
            print_throughput_result("STREAMING THROUGHPUT - $(basename(file))", stream_result)
            push!(all_results, ("stream", basename(file), stream_result))

            # Write throughput (only for smaller files to save time)
            if read_result.records <= 1_000_000
                println("\n[3/3] Benchmarking write (write_dbn)...")
                metadata, records = read_dbn_with_metadata(file)
                output_file = joinpath(data_dir, "tmp_benchmark_output.dbn")
                write_result = benchmark_write_throughput(records, metadata, output_file, runs=runs)
                print_throughput_result("WRITE THROUGHPUT - $(basename(file))", write_result)
                push!(all_results, ("write", basename(file), write_result))
            else
                println("\n[3/3] Skipping write benchmark (file too large)")
            end

        catch e
            @warn "Failed to benchmark $file" exception=e
            continue
        end
    end

    # Print summary
    print_summary(all_results)

    println("\n\nCompleted at: $(Dates.format(now(), "yyyy-mm-dd HH:MM:SS"))")
end

"""
    print_summary(all_results)

Print a summary table of all benchmark results.
"""
function print_summary(all_results)
    println("\n\n")
    println("█"^70)
    println("█" * " "^68 * "█")
    println("█" * "  BENCHMARK SUMMARY" * " "^49 * "█")
    println("█" * " "^68 * "█")
    println("█"^70)

    # Group by operation type
    for op_type in ["read", "stream", "write"]
        results = filter(r -> r[1] == op_type, all_results)
        if isempty(results)
            continue
        end

        op_label = uppercase(op_type)
        println("\n\n$op_label THROUGHPUT:")
        println("─"^70)
        @printf "%-30s %12s %12s %10s\n" "File" "Records" "Time (s)" "Mrec/s"
        println("─"^70)

        for (_, file, result) in results
            @printf "%-30s %12s %12.3f %10.4f\n" file format_number(result.records) result.mean_time_s result.throughput_mrecs_per_sec
        end
    end

    println("\n" * "█"^70)
end

# Run if executed as script
if abspath(PROGRAM_FILE) == @__FILE__
    data_dir = length(ARGS) >= 1 ? ARGS[1] : "benchmark/data"
    runs = length(ARGS) >= 2 ? parse(Int, ARGS[2]) : 5

    run_throughput_benchmarks(data_dir, runs=runs)
end
