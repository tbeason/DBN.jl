# Reading Data

DBN.jl provides multiple ways to read DBN files, each optimized for different use cases. This guide helps you choose the right approach for your needs.

## Quick Reference

| Method | Best For | Performance | Memory Usage |
|--------|----------|-------------|--------------|
| `foreach_*()` callbacks | Processing/aggregation | ⚡⚡⚡ Fastest (40M rec/sec) | Minimal |
| `read_trades()`, etc. | Bulk loading single schema | ⚡⚡ Fast (5-6x generic) | Full file |
| `DBNStream()` iterator | Large files, mixed schemas | ⚡ Moderate | Minimal |
| `read_dbn()` generic | Quick exploration, mixed schemas | Baseline | Full file |

## Reading Approaches

### Approach 1: Type-Specific Readers (Recommended for Bulk Loading)

When you know the schema and want to load the entire file into memory:

```julia
# 5-6x faster than generic read_dbn()
trades = read_trades("trades.dbn")
mbos = read_mbo("mbo.dbn")
ohlcv = read_ohlcv("ohlcv.dbn")
```

**Available readers:**
- `read_trades()` - Trade messages
- `read_mbo()` - Market-by-order messages
- `read_mbp1()` - Top-of-book market-by-price
- `read_mbp10()` - 10-level market-by-price
- `read_tbbo()` - Top-of-book BBO
- `read_ohlcv()` - OHLCV bars (generic)
- `read_ohlcv_1s()`, `read_ohlcv_1m()`, `read_ohlcv_1h()`, `read_ohlcv_1d()` - Time-specific OHLCV

Plus additional readers for other schemas. See the [API Reference](../api/reading.md) for the complete list.

**When to use:**
- You need all records in memory
- Working with single-schema files
- Performance is important
- File size fits in available RAM

**Example:**
```julia
using DBN

# Read trades file
trades = read_trades("AAPL_trades_2024-01-01.dbn.zst")

# All records are now in a Vector{TradeMsg}
println("Loaded $(length(trades)) trades")

# Direct access to any record
first_trade = trades[1]
println("First trade: price=$(price_to_float(first_trade.price)), size=$(first_trade.size)")
```

### Approach 2: Callback Streaming (Recommended for Processing)

For maximum performance when you don't need to keep all records in memory:

```julia
# Near-zero allocation, up to 40M records/sec
total_volume = Ref(0)
foreach_trade("large_file.dbn.zst") do trade
    total_volume[] += trade.size
end
```

**Available callback functions:**
- `foreach_trade()` - Stream trades
- `foreach_mbo()` - Stream MBO messages
- `foreach_mbp1()` - Stream top-of-book
- `foreach_mbp10()` - Stream 10-level depth
- `foreach_ohlcv()` - Stream OHLCV bars
- And more... (see [Streaming API](../api/streaming.md))

**When to use:**
- Processing or aggregating data (sums, statistics, filters)
- Files too large for available RAM
- Maximum performance needed
- You don't need random access to records

**Example: Calculate VWAP**
```julia
using DBN

total_price_volume = Ref(0.0)
total_volume = Ref(0)

foreach_trade("trades.dbn") do trade
    price = price_to_float(trade.price)
    total_price_volume[] += price * trade.size
    total_volume[] += trade.size
end

vwap = total_price_volume[] / total_volume[]
println("VWAP: $vwap")
```

**Example: Filter and Save**
```julia
# Extract high-volume trades
high_volume = TradeMsg[]
foreach_trade("all_trades.dbn") do trade
    if trade.size >= 10_000
        push!(high_volume, trade)
    end
end

# Write filtered results
metadata, _ = read_dbn_with_metadata("all_trades.dbn")
write_dbn("high_volume.dbn", metadata, high_volume)
```

### Approach 3: Iterator Pattern (For Flexibility)

When you need streaming but want more control than callbacks:

```julia
for record in DBNStream("file.dbn")
    # Process record
    println("Price: $(price_to_float(record.price))")

    # Can break early if needed
    if some_condition
        break
    end
end
```

**When to use:**
- Need to break out of loop early
- Complex control flow
- Mixed-schema files
- Memory-efficient iteration

**Example: Find First Record Matching Condition**
```julia
using DBN

function find_first_large_trade(filename, threshold)
    for trade in DBNStream(filename)
        if trade.size >= threshold
            return trade
        end
    end
    return nothing
end

large_trade = find_first_large_trade("trades.dbn", 50_000)
if large_trade !== nothing
    println("Found trade: $(price_to_float(large_trade.price)) @ $(large_trade.size)")
end
```

### Approach 4: Generic Reader (For Quick Exploration)

Simple, but slower than type-specific readers:

```julia
# Works with any schema, but 5-6x slower
records = read_dbn("file.dbn")

# With metadata
metadata, records = read_dbn_with_metadata("file.dbn")
```

**When to use:**
- Quick exploration
- Unknown schema
- Small files where performance doesn't matter
- Prototyping

**Example:**
```julia
using DBN

# Quick look at a file
metadata, records = read_dbn_with_metadata("unknown.dbn")
println("Schema: $(metadata.schema)")
println("Records: $(length(records))")
println("First record type: $(typeof(records[1]))")
```

## Working with Compressed Files

All reading methods transparently handle Zstd compression:

```julia
# Compression is auto-detected by .zst extension
trades = read_trades("file.dbn.zst")

foreach_trade("compressed.dbn.zst") do trade
    # Process compressed data
end

for record in DBNStream("data.dbn.zst")
    # Iterate compressed data
end
```

No special handling needed - DBN.jl detects compression automatically!

## Reading Metadata

Get file metadata without reading all records:

```julia
# Read only metadata (fast)
metadata, records = read_dbn_with_metadata("file.dbn")

# Metadata fields
println("Dataset: $(metadata.dataset)")
println("Schema: $(metadata.schema)")
println("Start: $(ts_to_datetime(metadata.start_ts))")
println("End: $(ts_to_datetime(metadata.end_ts))")
println("Limit: $(metadata.limit)")
println("Symbol type: $(metadata.stype_in) → $(metadata.stype_out)")
```

## Mixed-Schema Files

For files containing multiple message types:

```julia
# Generic reading
records = read_dbn("mixed_schema.dbn")

# Type checking
for record in records
    if record isa TradeMsg
        # Handle trade
    elseif record isa MBOMsg
        # Handle MBO
    elseif record isa OHLCVMsg
        # Handle OHLCV
    end
end
```

Or with streaming:

```julia
for record in DBNStream("mixed.dbn")
    if record isa TradeMsg
        process_trade(record)
    elseif record isa MBOMsg
        process_mbo(record)
    end
end
```

## Performance Tips

### 1. Use Type-Specific Readers When Possible
```julia
# ❌ Slower (generic)
records = read_dbn("trades.dbn")

# ✅ Faster (5-6x speedup)
trades = read_trades("trades.dbn")
```

### 2. Use Callbacks for Pure Processing
```julia
# ❌ Slower (allocates array)
trades = read_trades("huge_file.dbn")
total = sum(t.size for t in trades)

# ✅ Faster (near-zero allocation)
total = Ref(0)
foreach_trade("huge_file.dbn") do trade
    total[] += trade.size
end
```

### 3. Pre-allocate for Filtering
```julia
# ✅ Pre-allocate if you know approximate size
filtered = Vector{TradeMsg}()
sizehint!(filtered, 100_000)  # Reserve space

foreach_trade("file.dbn") do trade
    if trade.size > 1000
        push!(filtered, trade)
    end
end
```

### 4. Process Compressed Files Directly
```julia
# ✅ No need to decompress first
foreach_trade("file.dbn.zst") do trade
    # Process directly from compressed file
end
```

## Error Handling

```julia
using DBN

try
    records = read_dbn("file.dbn")
catch e
    if e isa SystemError
        println("File not found or cannot be opened")
    elseif e isa ErrorException
        println("Error reading file: $(e.msg)")
    else
        rethrow(e)
    end
end
```

## Common Patterns

### Count Records by Type
```julia
counts = Dict{Symbol, Int}()

for record in DBNStream("mixed.dbn")
    type_name = Symbol(typeof(record))
    counts[type_name] = get(counts, type_name, 0) + 1
end

for (type, count) in counts
    println("$type: $count")
end
```

### Extract Time Range
```julia
using Dates

start_time = datetime_to_ts(DateTime(2024, 1, 1, 9, 30))
end_time = datetime_to_ts(DateTime(2024, 1, 1, 16, 0))

filtered = TradeMsg[]
foreach_trade("file.dbn") do trade
    if start_time <= trade.hd.ts_event <= end_time
        push!(filtered, trade)
    end
end
```

### Sample Every Nth Record
```julia
sampled = TradeMsg[]
counter = Ref(0)

foreach_trade("file.dbn") do trade
    counter[] += 1
    if counter[] % 100 == 0  # Keep every 100th record
        push!(sampled, trade)
    end
end
```

## See Also

- [Writing Data](writing.md) - How to write DBN files
- [Streaming Guide](streaming.md) - Detailed streaming documentation
- [Performance Guide](../performance.md) - Optimization techniques
- [API Reference - Reading](../api/reading.md) - Complete function reference
- [Databento Schemas](https://databento.com/docs/schemas-and-data-formats) - Schema details
