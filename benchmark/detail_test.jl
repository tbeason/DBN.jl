using DBN

const TEST_FILE = "benchmark/data/trades.100k.dbn"

println("Detailed test with memory tracking...")
println("="^80)

# Test streaming with fresh GC
println("\n1. Streaming (with GC before/after):")
GC.gc()
@time begin
    stream = DBNStream(TEST_FILE)
    count = 0
    for _ in stream
        count += 1
    end
    println("  Count: $count")
end
GC.gc()

# Test eager with fresh GC
println("\n2. Eager read (with GC before/after):")
GC.gc()
@time begin
    recs = read_dbn(TEST_FILE)
    println("  Count: $(length(recs))")
end
GC.gc()

println("\n="^80)
