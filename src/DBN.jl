"""
    DBN

Julia implementation of the Databento Binary Encoding (DBN) format for normalized market data.

# Overview

DBN.jl provides complete support for reading and writing DBN v3 format files with:
- Efficient streaming support for large files
- Automatic Zstd compression/decompression  
- All DBN v3 message types
- Timestamp utilities with nanosecond precision
- Price conversion utilities with fixed-point arithmetic

# Main Functions

## Reading Data
- `read_dbn(filename)`: Read entire file into memory
- `DBNStream(filename)`: Memory-efficient streaming iterator
- `DBNDecoder(filename)`: Low-level decoder with manual control

## Writing Data  
- `write_dbn(filename, metadata, records)`: Write complete file
- `DBNStreamWriter(filename, dataset, schema)`: Real-time streaming writer
- `DBNEncoder(io, metadata)`: Low-level encoder

## Compression
- `compress_dbn_file(input, output)`: Compress single file
- `compress_daily_files(date, directory)`: Batch compress files

## Utilities
- `price_to_float(price)` / `float_to_price(value)`: Price conversions
- `ts_to_datetime(ts)` / `datetime_to_ts(dt)`: Timestamp conversions
- `DBNTimestamp(ns)`: High-precision timestamp handling

# Example Usage

```julia
using DBN

# Reading data
records = read_dbn("data.dbn")
for record in DBNStream("large_file.dbn.zst")
    process(record)
end

# Writing data
metadata = Metadata(3, "XNAS", Schema.TRADES, start_ts, end_ts, 
                   length(records), SType.RAW_SYMBOL, SType.RAW_SYMBOL, 
                   false, symbols, [], [], [])
write_dbn("output.dbn", metadata, records)

# Streaming writer
writer = DBNStreamWriter("live.dbn", "XNAS", Schema.TRADES)
write_record!(writer, trade_msg)
close_writer!(writer)
```

# Supported Message Types

- Market Data: `MBOMsg`, `TradeMsg`, `MBP1Msg`, `MBP10Msg`, `OHLCVMsg`
- Consolidated: `CMBP1Msg`, `CBBO1sMsg`, `CBBO1mMsg`, `TCBBOMsg`, `BBO1sMsg`, `BBO1mMsg`  
- Status: `StatusMsg`, `ImbalanceMsg`, `StatMsg`
- System: `ErrorMsg`, `SymbolMappingMsg`, `SystemMsg`
- Definition: `InstrumentDefMsg`

See the [DBN specification](https://databento.com/docs/standards-and-conventions/databento-binary-encoding) 
for complete format documentation.
"""
module DBN

# All using statements at the top
using Dates
using CodecZstd
using TranscodingStreams
using EnumX
using DataFrames
using CSV
using Parquet2
using JSON3


# Include all the component files
include("types.jl")
include("messages.jl")
include("decode.jl")
include("encode.jl")
include("streaming.jl")
include("export.jl")

# Exports
export DBNDecoder, DBNEncoder, read_dbn, read_dbn_with_metadata, write_dbn
export Metadata, DBNHeader, RecordHeader, DBNTimestamp
export MBOMsg, TradeMsg, MBP1Msg, MBP10Msg, OHLCVMsg, StatusMsg, ImbalanceMsg, StatMsg
export CMBP1Msg, CBBO1sMsg, CBBO1mMsg, TCBBOMsg, BBO1sMsg, BBO1mMsg
export ErrorMsg, SymbolMappingMsg, SystemMsg, InstrumentDefMsg
export DBNStream, DBNStreamWriter, write_record!, close_writer!
export compress_dbn_file, compress_daily_files
export Schema, Compression, Encoding, SType, RType, Action, Side, InstrumentClass
export price_to_float, float_to_price, ts_to_datetime, datetime_to_ts, ts_to_date_time, date_time_to_ts, to_nanoseconds
export DBN_VERSION, FIXED_PRICE_SCALE, UNDEF_PRICE, UNDEF_ORDER_SIZE, UNDEF_TIMESTAMP
export BidAskPair, VersionUpgradePolicy, DatasetCondition
export write_header, read_header!, write_record, read_record, finalize_encoder
export dbn_to_csv, dbn_to_json, dbn_to_parquet, records_to_dataframe

end  # module DBN