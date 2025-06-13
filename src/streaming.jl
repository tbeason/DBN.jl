# DBN streaming functionality

# DBNStream iterator for streaming file reading
struct DBNStream
    filename::String
end

# Make DBNStream iterable
Base.iterate(stream::DBNStream) = begin
    io = open(stream.filename, "r")
    decoder = DBNDecoder(io)
    read_header!(decoder)
    return iterate(stream, (decoder, io))
end

Base.iterate(stream::DBNStream, state) = begin
    decoder, io = state
    if eof(decoder.io)
        close(io)
        return nothing
    end
    record = read_record(decoder)
    if record === nothing
        return iterate(stream, state)  # Skip unknown records
    end
    return (record, state)
end

Base.IteratorSize(::Type{DBNStream}) = Base.SizeUnknown()
Base.eltype(::Type{DBNStream}) = Any

# Streaming writer for real-time data capture
mutable struct DBNStreamWriter
    encoder::DBNEncoder
    record_count::Int64
    first_ts::Int64
    last_ts::Int64
    auto_flush::Bool
    flush_interval::Int
    last_flush_count::Int64
end

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

# Compression utility for end-of-day processing
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
    
    # Get stats before potentially deleting original
    original_size = filesize(input_file)
    compressed_size = filesize(output_file)
    compression_ratio = 1.0 - (compressed_size / original_size)
    
    # Optionally delete original
    if delete_original
        rm(input_file)
    end
    
    return (
        original_size = original_size,
        compressed_size = compressed_size,
        compression_ratio = compression_ratio,
        space_saved = original_size - compressed_size
    )
end

# Batch compression for multiple files
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