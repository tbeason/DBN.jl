# Reading API Reference

Functions for reading DBN files.

## Generic Reading

```@docs
read_dbn
read_dbn_with_metadata
read_dbn_typed
```

## Type-Specific Readers

These functions are 5-6x faster than the generic `read_dbn()` when you know the schema.

### Trade Data

```@docs
read_trades
```

### Market-by-Order (MBO)

```@docs
read_mbo
```

### Market-by-Price (MBP)

```@docs
read_mbp1
read_mbp10
```

### Top of Book (BBO/TBBO)

```@docs
read_tbbo
read_bbo1s
read_bbo1m
```

### OHLCV (Bars)

```@docs
read_ohlcv
read_ohlcv_1s
read_ohlcv_1m
read_ohlcv_1h
read_ohlcv_1d
```

### Consolidated Market Data

```@docs
read_cmbp1
read_cbbo1s
read_cbbo1m
read_tcbbo
```

## Performance Tips

For maximum performance when reading:

1. **Use type-specific readers** when you know the schema (5-6x faster)
2. **Use callback streaming** for processing without keeping data in memory (fastest)
3. **Use iterators** for flexible streaming with control flow
4. **Work with compressed files** directly (no need to decompress first)

See the [Reading Guide](../guide/reading.md) for detailed usage examples and performance comparisons.
