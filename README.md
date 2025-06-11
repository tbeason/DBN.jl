# DBN.jl

Julia implementation of the Databento Binary Enconding (DBN) message encoding and storage format for normalized market data.

For more details, read the [introduction to DBN](https://databento.com/docs/standards-and-conventions/databento-binary-encoding).

## Features

- [] Complete DBN v3 Format Support
- [] Efficient streaming support (read and write)
- [] Zstd file compression support (read and write)
- [] Convert to Parquet, CSV, JSON

## Installation

Once registered in the General Registry, this package can be added with

```julia
] add DBN
```

## Usage

```julia
# Reading
records = read_dbn("file.dbn")
for record in DBNStream("file.dbn")
    # Process record
end

# Writing
write_dbn("out.dbn", metadata, records)
writer = DBNStreamWriter("live.dbn", "XNAS", TRADES)
write_record!(writer, record)
close_writer!(writer)

# Compression
compress_dbn_file("input.dbn", "output.dbn.zst")
compress_daily_files(Date("2024-01-01"), "data/")

# Conversion
dbn_to_parquet("input.dbn", "output_dir/")
```

## License

I am not affiliated with Databento.

The official implementations for [dbn](https://github.com/databento/dbn) are distributed under the [Apache 2.0 License](https://www.apache.org/licenses/LICENSE-2.0.html).
