using DBN, BenchmarkTools

const TEST_FILE = "benchmark/data/trades.100k.dbn"

println("Quick benchmark: 100k records")
println("="^60)

println("\nStreaming (DBNStream):")
@btime begin 
    s = DBNStream($TEST_FILE)
    for _ in s; end
end samples=5

println("\nEager read (read_dbn):")
@btime read_dbn($TEST_FILE) samples=5

println("\n" * "="^60)
