"""
Comprehensive DBN performance comparison using BenchmarkTools.jl

Tests all combinations of:
- Schemas: trades, mbo, ohlcv
- Sizes: 1k, 10k, 100k, 1m, 10m (where available)
- Operations: read, write
- Compression: uncompressed, zstd

Write benchmarks use optimized serialization:
- Most message types use direct unsafe_write() for zero-copy serialization
- MBOMsg uses IOBuffer batching (1.4x speedup over field-by-field)
- All optimizations maintain byte-for-byte DBN format compatibility

Usage: julia --project=. benchmark/compare_all_comprehensive.jl
"""

using DBN, BenchmarkTools, Printf, Statistics

# Benchmark configuration
const BENCHMARK_SECONDS = 2  # Minimum time to run each benchmark
const BENCHMARK_SAMPLES = 20  # Minimum number of samples (20 is enough for stable median)

"""
Generate compressed versions of test files if they don't exist
"""
function ensure_compressed_files()
    data_dir = "benchmark/data"
    files = filter(f -> endswith(f, ".dbn") && !endswith(f, ".zst"), readdir(data_dir, join=true))
    
    for f in files
        compressed = f * ".zst"
        if !isfile(compressed)
            println("Creating compressed version: $(basename(compressed))")
            meta, recs = read_dbn_with_metadata(f)
            write_dbn(compressed, meta, recs)
        end
    end
end

"""
Run a read benchmark on a file
"""
function benchmark_read(file::String)
    # Warm up
    read_dbn(file)
    GC.gc()
    
    # Benchmark
    trial = @benchmark read_dbn($file) seconds=BENCHMARK_SECONDS samples=BENCHMARK_SAMPLES
    
    count = length(read_dbn(file))
    return (trial, count)
end

"""
Run a read benchmark using optimized schema-specific reader
"""
function benchmark_read_optimized(file::String, reader_func::Function)
    # Warm up
    reader_func(file)
    GC.gc()
    
    # Benchmark
    trial = @benchmark $reader_func($file) seconds=BENCHMARK_SECONDS samples=BENCHMARK_SAMPLES
    
    count = length(reader_func(file))
    return (trial, count)
end

"""
Run a streaming read benchmark using DBNStream (generic iterator)
"""
function benchmark_stream(file::String)
    # Warm up
    for _ in DBNStream(file); end
    GC.gc()

    # Benchmark
    trial = @benchmark begin
        for _ in DBNStream($file); end
    end seconds=BENCHMARK_SECONDS samples=BENCHMARK_SAMPLES

    count = sum(1 for _ in DBNStream(file))
    return (trial, count)
end

"""
Run a callback streaming benchmark (near-zero allocation)
"""
function benchmark_foreach(file::String, foreach_func::Function)
    # Warm up
    foreach_func(file) do _; end
    GC.gc()

    # Benchmark
    trial = @benchmark begin
        $foreach_func($file) do _
            # Just iterate
        end
    end seconds=BENCHMARK_SECONDS samples=BENCHMARK_SAMPLES

    count = 0
    foreach_func(file) do _
        count += 1
    end
    return (trial, count)
end

"""
Run a write benchmark - reads once then writes multiple times

Note: Uses optimized write_record() implementations internally:
- TradeMsg, MBP1Msg, MBP10Msg, OHLCVMsg, StatusMsg, ImbalanceMsg: direct unsafe_write()
- MBOMsg: IOBuffer batching (1.4x faster than field-by-field)
- Other types: field-by-field serialization
"""
function benchmark_write(file::String, compressed::Bool=false)
    # Read the data once
    meta, recs = read_dbn_with_metadata(file)
    count = length(recs)

    # Warm up
    tmp = tempname() * (compressed ? ".dbn.zst" : ".dbn")
    write_dbn(tmp, meta, recs)
    rm(tmp, force=true)
    GC.gc()

    # Benchmark
    trial = @benchmark begin
        tmp = tempname() * $(compressed ? ".dbn.zst" : ".dbn")
        write_dbn(tmp, $meta, $recs)
        rm(tmp, force=true)
    end seconds=BENCHMARK_SECONDS samples=BENCHMARK_SAMPLES

    return (trial, count)
end

"""
Run a streaming write benchmark using DBNStreamWriter

Note: Uses same optimized write_record() implementations as benchmark_write():
- TradeMsg, MBP1Msg, MBP10Msg, OHLCVMsg, StatusMsg, ImbalanceMsg: direct unsafe_write()
- MBOMsg: IOBuffer batching (1.4x faster than field-by-field)
- Other types: field-by-field serialization
"""
function benchmark_write_stream(file::String, compressed::Bool=false)
    # Read the data and metadata once
    meta, recs = read_dbn_with_metadata(file)
    count = length(recs)

    # Warm up
    tmp = tempname() * (compressed ? ".dbn.zst" : ".dbn")
    writer = DBNStreamWriter(tmp, meta.dataset, meta.schema, symbols=meta.symbols, auto_flush=false)
    for rec in recs
        write_record!(writer, rec)
    end
    close_writer!(writer)
    rm(tmp, force=true)
    GC.gc()

    # Benchmark
    trial = @benchmark begin
        tmp = tempname() * $(compressed ? ".dbn.zst" : ".dbn")
        writer = DBNStreamWriter(tmp, $meta.dataset, $meta.schema, symbols=$meta.symbols, auto_flush=false)
        for rec in $recs
            write_record!(writer, rec)
        end
        close_writer!(writer)
        rm(tmp, force=true)
    end seconds=BENCHMARK_SECONDS samples=BENCHMARK_SAMPLES

    return (trial, count)
end

"""
Check if Python databento is available
"""
function python_available()
    try
        run(pipeline(`python3 -c "import databento"`, stdout=devnull, stderr=devnull))
        return true
    catch
        try
            run(pipeline(`python -c "import databento"`, stdout=devnull, stderr=devnull))
            return true
        catch
            return false
        end
    end
end

"""
Get the python command
"""
function get_python_cmd()
    try
        run(pipeline(`python3 -c "import databento"`, stdout=devnull, stderr=devnull))
        return `python3`
    catch
        return `python`
    end
end

"""
Benchmark Python databento read operation
"""
function benchmark_python_read(file::String)
    script = tempname() * ".py"
    write(script, """
import databento as db
import time
import sys

filepath = sys.argv[1]
n = int(sys.argv[2])

# Warmup and count
data = db.read_dbn(filepath)
records = list(data)  # Materialize to list to count and for fair comparison
record_count = len(records)

times = []
for _ in range(n):
    start = time.perf_counter()
    data = db.read_dbn(filepath)
    _ = list(data)  # Materialize to list for fair comparison with Julia
    elapsed = time.perf_counter() - start
    times.append(elapsed)

import statistics
median_time = statistics.median(times)
print(f"{median_time},{record_count}")
""")
    
    try
        python_cmd = get_python_cmd()
        output = read(`$python_cmd $script $file $(BENCHMARK_SAMPLES)`, String)
        rm(script, force=true)
        
        parts = split(strip(output), ',')
        time_sec = parse(Float64, parts[1])
        count = parse(Int, parts[2])
        
        # Create a mock trial with the Python timing
        return (time_sec, count)
    catch e
        rm(script, force=true)
        return nothing
    end
end

"""
Benchmark Python databento write operation

NOTE: Python's DBNStore.to_file() may use optimized file copying rather than
full deserialization+reserialization, making it not directly comparable to Julia's
write_dbn() which serializes from in-memory structures.
"""
function benchmark_python_write(file::String, compressed::Bool=false)
    # First read with Julia to get the data
    meta, recs = read_dbn_with_metadata(file)
    
    # Write to temp file for Python to read
    python_input = tempname() * ".dbn"
    write_dbn(python_input, meta, recs)
    
    script = tempname() * ".py"
    ext = compressed ? ".dbn.zst" : ".dbn"
    write(script, """
import databento as db
import time
import sys
import os
import tempfile

input_file = sys.argv[1]
n = int(sys.argv[2])
use_compression = sys.argv[3] == 'true'

# Load data once and materialize to memory (like Julia does)
data_store = db.read_dbn(input_file)
record_count = len(list(data_store))

# Re-read for actual benchmarking (consume iterator)
data_store = db.read_dbn(input_file)

times = []
for _ in range(n):
    tmp = tempfile.mktemp(suffix='$ext')
    start = time.perf_counter()
    # Write from the in-memory store (fair comparison with Julia)
    data_store.to_file(tmp)
    elapsed = time.perf_counter() - start
    times.append(elapsed)
    os.remove(tmp)

import statistics
median_time = statistics.median(times)
print(f"{median_time},{record_count}")
""")
    
    try
        python_cmd = get_python_cmd()
        comp_str = compressed ? "true" : "false"
        output = read(`$python_cmd $script $python_input $(BENCHMARK_SAMPLES) $comp_str`, String)
        rm(script, force=true)
        rm(python_input, force=true)
        
        parts = split(strip(output), ',')
        time_sec = parse(Float64, parts[1])
        count = parse(Int, parts[2])
        
        return (time_sec, count)
    catch e
        rm(script, force=true)
        rm(python_input, force=true)
        return nothing
    end
end

"""
Format benchmark results as throughput
"""
function format_throughput(trial::BenchmarkTools.Trial, count::Int)
    time_sec = median(trial.times) / 1e9
    throughput = count / time_sec / 1e6  # Million records/sec
    @sprintf("%.2f M/s (%.3f s)", throughput, time_sec)
end

"""
Format benchmark results with more details
"""
function format_detailed(trial::BenchmarkTools.Trial, count::Int)
    time_sec = median(trial.times) / 1e9
    throughput = count / time_sec / 1e6
    mem_mb = trial.memory / 1024^2
    @sprintf("%.2f M/s | %.3f s | %.1f MB", throughput, time_sec, mem_mb)
end

"""
Format Python timing results (time, count tuple)
"""
function format_python_result(time_sec::Float64, count::Int)
    throughput = count / time_sec / 1e6
    @sprintf("%.2f M/s | %.3f s", throughput, time_sec)
end

"""
Get compression ratio for a file
"""
function get_compression_ratio(uncompressed_file::String, compressed_file::String)
    if !isfile(compressed_file) || !isfile(uncompressed_file)
        return nothing
    end
    ratio = filesize(uncompressed_file) / filesize(compressed_file)
    return round(ratio, digits=2)
end

"""
Main benchmark runner
"""
function run_benchmarks(outfile::String)
    ensure_compressed_files()
    
    # Check Python availability
    has_python = python_available()
    
    io = open(outfile, "w")
    
    println(io, "="^100)
    println(io, "DBN.jl COMPREHENSIVE PERFORMANCE COMPARISON")
    println(io, "Using BenchmarkTools.jl with $(BENCHMARK_SECONDS)s min runtime per benchmark")
    if has_python
        println(io, "Python databento-dbn comparison: ENABLED")
    else
        println(io, "Python databento-dbn comparison: DISABLED (package not found)")
    end
    println(io, "="^100)
    println(io)
    
    # Define test matrix
    schemas = ["trades", "mbo", "ohlcv"]
    sizes = ["1k", "10k", "100k", "1m", "10m"]
    
    # Track results for summary
    results = Dict()
    
    for schema in schemas
        println(io, "\n" * "="^100)
        println(io, "SCHEMA: $(uppercase(schema))")
        println(io, "="^100)
        
        for size in sizes
            # Find the file
            pattern = "$(schema).$(size).dbn"
            file = joinpath("benchmark/data", pattern)
            
            if !isfile(file)
                continue
            end
            
            compressed_file = file * ".zst"
            
            println(io, "\n" * "-"^100)
            println(io, "Size: $(uppercase(size)) ($(basename(file)))")
            file_size_mb = round(filesize(file) / 1024^2, digits=2)
            println(io, "File size: $(file_size_mb) MB")
            
            if isfile(compressed_file)
                comp_size_mb = round(filesize(compressed_file) / 1024^2, digits=2)
                ratio = get_compression_ratio(file, compressed_file)
                println(io, "Compressed size: $(comp_size_mb) MB ($(ratio)x compression)")
            end
            
            println(io, "-"^100)
            
            # Print header
            println(io, @sprintf("  %-40s %s", "Operation", "Throughput | Time | Memory"))
            println(io, "  " * "-"^96)
            
            print("Benchmarking $(schema).$(size)... ")
            flush(stdout)
            
            # READ UNCOMPRESSED
            try
                trial, count = benchmark_read(file)
                println(io, @sprintf("  %-40s %s", "Read (uncompressed)", format_detailed(trial, count)))
                results["$(schema)_$(size)_read"] = (trial, count)
            catch e
                println(io, @sprintf("  %-40s FAILED: %s", "Read (uncompressed)", string(e)))
            end
            
            # STREAM UNCOMPRESSED (Generic)
            try
                trial, count = benchmark_stream(file)
                println(io, @sprintf("  %-40s %s", "Stream DBNStream() (uncompressed)", format_detailed(trial, count)))
                results["$(schema)_$(size)_stream"] = (trial, count)
            catch e
                println(io, @sprintf("  %-40s FAILED: %s", "Stream DBNStream()", string(e)))
            end

            # CALLBACK STREAMING (Near-zero allocation)
            callback_stream = nothing
            if schema == "trades"
                callback_stream = (foreach_trade, "foreach_trade()")
            elseif schema == "mbo"
                callback_stream = (foreach_mbo, "foreach_mbo()")
            end

            if callback_stream !== nothing
                try
                    foreach_func, foreach_name = callback_stream
                    trial, count = benchmark_foreach(file, foreach_func)
                    println(io, @sprintf("  %-40s %s", "Callback $foreach_name (uncompressed)", format_detailed(trial, count)))
                    results["$(schema)_$(size)_foreach"] = (trial, count)
                catch e
                    println(io, @sprintf("  %-40s FAILED: %s", "Callback streaming", string(e)))
                end
            end
            
            # READ UNCOMPRESSED (OPTIMIZED)
            optimized_reader = nothing
            if schema == "trades"
                optimized_reader = (read_trades, "read_trades()")
            elseif schema == "mbo"
                optimized_reader = (read_mbo, "read_mbo()")
            end
            
            if optimized_reader !== nothing
                try
                    reader_func, reader_name = optimized_reader
                    trial, count = benchmark_read_optimized(file, reader_func)
                    println(io, @sprintf("  %-40s %s", "Read optimized ($reader_name)", format_detailed(trial, count)))
                    results["$(schema)_$(size)_read_opt"] = (trial, count)
                catch e
                    println(io, @sprintf("  %-40s FAILED: %s", "Read optimized", string(e)))
                end
            end
            
            # READ COMPRESSED
            if isfile(compressed_file)
                try
                    trial, count = benchmark_read(compressed_file)
                    println(io, @sprintf("  %-40s %s", "Read (compressed .zst)", format_detailed(trial, count)))
                    results["$(schema)_$(size)_read_zst"] = (trial, count)
                catch e
                    println(io, @sprintf("  %-40s FAILED: %s", "Read (compressed .zst)", string(e)))
                end
                
                # STREAM COMPRESSED (Generic)
                try
                    trial, count = benchmark_stream(compressed_file)
                    println(io, @sprintf("  %-40s %s", "Stream DBNStream() (compressed .zst)", format_detailed(trial, count)))
                    results["$(schema)_$(size)_stream_zst"] = (trial, count)
                catch e
                    println(io, @sprintf("  %-40s FAILED: %s", "Stream DBNStream() .zst", string(e)))
                end

                # CALLBACK STREAMING COMPRESSED
                if callback_stream !== nothing
                    try
                        foreach_func, foreach_name = callback_stream
                        trial, count = benchmark_foreach(compressed_file, foreach_func)
                        println(io, @sprintf("  %-40s %s", "Callback $foreach_name (compressed .zst)", format_detailed(trial, count)))
                        results["$(schema)_$(size)_foreach_zst"] = (trial, count)
                    catch e
                        println(io, @sprintf("  %-40s FAILED: %s", "Callback streaming .zst", string(e)))
                    end
                end
                
                # READ COMPRESSED (OPTIMIZED)
                if optimized_reader !== nothing
                    try
                        reader_func, reader_name = optimized_reader
                        trial, count = benchmark_read_optimized(compressed_file, reader_func)
                        println(io, @sprintf("  %-40s %s", "Read optimized .zst ($reader_name)", format_detailed(trial, count)))
                        results["$(schema)_$(size)_read_opt_zst"] = (trial, count)
                    catch e
                        println(io, @sprintf("  %-40s FAILED: %s", "Read optimized .zst", string(e)))
                    end
                end
            end
            
            # WRITE UNCOMPRESSED
            try
                trial, count = benchmark_write(file, false)
                println(io, @sprintf("  %-40s %s", "Write (uncompressed)", format_detailed(trial, count)))
                results["$(schema)_$(size)_write"] = (trial, count)
            catch e
                println(io, @sprintf("  %-40s FAILED: %s", "Write (uncompressed)", string(e)))
            end
            
            # WRITE STREAM UNCOMPRESSED
            try
                trial, count = benchmark_write_stream(file, false)
                println(io, @sprintf("  %-40s %s", "Write stream (uncompressed)", format_detailed(trial, count)))
                results["$(schema)_$(size)_write_stream"] = (trial, count)
            catch e
                println(io, @sprintf("  %-40s FAILED: %s", "Write stream (uncompressed)", string(e)))
            end
            
            # WRITE COMPRESSED
            try
                trial, count = benchmark_write(file, true)
                println(io, @sprintf("  %-40s %s", "Write (compressed .zst)", format_detailed(trial, count)))
                results["$(schema)_$(size)_write_zst"] = (trial, count)
            catch e
                println(io, @sprintf("  %-40s FAILED: %s", "Write (compressed .zst)", string(e)))
            end
            
            # WRITE STREAM COMPRESSED
            try
                trial, count = benchmark_write_stream(file, true)
                println(io, @sprintf("  %-40s %s", "Write stream (compressed .zst)", format_detailed(trial, count)))
                results["$(schema)_$(size)_write_stream_zst"] = (trial, count)
            catch e
                println(io, @sprintf("  %-40s FAILED: %s", "Write stream (compressed .zst)", string(e)))
            end
            
            # PYTHON BENCHMARKS
            if has_python
                println(io, "  " * "-"^96)
                println(io, @sprintf("  %-40s %s", "Python Comparison:", ""))
                
                # Python read uncompressed
                result = benchmark_python_read(file)
                if result !== nothing
                    time_sec, count = result
                    println(io, @sprintf("  %-40s %s", "  Python read (uncompressed)", format_python_result(time_sec, count)))
                    results["$(schema)_$(size)_python_read"] = (time_sec, count)
                end
                
                # Python read compressed
                if isfile(compressed_file)
                    result = benchmark_python_read(compressed_file)
                    if result !== nothing
                        time_sec, count = result
                        println(io, @sprintf("  %-40s %s", "  Python read (compressed .zst)", format_python_result(time_sec, count)))
                        results["$(schema)_$(size)_python_read_zst"] = (time_sec, count)
                    end
                end
                
                # Python write uncompressed
                result = benchmark_python_write(file, false)
                if result !== nothing
                    time_sec, count = result
                    println(io, @sprintf("  %-40s %s", "  Python write (uncompressed)", format_python_result(time_sec, count)))
                    results["$(schema)_$(size)_python_write"] = (time_sec, count)
                end
                
                # Python write compressed
                result = benchmark_python_write(file, true)
                if result !== nothing
                    time_sec, count = result
                    println(io, @sprintf("  %-40s %s", "  Python write (compressed .zst)", format_python_result(time_sec, count)))
                    results["$(schema)_$(size)_python_write_zst"] = (time_sec, count)
                end
            end
            
            println("✓")
        end
    end
    
    # Summary section
    println(io, "\n" * "="^100)
    println(io, "SUMMARY")
    println(io, "="^100)
    println(io)
    
    println(io, "Read Performance (uncompressed):")
    println(io, "-"^100)
    for schema in schemas
        for size in sizes
            key = "$(schema)_$(size)_read"
            if haskey(results, key)
                trial, count = results[key]
                println(io, @sprintf("  %-20s %s", "$(schema) $(size):", format_throughput(trial, count)))
            end
        end
    end
    
    println(io, "\nStream Performance - Generic DBNStream() (uncompressed):")
    println(io, "-"^100)
    for schema in schemas
        for size in sizes
            key = "$(schema)_$(size)_stream"
            if haskey(results, key)
                trial, count = results[key]
                println(io, @sprintf("  %-20s %s", "$(schema) $(size):", format_throughput(trial, count)))
            end
        end
    end

    println(io, "\nStream Performance - Callback foreach_*() (uncompressed):")
    println(io, "-"^100)
    for schema in schemas
        for size in sizes
            key = "$(schema)_$(size)_foreach"
            if haskey(results, key)
                trial, count = results[key]
                println(io, @sprintf("  %-20s %s", "$(schema) $(size):", format_throughput(trial, count)))
            end
        end
    end
    
    println(io, "\nRead Performance (optimized, uncompressed):")
    println(io, "-"^100)
    for schema in schemas
        for size in sizes
            key = "$(schema)_$(size)_read_opt"
            if haskey(results, key)
                trial, count = results[key]
                println(io, @sprintf("  %-20s %s", "$(schema) $(size):", format_throughput(trial, count)))
            end
        end
    end
    
    println(io, "\nRead Performance (compressed):")
    println(io, "-"^100)
    for schema in schemas
        for size in sizes
            key = "$(schema)_$(size)_read_zst"
            if haskey(results, key)
                trial, count = results[key]
                println(io, @sprintf("  %-20s %s", "$(schema) $(size):", format_throughput(trial, count)))
            end
        end
    end
    
    println(io, "\nStream Performance - Generic DBNStream() (compressed):")
    println(io, "-"^100)
    for schema in schemas
        for size in sizes
            key = "$(schema)_$(size)_stream_zst"
            if haskey(results, key)
                trial, count = results[key]
                println(io, @sprintf("  %-20s %s", "$(schema) $(size):", format_throughput(trial, count)))
            end
        end
    end

    println(io, "\nStream Performance - Callback foreach_*() (compressed):")
    println(io, "-"^100)
    for schema in schemas
        for size in sizes
            key = "$(schema)_$(size)_foreach_zst"
            if haskey(results, key)
                trial, count = results[key]
                println(io, @sprintf("  %-20s %s", "$(schema) $(size):", format_throughput(trial, count)))
            end
        end
    end
    
    println(io, "\nRead Performance (optimized, compressed):")
    println(io, "-"^100)
    for schema in schemas
        for size in sizes
            key = "$(schema)_$(size)_read_opt_zst"
            if haskey(results, key)
                trial, count = results[key]
                println(io, @sprintf("  %-20s %s", "$(schema) $(size):", format_throughput(trial, count)))
            end
        end
    end
    
    println(io, "\nWrite Performance (uncompressed):")
    println(io, "-"^100)
    for schema in schemas
        for size in sizes
            key = "$(schema)_$(size)_write"
            if haskey(results, key)
                trial, count = results[key]
                println(io, @sprintf("  %-20s %s", "$(schema) $(size):", format_throughput(trial, count)))
            end
        end
    end
    
    println(io, "\nWrite Stream Performance (uncompressed):")
    println(io, "-"^100)
    for schema in schemas
        for size in sizes
            key = "$(schema)_$(size)_write_stream"
            if haskey(results, key)
                trial, count = results[key]
                println(io, @sprintf("  %-20s %s", "$(schema) $(size):", format_throughput(trial, count)))
            end
        end
    end
    
    println(io, "\nWrite Performance (compressed):")
    println(io, "-"^100)
    for schema in schemas
        for size in sizes
            key = "$(schema)_$(size)_write_zst"
            if haskey(results, key)
                trial, count = results[key]
                println(io, @sprintf("  %-20s %s", "$(schema) $(size):", format_throughput(trial, count)))
            end
        end
    end
    
    println(io, "\nWrite Stream Performance (compressed):")
    println(io, "-"^100)
    for schema in schemas
        for size in sizes
            key = "$(schema)_$(size)_write_stream_zst"
            if haskey(results, key)
                trial, count = results[key]
                println(io, @sprintf("  %-20s %s", "$(schema) $(size):", format_throughput(trial, count)))
            end
        end
    end
    
    # Python comparison summary
    if has_python
        println(io, "\n" * "="^100)
        println(io, "PYTHON DATABENTO COMPARISON")
        println(io, "="^100)
        println(io)
        
        println(io, "Python Read Performance (uncompressed):")
        println(io, "-"^100)
        for schema in schemas
            for size in sizes
                key = "$(schema)_$(size)_python_read"
                if haskey(results, key)
                    time_sec, count = results[key]
                    throughput = count / time_sec / 1e6
                    println(io, @sprintf("  %-20s %.2f M/s (%.3f s)", "$(schema) $(size):", throughput, time_sec))
                end
            end
        end
        
        println(io, "\nPython Read Performance (compressed):")
        println(io, "-"^100)
        for schema in schemas
            for size in sizes
                key = "$(schema)_$(size)_python_read_zst"
                if haskey(results, key)
                    time_sec, count = results[key]
                    throughput = count / time_sec / 1e6
                    println(io, @sprintf("  %-20s %.2f M/s (%.3f s)", "$(schema) $(size):", throughput, time_sec))
                end
            end
        end
        
        println(io, "\nPython Write Performance (uncompressed):")
        println(io, "-"^100)
        for schema in schemas
            for size in sizes
                key = "$(schema)_$(size)_python_write"
                if haskey(results, key)
                    time_sec, count = results[key]
                    throughput = count / time_sec / 1e6
                    println(io, @sprintf("  %-20s %.2f M/s (%.3f s)", "$(schema) $(size):", throughput, time_sec))
                end
            end
        end
        
        println(io, "\nPython Write Performance (compressed):")
        println(io, "-"^100)
        for schema in schemas
            for size in sizes
                key = "$(schema)_$(size)_python_write_zst"
                if haskey(results, key)
                    time_sec, count = results[key]
                    throughput = count / time_sec / 1e6
                    println(io, @sprintf("  %-20s %.2f M/s (%.3f s)", "$(schema) $(size):", throughput, time_sec))
                end
            end
        end
    end
    
    println(io, "\n" * "="^100)
    println(io, "Benchmark complete")
    println(io, "="^100)
    
    close(io)
    println("\nResults saved to: $outfile")
end

# Main
if abspath(PROGRAM_FILE) == @__FILE__
    outfile = length(ARGS) > 0 ? ARGS[1] : "benchmark/benchmark_results.txt"
    run_benchmarks(outfile)
end
