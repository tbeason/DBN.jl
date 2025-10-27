using DBN

const TEST_FILE = "benchmark/data/trades.10k.dbn"

println("Verifying streaming reads all records...")

stream_count = sum(1 for _ in DBNStream(TEST_FILE))
println("Stream count: $stream_count")

recs = read_dbn(TEST_FILE)
println("Eager count: $(length(recs))")

if stream_count == length(recs)
    println("✓ Counts match!")
else
    println("✗ ERROR: Counts don't match!")
end
