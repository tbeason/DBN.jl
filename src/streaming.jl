# DBN streaming functionality

"""
    DBNStream

Iterator for streaming DBN file reading with automatic compression support.

# Fields
- `decoder::DBNDecoder`: Decoder instance (stored to avoid allocation overhead)
- `cleanup::Ref{Bool}`: Flag to track if cleanup has been done

# Usage
```julia
for record in DBNStream("data.dbn")
    println(typeof(record))
end
```

# Details
Provides memory-efficient streaming access to DBN files without loading
the entire file into memory. Automatically detects and handles Zstd compression.
Gracefully skips unknown record types.
"""
mutable struct DBNStream
    decoder::DBNDecoder
    cleanup::Ref{Bool}
    
    function DBNStream(filename::String)
        decoder = DBNDecoder(filename)
        new(decoder, Ref(false))
    end
end

"""
    Base.iterate(stream::DBNStream)

Initialize iteration over a DBN stream.

# Arguments
- `stream::DBNStream`: Stream to iterate over

# Returns
- `Tuple`: (first_record, nothing) or `nothing` if empty
"""
Base.iterate(stream::DBNStream) = iterate(stream, nothing)

"""
    Base.iterate(stream::DBNStream, state)

Continue iteration over a DBN stream.

# Arguments
- `stream::DBNStream`: Stream being iterated
- `state`: Unused (kept for API compatibility)

# Returns
- `Tuple`: (next_record, nothing) or `nothing` if end reached
"""
Base.iterate(stream::DBNStream, state) = begin
    decoder = stream.decoder
    
    # Check if already cleaned up
    if stream.cleanup[]
        return nothing
    end
    
    if eof(decoder.io)
        # Clean up resources once
        if !stream.cleanup[]
            if decoder.io !== decoder.base_io
                close(decoder.io)
            end
            if isa(decoder.base_io, IOStream)
                close(decoder.base_io)
            end
            stream.cleanup[] = true
        end
        return nothing
    end
    
    record = read_record(decoder)
    if record === nothing
        return iterate(stream, state)  # Skip unknown records
    end
    return (record, nothing)
end

"""
    Base.IteratorSize(::Type{DBNStream})

Indicates that DBNStream has unknown size (cannot determine record count without reading).
"""
Base.IteratorSize(::Type{DBNStream}) = Base.SizeUnknown()
"""
    Base.eltype(::Type{DBNStream})

Element type for DBNStream iterator (Any, since different record types are possible).
"""
Base.eltype(::Type{DBNStream}) = Any

# ============================================================================
# Internal Helpers (Shared by Eager Read and Callback Streaming)
# ============================================================================

# Map type to RType for validation
_type_to_rtype_stream(::Type{TradeMsg}) = RType.MBP_0_MSG
_type_to_rtype_stream(::Type{MBOMsg}) = RType.MBO_MSG
_type_to_rtype_stream(::Type{MBP1Msg}) = RType.MBP_1_MSG
_type_to_rtype_stream(::Type{MBP10Msg}) = RType.MBP_10_MSG
_type_to_rtype_stream(::Type{OHLCVMsg}) = RType.OHLCV_1S_MSG  # Default to 1s
_type_to_rtype_stream(::Type{StatusMsg}) = RType.STATUS_MSG
_type_to_rtype_stream(::Type{InstrumentDefMsg}) = RType.INSTRUMENT_DEF_MSG
_type_to_rtype_stream(::Type{ImbalanceMsg}) = RType.IMBALANCE_MSG

# Type-stable record reading helpers (shared by eager read and callback API)
@inline function _read_typed_record_stream(decoder::DBNDecoder, ::Type{TradeMsg}, hd::RecordHeader)
    return read_trade_msg(decoder, hd)
end

@inline function _read_typed_record_stream(decoder::DBNDecoder, ::Type{MBOMsg}, hd::RecordHeader)
    return read_mbo_msg(decoder, hd)
end

@inline function _read_typed_record_stream(decoder::DBNDecoder, ::Type{MBP1Msg}, hd::RecordHeader)
    return read_mbp1_msg(decoder, hd)
end

@inline function _read_typed_record_stream(decoder::DBNDecoder, ::Type{MBP10Msg}, hd::RecordHeader)
    return read_mbp10_msg(decoder, hd)
end

@inline function _read_typed_record_stream(decoder::DBNDecoder, ::Type{OHLCVMsg}, hd::RecordHeader)
    return read_ohlcv_msg(decoder, hd)
end

@inline function _read_typed_record_stream(decoder::DBNDecoder, ::Type{StatusMsg}, hd::RecordHeader)
    return read_status_msg(decoder, hd)
end

@inline function _read_typed_record_stream(decoder::DBNDecoder, ::Type{InstrumentDefMsg}, hd::RecordHeader)
    return read_instrument_def_msg(decoder, hd)
end

@inline function _read_typed_record_stream(decoder::DBNDecoder, ::Type{ImbalanceMsg}, hd::RecordHeader)
    return read_imbalance_msg(decoder, hd)
end

# ============================================================================
# Near-Zero-Allocation Callback-Based Streaming
# ============================================================================

"""
    foreach_record(f::Function, filename::String, ::Type{T}) where T

Highly optimized callback-based streaming with minimal allocations.

# Arguments
- `f::Function`: Callback function that processes each record
- `filename::String`: Path to DBN file
- `::Type{T}`: Record type (e.g., `TradeMsg`)

# Performance
Achieves near-zero allocations (typically <50 total allocations for any size file)
when the callback uses `Ref` for mutable state. The Julia compiler optimizes away
most per-record allocations, making this significantly faster than iterator-based
streaming for pure processing workloads.

# Performance tip: Use Ref for mutable state!
To achieve true near-zero allocations, use `Ref` for any mutable state in your
callback instead of plain variables:

```julia
# ✅ GOOD: Only ~44 allocations total (not per record!)
total = Ref(0.0)
foreach_record("trades.dbn", TradeMsg) do trade
    total[] += price_to_float(trade.price)
end
println(total[])

# ❌ SLOWER: May allocate per record due to closure overhead
total = 0.0
foreach_record("trades.dbn", TradeMsg) do trade
    total += price_to_float(trade.price)  # Closure capture causes allocations
end
```

# More examples
```julia
# Count records by side (using Ref for mutable Dict)
counts = Ref(Dict('A' => 0, 'B' => 0))
foreach_record("trades.dbn", TradeMsg) do trade
    counts[][Char(trade.side)] += 1
end

# Collect records (push! automatically copies bitstypes)
trades = TradeMsg[]
sizehint!(trades, 100_000)
foreach_record("trades.dbn", TradeMsg) do trade
    push!(trades, trade)  # Safe: TradeMsg is copied
end

# Filter while streaming - only store what you need
high_volume = TradeMsg[]
foreach_record("trades.dbn", TradeMsg) do trade
    if trade.size > 1000
        push!(high_volume, trade)
    end
end
```

# Note on bitstypes
All DBN message types are immutable bitstypes, so `push!(array, record)`
automatically makes a value copy. You can safely store records in arrays without
explicit copying.
"""
function foreach_record(f::Function, filename::String, ::Type{T}) where T
    decoder = DBNDecoder(filename)
    _foreach_record_impl(f, decoder, T)
    return nothing
end

# Internal implementation that works with an open decoder
# This allows eager read to avoid opening the file twice
function _foreach_record_impl(f::Function, decoder::DBNDecoder, ::Type{T}) where T
    expected_rtype = _type_to_rtype_stream(T)

    # Pre-allocate a single buffer that we'll reuse
    # Since T is a bitstype (all our message types are), we can safely mutate it
    buffer = Ref{T}()

    try
        while !eof(decoder.io)
            # Read header
            hd_result = read_record_header(decoder.io)

            # Handle unknown record types
            if hd_result isa Tuple
                _, rtype_raw, record_length = hd_result
                skip(decoder.io, record_length - 2)
                continue
            end

            hd = hd_result

            # Verify type matches expected
            if hd.rtype != expected_rtype
                # Special handling for OHLCV variants
                if T === OHLCVMsg && hd.rtype in (RType.OHLCV_1S_MSG, RType.OHLCV_1M_MSG, RType.OHLCV_1H_MSG, RType.OHLCV_1D_MSG)
                    # OK, continue
                else
                    error("Expected $(T) (rtype=$(expected_rtype)) but got rtype=$(hd.rtype)")
                end
            end

            # Read record directly into buffer
            buffer[] = _read_typed_record_stream(decoder, T, hd)

            # Call user function with buffer contents
            f(buffer[])
        end
    finally
        # Clean up
        if decoder.io !== decoder.base_io
            close(decoder.io)
        end
        if isa(decoder.base_io, IOStream)
            close(decoder.base_io)
        end
    end
end

# Convenience functions for callback-based streaming

"""
    foreach_trade(f::Function, filename::String)

Near-zero-allocation streaming of trade data using callback pattern.
See `foreach_record` for usage and performance tips.
"""
foreach_trade(f::Function, filename::String) = foreach_record(f, filename, TradeMsg)

"""
    foreach_mbo(f::Function, filename::String)

Near-zero-allocation streaming of MBO data using callback pattern.
See `foreach_record` for usage and performance tips.
"""
foreach_mbo(f::Function, filename::String) = foreach_record(f, filename, MBOMsg)

"""
    foreach_mbp1(f::Function, filename::String)

Near-zero-allocation streaming of MBP-1 (top-of-book) data using callback pattern.
See `foreach_record` for usage and performance tips.
"""
foreach_mbp1(f::Function, filename::String) = foreach_record(f, filename, MBP1Msg)

"""
    foreach_mbp10(f::Function, filename::String)

Near-zero-allocation streaming of MBP-10 (10-level depth) data using callback pattern.
See `foreach_record` for usage and performance tips.
"""
foreach_mbp10(f::Function, filename::String) = foreach_record(f, filename, MBP10Msg)

"""
    foreach_tbbo(f::Function, filename::String)

Near-zero-allocation streaming of TBBO (Trade BBO) data using callback pattern.
Uses MBP-1 records. See `foreach_record` for usage and performance tips.
"""
foreach_tbbo(f::Function, filename::String) = foreach_record(f, filename, MBP1Msg)

"""
    foreach_ohlcv(f::Function, filename::String)

Near-zero-allocation streaming of OHLCV (candlestick) data using callback pattern.
See `foreach_record` for usage and performance tips.
"""
foreach_ohlcv(f::Function, filename::String) = foreach_record(f, filename, OHLCVMsg)

"""
    foreach_ohlcv_1s(f::Function, filename::String)

Near-zero-allocation streaming of 1-second OHLCV data using callback pattern.
See `foreach_record` for usage and performance tips.
"""
foreach_ohlcv_1s(f::Function, filename::String) = foreach_record(f, filename, OHLCVMsg)

"""
    foreach_ohlcv_1m(f::Function, filename::String)

Near-zero-allocation streaming of 1-minute OHLCV data using callback pattern.
See `foreach_record` for usage and performance tips.
"""
foreach_ohlcv_1m(f::Function, filename::String) = foreach_record(f, filename, OHLCVMsg)

"""
    foreach_ohlcv_1h(f::Function, filename::String)

Near-zero-allocation streaming of 1-hour OHLCV data using callback pattern.
See `foreach_record` for usage and performance tips.
"""
foreach_ohlcv_1h(f::Function, filename::String) = foreach_record(f, filename, OHLCVMsg)

"""
    foreach_ohlcv_1d(f::Function, filename::String)

Near-zero-allocation streaming of 1-day OHLCV data using callback pattern.
See `foreach_record` for usage and performance tips.
"""
foreach_ohlcv_1d(f::Function, filename::String) = foreach_record(f, filename, OHLCVMsg)

# Consolidated/BBO message streaming
"""
    foreach_cmbp1(f::Function, filename::String)

Near-zero-allocation streaming of Consolidated MBP-1 data using callback pattern.
See `foreach_record` for usage and performance tips.
"""
foreach_cmbp1(f::Function, filename::String) = foreach_record(f, filename, CMBP1Msg)

"""
    foreach_cbbo1s(f::Function, filename::String)

Near-zero-allocation streaming of Consolidated BBO 1-second data using callback pattern.
See `foreach_record` for usage and performance tips.
"""
foreach_cbbo1s(f::Function, filename::String) = foreach_record(f, filename, CBBO1sMsg)

"""
    foreach_cbbo1m(f::Function, filename::String)

Near-zero-allocation streaming of Consolidated BBO 1-minute data using callback pattern.
See `foreach_record` for usage and performance tips.
"""
foreach_cbbo1m(f::Function, filename::String) = foreach_record(f, filename, CBBO1mMsg)

"""
    foreach_tcbbo(f::Function, filename::String)

Near-zero-allocation streaming of Top Consolidated BBO data using callback pattern.
See `foreach_record` for usage and performance tips.
"""
foreach_tcbbo(f::Function, filename::String) = foreach_record(f, filename, TCBBOMsg)

"""
    foreach_bbo1s(f::Function, filename::String)

Near-zero-allocation streaming of BBO 1-second data using callback pattern.
See `foreach_record` for usage and performance tips.
"""
foreach_bbo1s(f::Function, filename::String) = foreach_record(f, filename, BBO1sMsg)

"""
    foreach_bbo1m(f::Function, filename::String)

Near-zero-allocation streaming of BBO 1-minute data using callback pattern.
See `foreach_record` for usage and performance tips.
"""
foreach_bbo1m(f::Function, filename::String) = foreach_record(f, filename, BBO1mMsg)

"""
    DBNStreamWriter

Streaming writer for real-time DBN data capture with automatic timestamp tracking.

# Fields
- `encoder::DBNEncoder`: Underlying encoder for writing data
- `record_count::Int64`: Number of records written
- `first_ts::Int64`: First timestamp encountered
- `last_ts::Int64`: Last timestamp encountered  
- `auto_flush::Bool`: Whether to automatically flush data
- `flush_interval::Int`: Number of records between automatic flushes
- `last_flush_count::Int64`: Record count at last flush

# Usage
```julia
writer = DBNStreamWriter("live.dbn", "XNAS", Schema.TRADES)
write_record!(writer, trade_record)
close_writer!(writer)
```
"""
mutable struct DBNStreamWriter
    encoder::DBNEncoder
    record_count::Int64
    first_ts::Int64
    last_ts::Int64
    auto_flush::Bool
    flush_interval::Int
    last_flush_count::Int64
end

"""
    DBNStreamWriter(filename::String, dataset::String, schema::Schema.T; 
                   symbols::Vector{String}=String[],
                   auto_flush::Bool=true,
                   flush_interval::Int=1000)

Construct a streaming writer for real-time DBN data capture.

# Arguments
- `filename::String`: Output file path
- `dataset::String`: Dataset identifier
- `schema::Schema.T`: Data schema type
- `symbols::Vector{String}`: List of symbols (optional)
- `auto_flush::Bool`: Enable automatic flushing (default: true)
- `flush_interval::Int`: Records between flushes (default: 1000)

# Returns
- `DBNStreamWriter`: Writer instance ready for recording

# Details
Creates a writer with placeholder timestamps that will be updated as records
are written. The header is written immediately but will be updated with
final timestamps when the writer is closed.
"""
function DBNStreamWriter(filename::String, dataset::String, schema::Schema.T; 
                        symbols::Vector{String}=String[],
                        auto_flush::Bool=true,
                        flush_interval::Int=1000)
    # Create metadata with placeholder timestamps (using 0 instead of typemin)
    metadata = Metadata(
        UInt8(DBN_VERSION),
        dataset,
        schema,
        0,  # Will update with first record
        0,  # Will update with last record
        UInt64(0),
        SType.RAW_SYMBOL,
        SType.RAW_SYMBOL,
        false,
        symbols,
        String[],
        String[],
        Tuple{String,String,Int64,Int64}[]
    )
    
    io = open(filename, "w")
    encoder = DBNEncoder(io, metadata)
    
    # Write header (will update it later)
    write_header(encoder)
    
    return DBNStreamWriter(encoder, 0, typemax(Int64), 0, 
                          auto_flush, flush_interval, 0)
end

"""
    write_record!(writer::DBNStreamWriter, record)

Write a record to the streaming writer and update timestamps.

# Arguments
- `writer::DBNStreamWriter`: Writer instance
- `record`: Record to write (any DBN message type)

# Details
Writes the record and automatically:
- Updates first/last timestamp tracking
- Increments record count
- Performs auto-flush if enabled and interval reached

# Throws
- `IOError`: If the writer has been closed
"""
function write_record!(writer::DBNStreamWriter, record)
    # Check if the stream is still open
    if !isopen(writer.encoder.io)
        throw(Base.IOError("Cannot write to closed DBNStreamWriter", 0))
    end
    
    # Update timestamps
    if hasproperty(record, :hd) && hasproperty(record.hd, :ts_event)
        ts = record.hd.ts_event
        writer.first_ts = min(writer.first_ts, ts)
        writer.last_ts = max(writer.last_ts, ts)
    end
    
    # Write the record
    write_record(writer.encoder, record)
    writer.record_count += 1
    
    # Auto-flush if enabled
    if writer.auto_flush && (writer.record_count - writer.last_flush_count) >= writer.flush_interval
        flush(writer.encoder.io)
        writer.last_flush_count = writer.record_count
    end
end

"""
    close_writer!(writer::DBNStreamWriter)

Finalize and close the streaming writer, updating the header with final metadata.

# Arguments
- `writer::DBNStreamWriter`: Writer to close

# Details
Finalizes the file by:
- Flushing any remaining data
- Updating the header with final timestamps and record count
- Properly closing the file handle

The header is rewritten with accurate metadata based on all records written.
"""
function close_writer!(writer::DBNStreamWriter)
    # Flush any remaining data
    flush(writer.encoder.io)
    
    # Save current position
    current_pos = position(writer.encoder.io)
    
    # Update header with final timestamps and count
    seekstart(writer.encoder.io)
    
    # Handle the case where no records were written
    final_start_ts = writer.first_ts == typemax(Int64) ? 0 : writer.first_ts
    final_end_ts = writer.last_ts == 0 ? 0 : writer.last_ts
    
    # Update metadata
    writer.encoder.metadata = Metadata(
        writer.encoder.metadata.version,
        writer.encoder.metadata.dataset,
        writer.encoder.metadata.schema,
        final_start_ts,
        final_end_ts,
        UInt64(writer.record_count),
        writer.encoder.metadata.stype_in,
        writer.encoder.metadata.stype_out,
        writer.encoder.metadata.ts_out,
        writer.encoder.metadata.symbols,
        writer.encoder.metadata.partial,
        writer.encoder.metadata.not_found,
        writer.encoder.metadata.mappings
    )
    
    # Rewrite header with updated metadata
    write_header(writer.encoder)
    
    # Make sure we don't truncate the file - seek back to the end
    if current_pos > position(writer.encoder.io)
        seek(writer.encoder.io, current_pos)
    end
    
    # Close the file
    close(writer.encoder.io)
end

"""
    compress_dbn_file(input_file::String, output_file::String; 
                     compression_level::Int=3,
                     delete_original::Bool=false)

Compress a DBN file using Zstd compression.

# Arguments
- `input_file::String`: Path to input DBN file
- `output_file::String`: Path for compressed output file
- `compression_level::Int`: Zstd compression level (default: 3)
- `delete_original::Bool`: Whether to delete input file after compression (default: false)

# Returns
- `NamedTuple`: Compression statistics including:
  - `original_size::Int`: Original file size in bytes
  - `compressed_size::Int`: Compressed file size in bytes
  - `compression_ratio::Float64`: Compression ratio (0.0-1.0)
  - `space_saved::Int`: Bytes saved by compression

# Details
Performs streaming compression to handle large files efficiently.
Preserves all metadata and record integrity.
"""
function compress_dbn_file(input_file::String, output_file::String; 
                          compression_level::Int=3,
                          delete_original::Bool=false)
    # Read header to get metadata
    metadata = open(input_file, "r") do io
        decoder = DBNDecoder(io)
        read_header!(decoder)
        decoder.metadata
    end
    
    # Update metadata for compression
    compressed_metadata = Metadata(
        metadata.version,
        metadata.dataset,
        metadata.schema,
        metadata.start_ts,
        metadata.end_ts,
        metadata.limit,
        metadata.stype_in,
        metadata.stype_out,
        metadata.ts_out,
        metadata.symbols,
        metadata.partial,
        metadata.not_found,
        metadata.mappings
    )
    
    # Stream compress the file using Zstd compression
    open(output_file, "w") do base_io
        # Create a Zstd compression stream
        compressed_io = TranscodingStream(ZstdCompressor(level=compression_level), base_io)
        
        try
            encoder = DBNEncoder(compressed_io, compressed_metadata)
            write_header(encoder)
            
            # Stream through input file
            for record in DBNStream(input_file)
                write_record(encoder, record)
            end
            
            finalize_encoder(encoder)
        finally
            # Close the compression stream
            close(compressed_io)
        end
    end

    # Force garbage collection to ensure file handles are released on Windows
    GC.gc()

    # Get stats before potentially deleting original
    original_size = filesize(input_file)
    compressed_size = filesize(output_file)
    compression_ratio = 1.0 - (compressed_size / original_size)

    # Optionally delete original
    if delete_original
        # Force GC again before deletion to ensure handles are released
        GC.gc()
        rm(input_file)
    end
    
    return (
        original_size = original_size,
        compressed_size = compressed_size,
        compression_ratio = compression_ratio,
        space_saved = original_size - compressed_size
    )
end

"""
    compress_daily_files(date::Date, base_dir::String; 
                        pattern::Regex=r".*\\.dbn\$",
                        workers::Int=Threads.nthreads())

Compress multiple DBN files for a specific date in parallel.

# Arguments
- `date::Date`: Date to process (looks for files containing "yyyy-mm-dd")
- `base_dir::String`: Directory containing DBN files
- `pattern::Regex`: File pattern to match (default: r".*\\.dbn\$")
- `workers::Int`: Number of parallel workers (default: thread count)

# Returns
- `Vector`: Compression results for each file (or `nothing` for failures)

# Details
Finds all uncompressed DBN files matching the date pattern and compresses
them in parallel. Original files are deleted after successful compression.
Provides detailed logging of compression results and any errors.

# Example
```julia
results = compress_daily_files(Date("2024-01-01"), "data/")
```
"""
function compress_daily_files(date::Date, base_dir::String; 
                            pattern::Regex=r".*\.dbn$",
                            workers::Int=Threads.nthreads())
    
    # Find all uncompressed DBN files for the date
    date_str = Dates.format(date, "yyyy-mm-dd")
    files = filter(readdir(base_dir, join=true)) do file
        occursin(pattern, file) && occursin(date_str, file)
    end
    
    # Compress in parallel
    results = Vector{Any}(undef, length(files))
    
    Threads.@threads for i in 1:length(files)
        input_file = files[i]
        output_file = replace(input_file, ".dbn" => ".dbn.zst")
        
        try
            results[i] = compress_dbn_file(input_file, output_file, delete_original=true)
            @info "Compressed $input_file" results[i]...
        catch e
            @error "Failed to compress $input_file" exception=e
            results[i] = nothing
        end
    end
    
    return results
end