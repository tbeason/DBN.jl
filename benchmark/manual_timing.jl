using DBN

const TEST_FILE = "benchmark/data/trades.10k.dbn"

println("Manual timing test...")
println("="^80)

# Test 1: Streaming with construction
println("\n1. Streaming (including construction):")
@time begin
    stream = DBNStream(TEST_FILE)
    for _ in stream; end
end

# Test 2: Streaming (reusing stream - should be fast but empty)
println("\n2. Streaming (reusing exhausted stream):")
stream2 = DBNStream(TEST_FILE)
for _ in stream2; end  # First iteration (real work)
@time begin
    for _ in stream2; end  # Second iteration (should be instant - already exhausted)
end

# Test 3: Eager read
println("\n3. Eager read:")
@time recs = read_dbn(TEST_FILE)

println("\n="^80)
