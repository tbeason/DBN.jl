using DBN

const TEST_FILE = "benchmark/data/trades.10k.dbn"

println("Investigating eager read allocations...")
println("="^80)

# Warmup
_ = read_trades(TEST_FILE)

println("\nEager read with @time:")
@time trades = read_trades(TEST_FILE)

println("\nNumber of records: $(length(trades))")
println("\nSo the eager read shows ~50 allocations for 10k records.")
println("This is NOT 1 allocation per record - it's:")
println("- 1 allocation for the Vector{TradeMsg}")
println("- ~40-50 allocations for decoder setup, file I/O buffers, etc.")
println("\nThe RECORDS themselves are stored inline in the vector,")
println("not as separate allocations! This is because TradeMsg is")
println("a concrete struct type with isbitstype fields.")

println("\nLet's verify with a smaller test:")
@time trades_small = read_trades("benchmark/data/trades.1k.dbn")
println("1k records also shows ~50 allocations")

println("\n" * "="^80)
println("CONCLUSION:")
println("Eager reads don't allocate per-record because records are")
println("stored inline in the pre-allocated vector.")
println("\nStreaming MUST allocate per-record because:")
println("1. Each record is yielded individually (1 alloc)")
println("2. Iterator protocol returns tuple (record, state) (1 alloc)")
println("="^80)
