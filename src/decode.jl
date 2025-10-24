# DBN decoding functionality

"""
    DBNDecoder

Decoder for reading DBN (Databento Binary Encoding) files with support for compression.

# Fields
- `io::IO`: Current IO stream (may be wrapped with compression)
- `base_io::IO`: Original IO stream before any compression wrapper
- `header::Union{DBNHeader,Nothing}`: Parsed DBN header information
- `metadata::Union{Metadata,Nothing}`: Parsed metadata information
- `upgrade_policy::UInt8`: Version upgrade policy
"""
mutable struct DBNDecoder
    io::IO
    base_io::IO  # Original IO before compression wrapper
    header::Union{DBNHeader,Nothing}
    metadata::Union{Metadata,Nothing}
    upgrade_policy::UInt8
end

"""
    DBNDecoder(io::IO)

Construct a DBNDecoder from an existing IO stream.

# Arguments
- `io::IO`: Input stream to read from

# Returns
- `DBNDecoder`: Decoder instance ready for reading
"""
DBNDecoder(io::IO) = DBNDecoder(io, io, nothing, nothing, 0)

"""
    DBNDecoder(filename::String)

Construct a DBNDecoder from a file, automatically detecting and handling compression.

# Arguments
- `filename::String`: Path to the DBN file (can be compressed with .zst extension)

# Returns
- `DBNDecoder`: Decoder instance with header already parsed

# Details
Automatically detects Zstd compression by checking magic bytes and file extension.
Reads and parses the DBN header during construction.
"""
function DBNDecoder(filename::String)
    base_io = open(filename, "r")
    
    # Check if the file is compressed by looking at magic bytes
    # Zstd magic number is 0xFD2FB528 (little-endian)
    mark_pos = position(base_io)
    magic_bytes = read(base_io, 4)
    seek(base_io, mark_pos)  # Reset to beginning
    
    is_zstd = false
    if length(magic_bytes) == 4
        # Check for Zstd magic number (0x28B52FFD in little-endian)
        is_zstd = magic_bytes == UInt8[0x28, 0xB5, 0x2F, 0xFD]
    end
    
    # Create appropriate IO stream
    if is_zstd || endswith(filename, ".zst")
        # Create a streaming decompressor
        io = TranscodingStream(ZstdDecompressor(), base_io)
    else
        io = base_io
    end
    
    decoder = DBNDecoder(io, base_io, nothing, nothing, 0)
    read_header!(decoder)
    return decoder
end

"""
    read_header!(decoder::DBNDecoder)

Read and parse the DBN file header, populating the decoder's metadata.

# Arguments
- `decoder::DBNDecoder`: Decoder instance to populate

# Details
Reads the magic bytes, version, and metadata section of a DBN file.
Populates the decoder's `metadata` field with parsed information including:
- Dataset identifier
- Schema type
- Time range
- Symbol information
- Mappings

# Throws
- `ErrorException`: If magic bytes are invalid or version is unsupported
"""
function read_header!(decoder::DBNDecoder)
    # Read magic bytes "DBN"
    magic = read(decoder.io, 3)
    if magic != b"DBN"
        error("Invalid DBN file: wrong magic bytes")
    end
    
    # Read version
    version = read(decoder.io, UInt8)
    if version > DBN_VERSION
        error("Unsupported DBN version: $version (decoder supports up to $DBN_VERSION)")
    end
    
    # Read metadata length (4 bytes)
    metadata_length = read(decoder.io, UInt32)
    
    # Read the entire metadata block
    metadata_start_pos = position(decoder.io)
    metadata_bytes = read(decoder.io, metadata_length)
    metadata_io = IOBuffer(metadata_bytes)
    
    # Parse metadata fields from the buffer
    pos = 1
    
    # Dataset (16 bytes fixed-length C string)
    dataset_bytes = metadata_bytes[pos:pos+15]
    pos += 16
    # Remove null terminator bytes
    dataset = String(dataset_bytes[1:findfirst(==(0), dataset_bytes)-1])
    
    # Schema (2 bytes)
    schema_val = ltoh(reinterpret(UInt16, metadata_bytes[pos:pos+1])[1])
    pos += 2
    schema = schema_val == 0xFFFF ? Schema.MIX : Schema.T(schema_val)
    
    # Start timestamp (8 bytes)
    start_ts_raw = ltoh(reinterpret(UInt64, metadata_bytes[pos:pos+7])[1])
    pos += 8
    start_ts = start_ts_raw <= typemax(Int64) ? Int64(start_ts_raw) : 0
    
    # End timestamp (8 bytes) 
    end_ts_raw = ltoh(reinterpret(UInt64, metadata_bytes[pos:pos+7])[1])
    pos += 8
    end_ts = if end_ts_raw == 0 || end_ts_raw == 0xffffffffffffffff
        nothing
    else
        # Safe conversion - check if it fits in Int64
        end_ts_raw <= typemax(Int64) ? Int64(end_ts_raw) : nothing
    end
    
    # Limit (8 bytes)
    limit_raw = ltoh(reinterpret(UInt64, metadata_bytes[pos:pos+7])[1])
    pos += 8
    limit = limit_raw == 0 ? nothing : limit_raw
    
    # For version 1, skip record_count (8 bytes)
    if version == 1
        pos += 8
    end
    
    # SType in (1 byte)
    stype_in_val = metadata_bytes[pos]
    pos += 1
    stype_in = stype_in_val == 0xFF ? nothing : SType.T(stype_in_val)
    
    # SType out (1 byte)
    stype_out = SType.T(metadata_bytes[pos])
    pos += 1
    
    # TS out (1 byte boolean)
    ts_out = metadata_bytes[pos] != 0
    pos += 1
    
    # Symbol string length (2 bytes, only for version > 1)
    symbol_cstr_len = if version == 1
        22  # v1::SYMBOL_CSTR_LEN
    else
        len = ltoh(reinterpret(UInt16, metadata_bytes[pos:pos+1])[1])
        pos += 2
        len
    end
    
    # Skip reserved padding
    reserved_len = if version == 1
        39  # v1::METADATA_RESERVED_LEN
    else
        53  # METADATA_RESERVED_LEN
    end
    pos += reserved_len
    
    # Schema definition length (4 bytes) - always 0 for now
    schema_def_len = ltoh(reinterpret(UInt32, metadata_bytes[pos:pos+3])[1])
    pos += 4
    if schema_def_len != 0
        error("Schema definitions not supported yet")
    end
    
    # Read variable-length sections
    
    # Symbols
    symbols_count = ltoh(reinterpret(UInt32, metadata_bytes[pos:pos+3])[1])
    pos += 4
    symbols = String[]
    for _ in 1:symbols_count
        symbol_bytes = metadata_bytes[pos:pos+symbol_cstr_len-1]
        pos += symbol_cstr_len
        # Remove null terminator
        null_pos = findfirst(==(0), symbol_bytes)
        if null_pos !== nothing
            symbol = String(symbol_bytes[1:null_pos-1])
        else
            symbol = String(symbol_bytes)
        end
        push!(symbols, symbol)
    end
    
    # Partial symbols
    partial_count = ltoh(reinterpret(UInt32, metadata_bytes[pos:pos+3])[1])
    pos += 4
    partial = String[]
    for _ in 1:partial_count
        symbol_bytes = metadata_bytes[pos:pos+symbol_cstr_len-1]
        pos += symbol_cstr_len
        null_pos = findfirst(==(0), symbol_bytes)
        if null_pos !== nothing
            symbol = String(symbol_bytes[1:null_pos-1])
        else
            symbol = String(symbol_bytes)
        end
        push!(partial, symbol)
    end
    
    # Not found symbols
    not_found_count = ltoh(reinterpret(UInt32, metadata_bytes[pos:pos+3])[1])
    pos += 4
    not_found = String[]
    for _ in 1:not_found_count
        symbol_bytes = metadata_bytes[pos:pos+symbol_cstr_len-1]
        pos += symbol_cstr_len
        null_pos = findfirst(==(0), symbol_bytes)
        if null_pos !== nothing
            symbol = String(symbol_bytes[1:null_pos-1])
        else
            symbol = String(symbol_bytes)
        end
        push!(not_found, symbol)
    end
    
    # Symbol mappings
    mappings_count = ltoh(reinterpret(UInt32, metadata_bytes[pos:pos+3])[1])
    pos += 4
    mappings = Tuple{String,String,Int64,Int64}[]
    for _ in 1:mappings_count
        # Raw symbol
        raw_symbol_bytes = metadata_bytes[pos:pos+symbol_cstr_len-1]
        pos += symbol_cstr_len
        null_pos = findfirst(==(0), raw_symbol_bytes)
        if null_pos !== nothing
            raw_symbol = String(raw_symbol_bytes[1:null_pos-1])
        else
            raw_symbol = String(raw_symbol_bytes)
        end
        
        # Intervals count
        intervals_count = ltoh(reinterpret(UInt32, metadata_bytes[pos:pos+3])[1])
        pos += 4
        
        # For now, just read the first interval (simplified)
        if intervals_count > 0
            # Start date (4 bytes)
            start_date_raw = ltoh(reinterpret(UInt32, metadata_bytes[pos:pos+3])[1])
            pos += 4
            
            # End date (4 bytes)
            end_date_raw = ltoh(reinterpret(UInt32, metadata_bytes[pos:pos+3])[1])
            pos += 4
            
            # Mapped symbol
            mapped_symbol_bytes = metadata_bytes[pos:pos+symbol_cstr_len-1]
            pos += symbol_cstr_len
            null_pos = findfirst(==(0), mapped_symbol_bytes)
            if null_pos !== nothing
                mapped_symbol = String(mapped_symbol_bytes[1:null_pos-1])
            else
                mapped_symbol = String(mapped_symbol_bytes)
            end
            
            push!(mappings, (raw_symbol, mapped_symbol, Int64(start_date_raw), Int64(end_date_raw)))
            
            # Skip remaining intervals for now
            for _ in 2:intervals_count
                pos += 4 + 4 + symbol_cstr_len  # start_date + end_date + symbol
            end
        end
    end
    
    decoder.metadata = Metadata(
        version, dataset, schema, start_ts, end_ts, limit,
        stype_in, stype_out, ts_out,
        symbols, partial, not_found, mappings
    )
    
    # Convert timestamps for DatasetCondition, handling nothing values
    condition_start_ts = start_ts
    condition_end_ts = end_ts === nothing ? 0 : end_ts
    condition_limit = limit === nothing ? 0 : limit
    
    decoder.header = DBNHeader(
        VersionUpgradePolicy(decoder.upgrade_policy),
        DatasetCondition(0, condition_start_ts, condition_end_ts, condition_limit),
        decoder.metadata
    )
    
    # For streaming compatibility, skip remaining metadata bytes instead of seeking
    # We've already read metadata_length bytes into metadata_bytes
    # No need to do anything - we're already at the right position
end

"""
    read_record_header(io::IO)

Read a record header from the IO stream.

# Arguments
- `io::IO`: Input stream positioned at the start of a record header

# Returns
- `RecordHeader`: Parsed record header, or
- `Tuple`: (nothing, raw_rtype, length) for unknown record types

# Details
Reads the standard DBN record header fields:
- Record length
- Record type
- Publisher ID
- Instrument ID  
- Event timestamp

Gracefully handles unknown record types by returning a tuple instead of throwing an error.
"""
function read_record_header(io::IO)
    record_length_units = read(io, UInt8)
    rtype_raw = read(io, UInt8)
    
    # Handle unknown record types first, before trying to read more data
    rtype = try
        RType.T(rtype_raw)
    catch ArgumentError
        # Return special marker for unknown types - don't read more data
        return nothing, rtype_raw, record_length_units
    end
    
    # Always read the standard header fields
    publisher_id = read(io, UInt16)
    instrument_id = read(io, UInt32)
    ts_event = read(io, Int64)
    
    # Store the raw length units value (not converted to bytes)
    RecordHeader(record_length_units, rtype, publisher_id, instrument_id, ts_event)
end

"""
    read_record(decoder::DBNDecoder)

Read a complete record from the DBN stream.

# Arguments
- `decoder::DBNDecoder`: Decoder instance to read from

# Returns
- Record instance (MBOMsg, TradeMsg, etc.): Parsed record, or
- `nothing`: If EOF reached or unknown record type encountered

# Details
Reads the record header and then the appropriate record body based on the record type.
Supports all DBN v3 record types including:
- Market data (MBO, MBP, Trade, OHLCV)
- Status and system messages
- Instrument definitions
- Error and mapping messages

Unknown record types are skipped gracefully.
"""
function read_record(decoder::DBNDecoder)
    if eof(decoder.io)
        return nothing
    end
    
    hd_result = read_record_header(decoder.io)
    
    # Handle unknown record types
    if hd_result isa Tuple
        # Unknown record type - skip it
        _, rtype_raw, record_length = hd_result
        skip(decoder.io, record_length - 2)  # Already read length(1) + rtype(1) = 2 bytes
        return nothing
    end
    
    hd = hd_result
    
    if hd.rtype == RType.MBO_MSG
        # For MBO records, we need to read exactly 56 bytes total
        # We've already read: length(1) + rtype(1) + publisher_id(2) + instrument_id(4) + ts_event(8) = 16 bytes
        # Remaining to read: 56 - 16 = 40 bytes
        
        # Based on Rust struct order and empirical evidence:
        ts_recv = read(decoder.io, Int64)      # 8 bytes (positions 16-23)
        order_id = read(decoder.io, UInt64)    # 8 bytes (positions 24-31)
        size = read(decoder.io, UInt32)        # 4 bytes (positions 32-35)
        flags = read(decoder.io, UInt8)        # 1 byte (position 36)
        channel_id = read(decoder.io, UInt8)   # 1 byte (position 37)
        action = safe_action(read(decoder.io, UInt8))   # 1 byte (position 38)
        side = safe_side(read(decoder.io, UInt8))       # 1 byte (position 39)
        price = read(decoder.io, Int64)        # 8 bytes (positions 40-47)
        ts_in_delta = read(decoder.io, Int32)  # 4 bytes (positions 48-51)
        sequence = read(decoder.io, UInt32)    # 4 bytes (positions 52-55)
        
        return MBOMsg(hd, order_id, price, size, flags, channel_id, action, side, ts_recv, ts_in_delta, sequence)
        
    elseif hd.rtype == RType.MBP_0_MSG
        price = read(decoder.io, Int64)
        size = read(decoder.io, UInt32)
        action = safe_action(read(decoder.io, UInt8))
        side = safe_side(read(decoder.io, UInt8))
        flags = read(decoder.io, UInt8)
        depth = read(decoder.io, UInt8)
        ts_recv = read(decoder.io, Int64)
        ts_in_delta = read(decoder.io, Int32)
        sequence = read(decoder.io, UInt32)
        return TradeMsg(hd, price, size, action, side, flags, depth, ts_recv, ts_in_delta, sequence)
        
    elseif hd.rtype == RType.MBP_1_MSG
        price = read(decoder.io, Int64)
        size = read(decoder.io, UInt32)
        action = safe_action(read(decoder.io, UInt8))
        side = safe_side(read(decoder.io, UInt8))
        flags = read(decoder.io, UInt8)
        depth = read(decoder.io, UInt8)
        ts_recv = read(decoder.io, Int64)
        ts_in_delta = read(decoder.io, Int32)
        sequence = read(decoder.io, UInt32)
        
        bid_px = read(decoder.io, Int64)
        ask_px = read(decoder.io, Int64)
        bid_sz = read(decoder.io, UInt32)
        ask_sz = read(decoder.io, UInt32)
        bid_ct = read(decoder.io, UInt32)
        ask_ct = read(decoder.io, UInt32)
        levels = BidAskPair(bid_px, ask_px, bid_sz, ask_sz, bid_ct, ask_ct)
        
        return MBP1Msg(hd, price, size, action, side, flags, depth, ts_recv, ts_in_delta, sequence, levels)
        
    elseif hd.rtype == RType.MBP_10_MSG
        price = read(decoder.io, Int64)
        size = read(decoder.io, UInt32)
        action = safe_action(read(decoder.io, UInt8))
        side = safe_side(read(decoder.io, UInt8))
        flags = read(decoder.io, UInt8)
        depth = read(decoder.io, UInt8)
        ts_recv = read(decoder.io, Int64)
        ts_in_delta = read(decoder.io, Int32)
        sequence = read(decoder.io, UInt32)
        
        levels = ntuple(10) do _
            bid_px = read(decoder.io, Int64)
            ask_px = read(decoder.io, Int64)
            bid_sz = read(decoder.io, UInt32)
            ask_sz = read(decoder.io, UInt32)
            bid_ct = read(decoder.io, UInt32)
            ask_ct = read(decoder.io, UInt32)
            BidAskPair(bid_px, ask_px, bid_sz, ask_sz, bid_ct, ask_ct)
        end
        
        return MBP10Msg(hd, price, size, action, side, flags, depth, ts_recv, ts_in_delta, sequence, levels)
        
    elseif hd.rtype in [RType.OHLCV_1S_MSG, RType.OHLCV_1M_MSG, RType.OHLCV_1H_MSG, RType.OHLCV_1D_MSG]
        open = read(decoder.io, Int64)
        high = read(decoder.io, Int64)
        low = read(decoder.io, Int64)
        close = read(decoder.io, Int64)
        volume = read(decoder.io, UInt64)
        return OHLCVMsg(hd, open, high, low, close, volume)
        
    elseif hd.rtype == RType.STATUS_MSG
        ts_recv = read(decoder.io, UInt64)
        action = read(decoder.io, UInt16)
        reason = read(decoder.io, UInt16)
        trading_event = read(decoder.io, UInt16)
        is_trading = read(decoder.io, UInt8)
        is_quoting = read(decoder.io, UInt8)
        is_short_sell_restricted = read(decoder.io, UInt8)
        _ = read(decoder.io, 7)  # Reserved (was 5, now 7 to align to 40 bytes total)
        return StatusMsg(hd, ts_recv, action, reason, trading_event, is_trading, is_quoting, is_short_sell_restricted)
        
    elseif hd.rtype == RType.INSTRUMENT_DEF_MSG
        # Track position to ensure we read exactly the right amount
        start_pos = position(decoder.io)
        record_size_bytes = hd.length * LENGTH_MULTIPLIER
        body_size = record_size_bytes - 16  # Subtract header size

        # Determine raw_symbol length based on DBN version from metadata
        # Different DBN versions have different string field sizes
        # v2: raw_symbol=19 bytes, total body=384 bytes
        # v3: raw_symbol=22 bytes, total body=387+ bytes
        file_version = decoder.metadata !== nothing ? decoder.metadata.version : 3
        raw_symbol_len = if file_version == 2
            19  # v2 format (smaller raw_symbol)
        else
            22  # v3 format (default, larger raw_symbol)
        end

        # Read fields following Rust #[repr(C)] struct declaration order
        # All 8-byte fields first (15 fields = 120 bytes)
        ts_recv = read(decoder.io, Int64)
        min_price_increment = read(decoder.io, Int64)
        display_factor = read(decoder.io, Int64)
        expiration = read(decoder.io, Int64)
        activation = read(decoder.io, Int64)
        high_limit_price = read(decoder.io, Int64)
        low_limit_price = read(decoder.io, Int64)
        max_price_variation = read(decoder.io, Int64)
        unit_of_measure_qty = read(decoder.io, Int64)
        min_price_increment_amount = read(decoder.io, Int64)
        price_ratio = read(decoder.io, Int64)
        strike_price = read(decoder.io, Int64)
        raw_instrument_id = read(decoder.io, UInt64)
        leg_price = read(decoder.io, Int64)
        leg_delta = read(decoder.io, Int64)

        # All 4-byte fields (19 fields = 76 bytes, total 196)
        inst_attrib_value = read(decoder.io, Int32)
        underlying_id = read(decoder.io, UInt32)
        market_depth_implied = read(decoder.io, Int32)
        market_depth = read(decoder.io, Int32)
        market_segment_id = read(decoder.io, UInt32)
        max_trade_vol = read(decoder.io, UInt32)
        min_lot_size = read(decoder.io, Int32)
        min_lot_size_block = read(decoder.io, Int32)
        min_lot_size_round_lot = read(decoder.io, Int32)
        min_trade_vol = read(decoder.io, UInt32)
        contract_multiplier = read(decoder.io, Int32)
        decay_quantity = read(decoder.io, Int32)
        original_contract_size = read(decoder.io, Int32)
        leg_instrument_id = read(decoder.io, UInt32)
        leg_ratio_price_numerator = read(decoder.io, UInt32)
        leg_ratio_price_denominator = read(decoder.io, UInt32)
        leg_ratio_qty_numerator = read(decoder.io, UInt32)
        leg_ratio_qty_denominator = read(decoder.io, UInt32)
        leg_underlying_id = read(decoder.io, UInt32)

        # All 2-byte fields (6 fields = 12 bytes, total 208)
        appl_id = read(decoder.io, Int16)
        maturity_year = read(decoder.io, UInt16)
        decay_start_date = read(decoder.io, UInt16)
        channel_id = read(decoder.io, UInt16)
        leg_count = read(decoder.io, UInt16)
        leg_index = read(decoder.io, UInt16)

        # All string fields - using version-specific raw_symbol length
        currency = String(strip(String(read(decoder.io, 4)), '\0'))
        settl_currency = String(strip(String(read(decoder.io, 4)), '\0'))
        secsubtype = String(strip(String(read(decoder.io, 6)), '\0'))
        raw_symbol = String(strip(String(read(decoder.io, raw_symbol_len)), '\0'))
        group = String(strip(String(read(decoder.io, 21)), '\0'))
        exchange = String(strip(String(read(decoder.io, 5)), '\0'))
        asset = String(strip(String(read(decoder.io, 11)), '\0'))
        cfi = String(strip(String(read(decoder.io, 7)), '\0'))
        security_type = String(strip(String(read(decoder.io, 7)), '\0'))
        unit_of_measure = String(strip(String(read(decoder.io, 31)), '\0'))
        underlying = String(strip(String(read(decoder.io, 21)), '\0'))
        strike_price_currency = String(strip(String(read(decoder.io, 4)), '\0'))
        leg_raw_symbol = String(strip(String(read(decoder.io, 20)), '\0'))

        # All single-byte fields (16 fields = 16 bytes, total 384)
        instrument_class_byte = read(decoder.io, UInt8)
        instrument_class = safe_instrument_class(instrument_class_byte)
        match_algorithm_byte = read(decoder.io, UInt8)
        match_algorithm = match_algorithm_byte == 0 ? '\0' : Char(match_algorithm_byte)
        main_fraction = read(decoder.io, UInt8)
        price_display_format = read(decoder.io, UInt8)
        sub_fraction = read(decoder.io, UInt8)
        underlying_product = read(decoder.io, UInt8)
        security_update_action_byte = read(decoder.io, UInt8)
        security_update_action = security_update_action_byte == 0 ? '\0' : Char(security_update_action_byte)
        maturity_month = read(decoder.io, UInt8)
        maturity_day = read(decoder.io, UInt8)
        maturity_week = read(decoder.io, UInt8)
        user_defined_instrument_byte = read(decoder.io, UInt8)
        user_defined_instrument = user_defined_instrument_byte != 0x00 && user_defined_instrument_byte != UInt8('N')
        contract_multiplier_unit = read(decoder.io, Int8)
        flow_schedule_type = read(decoder.io, Int8)
        tick_rule = read(decoder.io, UInt8)
        leg_instrument_class_byte = read(decoder.io, UInt8)
        leg_instrument_class = safe_instrument_class(leg_instrument_class_byte)
        leg_side_byte = read(decoder.io, UInt8)
        leg_side = safe_side(leg_side_byte)

        # Verify we read exactly the right amount
        bytes_read = position(decoder.io) - start_pos
        if bytes_read < body_size
            # Skip any remaining bytes (like _reserved padding in some versions)
            skip(decoder.io, body_size - bytes_read)
        elseif bytes_read > body_size
            error("InstrumentDefMsg: Read $bytes_read bytes but expected $body_size (over by $(bytes_read - body_size))")
        end

        return InstrumentDefMsg(
            hd, ts_recv, min_price_increment, display_factor, expiration, activation,
            high_limit_price, low_limit_price, max_price_variation,
            unit_of_measure_qty, min_price_increment_amount, price_ratio, inst_attrib_value,
            underlying_id, raw_instrument_id, market_depth_implied, market_depth,
            market_segment_id, max_trade_vol, min_lot_size, min_lot_size_block,
            min_lot_size_round_lot, min_trade_vol, contract_multiplier, decay_quantity,
            original_contract_size, appl_id, maturity_year,
            decay_start_date, channel_id, currency, settl_currency, secsubtype,
            raw_symbol, group, exchange, asset, cfi, security_type, unit_of_measure,
            underlying, strike_price_currency, instrument_class, strike_price,
            match_algorithm, main_fraction, price_display_format,
            sub_fraction, underlying_product, security_update_action,
            maturity_month, maturity_day, maturity_week, user_defined_instrument,
            contract_multiplier_unit, flow_schedule_type, tick_rule,
            leg_count, leg_index, leg_instrument_id, leg_raw_symbol, leg_side,
            leg_underlying_id, leg_instrument_class, leg_ratio_qty_numerator,
            leg_ratio_qty_denominator, leg_ratio_price_numerator, leg_ratio_price_denominator,
            leg_price, leg_delta
        )

    elseif hd.rtype == RType.IMBALANCE_MSG
        ts_recv = read(decoder.io, UInt64)
        ref_price = read(decoder.io, Int64)
        auction_time = read(decoder.io, UInt64)
        cont_book_clr_price = read(decoder.io, Int64)
        auct_interest_clr_price = read(decoder.io, Int64)
        ssr_filling_price = read(decoder.io, Int64)
        ind_match_price = read(decoder.io, Int64)
        upper_collar = read(decoder.io, Int64)
        lower_collar = read(decoder.io, Int64)
        paired_qty = read(decoder.io, UInt32)
        total_imbalance_qty = read(decoder.io, UInt32)
        market_imbalance_qty = read(decoder.io, UInt32)
        unpaired_qty = read(decoder.io, UInt32)
        auction_type = read(decoder.io, UInt8)
        side = safe_side(read(decoder.io, UInt8))
        auction_status = read(decoder.io, UInt8)
        freeze_status = read(decoder.io, UInt8)
        num_extensions = read(decoder.io, UInt8)
        unpaired_side = read(decoder.io, UInt8)
        significant_imbalance = read(decoder.io, UInt8)
        _ = read(decoder.io, 1)  # Reserved
        return ImbalanceMsg(hd, ts_recv, ref_price, auction_time, cont_book_clr_price, auct_interest_clr_price, ssr_filling_price, ind_match_price, upper_collar, lower_collar, paired_qty, total_imbalance_qty, market_imbalance_qty, unpaired_qty, auction_type, side, auction_status, freeze_status, num_extensions, unpaired_side, significant_imbalance)
        
    elseif hd.rtype == RType.STAT_MSG
        ts_recv = read(decoder.io, UInt64)
        ts_ref = read(decoder.io, UInt64) 
        price = read(decoder.io, Int64)
        # Handle UNDEF values in quantity field - read as UInt64 first
        quantity_raw = read(decoder.io, UInt64)
        quantity = if quantity_raw == 0xffffffffffffffff
            # UNDEF_STAT_QUANTITY - use a special value or convert safely
            typemax(Int64)  
        else
            # Safe conversion for normal values
            quantity_raw <= typemax(Int64) ? Int64(quantity_raw) : typemax(Int64)
        end
        sequence = read(decoder.io, UInt32)
        ts_in_delta = read(decoder.io, Int32)
        stat_type = read(decoder.io, UInt16)
        channel_id = read(decoder.io, UInt16)
        update_action = read(decoder.io, UInt8)
        stat_flags = read(decoder.io, UInt8)
        _ = read(decoder.io, 18)  # Reserved (adjusted for field size changes)
        return StatMsg(hd, ts_recv, ts_ref, price, quantity, sequence, ts_in_delta, stat_type, channel_id, update_action, stat_flags)
        
    elseif hd.rtype == RType.ERROR_MSG
        # Read error message string
        msg_bytes = hd.length - 16  # Subtract header size
        if msg_bytes > 0
            err_data = read(decoder.io, msg_bytes)
            # Remove null terminator if present
            null_pos = findfirst(==(0), err_data)
            if null_pos !== nothing
                err_string = String(err_data[1:null_pos-1])
            else
                err_string = String(err_data)
            end
        else
            err_string = ""
        end
        return ErrorMsg(hd, err_string)
        
    elseif hd.rtype == RType.SYMBOL_MAPPING_MSG
        # Read symbol mapping fields
        stype_in = SType.T(read(decoder.io, UInt8))
        _ = read(decoder.io, 3)  # Padding
        
        # Read input symbol (variable length string)
        stype_in_len = read(decoder.io, UInt16)
        stype_in_symbol = String(read(decoder.io, stype_in_len))
        
        stype_out = SType.T(read(decoder.io, UInt8))
        _ = read(decoder.io, 3)  # Padding
        
        # Read output symbol (variable length string)
        stype_out_len = read(decoder.io, UInt16)
        stype_out_symbol = String(read(decoder.io, stype_out_len))
        
        start_ts = read(decoder.io, Int64)
        end_ts = read(decoder.io, Int64)
        
        return SymbolMappingMsg(hd, stype_in, stype_in_symbol, stype_out, stype_out_symbol, start_ts, end_ts)
        
    elseif hd.rtype == RType.SYSTEM_MSG
        # Read system message fields
        remaining_bytes = hd.length - 16
        if remaining_bytes > 0
            # Split remaining data into msg and code (format TBD)
            # For now, read as single message string
            msg_data = read(decoder.io, remaining_bytes)
            null_pos = findfirst(==(0), msg_data)
            if null_pos !== nothing
                msg_string = String(msg_data[1:null_pos-1])
                # If there's more data after null, treat as code
                if null_pos < length(msg_data)
                    code_data = msg_data[null_pos+1:end]
                    code_null = findfirst(==(0), code_data)
                    if code_null !== nothing
                        code_string = String(code_data[1:code_null-1])
                    else
                        code_string = String(code_data)
                    end
                else
                    code_string = ""
                end
            else
                msg_string = String(msg_data)
                code_string = ""
            end
        else
            msg_string = ""
            code_string = ""
        end
        return SystemMsg(hd, msg_string, code_string)
        
    elseif hd.rtype == RType.CMBP_1_MSG
        price = read(decoder.io, Int64)
        size = read(decoder.io, UInt32)
        action = safe_action(read(decoder.io, UInt8))
        side = safe_side(read(decoder.io, UInt8))
        flags = read(decoder.io, UInt8)
        depth = read(decoder.io, UInt8)
        ts_recv = read(decoder.io, Int64)
        ts_in_delta = read(decoder.io, Int32)
        sequence = read(decoder.io, UInt32)
        
        bid_px = read(decoder.io, Int64)
        ask_px = read(decoder.io, Int64)
        bid_sz = read(decoder.io, UInt32)
        ask_sz = read(decoder.io, UInt32)
        bid_ct = read(decoder.io, UInt32)
        ask_ct = read(decoder.io, UInt32)
        levels = BidAskPair(bid_px, ask_px, bid_sz, ask_sz, bid_ct, ask_ct)
        
        return CMBP1Msg(hd, price, size, action, side, flags, depth, ts_recv, ts_in_delta, sequence, levels)
        
    elseif hd.rtype == RType.CBBO_1S_MSG
        price = read(decoder.io, Int64)
        size = read(decoder.io, UInt32)
        action = safe_action(read(decoder.io, UInt8))
        side = safe_side(read(decoder.io, UInt8))
        flags = read(decoder.io, UInt8)
        depth = read(decoder.io, UInt8)
        ts_recv = read(decoder.io, Int64)
        ts_in_delta = read(decoder.io, Int32)
        sequence = read(decoder.io, UInt32)
        
        bid_px = read(decoder.io, Int64)
        ask_px = read(decoder.io, Int64)
        bid_sz = read(decoder.io, UInt32)
        ask_sz = read(decoder.io, UInt32)
        bid_ct = read(decoder.io, UInt32)
        ask_ct = read(decoder.io, UInt32)
        levels = BidAskPair(bid_px, ask_px, bid_sz, ask_sz, bid_ct, ask_ct)
        
        return CBBO1sMsg(hd, price, size, action, side, flags, depth, ts_recv, ts_in_delta, sequence, levels)
        
    elseif hd.rtype == RType.CBBO_1M_MSG
        price = read(decoder.io, Int64)
        size = read(decoder.io, UInt32)
        action = safe_action(read(decoder.io, UInt8))
        side = safe_side(read(decoder.io, UInt8))
        flags = read(decoder.io, UInt8)
        depth = read(decoder.io, UInt8)
        ts_recv = read(decoder.io, Int64)
        ts_in_delta = read(decoder.io, Int32)
        sequence = read(decoder.io, UInt32)
        
        bid_px = read(decoder.io, Int64)
        ask_px = read(decoder.io, Int64)
        bid_sz = read(decoder.io, UInt32)
        ask_sz = read(decoder.io, UInt32)
        bid_ct = read(decoder.io, UInt32)
        ask_ct = read(decoder.io, UInt32)
        levels = BidAskPair(bid_px, ask_px, bid_sz, ask_sz, bid_ct, ask_ct)
        
        return CBBO1mMsg(hd, price, size, action, side, flags, depth, ts_recv, ts_in_delta, sequence, levels)
        
    elseif hd.rtype == RType.TCBBO_MSG
        price = read(decoder.io, Int64)
        size = read(decoder.io, UInt32)
        action = safe_action(read(decoder.io, UInt8))
        side = safe_side(read(decoder.io, UInt8))
        flags = read(decoder.io, UInt8)
        depth = read(decoder.io, UInt8)
        ts_recv = read(decoder.io, Int64)
        ts_in_delta = read(decoder.io, Int32)
        sequence = read(decoder.io, UInt32)
        
        bid_px = read(decoder.io, Int64)
        ask_px = read(decoder.io, Int64)
        bid_sz = read(decoder.io, UInt32)
        ask_sz = read(decoder.io, UInt32)
        bid_ct = read(decoder.io, UInt32)
        ask_ct = read(decoder.io, UInt32)
        levels = BidAskPair(bid_px, ask_px, bid_sz, ask_sz, bid_ct, ask_ct)
        
        return TCBBOMsg(hd, price, size, action, side, flags, depth, ts_recv, ts_in_delta, sequence, levels)
        
    elseif hd.rtype == RType.BBO_1S_MSG
        price = read(decoder.io, Int64)
        size = read(decoder.io, UInt32)
        action = safe_action(read(decoder.io, UInt8))
        side = safe_side(read(decoder.io, UInt8))
        flags = read(decoder.io, UInt8)
        depth = read(decoder.io, UInt8)
        ts_recv = read(decoder.io, Int64)
        ts_in_delta = read(decoder.io, Int32)
        sequence = read(decoder.io, UInt32)
        
        bid_px = read(decoder.io, Int64)
        ask_px = read(decoder.io, Int64)
        bid_sz = read(decoder.io, UInt32)
        ask_sz = read(decoder.io, UInt32)
        bid_ct = read(decoder.io, UInt32)
        ask_ct = read(decoder.io, UInt32)
        levels = BidAskPair(bid_px, ask_px, bid_sz, ask_sz, bid_ct, ask_ct)
        
        return BBO1sMsg(hd, price, size, action, side, flags, depth, ts_recv, ts_in_delta, sequence, levels)
        
    elseif hd.rtype == RType.BBO_1M_MSG
        price = read(decoder.io, Int64)
        size = read(decoder.io, UInt32)
        action = safe_action(read(decoder.io, UInt8))
        side = safe_side(read(decoder.io, UInt8))
        flags = read(decoder.io, UInt8)
        depth = read(decoder.io, UInt8)
        ts_recv = read(decoder.io, Int64)
        ts_in_delta = read(decoder.io, Int32)
        sequence = read(decoder.io, UInt32)
        
        bid_px = read(decoder.io, Int64)
        ask_px = read(decoder.io, Int64)
        bid_sz = read(decoder.io, UInt32)
        ask_sz = read(decoder.io, UInt32)
        bid_ct = read(decoder.io, UInt32)
        ask_ct = read(decoder.io, UInt32)
        levels = BidAskPair(bid_px, ask_px, bid_sz, ask_sz, bid_ct, ask_ct)
        
        return BBO1mMsg(hd, price, size, action, side, flags, depth, ts_recv, ts_in_delta, sequence, levels)
        
    else
        # Skip unknown record types
        skip(decoder.io, hd.length - 16)  # 16 bytes for record header
        return nothing
    end
end

# Convenience function
"""
    read_dbn(filename::String)

Convenience function to read all records from a DBN file.

# Arguments
- `filename::String`: Path to the DBN file (compressed or uncompressed)

# Returns
- `Vector`: Array containing all records from the file

# Details
Reads the entire DBN file into memory, automatically handling:
- Compression detection and decompression
- Resource cleanup
- Error recovery for unknown record types

For large files, consider using `DBNStream` for memory-efficient streaming.
For metadata access, use `read_dbn_with_metadata()`.

# Example
```julia
records = read_dbn("data.dbn")
for record in records
    println(typeof(record))
end
```
"""
function read_dbn(filename::String)
    records = []
    decoder = DBNDecoder(filename)  # This now handles compression automatically
    
    try
        while !eof(decoder.io)
            record = read_record(decoder)
            if record !== nothing
                push!(records, record)
            end
        end
    finally
        # Clean up resources
        if decoder.io !== decoder.base_io
            # Close the TranscodingStream first
            close(decoder.io)
        end
        # Always close the base IO
        if isa(decoder.base_io, IOStream)
            close(decoder.base_io)
        end
        # Force garbage collection to ensure file handles are released on Windows
        # Windows may not immediately release file locks even after close()
        GC.gc()
    end

    return records
end

"""
    read_dbn_with_metadata(filename::String)

Read a DBN file and return both metadata and records.

# Arguments
- `filename::String`: Path to the DBN file (compressed or uncompressed)

# Returns
- `Tuple{Metadata, Vector}`: A tuple containing the file metadata and array of all records

# Details
Similar to `read_dbn()` but also returns the file metadata containing dataset information,
schema, timestamp ranges, symbol mappings, and other file properties.

# Example
```julia
metadata, records = read_dbn_with_metadata("data.dbn")
println("Dataset: \$(metadata.dataset)")
println("Schema: \$(metadata.schema)")
println("Records: \$(length(records))")
```
"""
function read_dbn_with_metadata(filename::String)
    records = []
    decoder = DBNDecoder(filename)  # This now handles compression automatically

    try
        while !eof(decoder.io)
            record = read_record(decoder)
            if record !== nothing
                push!(records, record)
            end
        end
    finally
        # Clean up resources
        if decoder.io !== decoder.base_io
            # Close the TranscodingStream first
            close(decoder.io)
        end
        # Always close the base IO
        if isa(decoder.base_io, IOStream)
            close(decoder.base_io)
        end
        # Force garbage collection to ensure file handles are released on Windows
        # Windows may not immediately release file locks even after close()
        GC.gc()
    end

    return decoder.metadata, records
end