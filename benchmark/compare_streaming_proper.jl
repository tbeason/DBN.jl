"""
Proper comparison of streaming vs eager with fresh instances
"""

using DBN, Statistics

const TEST_FILE = "benchmark/data/trades.100k.dbn"
const N_ITERATIONS = 10

println("Comparing streaming vs eager ($(N_ITERATIONS) iterations each)...")
println("="^80)

# Warmup
_ = read_dbn(TEST_FILE)
stream = DBNStream(TEST_FILE)
for _ in stream; end

println("\n1. Streaming (creating fresh stream each time):")
stream_times = Float64[]
for i in 1:N_ITERATIONS
    t = @elapsed begin
        stream = DBNStream(TEST_FILE)
        for _ in stream; end
    end
    push!(stream_times, t)
end
println("  Median time: $(median(stream_times)*1000) ms")
println("  Min time: $(minimum(stream_times)*1000) ms")
println("  Max time: $(maximum(stream_times)*1000) ms")

println("\n2. Eager read:")
eager_times = Float64[]
for i in 1:N_ITERATIONS
    t = @elapsed begin
        _ = read_dbn(TEST_FILE)
    end
    push!(eager_times, t)
end
println("  Median time: $(median(eager_times)*1000) ms")
println("  Min time: $(minimum(eager_times)*1000) ms")
println("  Max time: $(maximum(eager_times)*1000) ms")

ratio = median(stream_times) / median(eager_times)
println("\n" * "="^80)
if ratio < 1
    println("Streaming is $(round(1/ratio, digits=2))x FASTER")
else
    println("Streaming is $(round(ratio, digits=2))x SLOWER")
end
println("="^80)
