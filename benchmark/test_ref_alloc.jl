using DBN

# Warmup
println("Warming up...")
stream = DBNStream("benchmark/data/trades.10k.dbn")
for _ in stream; end

# Test 1: Current implementation with Ref
println("\nTest 1: With Ref{Bool}")
GC.gc()
@time begin
    stream = DBNStream("benchmark/data/trades.10k.dbn")
    for _ in stream; end
end

# Test 2: Check construction cost
println("\nTest 2: Just construction (no iteration)")
GC.gc()
@time begin
    stream = DBNStream("benchmark/data/trades.10k.dbn")
end

println("\nLooking at allocations:")
println("- If 'just construction' shows significant allocations,")
println("  they're from DBNDecoder creation (file opening, buffering)")
println("- The iteration allocations are: record + tuple + ???")
