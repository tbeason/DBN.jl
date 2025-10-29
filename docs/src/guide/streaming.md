# Streaming

Streaming is essential for working with large DBN files that don't fit in memory or when you want maximum performance. DBN.jl provides two streaming patterns: **callback-based** (fastest) and **iterator-based** (most flexible).

## Why Stream?

**Memory Efficiency**: Process files larger than your available RAM
- A 10M record trade file (~460 MB) requires only KB of memory when streaming
- Can process billion-record files on modest hardware

**Performance**: Callback streaming achieves up to 40M records/sec
- Near-zero allocations during processing
- Minimal overhead per record
- Optimal for aggregation and filtering

**Flexibility**: Process data as it's read
- Early termination when condition is met
- Real-time processing
- Conditional logic during iteration

## Callback Pattern (Fastest)

The callback pattern uses `foreach_*()` functions for maximum performance.

### Basic Usage

```julia
using DBN

# Process all trades with a callback
total_volume = Ref(0)
foreach_trade("trades.dbn") do trade
    total_volume[] += trade.size
end
println("Total volume: $(total_volume[])")
```

### Available Callback Functions

**Market Data:**
- `foreach_trade()` - Trade messages
- `foreach_mbo()` - Market-by-order
- `foreach_mbp1()` - Top-of-book MBP
- `foreach_mbp10()` - 10-level MBP
- `foreach_tbbo()` - Top BBO
- `foreach_ohlcv()` - OHLCV bars (generic)
- `foreach_ohlcv_1s()`, `foreach_ohlcv_1m()`, `foreach_ohlcv_1h()`, `foreach_ohlcv_1d()` - Time-specific OHLCV

**Other Schemas:**
- `foreach_cmbp1()` - Consolidated MBP-1
- `foreach_cbbo1s()`, `foreach_cbbo1m()` - Consolidated BBO
- `foreach_tcbbo()` - Top consolidated BBO
- `foreach_bbo1s()`, `foreach_bbo1m()` - BBO

And more! See the [Streaming API Reference](../api/streaming.md) for the complete list.

### Performance Characteristics

Callback streaming achieves exceptional performance through:
- **Zero allocation** per record (records reused internally)
- **Type stability** (compiler optimizes callback)
- **Minimal overhead** (direct function calls)

**Benchmark results** (10M trades, uncompressed):
```
Callback streaming:  42.37 M records/sec (0.236s, 0.1 MB allocated)
Iterator streaming:  10.21 M records/sec (0.979s, 1221 MB allocated)
Bulk read:           6.86 M records/sec  (1.457s, 687 MB allocated)
```

### Common Patterns

#### Aggregation

```julia
using DBN

# Calculate VWAP
price_volume_sum = Ref(0.0)
volume_sum = Ref(0)

foreach_trade("trades.dbn.zst") do trade
    price = price_to_float(trade.price)
    price_volume_sum[] += price * trade.size
    volume_sum[] += trade.size
end

vwap = price_volume_sum[] / volume_sum[]
println("VWAP: $vwap")
```

#### Counting

```julia
# Count by side
bid_count = Ref(0)
ask_count = Ref(0)

foreach_trade("trades.dbn") do trade
    if trade.side == Side.BID
        bid_count[] += 1
    else
        ask_count[] += 1
    end
end

println("Bids: $(bid_count[]), Asks: $(ask_count[])")
```

#### Filtering (with collection)

```julia
# Extract specific records
large_trades = TradeMsg[]

foreach_trade("all_trades.dbn") do trade
    if trade.size > 10_000
        push!(large_trades, trade)
    end
end

println("Found $(length(large_trades)) large trades")
```

#### Time-windowed Aggregation

```julia
using Dates

# Group trades into 5-minute buckets
buckets = Dict{DateTime, Int}()

foreach_trade("trades.dbn") do trade
    bucket = floor(ts_to_datetime(trade.hd.ts_event), Minute(5))
    buckets[bucket] = get(buckets, bucket, 0) + trade.size
end

# Print volume per bucket
for (time, volume) in sort(collect(buckets))
    println("$time: $volume")
end
```

#### Statistical Calculation

```julia
# Calculate mean and std dev of trade sizes (online algorithm)
n = Ref(0)
mean = Ref(0.0)
m2 = Ref(0.0)

foreach_trade("trades.dbn") do trade
    n[] += 1
    delta = trade.size - mean[]
    mean[] += delta / n[]
    m2[] += delta * (trade.size - mean[])
end

variance = m2[] / n[]
stddev = sqrt(variance)

println("Mean size: $(mean[])")
println("Std dev: $stddev")
```

### Limitations

!!! warning "Cannot Break Early"
    Callback functions process all records - you cannot break out early. Use the iterator pattern if you need early termination.

```julia
# ❌ Cannot do this with callbacks
foreach_trade("trades.dbn") do trade
    if trade.size > 100_000
        break  # ERROR: Cannot break from callback
    end
end

# ✅ Use iterator instead
for trade in DBNStream("trades.dbn")
    if trade.size > 100_000
        println("Found large trade!")
        break  # OK
    end
end
```

## Iterator Pattern (Most Flexible)

The iterator pattern uses `DBNStream()` for maximum flexibility.

### Basic Usage

```julia
using DBN

# Iterate through records
for record in DBNStream("file.dbn")
    # Process record
    println("Price: $(price_to_float(record.price))")
end
```

### Features

**Advantages:**
- Can break early
- Works with any Julia iterator tools (`take`, `filter`, etc.)
- Handles mixed-schema files
- More familiar pattern for Julia users

**Disadvantages:**
- Slower than callbacks (still faster than bulk read)
- Higher memory allocation
- Less optimized by compiler

### Common Patterns

#### Early Termination

```julia
# Find first record matching condition
for trade in DBNStream("trades.dbn")
    if trade.size > 50_000
        println("First large trade: $(price_to_float(trade.price))")
        break
    end
end
```

#### Limited Processing

```julia
# Process only first N records
using IterTools

for (i, trade) in enumerate(DBNStream("trades.dbn"))
    println("Trade $i: $(price_to_float(trade.price))")
    if i >= 1000
        break
    end
end
```

#### Conditional Collection

```julia
# Collect records matching complex criteria
selected = TradeMsg[]

for trade in DBNStream("trades.dbn")
    # Complex filtering logic
    if meets_criteria(trade)
        push!(selected, trade)

        # Stop after finding enough
        if length(selected) >= 100
            break
        end
    end
end
```

#### Mixed Schema Handling

```julia
# Count different message types
counts = Dict{DataType, Int}()

for record in DBNStream("mixed.dbn")
    record_type = typeof(record)
    counts[record_type] = get(counts, record_type, 0) + 1
end

for (type, count) in counts
    println("$type: $count")
end
```

## Generic Callback (For Mixed Schemas)

For mixed-schema files with callbacks:

```julia
using DBN

# Generic callback with type checking
trade_count = Ref(0)
mbo_count = Ref(0)

foreach_record("mixed.dbn", Union{TradeMsg, MBOMsg}) do record
    if record isa TradeMsg
        trade_count[] += 1
    elseif record isa MBOMsg
        mbo_count[] += 1
    end
end

println("Trades: $(trade_count[]), MBOs: $(mbo_count[])")
```

## Compressed Files

All streaming methods transparently handle compression:

```julia
# Compressed files work identically
foreach_trade("trades.dbn.zst") do trade
    # Process compressed data
end

for record in DBNStream("file.dbn.zst")
    # Iterate compressed data
end
```

Compression is detected automatically by the `.zst` extension.

## Choosing the Right Pattern

| Use Case | Recommended Pattern | Reason |
|----------|-------------------|--------|
| Calculate statistics | Callback (`foreach_*`) | Maximum performance, minimal memory |
| Filter all records | Callback (`foreach_*`) | Fast iteration, collect matching records |
| Find first match | Iterator (`DBNStream`) | Can break early |
| Process first N records | Iterator (`DBNStream`) | Early termination |
| Mixed schema file | Iterator (`DBNStream`) | Easier type handling |
| Need complex control flow | Iterator (`DBNStream`) | More flexibility |
| Maximum performance | Callback (`foreach_*`) | Up to 4x faster |

## Performance Tips

### 1. Use Callbacks When Possible

```julia
# ✅ Fastest
total = Ref(0)
foreach_trade("file.dbn") do trade
    total[] += trade.size
end

# ❌ Slower
total = 0
for trade in DBNStream("file.dbn")
    total += trade.size
end
```

### 2. Pre-allocate Collections

```julia
# ✅ Pre-allocate
result = Vector{TradeMsg}()
sizehint!(result, 100_000)

foreach_trade("file.dbn") do trade
    if condition(trade)
        push!(result, trade)
    end
end
```

### 3. Minimize Work in Loop

```julia
# ✅ Hoist constant computations
threshold = calculate_threshold()

foreach_trade("file.dbn") do trade
    if trade.size > threshold
        # Process
    end
end

# ❌ Repeated computation
foreach_trade("file.dbn") do trade
    if trade.size > calculate_threshold()  # Don't do this!
        # Process
    end
end
```

### 4. Use Refs for Mutable State

```julia
# ✅ Use Ref for accumulation in callbacks
sum = Ref(0)
foreach_trade("file.dbn") do trade
    sum[] += trade.size
end
```

### 5. Avoid Type Instability

```julia
# ✅ Type-stable
total::Int = 0
for trade in DBNStream("file.dbn")
    total += trade.size  # Type is known
end

# ❌ Type-unstable
total = 0
for trade in DBNStream("file.dbn")
    total = trade.size > 1000 ? trade.size : 0.0  # Type changes!
end
```

## Memory Usage Comparison

For a 10M record file (458 MB):

| Method | Peak Memory | Records/sec |
|--------|-------------|-------------|
| Callback streaming | 0.1 MB | 42.37 M |
| Iterator streaming | 1221 MB | 10.21 M |
| Bulk read | 687 MB | 6.86 M |

Callback streaming uses **~6,000x less memory** than iterator streaming!

## Error Handling

```julia
using DBN

try
    foreach_trade("file.dbn") do trade
        # Process
        if invalid(trade)
            error("Invalid trade found")
        end
    end
catch e
    println("Error processing file: $(e)")
end
```

## See Also

- [Reading Data](reading.md) - Other reading approaches
- [Writing Data](writing.md) - Writing DBN files
- [API Reference - Streaming](../api/streaming.md) - Complete function reference
- [Performance Guide](../performance.md) - Optimization techniques
