using DBN, BenchmarkTools

const TEST_FILE = "benchmark/data/trades.100k.dbn"

println("Testing Typed Streaming Performance")
println("="^80)

# Warmup
_ = read_dbn(TEST_FILE)
for _ in DBNStream(TEST_FILE); end
for _ in stream_trades(TEST_FILE); end

println("\n1. Generic Streaming (DBNStream):")
@btime begin
    s = DBNStream($TEST_FILE)
    for _ in s; end
end samples=5

println("\n2. Typed Streaming (stream_trades):")
@btime begin
    s = stream_trades($TEST_FILE)
    for _ in s; end
end samples=5

println("\n3. Eager Optimized Read (read_trades):")
@btime read_trades($TEST_FILE) samples=5

println("\n4. Eager Generic Read (read_dbn):")
@btime read_dbn($TEST_FILE) samples=5

println("\n" * "="^80)
println("Expected: Typed streaming should be faster than generic streaming")
println("due to elimination of Union type overhead")
println("="^80)
