using DBN, BenchmarkTools

const TEST_FILE = "benchmark/data/trades.100k.dbn"

println("Testing Callback-Based Zero-Allocation Streaming")
println("="^80)

# Warmup
_ = read_trades(TEST_FILE)
for _ in stream_trades(TEST_FILE); end
foreach_trade(TEST_FILE) do t; end

println("\n1. Callback streaming (foreach_trade):")
@btime begin
    foreach_trade($TEST_FILE) do trade
        # Just consume, don't store
    end
end samples=5

println("\n2. Iterator streaming (stream_trades):")
@btime begin
    for _ in stream_trades($TEST_FILE); end
end samples=5

println("\n3. Eager optimized (read_trades):")
@btime read_trades($TEST_FILE) samples=5

println("\n4. Callback with actual work (sum prices):")
@btime begin
    total = 0.0
    foreach_trade($TEST_FILE) do trade
        total += price_to_float(trade.price)
    end
    total
end samples=5

println("\n5. Iterator with same work (sum prices):")
@btime begin
    total = 0.0
    for trade in stream_trades($TEST_FILE)
        total += price_to_float(trade.price)
    end
    total
end samples=5

println("\n" * "="^80)
println("Expected: Callback streaming should have minimal allocations")
println("and potentially be faster than iterator streaming")
println("="^80)
