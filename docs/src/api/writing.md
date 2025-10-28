# Writing API Reference

Functions for writing DBN files.

## Bulk Writing

```@docs
write_dbn
```

## Low-Level Writing

```@docs
write_header
finalize_encoder
```

## Streaming Writer

For writing data as it arrives (real-time or sequential processing).

```@docs
DBNStreamWriter
write_record!
close_writer!
```

## Compression

```@docs
compress_dbn_file
compress_daily_files
```

## Usage Patterns

### Bulk Writing

Use `write_dbn()` when you have all records in memory:

```julia
write_dbn("output.dbn", metadata, records)

# With compression
write_dbn("output.dbn.zst", metadata, records)
```

### Streaming Writing

Use `DBNStreamWriter` for real-time or sequential data:

```julia
writer = DBNStreamWriter("output.dbn", "XNAS", Schema.TRADES)

for record in data_source
    write_record!(writer, record)
end

close_writer!(writer)
```

## Performance Tips

- **Bulk writing** is faster than streaming when you have all data
- **Use compression** for storage (2-3x smaller files)
- **Pre-allocate** vectors when building record collections
- Always **close stream writers** to finalize the file

See the [Writing Guide](../guide/writing.md) for detailed examples and best practices.
