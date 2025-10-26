using DBN
using Profile
using Printf

# Use huge buffer: 100 million samples
Profile.init(n=100_000_000, delay=0.0001)

file = "benchmark/data/trades.1m.dbn"

println("Warming up...")
records = read_dbn(file)
record_count = length(records)
println("File contains $(record_count) records")

# Clear and profile
println("\nProfiling with 100M sample buffer...")
Profile.clear()
GC.gc()
sleep(0.5)

@profile begin
    for _ in 1:3
        records = read_dbn(file)
    end
end

println("\nProfile complete! Analyzing...\n")

# Print detailed flat profile
println("="^70)
println("FLAT PROFILE (Top 50 functions by sample count)")
println("="^70)
Profile.print(format=:flat, maxdepth=50, sortedby=:count, noisefloor=1.0)

println("\n" * "="^70)
println("TREE PROFILE (Call hierarchy)")
println("="^70)
Profile.print(format=:tree, maxdepth=20)
