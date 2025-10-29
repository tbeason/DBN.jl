# Troubleshooting

Common issues and solutions when working with DBN.jl.

## Installation Issues

### Package Not Found

**Problem**: `ERROR: Package DBN not found`

**Solution**: DBN.jl is not registered. Install from GitHub:
```julia
using Pkg
Pkg.add(url="https://github.com/tbeason/DBN.jl")
```

### Dependency Conflicts

**Problem**: Version conflicts with other packages

**Solution**:
```julia
using Pkg
Pkg.update()  # Update all packages
Pkg.resolve()  # Resolve conflicts
```

If problems persist:
```julia
Pkg.rm("DBN")
Pkg.gc()  # Clean up
Pkg.add(url="https://github.com/tbeason/DBN.jl")
```

## Compression Issues

### Zstd Decompression Errors

**Problem**: `ERROR: zstd error` when reading `.zst` files

**Possible causes:**
1. Corrupt compressed file
2. CodecZstd not properly installed
3. File not actually Zstd compressed

**Solutions**:
```julia
# 1. Verify CodecZstd is installed
using CodecZstd

# 2. Reinstall codec
using Pkg
Pkg.rm("CodecZstd")
Pkg.add("CodecZstd")

# 3. Check file is valid
# Try decompressing manually
using TranscodingStreams, CodecZstd
open("file.dbn.zst") do io
    zstd_stream = ZstdDecompressorStream(io)
    # Should not error
end
```

### Compression Not Working

**Problem**: `.zst` files created but not compressed

**Solution**: Ensure you're using the `.zst` extension:
```julia
# ✅ Will compress
write_dbn("output.dbn.zst", metadata, records)

# ❌ Won't compress (missing .zst)
write_dbn("output.dbn", metadata, records)
```

## Memory Issues

### Out of Memory When Reading

**Problem**: `ERROR: Out of memory` when reading large files

**Solution**: Use streaming instead of bulk reading:
```julia
# ❌ Don't load huge files into memory
records = read_dbn("huge_file.dbn")  # OOM!

# ✅ Stream instead
foreach_record("huge_file.dbn", TradeMsg) do record
    # Process without loading all records
end

# ✅ Or use iterator
for record in DBNStream("huge_file.dbn")
    # Process one at a time
end
```

### High Memory Usage with Iterator

**Problem**: `DBNStream` uses too much memory

**Solution**: Use callback pattern instead:
```julia
# ❌ Iterator uses more memory
for trade in DBNStream("file.dbn")
    process(trade)
end

# ✅ Callback uses minimal memory
foreach_trade("file.dbn") do trade
    process(trade)
end
```

## Performance Issues

### Slower Than Expected

**Problem**: Reading/writing is slow

**Checklist**:

1. **Use type-specific readers**:
```julia
# ❌ Slow
records = read_dbn("trades.dbn")

# ✅ 5-6x faster
trades = read_trades("trades.dbn")
```

2. **Use callbacks for processing**:
```julia
# ❌ Slower
trades = read_trades("file.dbn")
total = sum(t.size for t in trades)

# ✅ Up to 6x faster
total = Ref(0)
foreach_trade("file.dbn") do trade
    total[] += trade.size
end
```

3. **Check for type instability**:
```julia
# Run with type checking
using DBN
@code_warntype read_trades("file.dbn")
```

4. **Profile your code**:
```julia
using Profile

@profile begin
    foreach_trade("file.dbn") do trade
        # Your processing code
    end
end

Profile.print()
```

## Data Issues

### Wrong Schema Error

**Problem**: `ERROR: Expected TradeMsg but got rtype=...`

**Cause**: File contains different message type than expected

**Solutions**:

1. **Check file schema**:
```julia
metadata, _ = read_dbn_with_metadata("file.dbn")
println("Schema: $(metadata.schema)")
```

2. **Use generic reader**:
```julia
# For mixed-schema files
records = read_dbn("file.dbn")

# Or iterator
for record in DBNStream("file.dbn")
    if record isa TradeMsg
        # Handle trade
    elseif record isa MBOMsg
        # Handle MBO
    end
end
```

### Price Conversion Issues

**Problem**: Prices look wrong

**Remember**: DBN uses fixed-point prices!

```julia
# ❌ Wrong - prices are fixed-point integers
println(trade.price)  # e.g., 1005000 (not 100.50!)

# ✅ Convert to float
println(price_to_float(trade.price))  # 100.5
```

**Creating prices**:
```julia
# ✅ Convert float to fixed-point
price = float_to_price(100.50)  # 1005000

# ❌ Don't use float directly
trade.price = 100.50  # WRONG!
```

### Timestamp Conversion Issues

**Problem**: Timestamps look strange

**Remember**: DBN uses nanosecond timestamps!

```julia
# ❌ Raw timestamp
println(trade.hd.ts_event)  # 1704067200000000000 (nanoseconds!)

# ✅ Convert to DateTime
using Dates
println(ts_to_datetime(trade.hd.ts_event))  # 2024-01-01T00:00:00

# ✅ Format nicely
dt = ts_to_datetime(trade.hd.ts_event)
println(Dates.format(dt, "yyyy-mm-dd HH:MM:SS"))
```

**Creating timestamps**:
```julia
using Dates

# ✅ Convert DateTime to nanoseconds
dt = DateTime(2024, 1, 1, 9, 30)
ts = datetime_to_ts(dt)

# ❌ Don't use DateTime directly
record.ts_event = DateTime(2024, 1, 1)  # WRONG!
```

## File Format Issues

### Unsupported DBN Version

**Problem**: `ERROR: Unsupported DBN version 1`

**Cause**: DBN.jl only supports DBN v2 and v3

**Solution**: Upgrade v1 files using Databento CLI:
```bash
dbn version1.dbn --output version2.dbn --upgrade
```

See [Databento CLI documentation](https://databento.com/docs/api-reference-historical/cli).

### Corrupt File

**Problem**: `ERROR` when reading file

**Diagnostics**:
```julia
# Check file size
filesize("file.dbn")  # Should be > 0

# Check file is readable
open("file.dbn", "r") do io
    read(io, 1)  # Should not error
end

# Try reading just metadata
metadata, _ = read_dbn_with_metadata("file.dbn")
println(metadata)
```

## Callback Issues

### Cannot Mutate Variable

**Problem**: `ERROR: cannot assign variable from callback`

**Cause**: Variables from outer scope are immutable in callbacks

**Solution**: Use `Ref` for mutable state:
```julia
# ❌ Won't work
count = 0
foreach_trade("file.dbn") do trade
    count += 1  # ERROR!
end

# ✅ Use Ref
count = Ref(0)
foreach_trade("file.dbn") do trade
    count[] += 1  # OK
end
println(count[])
```

### Cannot Break From Callback

**Problem**: Want to stop early but callbacks can't break

**Solution**: Use iterator pattern instead:
```julia
# ❌ Can't do this with callbacks
foreach_trade("file.dbn") do trade
    if trade.size > 100_000
        break  # ERROR: can't break from callback
    end
end

# ✅ Use iterator
for trade in DBNStream("file.dbn")
    if trade.size > 100_000
        println("Found large trade!")
        break  # OK
    end
end
```

## Conversion Issues

### CSV/JSON Round-Trip Differences

**Problem**: Data changes after CSV → DBN → CSV conversion

**Cause**: Text formats may lose precision or metadata

**Best Practice**:
- Use DBN format for archival storage
- Use CSV/JSON only for analysis or export
- Don't rely on perfect round-trip through text formats

### Parquet Schema Mismatch

**Problem**: `ERROR` when converting Parquet to DBN

**Cause**: Column names or types don't match DBN schema

**Solution**: Ensure Parquet has correct schema:
```julia
# Check column names
using Parquet2
df = Parquet2.Dataset("file.parquet") |> DataFrame
names(df)  # Should match DBN field names

# Ensure correct types (especially timestamps, prices)
```

## Getting Help

If you encounter issues not covered here:

1. **Check the documentation** for the specific function
2. **Search existing GitHub issues**: [github.com/tbeason/DBN.jl/issues](https://github.com/tbeason/DBN.jl/issues)
3. **Ask on GitHub Discussions** (if available)
4. **Open a new issue** with:
   - Julia version (`versioninfo()`)
   - DBN.jl version
   - Minimal example reproducing the issue
   - Error message and stack trace

### Minimal Reproducible Example

When reporting issues, include:

```julia
using Pkg, DBN

# Julia version
versioninfo()

# Package version
Pkg.status("DBN")

# Minimal code that reproduces the issue
# (Use synthetic data if possible)
metadata = Metadata(...)
records = [TradeMsg(...)]
write_dbn("test.dbn", metadata, records)
result = read_trades("test.dbn")  # Error occurs here
```

## Common Error Messages

| Error | Likely Cause | Solution |
|-------|--------------|----------|
| `Out of memory` | File too large for RAM | Use streaming (callbacks or iterator) |
| `zstd error` | Corrupt .zst file or codec issue | Reinstall CodecZstd or check file |
| `Expected TradeMsg but got rtype=...` | Wrong schema | Check metadata.schema, use correct reader |
| `Unsupported DBN version 1` | Old DBN format | Upgrade using Databento CLI |
| `cannot assign variable` | Immutable in callback scope | Use Ref for mutable state |
| `SystemError: opening file` | File not found or permissions | Check path and file permissions |

## See Also

- [Quick Start Guide](quickstart.md) - Basic usage
- [Reading Guide](guide/reading.md) - Reading methods
- [Performance Guide](performance.md) - Optimization
- [GitHub Issues](https://github.com/tbeason/DBN.jl/issues) - Report bugs
- [Databento Documentation](https://databento.com/docs/) - DBN format details
