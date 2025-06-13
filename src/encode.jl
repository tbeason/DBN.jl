# DBN encoding functionality

"""
    DBNEncoder

Encoder for writing DBN (Databento Binary Encoding) files with optional compression.

# Fields
- `io::IO`: Current IO stream (may be wrapped with compression)
- `base_io::IO`: Original IO stream before any compression wrapper
- `metadata::Metadata`: Metadata for the DBN file
- `compressed_buffer::Union{IOBuffer,Nothing}`: Buffer for compressed data (if applicable)
"""
mutable struct DBNEncoder
    io::IO
    base_io::IO  # Original IO before compression wrapper
    metadata::Metadata
    compressed_buffer::Union{IOBuffer,Nothing}
end

"""
    DBNEncoder(io::IO, metadata::Metadata)

Construct a DBNEncoder for writing to an IO stream.

# Arguments
- `io::IO`: Output stream to write to
- `metadata::Metadata`: Metadata information for the DBN file

# Returns
- `DBNEncoder`: Encoder instance ready for writing
"""
DBNEncoder(io::IO, metadata::Metadata) = DBNEncoder(io, io, metadata, nothing)

"""
    write_header(encoder::DBNEncoder)

Write the DBN file header including magic bytes, version, and metadata.

# Arguments
- `encoder::DBNEncoder`: Encoder instance containing metadata to write

# Details
Writes the complete DBN header in the correct binary format:
- Magic bytes "DBN"
- Version number
- Metadata length
- Complete metadata section with all fields

Always writes to the base IO stream (uncompressed) as headers must be readable
for compression detection.
"""
function write_header(encoder::DBNEncoder)
    # Always write header to the base IO (uncompressed)
    io = encoder.base_io
    
    # Write magic bytes "DBN"
    write(io, b"DBN")
    
    # Write version
    write(io, UInt8(DBN_VERSION))
    
    # Create metadata buffer to calculate size
    metadata_buf = IOBuffer()
    
    # Write metadata fields in the exact format that read_header! expects
    
    # Dataset (16 bytes fixed-length C string)
    dataset_bytes = Vector{UInt8}(undef, 16)
    fill!(dataset_bytes, 0)
    dataset_str_bytes = Vector{UInt8}(encoder.metadata.dataset)
    copy_len = min(length(dataset_str_bytes), 15)  # Leave room for null terminator
    if copy_len > 0
        dataset_bytes[1:copy_len] = dataset_str_bytes[1:copy_len]
    end
    write(metadata_buf, dataset_bytes)
    
    # Schema (2 bytes)
    write(metadata_buf, htol(UInt16(encoder.metadata.schema)))
    
    # Start timestamp (8 bytes)
    write(metadata_buf, htol(UInt64(encoder.metadata.start_ts)))
    
    # End timestamp (8 bytes)
    end_ts = encoder.metadata.end_ts === nothing ? 0 : UInt64(encoder.metadata.end_ts)
    write(metadata_buf, htol(end_ts))
    
    # Limit (8 bytes)
    limit = encoder.metadata.limit === nothing ? 0 : encoder.metadata.limit
    write(metadata_buf, htol(UInt64(limit)))
    
    # NOTE: For version > 1, we DON'T write record_count (8 bytes) here
    # This is skipped in the read function for version > 1
    
    # SType in (1 byte)
    stype_in_val = encoder.metadata.stype_in === nothing ? 0xFF : UInt8(encoder.metadata.stype_in)
    write(metadata_buf, stype_in_val)
    
    # SType out (1 byte)
    write(metadata_buf, UInt8(encoder.metadata.stype_out))
    
    # TS out (1 byte boolean)
    write(metadata_buf, encoder.metadata.ts_out ? UInt8(1) : UInt8(0))
    
    # Symbol string length (2 bytes) - only for version > 1
    # DBN v3 uses 71-byte symbol length (same as v2)
    symbol_cstr_len = UInt16(71)
    write(metadata_buf, htol(symbol_cstr_len))
    
    # Reserved padding (53 bytes for v3)
    write(metadata_buf, zeros(UInt8, 53))
    
    # Schema definition length (4 bytes) - always 0 for now
    write(metadata_buf, htol(UInt32(0)))
    
    # Variable-length sections
    
    # Symbols
    write(metadata_buf, htol(UInt32(length(encoder.metadata.symbols))))
    for sym in encoder.metadata.symbols
        sym_bytes = Vector{UInt8}(undef, symbol_cstr_len)
        fill!(sym_bytes, 0)
        sym_str_bytes = Vector{UInt8}(sym)
        copy_len = min(length(sym_str_bytes), symbol_cstr_len - 1)
        if copy_len > 0
            sym_bytes[1:copy_len] = sym_str_bytes[1:copy_len]
        end
        write(metadata_buf, sym_bytes)
    end
    
    # Partial symbols
    write(metadata_buf, htol(UInt32(length(encoder.metadata.partial))))
    for sym in encoder.metadata.partial
        sym_bytes = Vector{UInt8}(undef, symbol_cstr_len)
        fill!(sym_bytes, 0)
        sym_str_bytes = Vector{UInt8}(sym)
        copy_len = min(length(sym_str_bytes), symbol_cstr_len - 1)
        if copy_len > 0
            sym_bytes[1:copy_len] = sym_str_bytes[1:copy_len]
        end
        write(metadata_buf, sym_bytes)
    end
    
    # Not found symbols
    write(metadata_buf, htol(UInt32(length(encoder.metadata.not_found))))
    for sym in encoder.metadata.not_found
        sym_bytes = Vector{UInt8}(undef, symbol_cstr_len)
        fill!(sym_bytes, 0)
        sym_str_bytes = Vector{UInt8}(sym)
        copy_len = min(length(sym_str_bytes), symbol_cstr_len - 1)
        if copy_len > 0
            sym_bytes[1:copy_len] = sym_str_bytes[1:copy_len]
        end
        write(metadata_buf, sym_bytes)
    end
    
    # Symbol mappings - need to write the exact format the reader expects
    write(metadata_buf, htol(UInt32(length(encoder.metadata.mappings))))
    for (raw_symbol, mapped_symbol, start_date, end_date) in encoder.metadata.mappings
        # Raw symbol (fixed length)
        raw_sym_bytes = Vector{UInt8}(undef, symbol_cstr_len)
        fill!(raw_sym_bytes, 0)
        raw_str_bytes = Vector{UInt8}(raw_symbol)
        copy_len = min(length(raw_str_bytes), symbol_cstr_len - 1)
        if copy_len > 0
            raw_sym_bytes[1:copy_len] = raw_str_bytes[1:copy_len]
        end
        write(metadata_buf, raw_sym_bytes)
        
        # Intervals count (1 interval per mapping for simplicity)
        write(metadata_buf, htol(UInt32(1)))
        
        # Start date (4 bytes)
        write(metadata_buf, htol(UInt32(start_date)))
        
        # End date (4 bytes)
        write(metadata_buf, htol(UInt32(end_date)))
        
        # Mapped symbol (fixed length)
        mapped_sym_bytes = Vector{UInt8}(undef, symbol_cstr_len)
        fill!(mapped_sym_bytes, 0)
        mapped_str_bytes = Vector{UInt8}(mapped_symbol)
        copy_len = min(length(mapped_str_bytes), symbol_cstr_len - 1)
        if copy_len > 0
            mapped_sym_bytes[1:copy_len] = mapped_str_bytes[1:copy_len]
        end
        write(metadata_buf, mapped_sym_bytes)
    end
    
    # Get metadata bytes and write length + metadata
    metadata_bytes = take!(metadata_buf)
    write(io, htol(UInt32(length(metadata_bytes))))
    write(io, metadata_bytes)
end

"""
    write_record_header(io::IO, hd::RecordHeader)

Write a record header to the output stream.

# Arguments
- `io::IO`: Output stream
- `hd::RecordHeader`: Record header to write

# Details
Writes the standard DBN record header fields in binary format:
- Length (1 byte)
- Record type (1 byte)
- Publisher ID (2 bytes)
- Instrument ID (4 bytes)
- Event timestamp (8 bytes)
"""
function write_record_header(io::IO, hd::RecordHeader)
    write(io, hd.length)
    write(io, UInt8(hd.rtype))
    write(io, hd.publisher_id)
    write(io, hd.instrument_id)
    write(io, hd.ts_event)
end

"""
    write_fixed_string(io::IO, s::String, len::Int)

Write a fixed-length string with null padding to the output stream.

# Arguments
- `io::IO`: Output stream
- `s::String`: String to write
- `len::Int`: Fixed length to write (in bytes)

# Details
Writes exactly `len` bytes, truncating the string if too long or padding
with null bytes if too short. This ensures fixed-width fields in the
binary format.
"""
function write_fixed_string(io::IO, s::String, len::Int)
    bytes = Vector{UInt8}(undef, len)
    fill!(bytes, 0)  # Fill with null bytes
    s_bytes = Vector{UInt8}(s)
    copy_len = min(length(s_bytes), len)
    if copy_len > 0
        bytes[1:copy_len] = s_bytes[1:copy_len]
    end
    write(io, bytes)
end

"""
    write_record(encoder::DBNEncoder, record)

Write a complete record to the DBN stream.

# Arguments
- `encoder::DBNEncoder`: Encoder instance
- `record`: Record to write (any DBN message type)

# Details
Writes the complete record including header and body based on the record type.
Supports all DBN v3 record types:
- Market data: MBOMsg, TradeMsg, MBP1Msg, MBP10Msg, OHLCVMsg
- Status: StatusMsg, ImbalanceMsg, StatMsg
- System: ErrorMsg, SymbolMappingMsg, SystemMsg
- Definition: InstrumentDefMsg
- Consolidated: CMBP1Msg, CBBO1sMsg, CBBO1mMsg, TCBBOMsg, BBO1sMsg, BBO1mMsg

Each record type is serialized according to its specific binary layout.
"""
function write_record(encoder::DBNEncoder, record)
    io = encoder.io
    
    if isa(record, MBOMsg)
        write_record_header(io, record.hd)
        write(io, record.ts_recv)
        write(io, record.order_id)
        write(io, record.size)
        write(io, record.flags)
        write(io, record.channel_id)
        write(io, UInt8(record.action))
        write(io, UInt8(record.side))
        write(io, record.price)
        write(io, record.ts_in_delta)
        write(io, record.sequence)
        
    elseif isa(record, TradeMsg)
        write_record_header(io, record.hd)
        write(io, record.price)
        write(io, record.size)
        write(io, UInt8(record.action))
        write(io, UInt8(record.side))
        write(io, record.flags)
        write(io, record.depth)
        write(io, record.ts_recv)
        write(io, record.ts_in_delta)
        write(io, record.sequence)
        
    elseif isa(record, MBP1Msg)
        write_record_header(io, record.hd)
        write(io, record.price)
        write(io, record.size)
        write(io, UInt8(record.action))
        write(io, UInt8(record.side))
        write(io, record.flags)
        write(io, record.depth)
        write(io, record.ts_recv)
        write(io, record.ts_in_delta)
        write(io, record.sequence)
        
        # Write level
        write(io, record.levels.bid_px)
        write(io, record.levels.ask_px)
        write(io, record.levels.bid_sz)
        write(io, record.levels.ask_sz)
        write(io, record.levels.bid_ct)
        write(io, record.levels.ask_ct)
        
    elseif isa(record, MBP10Msg)
        write_record_header(io, record.hd)
        write(io, record.price)
        write(io, record.size)
        write(io, UInt8(record.action))
        write(io, UInt8(record.side))
        write(io, record.flags)
        write(io, record.depth)
        write(io, record.ts_recv)
        write(io, record.ts_in_delta)
        write(io, record.sequence)
        
        # Write levels
        for level in record.levels
            write(io, level.bid_px)
            write(io, level.ask_px)
            write(io, level.bid_sz)
            write(io, level.ask_sz)
            write(io, level.bid_ct)
            write(io, level.ask_ct)
        end
        
    elseif isa(record, OHLCVMsg)
        write_record_header(io, record.hd)
        write(io, record.open)
        write(io, record.high)
        write(io, record.low)
        write(io, record.close)
        write(io, record.volume)
        
    elseif isa(record, StatusMsg)
        write_record_header(io, record.hd)
        write(io, record.ts_recv)
        write(io, record.action)
        write(io, record.reason)
        write(io, record.trading_event)
        write(io, record.is_trading)
        write(io, record.is_quoting)
        write(io, record.is_short_sell_restricted)
        write(io, zeros(UInt8, 7))  # Reserved (adjusted)
        
    elseif isa(record, InstrumentDefMsg)
        write_record_header(io, record.hd)
        write(io, record.ts_recv)
        write(io, record.min_price_increment)
        write(io, record.display_factor)
        write(io, record.expiration)
        write(io, record.activation)
        write(io, record.high_limit_price)
        write(io, record.low_limit_price)
        write(io, record.max_price_variation)
        write(io, record.unit_of_measure_qty)
        write(io, record.min_price_increment_amount)
        write(io, record.price_ratio)
        write(io, record.inst_attrib_value)
        write(io, record.underlying_id)
        write(io, record.raw_instrument_id)  # Now UInt64 in v3
        write(io, record.market_depth_implied)
        write(io, record.market_depth)
        write(io, record.market_segment_id)
        write(io, record.max_trade_vol)
        write(io, record.min_lot_size)
        write(io, record.min_lot_size_block)
        write(io, record.min_lot_size_round_lot)
        write(io, record.min_trade_vol)
        write(io, record.contract_multiplier)
        write(io, record.decay_quantity)
        write(io, record.original_contract_size)
        write(io, record.appl_id)
        write(io, record.maturity_year)
        write(io, record.decay_start_date)
        write(io, record.channel_id)
        
        # Write fixed-length strings with null padding
        
        write_fixed_string(io, record.currency, 4)
        write_fixed_string(io, record.settl_currency, 4)
        write_fixed_string(io, record.secsubtype, 6)
        write_fixed_string(io, record.raw_symbol, 22)
        write_fixed_string(io, record.group, 21)
        write_fixed_string(io, record.exchange, 5)
        write_fixed_string(io, record.asset, 11)  # Expanded to 11 bytes in v3
        write_fixed_string(io, record.cfi, 7)
        write_fixed_string(io, record.security_type, 7)
        write_fixed_string(io, record.unit_of_measure, 31)
        write_fixed_string(io, record.underlying, 21)
        write_fixed_string(io, record.strike_price_currency, 4)
        
        write(io, UInt8(record.instrument_class))
        write(io, record.strike_price)
        write(io, record.match_algorithm)
        write(io, record.main_fraction)
        write(io, record.price_display_format)
        write(io, record.sub_fraction)
        write(io, record.underlying_product)
        write(io, record.security_update_action)
        write(io, record.maturity_month)
        write(io, record.maturity_day)
        write(io, record.maturity_week)
        write(io, record.user_defined_instrument)
        write(io, record.contract_multiplier_unit)
        write(io, record.flow_schedule_type)
        write(io, record.tick_rule)
        
        # Write new strategy leg fields in DBN v3
        write(io, record.leg_count)
        write(io, record.leg_index)
        write(io, record.leg_instrument_id)
        write_fixed_string(io, record.leg_raw_symbol, 22)
        write(io, UInt8(record.leg_side))
        write(io, record.leg_underlying_id)
        write(io, UInt8(record.leg_instrument_class))
        write(io, record.leg_ratio_qty_numerator)
        write(io, record.leg_ratio_qty_denominator)
        write(io, record.leg_ratio_price_numerator)
        write(io, record.leg_ratio_price_denominator)
        write(io, record.leg_price)
        write(io, record.leg_delta)
        write(io, zeros(UInt8, 8))  # Reserved for alignment
        
    elseif isa(record, ImbalanceMsg)
        write_record_header(io, record.hd)
        write(io, record.ts_recv)
        write(io, record.ref_price)
        write(io, record.auction_time)
        write(io, record.cont_book_clr_price)
        write(io, record.auct_interest_clr_price)
        write(io, record.ssr_filling_price)
        write(io, record.ind_match_price)
        write(io, record.upper_collar)
        write(io, record.lower_collar)
        write(io, record.paired_qty)
        write(io, record.total_imbalance_qty)
        write(io, record.market_imbalance_qty)
        write(io, record.unpaired_qty)
        write(io, record.auction_type)
        write(io, UInt8(record.side))
        write(io, record.auction_status)
        write(io, record.freeze_status)
        write(io, record.num_extensions)
        write(io, record.unpaired_side)
        write(io, record.significant_imbalance)
        write(io, zeros(UInt8, 1))  # Reserved
        
    elseif isa(record, StatMsg)
        write_record_header(io, record.hd)
        write(io, record.ts_recv)
        write(io, record.ts_ref)
        write(io, record.price)
        # Write quantity as UInt64, converting back if needed
        quantity_to_write = record.quantity == typemax(Int64) ? 0xffffffffffffffff : UInt64(record.quantity)
        write(io, quantity_to_write)
        write(io, record.sequence)
        write(io, record.ts_in_delta)
        write(io, record.stat_type)
        write(io, record.channel_id)
        write(io, record.update_action)
        write(io, record.stat_flags)
        write(io, zeros(UInt8, 18))  # Reserved (adjusted for field size changes)
        
    elseif isa(record, CMBP1Msg)
        write_record_header(io, record.hd)
        write(io, record.price)
        write(io, record.size)
        write(io, UInt8(record.action))
        write(io, UInt8(record.side))
        write(io, record.flags)
        write(io, record.depth)
        write(io, record.ts_recv)
        write(io, record.ts_in_delta)
        write(io, record.sequence)
        
        # Write level
        write(io, record.levels.bid_px)
        write(io, record.levels.ask_px)
        write(io, record.levels.bid_sz)
        write(io, record.levels.ask_sz)
        write(io, record.levels.bid_ct)
        write(io, record.levels.ask_ct)
        
    elseif isa(record, CBBO1sMsg)
        write_record_header(io, record.hd)
        write(io, record.price)
        write(io, record.size)
        write(io, UInt8(record.action))
        write(io, UInt8(record.side))
        write(io, record.flags)
        write(io, record.depth)
        write(io, record.ts_recv)
        write(io, record.ts_in_delta)
        write(io, record.sequence)
        
        # Write level
        write(io, record.levels.bid_px)
        write(io, record.levels.ask_px)
        write(io, record.levels.bid_sz)
        write(io, record.levels.ask_sz)
        write(io, record.levels.bid_ct)
        write(io, record.levels.ask_ct)
        
    elseif isa(record, CBBO1mMsg)
        write_record_header(io, record.hd)
        write(io, record.price)
        write(io, record.size)
        write(io, UInt8(record.action))
        write(io, UInt8(record.side))
        write(io, record.flags)
        write(io, record.depth)
        write(io, record.ts_recv)
        write(io, record.ts_in_delta)
        write(io, record.sequence)
        
        # Write level
        write(io, record.levels.bid_px)
        write(io, record.levels.ask_px)
        write(io, record.levels.bid_sz)
        write(io, record.levels.ask_sz)
        write(io, record.levels.bid_ct)
        write(io, record.levels.ask_ct)
        
    elseif isa(record, TCBBOMsg)
        write_record_header(io, record.hd)
        write(io, record.price)
        write(io, record.size)
        write(io, UInt8(record.action))
        write(io, UInt8(record.side))
        write(io, record.flags)
        write(io, record.depth)
        write(io, record.ts_recv)
        write(io, record.ts_in_delta)
        write(io, record.sequence)
        
        # Write level
        write(io, record.levels.bid_px)
        write(io, record.levels.ask_px)
        write(io, record.levels.bid_sz)
        write(io, record.levels.ask_sz)
        write(io, record.levels.bid_ct)
        write(io, record.levels.ask_ct)
        
    elseif isa(record, BBO1sMsg)
        write_record_header(io, record.hd)
        write(io, record.price)
        write(io, record.size)
        write(io, UInt8(record.action))
        write(io, UInt8(record.side))
        write(io, record.flags)
        write(io, record.depth)
        write(io, record.ts_recv)
        write(io, record.ts_in_delta)
        write(io, record.sequence)
        
        # Write level
        write(io, record.levels.bid_px)
        write(io, record.levels.ask_px)
        write(io, record.levels.bid_sz)
        write(io, record.levels.ask_sz)
        write(io, record.levels.bid_ct)
        write(io, record.levels.ask_ct)
        
    elseif isa(record, BBO1mMsg)
        write_record_header(io, record.hd)
        write(io, record.price)
        write(io, record.size)
        write(io, UInt8(record.action))
        write(io, UInt8(record.side))
        write(io, record.flags)
        write(io, record.depth)
        write(io, record.ts_recv)
        write(io, record.ts_in_delta)
        write(io, record.sequence)
        
        # Write level
        write(io, record.levels.bid_px)
        write(io, record.levels.ask_px)
        write(io, record.levels.bid_sz)
        write(io, record.levels.ask_sz)
        write(io, record.levels.bid_ct)
        write(io, record.levels.ask_ct)
        
    elseif isa(record, ErrorMsg)
        write_record_header(io, record.hd)
        # Write error message string with null terminator
        err_bytes = Vector{UInt8}(record.err)
        write(io, err_bytes)
        if length(err_bytes) == 0 || err_bytes[end] != 0
            write(io, UInt8(0))  # Null terminator
        end
        
    elseif isa(record, SymbolMappingMsg)
        write_record_header(io, record.hd)
        write(io, UInt8(record.stype_in))
        write(io, zeros(UInt8, 3))  # Padding
        
        # Write input symbol with length prefix
        stype_in_bytes = Vector{UInt8}(record.stype_in_symbol)
        write(io, htol(UInt16(length(stype_in_bytes))))
        write(io, stype_in_bytes)
        
        write(io, UInt8(record.stype_out))
        write(io, zeros(UInt8, 3))  # Padding
        
        # Write output symbol with length prefix
        stype_out_bytes = Vector{UInt8}(record.stype_out_symbol)
        write(io, htol(UInt16(length(stype_out_bytes))))
        write(io, stype_out_bytes)
        
        write(io, record.start_ts)
        write(io, record.end_ts)
        
    elseif isa(record, SystemMsg)
        write_record_header(io, record.hd)
        # Write message string
        msg_bytes = Vector{UInt8}(record.msg)
        write(io, msg_bytes)
        write(io, UInt8(0))  # Null terminator
        
        # Write code string  
        code_bytes = Vector{UInt8}(record.code)
        write(io, code_bytes)
        if length(code_bytes) == 0 || code_bytes[end] != 0
            write(io, UInt8(0))  # Null terminator
        end
    end
end

# Add finalize function for encoder
"""
    finalize_encoder(encoder::DBNEncoder)

Finalize the encoder and flush any remaining data.

# Arguments
- `encoder::DBNEncoder`: Encoder to finalize

# Details
Ensures all buffered data is written to the output stream.
Should be called when finished writing all records.
"""
function finalize_encoder(encoder::DBNEncoder)
    # For now, we don't use compression in write mode for simplicity
    # In the future, compression support could be added here
end

# Convenience function
"""
    write_dbn(filename::String, metadata::Metadata, records)

Convenience function to write a complete DBN file.

# Arguments
- `filename::String`: Output file path
- `metadata::Metadata`: File metadata
- `records`: Collection of records to write

# Details
Creates a complete DBN file with header and all records.
Automatically handles:
- File creation and management
- Header writing
- Record serialization
- Resource cleanup

# Example
```julia
metadata = Metadata(3, "TEST", Schema.TRADES, start_ts, end_ts, length(records), 
                   SType.RAW_SYMBOL, SType.RAW_SYMBOL, false, symbols, [], [], [])
write_dbn("output.dbn", metadata, records)
```
"""
function write_dbn(filename::String, metadata::Metadata, records)
    open(filename, "w") do f
        encoder = DBNEncoder(f, metadata)
        write_header(encoder)
        
        for record in records
            write_record(encoder, record)
        end
        
        finalize_encoder(encoder)
    end
end