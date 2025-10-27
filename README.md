# DBN.jl

Julia implementation of the Databento Binary Encoding (DBN) message encoding and storage format for normalized market data.

**⚠️ Development Status**: This package is under active development. While core functionality is complete and tested for byte-for-byte compatibility with the official Rust implementation, the API may still evolve. Production use is possible but not yet recommended.

For more details, read the [introduction to DBN](https://databento.com/docs/standards-and-conventions/databento-binary-encoding).

## Features

- ✅ Complete DBN v3 Format Support
- ✅ Efficient streaming support (read and write)
- ✅ Zstd file compression support (read and write)
- ✅ Bidirectional format conversion (DBN ↔ JSON/Parquet/CSV)
- ✅ Byte-for-byte compatibility with official implementations
- ✅ All DBN message types (Trades, MBO, MBP, OHLCV, Status, etc.)
- ✅ High-precision timestamp handling
- ✅ Fixed-point price arithmetic

## Performance

DBN.jl is optimized for high-throughput market data processing:
- **Read**: Up to 40M records/sec with near-zero-allocation callback streaming
- **Write**: 11M records/sec with optimized bulk operations
- **Type-specific readers** (`read_trades`, `read_mbo`, etc.) are 5-6x faster than generic `read_dbn()`

**Note**: This package supports DBN v2 and v3 formats only. DBN v1 files are not supported. To convert DBN v1 files, use the official Databento CLI:
```bash
dbn version1.dbn --output version2.dbn --upgrade
```

## Installation

This package is not yet registered. Install directly from GitHub:

```julia
using Pkg
Pkg.add(url="https://github.com/tbeason/DBN.jl")
```

## Usage

### Reading DBN Files

```julia
using DBN

# Read entire file into memory (fastest for bulk loading)
records = read_dbn("trades.dbn")

# Read with metadata
metadata, records = read_dbn_with_metadata("trades.dbn")

# Optimized type-specific eager read (5-6x faster than read_dbn)
trades = read_trades("trades.dbn")
mbos = read_mbo("mbo.dbn")

# Generic streaming for mixed-type files
for record in DBNStream("large_file.dbn.zst")
    println("Trade: $(record.price) @ $(record.size)")
end

# High-performance callback streaming (near-zero allocations!)
# Best for pure processing workloads - 40 M records/sec
total = Ref(0.0)
foreach_trade("trades.dbn") do trade
    total[] += price_to_float(trade.price)
end
println("Total: $(total[])")
```

### Writing DBN Files

```julia
using DBN, Dates

# Create metadata for trades
metadata = Metadata(
    UInt8(3),                    # DBN version
    "XNAS",                      # dataset
    Schema.TRADES,               # schema
    datetime_to_ts(DateTime(2024, 1, 1)),  # start_ts
    datetime_to_ts(DateTime(2024, 1, 2)),  # end_ts
    UInt64(1000),                # limit
    SType.RAW_SYMBOL,            # stype_in
    SType.RAW_SYMBOL,            # stype_out
    false,                       # ts_out
    String[],                    # symbols
    String[],                    # partial
    String[],                    # not_found
    Tuple{String, String, Int64, Int64}[]  # mappings
)

# Create trade message
trade = TradeMsg(
    RecordHeader(
        UInt8(sizeof(TradeMsg)),
        RType.MBP_0_MSG,
        UInt16(1),      # publisher_id
        UInt32(12345),  # instrument_id
        UInt64(datetime_to_ts(DateTime(2024, 1, 1, 9, 30)))
    ),
    float_to_price(100.50),     # price
    UInt32(100),                # size
    Action.TRADE,
    Side.BID,
    UInt8(0),                   # flags
    UInt8(0),                   # depth
    UInt64(datetime_to_ts(DateTime(2024, 1, 1, 9, 30))),  # ts_recv
    Int32(0),                   # ts_in_delta
    UInt32(1)                   # sequence
)

# Write to file
write_dbn("output.dbn", metadata, [trade])

# Write compressed file
write_dbn("output.dbn.zst", metadata, [trade])
```

### Streaming Writer

```julia
# Create streaming writer for real-time data
writer = DBNStreamWriter("live_trades.dbn", "XNAS", Schema.TRADES)

# Write records as they arrive
for price in [100.0, 100.25, 100.50]
    trade = create_trade_message(price, 100)  # Your trade creation logic
    write_record!(writer, trade)
end

close_writer!(writer)
```

### Data Export

```julia
# Convert to different formats
dbn_to_csv("trades.dbn", "trades.csv")
dbn_to_json("trades.dbn", "trades.json")
dbn_to_parquet("trades.dbn", "output_dir/")

# Convert to DataFrame for analysis
df = records_to_dataframe(records)
```

### Data Import

```julia
# Convert other formats to DBN
json_to_dbn(\"trades.json\", \"trades.dbn\")
parquet_to_dbn(\"trades.parquet\", \"trades.dbn\", schema=Schema.TRADES, dataset=\"XNAS\")
csv_to_dbn(\"trades.csv\", \"trades.dbn\", schema=Schema.TRADES, dataset=\"XNAS\")

# JSONL format (one record per line) is also supported
json_to_dbn(\"trades.jsonl\", \"trades.dbn\")
```

### Compression

```julia
# Compress existing files
compress_dbn_file("input.dbn", "output.dbn.zst")

# Batch compress daily files
compress_daily_files(Date("2024-01-01"), "data/")
```

### Utilities

```julia
# Price conversions (DBN uses fixed-point arithmetic)
price_float = price_to_float(1000000)  # Convert to 100.0000
price_fixed = float_to_price(100.50)   # Convert to 1005000

# Timestamp conversions
dt = ts_to_datetime(1609459200000000000)  # Convert nanoseconds to DateTime
ts = datetime_to_ts(DateTime(2021, 1, 1))  # Convert DateTime to nanoseconds
```

## License

I am not affiliated with Databento.

The official implementations for [dbn](https://github.com/databento/dbn) are distributed under the [Apache 2.0 License](https://www.apache.org/licenses/LICENSE-2.0.html).
