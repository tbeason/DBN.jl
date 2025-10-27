using DBN, BenchmarkTools

const TEST_FILE = "benchmark/data/trades.100k.dbn"

println("Comparing decode cost vs storage cost")
println("="^80)

# Warmup
_ = read_trades(TEST_FILE)
for _ in stream_trades(TEST_FILE); end

println("\n1. Streaming (decode + yield):")
@btime begin
    for _ in stream_trades($TEST_FILE); end
end samples=5

println("\n2. Eager optimized (decode + store in vector):")
@btime read_trades($TEST_FILE) samples=5

println("\n3. Streaming but COLLECTING results:")
@btime begin
    trades = TradeMsg[]
    sizehint!(trades, 100000)
    for t in stream_trades($TEST_FILE)
        push!(trades, t)
    end
    trades
end samples=5

println("\n" * "="^80)
println("ANALYSIS:")
println("If streaming+collecting is similar to eager, then yielding has overhead.")
println("If streaming+collecting is much slower, then vector storage is cheap.")
println("="^80)
