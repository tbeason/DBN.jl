# Format Conversion

DBN.jl supports bidirectional conversion between DBN and other popular formats: CSV, JSON, Parquet, and DataFrames.

## Supported Formats

| Format | Read | Write | Use Case |
|--------|------|-------|----------|
| **CSV** | ✅ | ✅ | Human-readable, Excel-compatible |
| **JSON/JSONL** | ✅ | ✅ | Human-readable, web APIs |
| **Parquet** | ✅ | ✅ | Analytics, data lakes |
| **DataFrame** | N/A | ✅ | In-memory analysis |

## DBN to Other Formats

### DBN to CSV

```julia
using DBN

# Convert DBN to CSV
dbn_to_csv("trades.dbn", "trades.csv")

# Works with compressed files
dbn_to_csv("trades.dbn.zst", "trades.csv")
```

**CSV Output Format:**
- Header row with column names
- One record per row
- Timestamps as nanoseconds (Int64)
- Prices as fixed-point integers
- Enums as strings (e.g., "BID", "ASK")

**Example CSV:**
```csv
ts_event,publisher_id,instrument_id,price,size,action,side,flags,depth,ts_recv,ts_in_delta,sequence
1704067200000000000,1,12345,1005000,100,TRADE,BID,0,0,1704067200000000000,0,1
1704067200100000000,1,12345,1005500,200,TRADE,ASK,0,0,1704067200100000000,0,2
```

### DBN to JSON

```julia
using DBN

# Convert to JSON (array of objects)
dbn_to_json("trades.dbn", "trades.json")

# Convert to JSONL (one object per line)
dbn_to_json("trades.dbn", "trades.jsonl")
```

**JSON Output Format:**
```json
[
  {
    "hd": {
      "length": 11,
      "rtype": 160,
      "publisher_id": 1,
      "instrument_id": 12345,
      "ts_event": 1704067200000000000
    },
    "price": 1005000,
    "size": 100,
    "action": "T",
    "side": "B",
    "flags": 0,
    "depth": 0,
    "ts_recv": 1704067200000000000,
    "ts_in_delta": 0,
    "sequence": 1
  }
]
```

**JSONL Output Format** (one record per line):
```json
{"hd":{"length":11,"rtype":160,...},"price":1005000,...}
{"hd":{"length":11,"rtype":160,...},"price":1005500,...}
```

### DBN to Parquet

```julia
using DBN

# Convert to Parquet
dbn_to_parquet("trades.dbn", "output_directory/")

# Output creates trades.parquet in the directory
```

**Parquet Output:**
- Columnar format (efficient for analytics)
- Preserves data types
- Automatic compression
- Compatible with Arrow, DuckDB, pandas, etc.

### DBN to DataFrame

```julia
using DBN

# Read DBN file
records = read_trades("trades.dbn")

# Convert to DataFrame
df = records_to_dataframe(records)

# Now you can use DataFrames.jl operations
using DataFrames, Statistics

# Example: Calculate average price
mean_price = mean(df.price)

# Group by side
using DataFramesMeta
@chain df begin
    @groupby(:side)
    @combine(:avg_price = mean(:price),
             :total_volume = sum(:size))
end
```

## Other Formats to DBN

### JSON to DBN

```julia
using DBN

# Convert JSON to DBN
json_to_dbn("trades.json", "trades.dbn")

# Also supports JSONL (one record per line)
json_to_dbn("trades.jsonl", "trades.dbn")
```

**Requirements:**
- JSON must match DBN message structure
- Timestamps in nanoseconds
- Prices as fixed-point integers or floats (will be converted)
- Enum fields as strings or integer values

### CSV to DBN

```julia
using DBN

# Convert CSV to DBN (requires schema specification)
csv_to_dbn(
    "trades.csv",
    "trades.dbn",
    schema = Schema.TRADES,
    dataset = "XNAS"
)

# With compression
csv_to_dbn(
    "trades.csv",
    "trades.dbn.zst",
    schema = Schema.TRADES,
    dataset = "XNAS"
)
```

**CSV Requirements:**
- Column names must match DBN field names
- Timestamps as nanoseconds (Int64)
- Prices as fixed-point Int64 or will convert from Float64
- Enum fields as strings or integer codes

### Parquet to DBN

```julia
using DBN

# Convert Parquet to DBN
parquet_to_dbn(
    "trades.parquet",
    "trades.dbn",
    schema = Schema.TRADES,
    dataset = "XNAS"
)
```

**Parquet Requirements:**
- Schema must match DBN message type
- Column names must match field names
- Appropriate data types

## Use Cases

### CSV: Human-Readable Exchange

**Best for:**
- Sharing data with Excel users
- Quick inspection with text tools
- Simple data exchange

**Limitations:**
- Larger file size than DBN
- Slower read/write performance
- Loss of type information

**Example: Export sample for Excel analysis**
```julia
using DBN

# Read first 10,000 trades
trades = read_trades("large_file.dbn.zst")
sample = trades[1:10_000]

# Create temporary file
temp_metadata, _ = read_dbn_with_metadata("large_file.dbn.zst")
write_dbn("sample.dbn", temp_metadata, sample)

# Convert to CSV for Excel
dbn_to_csv("sample.dbn", "sample.csv")

# Clean up
rm("sample.dbn")
```

### JSON: API Integration

**Best for:**
- Web API responses
- JavaScript applications
- Human-readable debugging

**Limitations:**
- Largest file size
- Slowest performance
- Verbose

**Example: Export for web application**
```julia
using DBN

# Get recent trades
trades = read_trades("recent.dbn")

# Export most recent 100 as JSON
latest = trades[end-99:end]

# Create temporary DBN file
metadata, _ = read_dbn_with_metadata("recent.dbn")
write_dbn("latest.dbn", metadata, latest)

# Convert to JSON for API
dbn_to_json("latest.dbn", "api_response.json")

rm("latest.dbn")
```

### Parquet: Analytics Pipeline

**Best for:**
- Data lakes and warehouses
- Integration with Spark, Dask, DuckDB
- Columnar analytics
- Long-term storage

**Advantages:**
- Efficient columnar format
- Good compression
- Wide tool support

**Example: Export for DuckDB analysis**
```julia
using DBN

# Convert historical data to Parquet
dbn_to_parquet("2024_trades.dbn.zst", "data_lake/")

# Now you can query with DuckDB, pandas, etc.
# SELECT AVG(price) FROM 'data_lake/trades.parquet'
```

### DataFrame: In-Memory Analysis

**Best for:**
- Statistical analysis
- Data transformation
- Visualization
- Interactive exploration

**Example: Analyze trade patterns**
```julia
using DBN, DataFrames, Statistics, Dates

# Read data
trades = read_trades("trades.dbn")
df = records_to_dataframe(trades)

# Add derived columns
df.datetime = ts_to_datetime.(df.ts_event)
df.price_float = price_to_float.(df.price)

# Time series analysis
using DataFramesMeta

# Calculate 5-minute average prices
@chain df begin
    @transform(:minute = floor(:datetime, Minute(5)))
    @groupby(:minute)
    @combine(:avg_price = mean(:price_float),
             :volume = sum(:size),
             :count = length(:price_float))
end
```

## Round-Trip Conversion

### DBN → CSV → DBN

```julia
using DBN

# Original file
metadata_original, records_original = read_dbn_with_metadata("original.dbn")

# Convert to CSV
dbn_to_csv("original.dbn", "temp.csv")

# Convert back to DBN
csv_to_dbn("temp.csv", "restored.dbn",
           schema = metadata_original.schema,
           dataset = metadata_original.dataset)

# Verify
records_restored = read_dbn("restored.dbn")
@assert length(records_original) == length(records_restored)

# Clean up
rm("temp.csv")
```

!!! warning "Precision Loss"
    Round-trip conversions through text formats (CSV, JSON) may lose precision or metadata. Use DBN format for archival storage.

## Performance Comparison

**Conversion Time** (100k trades):

| Operation | Time | Notes |
|-----------|------|-------|
| DBN → CSV | ~0.5s | Simple text output |
| DBN → JSON | ~1.2s | More verbose format |
| DBN → Parquet | ~0.3s | Efficient columnar write |
| CSV → DBN | ~0.8s | Text parsing overhead |
| JSON → DBN | ~1.5s | Complex parsing |
| Parquet → DBN | ~0.4s | Efficient columnar read |

## File Size Comparison

**File Sizes** (1M trades):

| Format | Size | Compression |
|--------|------|-------------|
| DBN (uncompressed) | 46 MB | 1.0x (baseline) |
| DBN (compressed .zst) | 16 MB | 2.9x |
| CSV | 95 MB | 0.48x (larger!) |
| JSON | 180 MB | 0.26x (much larger!) |
| Parquet | 25 MB | 1.8x |

**Recommendation**: Use compressed DBN (.zst) for storage and distribution.

## Tips and Best Practices

### 1. Use Compressed DBN for Storage
```julia
# ✅ Smallest, fastest
dbn_to_csv("data.dbn.zst", "analysis.csv")  # For analysis only

# ❌ Don't store in CSV long-term
# CSV files are 2-6x larger than compressed DBN
```

### 2. Convert Only What You Need
```julia
# ✅ Filter before converting
trades = read_trades("all.dbn.zst")
high_value = filter(t -> price_to_float(t.price) > 1000, trades)

metadata, _ = read_dbn_with_metadata("all.dbn.zst")
write_dbn("filtered.dbn", metadata, high_value)
dbn_to_csv("filtered.dbn", "high_value.csv")

# ❌ Don't convert everything then filter
dbn_to_csv("all.dbn.zst", "huge.csv")  # Wasteful!
```

### 3. Batch Processing for Large Files
```julia
# Process in chunks for very large files
using DBN

writer = open("output.csv", "w")
println(writer, "ts_event,price,size,side")  # Header

foreach_trade("huge_file.dbn.zst") do trade
    # Write CSV row
    println(writer, "$(trade.hd.ts_event),$(trade.price),$(trade.size),$(trade.side)")
end

close(writer)
```

## See Also

- [Reading Data](reading.md) - Reading DBN files
- [Writing Data](writing.md) - Writing DBN files
- [API Reference - Conversion](../api/conversion.md) - Conversion function reference
- [Databento Documentation](https://databento.com/docs/) - Format specifications
