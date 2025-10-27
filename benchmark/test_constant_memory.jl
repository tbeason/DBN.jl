using DBN

println("Testing that streaming memory stays constant...")
println("="^80)

# Warmup
stream = DBNStream("benchmark/data/trades.10k.dbn")
for _ in stream; end

# Test with progress reporting
println("\nStreaming through 10k records...")
stream2 = DBNStream("benchmark/data/trades.10k.dbn")

mem_samples = Int[]
for (i, _) in enumerate(stream2)
    if i % 1000 == 0
        GC.gc()
        mem = Base.gc_live_bytes() ÷ (1024^2)  # MB
        push!(mem_samples, mem)
        println("  After $i records: $(mem) MB")
    end
end

println("\n" * "="^80)
println("Memory samples: ", mem_samples)
if length(mem_samples) > 1
    max_mem = maximum(mem_samples)
    min_mem = minimum(mem_samples)
    variation = max_mem - min_mem
    println("Memory variation: $variation MB")
    if variation < 10
        println("✓ Memory usage is relatively constant (good for streaming)")
    else
        println("⚠ Memory usage varies significantly")
    end
end
println("="^80)
