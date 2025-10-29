# Streaming API Reference

Functions for streaming DBN files with minimal memory usage.

## Iterator Pattern

```@docs
DBNStream
```

## Generic Callback

```@docs
foreach_record
```

## Type-Specific Callbacks

Callback functions provide the highest performance (up to 40M records/sec) with near-zero memory allocation.

### Trade Data

```@docs
foreach_trade
```

### Market-by-Order (MBO)

```@docs
foreach_mbo
```

### Market-by-Price (MBP)

```@docs
foreach_mbp1
foreach_mbp10
```

### Top of Book (BBO/TBBO)

```@docs
foreach_tbbo
foreach_bbo1s
foreach_bbo1m
```

### OHLCV (Bars)

```@docs
foreach_ohlcv
foreach_ohlcv_1s
foreach_ohlcv_1m
foreach_ohlcv_1h
foreach_ohlcv_1d
```

### Consolidated Market Data

```@docs
foreach_cmbp1
foreach_cbbo1s
foreach_cbbo1m
foreach_tcbbo
```

## Performance Characteristics

| Method | Throughput | Memory | Use Case |
|--------|------------|--------|----------|
| Callback (`foreach_*`) | Up to 40M rec/sec | Minimal (KB) | Processing, aggregation |
| Iterator (`DBNStream`) | ~10M rec/sec | Moderate (MB) | Flexible iteration |

## Usage Patterns

### Callback Pattern (Fastest)

```julia
# Aggregate data
total = Ref(0)
foreach_trade("file.dbn") do trade
    total[] += trade.size
end
```

**Limitations:** Cannot break early from callback

### Iterator Pattern (Most Flexible)

```julia
# Can break early
for trade in DBNStream("file.dbn")
    if condition(trade)
        break
    end
end
```

See the [Streaming Guide](../guide/streaming.md) for detailed examples and performance tips.
