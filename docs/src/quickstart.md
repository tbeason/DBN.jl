# Quick Start Guide

Get up and running with DBN.jl in 5 minutes!

## Installation

```julia
using Pkg
Pkg.add(url="https://github.com/tbeason/DBN.jl")
```

## Basic Usage

### Reading a DBN File

The simplest way to read a DBN file:

```julia
using DBN

# Read entire file into memory
records = read_dbn("trades.dbn")

# Read with metadata
metadata, records = read_dbn_with_metadata("trades.dbn")
```

For better performance with known schemas, use type-specific readers:

```julia
# 5-6x faster than generic read_dbn()
trades = read_trades("trades.dbn")
mbos = read_mbo("mbo.dbn")
ohlcv = read_ohlcv("ohlcv.dbn")
```

### Streaming Large Files

For files too large to fit in memory, use streaming:

```julia
# Iterator pattern
for record in DBNStream("large_file.dbn.zst")
    # Process each record
    println("Price: $(price_to_float(record.price))")
end
```

For maximum performance (up to 40M records/sec), use callbacks:

```julia
# Near-zero allocation streaming
total_volume = Ref(0)
foreach_trade("trades.dbn") do trade
    total_volume[] += trade.size
end
println("Total volume: $(total_volume[])")
```

### Writing DBN Files

Create a DBN file from Julia data:

```julia
using DBN, Dates

# Create metadata
metadata = Metadata(
    UInt8(3),                    # DBN version
    "XNAS",                      # dataset
    Schema.TRADES,               # schema
    datetime_to_ts(DateTime(2024, 1, 1)),
    datetime_to_ts(DateTime(2024, 1, 2)),
    UInt64(1000),                # limit
    SType.RAW_SYMBOL,            # stype_in
    SType.RAW_SYMBOL,            # stype_out
    false,                       # ts_out
    String[],                    # symbols
    String[],                    # partial
    String[],                    # not_found
    Tuple{String, String, Int64, Int64}[]  # mappings
)

# Create a trade message
trade = TradeMsg(
    RecordHeader(
        UInt8(sizeof(TradeMsg)),
        RType.MBP_0_MSG,
        UInt16(1),               # publisher_id
        UInt32(12345),           # instrument_id
        datetime_to_ts(DateTime(2024, 1, 1, 9, 30))
    ),
    float_to_price(100.50),      # price (fixed-point)
    UInt32(100),                 # size
    Action.TRADE,
    Side.BID,
    UInt8(0),                    # flags
    UInt8(0),                    # depth
    datetime_to_ts(DateTime(2024, 1, 1, 9, 30)),  # ts_recv
    Int32(0),                    # ts_in_delta
    UInt32(1)                    # sequence
)

# Write to file
write_dbn("output.dbn", metadata, [trade])

# Write with compression
write_dbn("output.dbn.zst", metadata, [trade])
```

### Streaming Writer (Real-time Data)

For writing data as it arrives:

```julia
# Create a streaming writer
writer = DBNStreamWriter("live_data.dbn", "XNAS", Schema.TRADES)

# Write records as they arrive
for price in [100.0, 100.25, 100.50, 100.75, 101.0]
    trade = TradeMsg(
        RecordHeader(
            UInt8(sizeof(TradeMsg)),
            RType.MBP_0_MSG,
            UInt16(1),
            UInt32(12345),
            datetime_to_ts(now())
        ),
        float_to_price(price),
        UInt32(100),
        Action.TRADE,
        Side.BID,
        UInt8(0), UInt8(0),
        datetime_to_ts(now()),
        Int32(0),
        UInt32(1)
    )
    write_record!(writer, trade)
end

# Close the writer
close_writer!(writer)
```

### Format Conversion

Convert DBN files to other formats:

```julia
# DBN → CSV
dbn_to_csv("trades.dbn", "trades.csv")

# DBN → JSON
dbn_to_json("trades.dbn", "trades.json")

# DBN → Parquet
dbn_to_parquet("trades.dbn", "output_dir/")

# DBN → DataFrame
df = records_to_dataframe(records)
```

Convert other formats to DBN:

```julia
# JSON → DBN
json_to_dbn("trades.json", "trades.dbn")

# CSV → DBN (requires schema specification)
csv_to_dbn("trades.csv", "trades.dbn",
           schema=Schema.TRADES,
           dataset="XNAS")

# Parquet → DBN (requires schema specification)
parquet_to_dbn("trades.parquet", "trades.dbn",
               schema=Schema.TRADES,
               dataset="XNAS")
```

### Working with Compressed Files

DBN.jl transparently handles Zstd-compressed files:

```julia
# Read compressed files (automatically detected by .zst extension)
records = read_dbn("trades.dbn.zst")

# Stream compressed files
for record in DBNStream("large_file.dbn.zst")
    # Process record
end

# Compress existing files
compress_dbn_file("input.dbn", "output.dbn.zst")
```

### Utility Functions

Common operations for working with DBN data:

```julia
# Price conversions (DBN uses fixed-point arithmetic)
price_float = price_to_float(1005000)    # → 100.50
price_fixed = float_to_price(100.50)     # → 1005000

# Timestamp conversions (nanoseconds ↔ DateTime)
dt = ts_to_datetime(1609459200000000000) # → DateTime
ts = datetime_to_ts(DateTime(2021, 1, 1)) # → nanoseconds (Int64)
```

## Common Patterns

### Processing Historical Data

```julia
# Count trades by side
bid_count = 0
ask_count = 0

foreach_trade("historical_trades.dbn.zst") do trade
    if trade.side == Side.BID
        bid_count += 1
    elseif trade.side == Side.ASK
        ask_count += 1
    end
end

println("Bids: $bid_count, Asks: $ask_count")
```

### Filtering Records

```julia
# Extract high-volume trades
high_volume = TradeMsg[]

foreach_trade("trades.dbn") do trade
    if trade.size > 10_000
        push!(high_volume, trade)
    end
end

# Write filtered data to new file
metadata, _ = read_dbn_with_metadata("trades.dbn")
write_dbn("high_volume_trades.dbn", metadata, high_volume)
```

### Working with Multiple Schemas

```julia
# Read a file with mixed message types
for record in DBNStream("mixed.dbn")
    if record isa TradeMsg
        # Handle trade
    elseif record isa MBOMsg
        # Handle MBO
    end
end
```

## Next Steps

Now that you know the basics:

- **Learn more about reading**: [Reading Data Guide](guide/reading.md)
- **Explore streaming options**: [Streaming Guide](guide/streaming.md)
- **Check all available functions**: [API Reference](api/reading.md)
- **Optimize for performance**: [Performance Guide](performance.md)

## Need Help?

- **Troubleshooting**: See [common issues](troubleshooting.md)
- **Databento Format**: Read the [official DBN documentation](https://databento.com/docs/standards-and-conventions/databento-binary-encoding)
- **Schemas**: Learn about [DBN schemas](https://databento.com/docs/schemas-and-data-formats)
- **Bug Reports**: Open an issue on [GitHub](https://github.com/tbeason/DBN.jl/issues)
