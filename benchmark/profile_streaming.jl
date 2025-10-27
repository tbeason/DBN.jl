"""
Profile streaming vs eager read performance to identify bottlenecks

Usage: julia --project=. benchmark/profile_streaming.jl
"""

using DBN, Profile, BenchmarkTools, Printf

# Test with 100k records file
const TEST_FILE = "benchmark/data/trades.100k.dbn"

println("="^80)
println("STREAMING VS EAGER READ COMPARISON")
println("="^80)
println()

# 1. Memory usage comparison
println("1. MEMORY USAGE:")
println("-"^80)

println("Eager read (read_dbn):")
@time recs_eager = read_dbn(TEST_FILE)
println("  Records: $(length(recs_eager))")
println()

println("Streaming read (DBNStream - iterate and discard):")
count_stream = 0
@time begin
    global count_stream = 0
    for _ in DBNStream(TEST_FILE)
        global count_stream += 1
    end
end
println("  Records: $(count_stream)")
println()

# 2. Speed comparison
println("\n2. SPEED COMPARISON:")
println("-"^80)

println("Eager read:")
@benchmark read_dbn($TEST_FILE) samples=10

println("\nStreaming read:")
@benchmark begin
    for _ in DBNStream($TEST_FILE); end
end samples=10

# 3. Allocation profiling
println("\n3. ALLOCATION ANALYSIS:")
println("-"^80)

println("Single streaming iteration:")
@time @allocated begin
    for _ in DBNStream(TEST_FILE); end
end

println("\n4. DETAILED ALLOCATION TRACKING:")
println("-"^80)
using Profile
Profile.Allocs.clear()
Profile.Allocs.@profile sample_rate=1.0 begin
    for _ in DBNStream(TEST_FILE); end
end

results = Profile.Allocs.fetch()
println("Total allocations tracked: $(length(results.allocs))")
if length(results.allocs) > 0
    println("\nFirst 10 allocations:")
    for (i, alloc) in enumerate(results.allocs[1:min(10, end)])
        println("  $i. Type: $(alloc.type), Size: $(alloc.size) bytes")
    end
end

println("\n" * "="^80)
println("ANALYSIS COMPLETE")
println("="^80)
