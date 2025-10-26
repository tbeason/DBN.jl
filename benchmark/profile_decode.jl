"""
    profile_decode.jl

Profile DBN decoding to identify performance bottlenecks.

This script uses Julia's built-in profiler to analyze where time is spent
during DBN file decoding, helping identify optimization opportunities.

Usage:
    julia --project=. benchmark/profile_decode.jl [file.dbn]
    julia --project=. --track-allocation=user benchmark/profile_decode.jl [file.dbn]
"""

using DBN
using Profile
using Printf
using Statistics
using BenchmarkTools

# Optional dependencies
const HAS_PROFILE_CANVAS = try
    using ProfileCanvas
    true
catch
    false
end

# Default test file
const DEFAULT_FILE = "benchmark/data/trades.1m.dbn"

# Helper functions for micro-benchmarks

"""Optimized string creation from null-terminated byte array"""
function fast_string_opt(bytes)
    len = findfirst(==(0x00), bytes)
    len = len === nothing ? length(bytes) : len - 1
    return len == 0 ? "" : String(bytes[1:len])
end

"""Unsafe enum conversion (for comparison)"""
@inline unsafe_action(x::UInt8) = DBN.Action.T(x)

"""
    profile_read(file::String; samples=10000)

Profile the read_dbn function using Julia's statistical profiler.
"""
function profile_read(file::String; samples=10000)
    println("\n" * "="^70)
    println("  PROFILING: read_dbn(\"$file\")")
    println("="^70)

    # Warmup
    println("\nWarming up...")
    records = read_dbn(file)
    record_count = length(records)
    println("File contains $(record_count) records")

    # Clear profile data
    Profile.clear()

    # Profile with high sample rate
    println("\nProfiling with $(samples) samples...")
    Profile.init(n=samples, delay=0.0001)  # 0.1ms sampling for finer granularity

    GC.gc()
    sleep(0.5)

    @profile begin
        for _ in 1:3  # Run multiple times for better statistics
            records = read_dbn(file)
        end
    end

    println("\nProfile complete!")

    return record_count
end

"""
    profile_streaming(file::String; samples=10000)

Profile the DBNStream iterator.
"""
function profile_streaming(file::String; samples=10000)
    println("\n" * "="^70)
    println("  PROFILING: DBNStream(\"$file\")")
    println("="^70)

    # Warmup
    println("\nWarming up...")
    count = 0
    for _ in DBNStream(file)
        count += 1
    end
    println("File contains $(count) records")

    # Clear profile data
    Profile.clear()

    # Profile
    println("\nProfiling with $(samples) samples...")
    Profile.init(n=samples, delay=0.001)

    GC.gc()
    sleep(0.5)

    @profile begin
        for _ in 1:3
            count = 0
            for _ in DBNStream(file)
                count += 1
            end
        end
    end

    println("\nProfile complete!")

    return count
end

"""
    micro_benchmark_operations()

Benchmark individual operations to identify specific bottlenecks.
"""
function micro_benchmark_operations()
    println("\n" * "="^70)
    println("  MICRO-BENCHMARKS: Individual Operations")
    println("="^70)

    # Create a small buffer to test with
    io = IOBuffer(rand(UInt8, 10000))
    buffered = DBN.BufferedReader(io)

    println("\n1. I/O Operations:")
    println("-"^70)

    # Test read performance
    print("  read(io, Int64):        ")
    seekstart(io)
    b1 = @benchmark read($io, Int64) setup=(seekstart($io))
    println(@sprintf("%.2f ns", minimum(b1.times)))

    print("  read(buffered, Int64):  ")
    seekstart(buffered.io)
    buffered.buffer_pos = 1
    buffered.buffer_size = 0
    b2 = @benchmark read($buffered, Int64) setup=(seekstart($buffered.io); $buffered.buffer_pos=1; $buffered.buffer_size=0)
    println(@sprintf("%.2f ns (%.2fx faster)", minimum(b2.times), minimum(b1.times)/minimum(b2.times)))

    println("\n2. String Operations:")
    println("-"^70)

    # Test string creation
    test_bytes = UInt8['T', 'E', 'S', 'T', '\0', '\0', '\0', '\0']

    print("  Current (double String + strip): ")
    b3 = @benchmark String(strip(String($test_bytes), '\0'))
    println(@sprintf("%.2f ns", minimum(b3.times)))

    print("  Optimized (find null first):     ")
    b4 = @benchmark fast_string_opt($test_bytes)
    println(@sprintf("%.2f ns (%.2fx faster)", minimum(b4.times), minimum(b3.times)/minimum(b4.times)))

    println("\n3. Enum Conversions:")
    println("-"^70)

    # Test safe vs unsafe enum conversion
    test_byte = UInt8(1)

    print("  safe_action(byte):    ")
    b5 = @benchmark DBN.safe_action($test_byte)
    println(@sprintf("%.2f ns", minimum(b5.times)))

    print("  unsafe Action.T(byte):")
    b6 = @benchmark unsafe_action($test_byte)
    println(@sprintf("%.2f ns (%.2fx faster)", minimum(b6.times), minimum(b5.times)/minimum(b6.times)))

    println("\n4. Struct Construction:")
    println("-"^70)

    # Test record creation
    hd = DBN.RecordHeader(UInt8(48), DBN.RType.MBP_0_MSG, UInt16(1), UInt32(12345), Int64(1234567890))

    print("  TradeMsg construction: ")
    b7 = @benchmark DBN.TradeMsg(
        $hd,
        Int64(1000000),
        UInt32(100),
        DBN.Action.TRADE,
        DBN.Side.BID,
        UInt8(0),
        UInt8(0),
        Int64(1234567890),
        Int32(0),
        UInt32(1)
    )
    println(@sprintf("%.2f ns", minimum(b7.times)))

    println()
end

"""
    analyze_allocations(file::String)

Analyze allocation patterns during decoding.

Run with: julia --track-allocation=user benchmark/profile_decode.jl --allocations
"""
function analyze_allocations(file::String)
    println("\n" * "="^70)
    println("  ALLOCATION ANALYSIS")
    println("="^70)
    println()
    println("NOTE: Run with: julia --track-allocation=user benchmark/profile_decode.jl")
    println()

    # Warmup to compile
    records = read_dbn(file)
    record_count = length(records)

    # Clear allocation counters
    Profile.clear_malloc_data()

    # Run once to track allocations
    GC.gc()
    records = read_dbn(file)

    println("Decoded $(record_count) records")
    println()
    println("Check .mem files in src/ directory for allocation hotspots:")
    println("  src/decode.jl.mem")
    println("  src/buffered_io.jl.mem")
    println("  src/messages.jl.mem")
    println()
    println("Lines with high allocation counts indicate bottlenecks.")
end

"""
    print_profile_results()

Print profile results in various formats.
"""
function print_profile_results()
    println("\n" * "="^70)
    println("  PROFILE RESULTS")
    println("="^70)

    println("\n1. Flat Profile (Top 20 functions by time):")
    println("-"^70)
    Profile.print(format=:flat, maxdepth=20, sortedby=:count)

    println("\n2. Tree Profile (Call hierarchy):")
    println("-"^70)
    Profile.print(format=:tree, maxdepth=10)

    # Try to generate flame graph if ProfileCanvas is available
    if HAS_PROFILE_CANVAS
        try
            println("\n3. Generating flame graph (profile_flamegraph.html)...")
            ProfileCanvas.html_file("profile_flamegraph.html")
            println("   ✓ Saved to profile_flamegraph.html")
        catch e
            println("   ✗ Error generating flame graph: $e")
        end
    else
        println("\n3. Flame graph not available")
        println("   Install ProfileCanvas with: Pkg.add(\"ProfileCanvas\")")
    end
end

"""
    compare_buffer_sizes()

Test different buffer sizes for BufferedReader.
"""
function compare_buffer_sizes()
    println("\n" * "="^70)
    println("  BUFFER SIZE COMPARISON")
    println("="^70)

    file = DEFAULT_FILE
    if !isfile(file)
        println("Test file not found: $file")
        return
    end

    buffer_sizes = [8192, 16384, 32768, 65536, 131072, 262144]  # 8KB to 256KB

    println("\nTesting different BufferedReader buffer sizes:")
    println(@sprintf("%-15s %12s %12s", "Buffer Size", "Time (s)", "Throughput"))
    println("-"^70)

    for buf_size in buffer_sizes
        # Modify DBN decoder to use custom buffer size
        # (This would require exposing buffer_size parameter)

        times = Float64[]
        for _ in 1:3
            GC.gc()
            sleep(0.1)

            # For now, just use default
            # In future: decoder = DBNDecoder(file, buffer_size=buf_size)
            t = @elapsed records = read_dbn(file)
            push!(times, t)
        end

        mean_time = mean(times)
        throughput = length(records) / mean_time

        # Note: Currently all use same 64KB default
        println(@sprintf("%-15s %12.4f %12.2f M/s",
                        "$(div(buf_size, 1024)) KB",
                        mean_time,
                        throughput / 1e6))
    end

    println("\nNote: Currently all use 64KB default (buffer size not yet parameterized)")
end

# Main function
function main()
    args = ARGS

    # Parse arguments
    file = DEFAULT_FILE
    mode = "profile"  # profile, micro, allocations, buffer

    i = 1
    while i <= length(args)
        arg = args[i]
        if arg == "--micro"
            mode = "micro"
        elseif arg == "--allocations"
            mode = "allocations"
        elseif arg == "--buffer"
            mode = "buffer"
        elseif arg == "--streaming"
            mode = "streaming"
        elseif !startswith(arg, "--")
            file = arg
        end
        i += 1
    end

    # Check file exists
    if !isfile(file)
        println("ERROR: File not found: $file")
        println("\nUsage: julia --project=. benchmark/profile_decode.jl [OPTIONS] [file.dbn]")
        println("\nOptions:")
        println("  --micro        Run micro-benchmarks of individual operations")
        println("  --allocations  Analyze allocation patterns (requires --track-allocation=user)")
        println("  --buffer       Compare different buffer sizes")
        println("  --streaming    Profile streaming iterator instead of full read")
        println("\nDefault file: $DEFAULT_FILE")
        return
    end

    # Run selected mode
    if mode == "micro"
        micro_benchmark_operations()
    elseif mode == "allocations"
        analyze_allocations(file)
    elseif mode == "buffer"
        compare_buffer_sizes()
    elseif mode == "streaming"
        record_count = profile_streaming(file)
        print_profile_results()
    else
        record_count = profile_read(file)
        print_profile_results()
    end

    println("\n" * "="^70)
    println("Profile analysis complete!")
    println("="^70)
end

# Run if executed as script
if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
