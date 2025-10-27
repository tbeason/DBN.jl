"""
Test if the iterator overhead is the issue
"""

using DBN, BenchmarkTools

const TEST_FILE = "benchmark/data/trades.10k.dbn"

println("Comparing decode speeds...")
println("="^80)

# Option 1: Manual loop like eager read does
println("\n1. Manual decoder loop (like eager read):")
@btime begin
    decoder = DBNDecoder($TEST_FILE)
    count = 0
    while !eof(decoder.io)
        record = read_record(decoder)
        if record !== nothing
            count += 1
        end
    end
    # Cleanup
    if decoder.io !== decoder.base_io
        close(decoder.io)
    end
    if isa(decoder.base_io, IOStream)
        close(decoder.base_io)
    end
    GC.gc()
end samples=5

# Option 2: Iterator (like DBNStream) - must create fresh stream each time
println("\n2. Iterator protocol (like DBNStream):")
@btime begin
    stream = DBNStream($TEST_FILE)
    for _ in stream; end
end samples=5

println("\n3. Eager read (for reference):")
@btime read_dbn($TEST_FILE) samples=5

println("\n="^80)
