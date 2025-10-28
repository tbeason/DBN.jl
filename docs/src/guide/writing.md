# Writing Data

DBN.jl provides two main approaches for writing DBN files: bulk writing for pre-existing data, and streaming for real-time data ingestion.

## Quick Reference

| Method | Best For | Performance |
|--------|----------|-------------|
| `write_dbn()` | Bulk writing existing data | 11M records/sec |
| `DBNStreamWriter` | Real-time/streaming data | Continuous writing |

## Bulk Writing

### Basic Usage

Write a collection of records with metadata:

```julia
using DBN, Dates

# Your records (e.g., from reading another file or creating synthetically)
records = [trade1, trade2, trade3, ...]

# Create metadata
metadata = Metadata(
    UInt8(3),                    # DBN version (use 3)
    "XNAS",                      # dataset (e.g., "XNAS", "GLBX")
    Schema.TRADES,               # schema
    datetime_to_ts(DateTime(2024, 1, 1)),  # start timestamp
    datetime_to_ts(DateTime(2024, 1, 2)),  # end timestamp
    UInt64(length(records)),     # limit (number of records)
    SType.RAW_SYMBOL,            # input symbol type
    SType.RAW_SYMBOL,            # output symbol type
    false,                       # ts_out (false unless upgrading)
    String[],                    # symbols
    String[],                    # partial
    String[],                    # not_found
    Tuple{String, String, Int64, Int64}[]  # mappings
)

# Write to file
write_dbn("output.dbn", metadata, records)
```

### Writing with Compression

Automatically compress with Zstd by using `.zst` extension:

```julia
# Compressed output (smaller file size)
write_dbn("output.dbn.zst", metadata, records)
```

Compression ratios typically range from 2-3x for market data.

### Creating Metadata

The `Metadata` constructor requires several fields. Here's a detailed breakdown:

```julia
metadata = Metadata(
    UInt8(3),              # version: Always use 3 for DBN v3
    "XNAS",                # dataset: Data source identifier
    Schema.TRADES,         # schema: Message schema (TRADES, MBO, MBP_1, etc.)
    start_ts,              # start_ts: First record timestamp (nanoseconds)
    end_ts,                # end_ts: Last record timestamp (nanoseconds)
    UInt64(num_records),   # limit: Total number of records
    SType.RAW_SYMBOL,      # stype_in: Input symbol type
    SType.RAW_SYMBOL,      # stype_out: Output symbol type
    false,                 # ts_out: Include ts_out field?
    String[],              # symbols: List of symbols (if applicable)
    String[],              # partial: Partial symbols
    String[],              # not_found: Symbols not found
    Tuple{String, String, Int64, Int64}[]  # mappings: Symbol mappings
)
```

**Field explanations:**
- **version**: Use `3` for DBN v3 (current standard)
- **dataset**: String identifier (e.g., "XNAS", "GLBX", "TEST")
- **schema**: One of the `Schema` enum values
- **start_ts/end_ts**: Nanosecond timestamps from first/last record
- **limit**: Total record count
- **stype_in/stype_out**: Symbol type (usually `SType.RAW_SYMBOL`)
- **ts_out**: Set to `true` only when converting from older DBN versions
- **symbols**: List of symbols in file (can be empty)
- **partial/not_found/mappings**: Usually empty for custom files

### Copying Metadata from Existing File

When transforming existing data, reuse metadata:

```julia
# Read existing file with metadata
metadata, records = read_dbn_with_metadata("input.dbn")

# Filter or transform records
filtered = filter(r -> r.size > 1000, records)

# Update metadata with new count
new_metadata = Metadata(
    metadata.version,
    metadata.dataset,
    metadata.schema,
    filtered[1].hd.ts_event,      # New start time
    filtered[end].hd.ts_event,    # New end time
    UInt64(length(filtered)),     # New count
    metadata.stype_in,
    metadata.stype_out,
    metadata.ts_out,
    metadata.symbols,
    metadata.partial,
    metadata.not_found,
    metadata.mappings
)

# Write filtered data
write_dbn("filtered.dbn", new_metadata, filtered)
```

## Streaming Writer

For writing data as it arrives (real-time or sequential processing):

### Basic Usage

```julia
using DBN

# Create a streaming writer
writer = DBNStreamWriter("output.dbn", "XNAS", Schema.TRADES)

# Write records as they arrive
for price in [100.0, 100.25, 100.50, 100.75]
    trade = create_trade(price)  # Your function to create trade
    write_record!(writer, trade)
end

# Always close when done
close_writer!(writer)
```

### Compressed Streaming

Use `.zst` extension for compressed output:

```julia
# Compressed streaming output
writer = DBNStreamWriter("output.dbn.zst", "XNAS", Schema.TRADES)

# Write records...
write_record!(writer, trade)

close_writer!(writer)
```

### Real-time Data Example

```julia
using DBN, Dates

# Create writer for live data
writer = DBNStreamWriter("live_trades.dbn.zst", "XNAS", Schema.TRADES)

try
    # Simulate receiving live data
    for event in event_stream  # Your data source
        # Create trade message from event
        trade = TradeMsg(
            RecordHeader(
                UInt8(sizeof(TradeMsg)),
                RType.MBP_0_MSG,
                UInt16(event.publisher_id),
                UInt32(event.instrument_id),
                datetime_to_ts(now())
            ),
            float_to_price(event.price),
            UInt32(event.size),
            Action.TRADE,
            event.side,
            UInt8(0), UInt8(0),
            datetime_to_ts(now()),
            Int32(0),
            UInt32(event.sequence)
        )

        # Write immediately
        write_record!(writer, trade)
    end
finally
    # Ensure writer is closed even if error occurs
    close_writer!(writer)
end
```

## Creating Messages

### Trade Messages

```julia
using DBN, Dates

function create_trade(price::Float64, size::Int, side::Side.T,
                     instrument_id::Int = 12345,
                     publisher_id::Int = 1,
                     sequence::Int = 1)
    timestamp = datetime_to_ts(now())

    return TradeMsg(
        RecordHeader(
            UInt8(sizeof(TradeMsg)),
            RType.MBP_0_MSG,      # Trades use MBP_0
            UInt16(publisher_id),
            UInt32(instrument_id),
            timestamp
        ),
        float_to_price(price),
        UInt32(size),
        Action.TRADE,
        side,
        UInt8(0),           # flags
        UInt8(0),           # depth
        timestamp,          # ts_recv
        Int32(0),           # ts_in_delta
        UInt32(sequence)    # sequence number
    )
end

# Usage
trade = create_trade(100.50, 100, Side.BID)
```

### MBO Messages

```julia
function create_mbo(order_id::Int, price::Float64, size::Int,
                    action::Action.T, side::Side.T,
                    instrument_id::Int = 12345)
    timestamp = datetime_to_ts(now())

    return MBOMsg(
        RecordHeader(
            UInt8(sizeof(MBOMsg)),
            RType.MBO_MSG,
            UInt16(1),
            UInt32(instrument_id),
            timestamp
        ),
        UInt64(order_id),
        float_to_price(price),
        UInt32(size),
        UInt8(0),           # flags
        UInt8(1),           # channel_id
        action,
        side,
        timestamp,
        Int32(0),
        UInt32(1)
    )
end

# Usage
mbo = create_mbo(1000001, 100.50, 500, Action.ADD, Side.BID)
```

### OHLCV Messages

```julia
function create_ohlcv(open::Float64, high::Float64, low::Float64,
                     close::Float64, volume::Int,
                     bar_time::DateTime,
                     instrument_id::Int = 12345)
    return OHLCVMsg(
        RecordHeader(
            UInt8(sizeof(OHLCVMsg)),
            RType.OHLCV_1M_MSG,    # 1-minute bars
            UInt16(1),
            UInt32(instrument_id),
            datetime_to_ts(bar_time)
        ),
        float_to_price(open),
        float_to_price(high),
        float_to_price(low),
        float_to_price(close),
        UInt64(volume)
    )
end

# Usage
ohlcv = create_ohlcv(100.0, 101.0, 99.5, 100.5, 50_000,
                     DateTime(2024, 1, 1, 9, 30))
```

## Transforming Data

### Filter and Save

```julia
# Read source file
source_trades = read_trades("all_trades.dbn")

# Filter
high_volume = filter(t -> t.size > 10_000, source_trades)

# Create metadata (copy and adjust from source)
metadata, _ = read_dbn_with_metadata("all_trades.dbn")
new_metadata = Metadata(
    metadata.version, metadata.dataset, metadata.schema,
    high_volume[1].hd.ts_event,
    high_volume[end].hd.ts_event,
    UInt64(length(high_volume)),
    metadata.stype_in, metadata.stype_out, metadata.ts_out,
    metadata.symbols, metadata.partial, metadata.not_found,
    metadata.mappings
)

# Write filtered data
write_dbn("high_volume.dbn.zst", new_metadata, high_volume)
```

### Aggregate and Save

```julia
# Aggregate tick data to 1-minute bars
using Dates

minute_bars = Dict{DateTime, Vector{TradeMsg}}()

# Group trades by minute
foreach_trade("ticks.dbn") do trade
    bar_time = floor(ts_to_datetime(trade.hd.ts_event), Minute(1))
    if !haskey(minute_bars, bar_time)
        minute_bars[bar_time] = TradeMsg[]
    end
    push!(minute_bars[bar_time], trade)
end

# Create OHLCV from each minute
ohlcv_records = OHLCVMsg[]
for (bar_time, trades) in sort(collect(minute_bars))
    prices = [price_to_float(t.price) for t in trades]

    ohlcv = create_ohlcv(
        prices[1],              # open
        maximum(prices),        # high
        minimum(prices),        # low
        prices[end],            # close
        sum(t.size for t in trades),  # volume
        bar_time,
        trades[1].hd.instrument_id
    )
    push!(ohlcv_records, ohlcv)
end

# Write OHLCV file
# (create appropriate metadata for OHLCV schema)
write_dbn("bars_1m.dbn", ohlcv_metadata, ohlcv_records)
```

## Performance Tips

### 1. Use Bulk Writing When Possible
```julia
# ✅ Faster - single write operation
write_dbn("output.dbn", metadata, all_records)

# ❌ Slower - many small writes
writer = DBNStreamWriter("output.dbn", "XNAS", Schema.TRADES)
for record in all_records
    write_record!(writer, record)
end
close_writer!(writer)
```

### 2. Pre-allocate for Building Records
```julia
# ✅ Pre-allocate if you know size
records = Vector{TradeMsg}(undef, expected_count)
for i in 1:expected_count
    records[i] = create_trade(...)
end
```

### 3. Use Compression for Storage
```julia
# ✅ 2-3x smaller files
write_dbn("output.dbn.zst", metadata, records)

# ❌ Larger files
write_dbn("output.dbn", metadata, records)
```

## Error Handling

```julia
using DBN

try
    writer = DBNStreamWriter("output.dbn", "XNAS", Schema.TRADES)
    try
        # Write records...
        write_record!(writer, record)
    finally
        # Always close writer
        close_writer!(writer)
    end
catch e
    if e isa SystemError
        println("Cannot write file: $(e.msg)")
    else
        rethrow(e)
    end
end
```

## Common Patterns

### Batch Writing with Progress
```julia
using ProgressMeter

records = generate_records(1_000_000)  # Your function

@showprogress "Writing..." for i in 1:10
    batch_start = (i-1) * 100_000 + 1
    batch_end = i * 100_000
    batch = records[batch_start:batch_end]

    # Write batch
    metadata = create_batch_metadata(batch)
    write_dbn("batch_$i.dbn.zst", metadata, batch)
end
```

### Merging Multiple Files
```julia
# Read multiple files
files = ["trades_1.dbn", "trades_2.dbn", "trades_3.dbn"]
all_trades = TradeMsg[]

for file in files
    append!(all_trades, read_trades(file))
end

# Sort by timestamp
sort!(all_trades, by = t -> t.hd.ts_event)

# Write merged file
metadata = create_merged_metadata(all_trades)
write_dbn("merged.dbn.zst", metadata, all_trades)
```

## See Also

- [Reading Data](reading.md) - How to read DBN files
- [Streaming Guide](streaming.md) - Detailed streaming information
- [API Reference - Writing](../api/writing.md) - Complete function reference
- [Databento DBN Format](https://databento.com/docs/standards-and-conventions/databento-binary-encoding) - Format specification
