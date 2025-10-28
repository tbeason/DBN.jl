# Performance

DBN.jl is designed for high-throughput market data processing. This page provides performance characteristics, benchmarks, and optimization tips.

## Performance Summary

| Operation | Best Method | Throughput | Memory |
|-----------|-------------|------------|--------|
| **Reading** | Callback streaming | 40M rec/sec | Minimal (KB) |
| **Reading** | Type-specific reader | 28M rec/sec | Full file |
| **Reading** | Generic iterator | 10M rec/sec | Moderate |
| **Writing** | Bulk write | 11M rec/sec | Full file |
| **Writing** | Stream writer | 10M rec/sec | Half file |

*Benchmarks: 10M trade messages on modern hardware*

## Reading Performance

### Method Comparison (10M Trades, Uncompressed)

| Method | Throughput | Time | Memory |
|--------|------------|------|--------|
| `foreach_trade()` callback | 42.37 M/s | 0.236s | 0.1 MB |
| `read_trades()` optimized | 27.94 M/s | 0.358s | 458 MB |
| `DBNStream()` iterator | 10.21 M/s | 0.979s | 1221 MB |
| `read_dbn()` generic | 6.86 M/s | 1.457s | 687 MB |

**Key Takeaways:**
- Callback streaming is **6x faster** than generic read
- Type-specific readers are **4x faster** than generic read
- Callbacks use **~6,000x less memory** than iterators

### With Compression (.zst)

| Method | Throughput | Time | Memory |
|--------|------------|------|--------|
| `foreach_trade()` callback | 19.24 M/s | 0.520s | 0.8 MB |
| `read_trades()` optimized | 15.65 M/s | 0.639s | 459 MB |
| `DBNStream()` iterator | 5.94 M/s | 1.683s | 1222 MB |
| `read_dbn()` generic | 4.74 M/s | 2.109s | 687 MB |

Compression reduces throughput by ~50% but file sizes by ~3x.

## Writing Performance

### Method Comparison (10M Trades)

| Method | Compressed | Throughput | Time | Memory |
|--------|------------|------------|------|--------|
| `write_dbn()` | No | 11.57 M/s | 0.864s | 1221 MB |
| `DBNStreamWriter` | No | 11.82 M/s | 0.846s | 610 MB |
| `write_dbn()` | Yes (.zst) | 4.70 M/s | 2.125s | 1221 MB |
| `DBNStreamWriter` | Yes (.zst) | 11.27 M/s | 0.887s | 610 MB |

**Key Takeaways:**
- Streaming writer uses **50% less memory**
- Bulk write and stream write have similar throughput
- Compression adds overhead but reduces file size significantly

## Schema-Specific Performance

Different message types have different performance characteristics due to record size and complexity.

### Read Performance by Schema (10M records, uncompressed)

| Schema | Callback | Type-Specific | Generic |
|--------|----------|---------------|---------|
| **Trades** | 42.37 M/s | 27.94 M/s | 6.86 M/s |
| **MBO** | 34.17 M/s | 23.35 M/s | 2.94 M/s |
| **OHLCV** | 41.33 M/s | 24.90 M/s | 6.49 M/s |

Larger records (MBO) are slightly slower due to more data transfer.

## File Size and Compression

### Compression Ratios

| Schema | Uncompressed | Compressed (.zst) | Ratio |
|--------|--------------|-------------------|-------|
| **Trades** (1M) | 46 MB | 16 MB | 2.9x |
| **MBO** (1M) | 53 MB | 18 MB | 2.9x |
| **OHLCV** (10M) | 534 MB | 279 MB | 1.9x |

**Recommendation**: Use `.zst` compression for storage and archival.

### Format Comparison (1M Trades)

| Format | Size | Ratio vs DBN |
|--------|------|--------------|
| DBN (compressed) | 16 MB | 1.0x (best) |
| DBN (uncompressed) | 46 MB | 2.9x |
| Parquet | 25 MB | 1.6x |
| CSV | 95 MB | 5.9x |
| JSON | 180 MB | 11.3x |

## Optimization Tips

### 1. Choose the Right Reading Method

```julia
# ✅ For processing/aggregation - use callbacks (fastest)
total = Ref(0)
foreach_trade("file.dbn") do trade
    total[] += trade.size
end

# ✅ For bulk loading - use type-specific readers
trades = read_trades("file.dbn")  # 5-6x faster than read_dbn()

# ✅ For flexible iteration - use DBNStream
for trade in DBNStream("file.dbn")
    if some_condition(trade)
        break  # Can exit early
    end
end

# ❌ Avoid generic reader when schema is known
records = read_dbn("trades.dbn")  # Slower!
```

### 2. Use Type-Specific Readers

```julia
# ❌ Generic (slow)
records = read_dbn("trades.dbn")

# ✅ Type-specific (5-6x faster)
trades = read_trades("trades.dbn")
```

### 3. Stream Large Files

```julia
# ❌ Don't load huge files into memory
all_data = read_trades("100gb_file.dbn")  # Will exhaust memory!

# ✅ Stream instead
foreach_trade("100gb_file.dbn") do trade
    process(trade)
end
```

### 4. Use Compression for Storage

```julia
# ✅ 2-3x smaller files
write_dbn("output.dbn.zst", metadata, records)

# ❌ Larger files
write_dbn("output.dbn", metadata, records)
```

### 5. Pre-allocate Collections

```julia
# ✅ Pre-allocate when size is known
filtered = Vector{TradeMsg}()
sizehint!(filtered, expected_count)

foreach_trade("file.dbn") do trade
    if condition(trade)
        push!(filtered, trade)
    end
end
```

### 6. Minimize Work in Loops

```julia
# ✅ Hoist constant computations
threshold = calculate_threshold()
foreach_trade("file.dbn") do trade
    if trade.size > threshold
        process(trade)
    end
end

# ❌ Don't repeat expensive operations
foreach_trade("file.dbn") do trade
    if trade.size > calculate_threshold()  # Repeated!
        process(trade)
    end
end
```

### 7. Use Refs for Callback Accumulation

```julia
# ✅ Use Ref for mutable state in callbacks
count = Ref(0)
foreach_trade("file.dbn") do trade
    count[] += 1
end

# ❌ Won't work (immutable)
count = 0
foreach_trade("file.dbn") do trade
    count += 1  # ERROR: count is immutable in this scope
end
```

## Comparison with Other Implementations

DBN.jl performance compared to official implementations:

### Read Performance (Trades, Uncompressed)

| Implementation | Size | Throughput |
|----------------|------|------------|
| **DBN.jl (callback)** | 10M | 42.37 M/s |
| **DBN.jl (optimized)** | 10M | 27.94 M/s |
| Python databento-dbn | 10M | 9.23 M/s |
| Rust dbn | - | (Reference) |

DBN.jl callback streaming is **4.5x faster** than Python implementation.

### Write Performance (Trades, Uncompressed)

| Implementation | Size | Throughput |
|----------------|------|------------|
| **DBN.jl** | 10M | 11.57 M/s |
| Python databento-dbn | 10M | 43.79 M/s |

Python has faster write performance due to optimized C extensions.

## Hardware Impact

Performance scales with:
- **CPU speed**: Single-threaded performance matters most
- **Memory bandwidth**: Important for bulk operations
- **SSD speed**: Matters for large compressed files
- **Available RAM**: Determines max file size for bulk reads

## Benchmarking Your System

Run benchmarks on your hardware:

```julia
using DBN, BenchmarkTools

# Download test data or generate synthetic data
# trades = generate_test_trades(10_000_000)
# write_dbn("test.dbn", metadata, trades)

# Benchmark reading
@benchmark read_trades("test.dbn")
@benchmark foreach_trade("test.dbn") do t; end

# Benchmark writing
@benchmark write_dbn("out.dbn", $metadata, $trades)
```

## See Also

- [Reading Guide](guide/reading.md) - Detailed reading methods
- [Streaming Guide](guide/streaming.md) - Streaming patterns
- [Writing Guide](guide/writing.md) - Writing methods
- Full benchmarks: `benchmark/PERFORMANCE_REPORT.md` in repository
