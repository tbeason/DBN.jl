# DBN.jl Documentation

Julia implementation of the Databento Binary Encoding (DBN) message encoding and storage format for normalized market data.

!!! warning "Development Status"
    This package is under active development. While core functionality is complete and tested for byte-for-byte compatibility with the official Rust implementation, the API may still evolve. Production use is possible but not yet recommended.

## What is DBN?

DBN (Databento Binary Encoding) is a fast, compact binary format for storing and transmitting market data. It's designed for:
- **High throughput**: Optimized for reading/writing millions of records per second
- **Compact storage**: Efficient binary encoding with optional Zstd compression
- **Standardization**: Consistent format across multiple data vendors and asset classes

For details on the DBN format specification, see the [official Databento documentation](https://databento.com/docs/standards-and-conventions/databento-binary-encoding).

## Why DBN.jl?

DBN.jl brings the power of DBN to Julia with:

- ✅ **Complete DBN v3 Format Support** - All message types and schemas
- ✅ **Efficient Streaming** - Read and write large files with minimal memory
- ✅ **Zstd Compression** - Transparent compression/decompression support
- ✅ **Format Conversion** - Bidirectional conversion between DBN, CSV, JSON, and Parquet
- ✅ **Byte-for-byte Compatibility** - Tested against official Rust implementation
- ✅ **High Performance** - Up to 40M records/sec with callback streaming
- ✅ **All Message Types** - Trades, MBO, MBP, OHLCV, Status, and more
- ✅ **Precision Handling** - Nanosecond timestamps and fixed-point price arithmetic

## Quick Example

```julia
using DBN

# Read a DBN file
trades = read_trades("trades.dbn")

# Process with high-performance streaming (40M records/sec)
total_volume = Ref(0)
foreach_trade("large_file.dbn.zst") do trade
    total_volume[] += trade.size
end

# Convert to other formats
dbn_to_csv("trades.dbn", "trades.csv")
dbn_to_parquet("trades.dbn", "output_dir/")
```

## Performance Characteristics

DBN.jl is optimized for high-throughput market data processing:

| Operation | Throughput | Method |
|-----------|-----------|---------|
| **Reading** | Up to 40M records/sec | Callback streaming (`foreach_trade`, etc.) |
| **Reading** | 5-6x faster than generic | Type-specific readers (`read_trades`, `read_mbo`, etc.) |
| **Writing** | 11M records/sec | Bulk operations (`write_dbn`) |

See the [Performance](@ref) page for detailed benchmarks and optimization tips.

## Format Support

**DBN Versions:**
- ✅ DBN v2 (read and write)
- ✅ DBN v3 (read and write)
- ❌ DBN v1 (not supported - use [Databento CLI](https://databento.com/docs/api-reference-historical/cli) to upgrade)

**Conversion Formats:**
- CSV (read and write)
- JSON/JSONL (read and write)
- Parquet (read and write)
- DataFrames (write)

## Getting Started

1. [Install DBN.jl](installation.md)
2. Follow the [Quick Start Guide](quickstart.md)
3. Explore the [User Guide](guide/reading.md)
4. Check the [API Reference](api/reading.md)

## Getting Help

- **Documentation**: You're reading it! Browse the sections in the sidebar
- **Issues**: Report bugs or request features on [GitHub](https://github.com/tbeason/DBN.jl/issues)
- **Databento Docs**: For DBN format details, see [databento.com/docs](https://databento.com/docs/)

## License

DBN.jl is not affiliated with Databento.

The official DBN implementations ([dbn](https://github.com/databento/dbn)) are distributed under the [Apache 2.0 License](https://www.apache.org/licenses/LICENSE-2.0.html).
