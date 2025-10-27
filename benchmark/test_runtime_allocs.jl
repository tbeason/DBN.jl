"""
Test runtime allocations after compilation/warmup
"""

using DBN

const TEST_FILE = "benchmark/data/trades.10k.dbn"

println("Runtime allocation test (after warmup)...")
println("="^80)

# Warmup both
println("\nWarming up...")
_ = read_dbn(TEST_FILE)
stream = DBNStream(TEST_FILE)
for _ in stream; end

# Test streaming
println("\n1. Streaming (after warmup):")
GC.gc()
@time begin
    stream = DBNStream(TEST_FILE)
    for _ in stream; end
end
GC.gc()

# Test eager  
println("\n2. Eager read (after warmup):")
GC.gc()
allocs_before_eager = Base.gc_live_bytes()
@time begin
    recs = read_dbn(TEST_FILE)
end
GC.gc()
allocs_after_eager = Base.gc_live_bytes()
println("Records loaded: ", length(recs))

# Analysis
println("\n" * "="^80)
println("ANALYSIS")
println("="^80)

# Get actual allocation info from @time output above
println("\nCheck the allocation counts from @time output above:")
println("- Streaming should show ~20k allocations (2 per record)")
println("- Eager should show ~10k allocations (1 per record)")
println("\nThe extra allocation in streaming is from the tuple (record, nothing)")
println("returned by the iterator protocol on each iteration.")

println("\n="^80)
