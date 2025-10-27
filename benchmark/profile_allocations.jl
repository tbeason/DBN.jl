"""
Profile where allocations are happening in streaming
"""

using DBN, Profile

const TEST_FILE = "benchmark/data/trades.10k.dbn"

println("Allocation profiling...")
println("="^80)

# Test 1: Count allocations in streaming
println("\n1. Streaming allocations:")
Profile.Allocs.clear()
Profile.Allocs.@profile sample_rate=1.0 begin
    stream = DBNStream(TEST_FILE)
    for _ in stream; end
end

results = Profile.Allocs.fetch()
allocs = results.allocs

println("Total allocations: $(length(allocs))")

# Group by type
type_counts = Dict{String, Int}()
for alloc in allocs
    type_str = string(alloc.type)
    type_counts[type_str] = get(type_counts, type_str, 0) + 1
end

println("\nTop allocation types:")
sorted = sort(collect(type_counts), by=x->x[2], rev=true)
for (i, (type, count)) in enumerate(sorted[1:min(15, end)])
    println("  $i. $type: $count allocations")
end

# Test 2: Compare with eager read
println("\n" * "="^80)
println("2. Eager read allocations:")
Profile.Allocs.clear()
Profile.Allocs.@profile sample_rate=1.0 begin
    recs = read_dbn(TEST_FILE)
end

results2 = Profile.Allocs.fetch()
allocs2 = results2.allocs

println("Total allocations: $(length(allocs2))")

type_counts2 = Dict{String, Int}()
for alloc in allocs2
    type_str = string(alloc.type)
    type_counts2[type_str] = get(type_counts2, type_str, 0) + 1
end

println("\nTop allocation types:")
sorted2 = sort(collect(type_counts2), by=x->x[2], rev=true)
for (i, (type, count)) in enumerate(sorted2[1:min(15, end)])
    println("  $i. $type: $count allocations")
end

println("\n" * "="^80)
println("DIFFERENCE ANALYSIS")
println("="^80)

println("\nTypes allocated MORE in streaming:")
for (type, count) in sort(collect(type_counts), by=x->x[2], rev=true)[1:10]
    eager_count = get(type_counts2, type, 0)
    if count > eager_count
        diff = count - eager_count
        println("  $type: +$diff (streaming: $count, eager: $eager_count)")
    end
end

println("\n="^80)
