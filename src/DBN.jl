"""
    DBN.jl

    DBN.jl is a Julia package for reading and writing Databento Binary Encoding (DBN) files.
"""
module DBN

using Dates
using CRC32c
using CodecZstd  # Commented out for basic testing
using TranscodingStreams  # Commented out for basic testing
using EnumX

export DBNDecoder, DBNEncoder, read_dbn, write_dbn
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

# Constants
const DBN_VERSION = 3
const FIXED_PRICE_SCALE = Int32(1_000_000_000)
const UNDEF_PRICE = typemax(Int64)
const UNDEF_ORDER_SIZE = typemax(UInt32)
const UNDEF_TIMESTAMP = typemax(Int64)
const LENGTH_MULTIPLIER = 4  # The multiplier for converting the length field to bytes

# Enums using EnumX for better namespace management
@enumx Schema::UInt16 begin
    MBO = 0
    MBP_1 = 1
    MBP_10 = 2
    TBBO = 3
    TRADES = 4
    OHLCV_1S = 5
    OHLCV_1M = 6
    OHLCV_1H = 7
    OHLCV_1D = 8
    DEFINITION = 9
    STATISTICS = 10
    STATUS = 11
    IMBALANCE = 12
    CBBO = 13
    CBBO_1S = 14
    CBBO_1M = 15
    CMBP_1 = 16
    TCBBO = 17
    BBO_1S = 18
    BBO_1M = 19
end

@enumx Compression::UInt8 begin
    NONE = 0
    ZSTD = 1
end

@enumx Encoding::UInt8 begin
    DBN = 0
    CSV = 1
    JSON = 2
end

@enumx SType::UInt8 begin
    INSTRUMENT_ID = 0
    RAW_SYMBOL = 1
    CONTINUOUS = 2
    PARENT = 3
end

@enumx RType::UInt8 begin
    MBP_0_MSG = 0x00        # Trades (book depth 0)
    MBP_1_MSG = 0x01        # TBBO/MBP-1 (book depth 1)
    MBP_10_MSG = 0x0A       # MBP-10 (book depth 10)
    STATUS_MSG = 0x12       # Exchange status record
    INSTRUMENT_DEF_MSG = 0x13  # Instrument definition record
    IMBALANCE_MSG = 0x14    # Order imbalance record
    ERROR_MSG = 0x15        # Error record from live gateway
    SYMBOL_MAPPING_MSG = 0x16  # Symbol mapping record from live gateway
    SYSTEM_MSG = 0x17       # Non-error record from live gateway
    STAT_MSG = 0x18         # Statistics record from publisher
    OHLCV_1S_MSG = 0x20     # OHLCV at 1-second cadence
    OHLCV_1M_MSG = 0x21     # OHLCV at 1-minute cadence
    OHLCV_1H_MSG = 0x22     # OHLCV at hourly cadence
    OHLCV_1D_MSG = 0x23     # OHLCV at daily cadence
    MBO_MSG = 0xA0          # Market-by-order record
    CMBP_1_MSG = 0xB1       # Consolidated market-by-price with book depth 1
    CBBO_1S_MSG = 0xC0      # Consolidated market-by-price with book depth 1 at 1-second cadence
    CBBO_1M_MSG = 0xC1      # Consolidated market-by-price with book depth 1 at 1-minute cadence
    TCBBO_MSG = 0xC2        # Consolidated market-by-price with book depth 1 (trades only)
    BBO_1S_MSG = 0xC3       # Market-by-price with book depth 1 at 1-second cadence
    BBO_1M_MSG = 0xC4       # Market-by-price with book depth 1 at 1-minute cadence
end

@enumx Action::UInt8 begin
    ADD = UInt8('A')      # Insert a new order into the book
    MODIFY = UInt8('M')   # Change an order's price and/or size
    CANCEL = UInt8('C')   # Fully or partially cancel an order from the book
    CLEAR = UInt8('R')    # Remove all resting orders for the instrument
    TRADE = UInt8('T')    # An aggressing order traded. Does not affect the book
    FILL = UInt8('F')     # A resting order was filled. Does not affect the book
    NONE = UInt8('N')     # No action: does not affect the book, but may carry flags or other information
end

@enumx Side::UInt8 begin
    ASK = UInt8('A')
    BID = UInt8('B')
    NONE = UInt8('N')
end

@enumx InstrumentClass::UInt8 begin
    STOCK = UInt8('K')
    OPTION = UInt8('O')
    FUTURE = UInt8('F')
    FX = UInt8('X')
    BOND = UInt8('B')
    MIXED_SPREAD = UInt8('M')
    COMMODITY = UInt8('C')
    INDEX = UInt8('I')
    CURRENCY = UInt8('U')
    SWAP = UInt8('S')
    OTHER = UInt8('?')
    # Also support numeric values
    UNKNOWN_0 = 0
    UNKNOWN_45 = 45
end

# Structures
struct VersionUpgradePolicy
    upgrade_policy::UInt8
end

struct DatasetCondition
    last_ts_out::Int64
    start_ts::Int64
    end_ts::Int64
    limit::UInt64
end

struct Metadata
    version::UInt8
    dataset::String
    schema::Schema.T
    start_ts::Int64
    end_ts::Union{Int64,Nothing}  # Can be null
    limit::Union{UInt64,Nothing}  # Can be null
    stype_in::Union{SType.T,Nothing}  # Can be null
    stype_out::SType.T
    ts_out::Bool
    symbols::Vector{String}
    partial::Vector{String}
    not_found::Vector{String}
    mappings::Vector{Tuple{String,String,Int64,Int64}}
end

struct DBNHeader
    version_upgrade_policy::VersionUpgradePolicy
    dataset_condition::DatasetCondition
    metadata::Metadata
end

struct RecordHeader
    length::UInt8
    rtype::RType.T
    publisher_id::UInt16
    instrument_id::UInt32
    ts_event::Int64
end

# Message Types
struct MBOMsg
    hd::RecordHeader
    order_id::UInt64
    price::Int64
    size::UInt32
    flags::UInt8
    channel_id::UInt8
    action::Action.T
    side::Side.T
    ts_recv::Int64
    ts_in_delta::Int32
    sequence::UInt32
end

struct TradeMsg
    hd::RecordHeader
    price::Int64
    size::UInt32
    action::Action.T
    side::Side.T
    flags::UInt8
    depth::UInt8
    ts_recv::Int64
    ts_in_delta::Int32
    sequence::UInt32
end

struct BidAskPair
    bid_px::Int64
    ask_px::Int64
    bid_sz::UInt32
    ask_sz::UInt32
    bid_ct::UInt32
    ask_ct::UInt32
end

struct MBP1Msg
    hd::RecordHeader
    price::Int64
    size::UInt32
    action::Action.T
    side::Side.T
    flags::UInt8
    depth::UInt8
    ts_recv::Int64
    ts_in_delta::Int32
    sequence::UInt32
    levels::BidAskPair
end

struct MBP10Msg
    hd::RecordHeader
    price::Int64
    size::UInt32
    action::Action.T
    side::Side.T
    flags::UInt8
    depth::UInt8
    ts_recv::Int64
    ts_in_delta::Int32
    sequence::UInt32
    levels::NTuple{10,BidAskPair}
end

struct OHLCVMsg
    hd::RecordHeader
    open::Int64
    high::Int64
    low::Int64
    close::Int64
    volume::UInt64
end

struct StatusMsg
    hd::RecordHeader
    ts_recv::UInt64
    action::UInt16
    reason::UInt16
    trading_event::UInt16
    is_trading::UInt8  # c_char in Rust
    is_quoting::UInt8  # c_char in Rust
    is_short_sell_restricted::UInt8  # c_char in Rust
end

struct ImbalanceMsg
    hd::RecordHeader
    ts_recv::Int64
    ref_price::Int64
    auction_time::UInt64
    cont_book_clr_price::Int64
    auct_interest_clr_price::Int64
    ssr_filling_price::Int64
    ind_match_price::Int64
    upper_collar::Int64
    lower_collar::Int64
    paired_qty::UInt32
    total_imbalance_qty::UInt32
    market_imbalance_qty::UInt32
    unpaired_qty::UInt32
    auction_type::UInt8
    side::Side.T
    auction_status::UInt8
    freeze_status::UInt8
    num_extensions::UInt8
    unpaired_side::UInt8
    significant_imbalance::UInt8
    # _reserved field for alignment
end

struct StatMsg
    hd::RecordHeader
    ts_recv::UInt64
    ts_ref::UInt64
    price::Int64
    quantity::Int64  # Expanded to 64 bits in DBN v3
    sequence::UInt32
    ts_in_delta::Int32
    stat_type::UInt16
    channel_id::UInt16  # Changed to UInt16 to match Rust
    update_action::UInt8
    stat_flags::UInt8
end

struct ErrorMsg
    hd::RecordHeader
    err::String
end

struct SymbolMappingMsg
    hd::RecordHeader
    stype_in::SType.T
    stype_in_symbol::String
    stype_out::SType.T
    stype_out_symbol::String
    start_ts::Int64
    end_ts::Int64
end

struct SystemMsg
    hd::RecordHeader
    msg::String
    code::String
end

struct InstrumentDefMsg
    hd::RecordHeader
    ts_recv::Int64
    min_price_increment::Int64
    display_factor::Int64
    expiration::Int64
    activation::Int64
    high_limit_price::Int64
    low_limit_price::Int64
    max_price_variation::Int64
    unit_of_measure_qty::Int64
    min_price_increment_amount::Int64
    price_ratio::Int64
    inst_attrib_value::Int32
    underlying_id::UInt32
    raw_instrument_id::UInt64  # Expanded to 64 bits in DBN v3
    market_depth_implied::Int32
    market_depth::Int32
    market_segment_id::UInt32
    max_trade_vol::UInt32
    min_lot_size::Int32
    min_lot_size_block::Int32
    min_lot_size_round_lot::Int32
    min_trade_vol::UInt32
    contract_multiplier::Int32
    decay_quantity::Int32
    original_contract_size::Int32
    appl_id::Int16
    maturity_year::UInt16
    decay_start_date::UInt16
    channel_id::UInt8
    currency::String
    settl_currency::String
    secsubtype::String
    raw_symbol::String
    group::String
    exchange::String
    asset::String  # Expanded to 11 bytes in DBN v3
    cfi::String
    security_type::String
    unit_of_measure::String
    underlying::String
    strike_price_currency::String
    instrument_class::InstrumentClass.T
    strike_price::Int64
    match_algorithm::Char
    main_fraction::UInt8
    price_display_format::UInt8
    sub_fraction::UInt8
    underlying_product::UInt8
    security_update_action::Char
    maturity_month::UInt8
    maturity_day::UInt8
    maturity_week::UInt8
    user_defined_instrument::Bool
    contract_multiplier_unit::Int8
    flow_schedule_type::Int8
    tick_rule::UInt8
    # New strategy leg fields in DBN v3
    leg_count::UInt8
    leg_index::UInt8
    leg_instrument_id::UInt32
    leg_raw_symbol::String
    leg_side::Side.T
    leg_underlying_id::UInt32
    leg_instrument_class::InstrumentClass.T
    leg_ratio_qty_numerator::UInt32
    leg_ratio_qty_denominator::UInt32
    leg_ratio_price_numerator::UInt32
    leg_ratio_price_denominator::UInt32
    leg_price::Int64
    leg_delta::Int64
end

# Additional message structures for consolidated and BBO records
struct CMBP1Msg
    hd::RecordHeader
    price::Int64
    size::UInt32
    action::Action.T
    side::Side.T
    flags::UInt8
    depth::UInt8
    ts_recv::Int64
    ts_in_delta::Int32
    sequence::UInt32
    levels::BidAskPair
end

struct CBBO1sMsg
    hd::RecordHeader
    price::Int64
    size::UInt32
    action::Action.T
    side::Side.T
    flags::UInt8
    depth::UInt8
    ts_recv::Int64
    ts_in_delta::Int32
    sequence::UInt32
    levels::BidAskPair
end

struct CBBO1mMsg
    hd::RecordHeader
    price::Int64
    size::UInt32
    action::Action.T
    side::Side.T
    flags::UInt8
    depth::UInt8
    ts_recv::Int64
    ts_in_delta::Int32
    sequence::UInt32
    levels::BidAskPair
end

struct TCBBOMsg
    hd::RecordHeader
    price::Int64
    size::UInt32
    action::Action.T
    side::Side.T
    flags::UInt8
    depth::UInt8
    ts_recv::Int64
    ts_in_delta::Int32
    sequence::UInt32
    levels::BidAskPair
end

struct BBO1sMsg
    hd::RecordHeader
    price::Int64
    size::UInt32
    action::Action.T
    side::Side.T
    flags::UInt8
    depth::UInt8
    ts_recv::Int64
    ts_in_delta::Int32
    sequence::UInt32
    levels::BidAskPair
end

struct BBO1mMsg
    hd::RecordHeader
    price::Int64
    size::UInt32
    action::Action.T
    side::Side.T
    flags::UInt8
    depth::UInt8
    ts_recv::Int64
    ts_in_delta::Int32
    sequence::UInt32
    levels::BidAskPair
end

# Helper function for safe enum conversion
function safe_action(raw_val::UInt8)
    # Special case: 0 might indicate no action for certain record types
    if raw_val == 0
        return Action.NONE
    end
    
    try
        return Action.T(raw_val)
    catch ArgumentError
        # For unknown action values, use a default or create a placeholder
        # For now, return TRADE as a safe default
        @warn "Unknown Action value: $raw_val (0x$(string(raw_val, base=16))), using TRADE as default"
        return Action.TRADE
    end
end

function safe_side(raw_val::UInt8)
    try
        return Side.T(raw_val)
    catch ArgumentError
        @warn "Unknown Side value: $raw_val, using NONE as default"
        return Side.NONE
    end
end

function safe_instrument_class(raw_val::UInt8)
    try
        return InstrumentClass.T(raw_val)
    catch ArgumentError
        @warn "Unknown InstrumentClass value: $raw_val, using OTHER as default"
        return InstrumentClass.OTHER
    end
end

# DBN Decoder
mutable struct DBNDecoder
    io::IO
    base_io::IO  # Original IO before compression wrapper
    header::Union{DBNHeader,Nothing}
    metadata::Union{Metadata,Nothing}
    upgrade_policy::UInt8
end

DBNDecoder(io::IO) = DBNDecoder(io, io, nothing, nothing, 0)

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
        ltoh(reinterpret(UInt16, metadata_bytes[pos:pos+1])[1])
        pos += 2
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

function read_record_header(io::IO)
    length = read(io, UInt8)
    rtype_raw = read(io, UInt8)
    
    # Handle unknown record types first, before trying to read more data
    rtype = try
        RType.T(rtype_raw)
    catch ArgumentError
        # Return special marker for unknown types - don't read more data
        return nothing, rtype_raw, length
    end
    
    # Always read the standard header fields
    publisher_id = read(io, UInt16)
    instrument_id = read(io, UInt32)
    ts_event = read(io, Int64)
    
    RecordHeader(length, rtype, publisher_id, instrument_id, ts_event)
end

function read_record(decoder::DBNDecoder)
    if eof(decoder.io)
        return nothing
    end
    
    hd_result = read_record_header(decoder.io)
    
    # Handle unknown record types
    if hd_result isa Tuple
        # Unknown record type - skip it
        _, rtype_raw, length = hd_result
        skip(decoder.io, length - 2)  # Already read length(1) + rtype(1) = 2 bytes
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
        # Read all fields for DBN v3 format
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
        inst_attrib_value = read(decoder.io, Int32)
        underlying_id = read(decoder.io, UInt32)
        raw_instrument_id = read(decoder.io, UInt64)  # Expanded in v3
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
        appl_id = read(decoder.io, Int16)
        maturity_year = read(decoder.io, UInt16)
        decay_start_date = read(decoder.io, UInt16)
        channel_id = read(decoder.io, UInt8)
        
        # Read string fields
        currency = String(strip(String(read(decoder.io, 4)), '\0'))
        settl_currency = String(strip(String(read(decoder.io, 4)), '\0'))
        secsubtype = String(strip(String(read(decoder.io, 6)), '\0'))
        raw_symbol = String(strip(String(read(decoder.io, 22)), '\0'))
        group = String(strip(String(read(decoder.io, 21)), '\0'))
        exchange = String(strip(String(read(decoder.io, 5)), '\0'))
        asset = String(strip(String(read(decoder.io, 11)), '\0'))  # Expanded to 11 bytes in v3
        cfi = String(strip(String(read(decoder.io, 7)), '\0'))
        security_type = String(strip(String(read(decoder.io, 7)), '\0'))
        unit_of_measure = String(strip(String(read(decoder.io, 31)), '\0'))
        underlying = String(strip(String(read(decoder.io, 21)), '\0'))
        strike_price_currency = String(strip(String(read(decoder.io, 4)), '\0'))
        
        instrument_class = safe_instrument_class(read(decoder.io, UInt8))
        strike_price = read(decoder.io, Int64)
        match_algorithm = read(decoder.io, Char)
        main_fraction = read(decoder.io, UInt8)
        price_display_format = read(decoder.io, UInt8)
        sub_fraction = read(decoder.io, UInt8)
        underlying_product = read(decoder.io, UInt8)
        security_update_action = read(decoder.io, Char)
        maturity_month = read(decoder.io, UInt8)
        maturity_day = read(decoder.io, UInt8)
        maturity_week = read(decoder.io, UInt8)
        user_defined_instrument = read(decoder.io, Bool)
        contract_multiplier_unit = read(decoder.io, Int8)
        flow_schedule_type = read(decoder.io, Int8)
        tick_rule = read(decoder.io, UInt8)
        
        # New strategy leg fields in DBN v3
        leg_count = read(decoder.io, UInt8)
        leg_index = read(decoder.io, UInt8)
        leg_instrument_id = read(decoder.io, UInt32)
        leg_raw_symbol = String(strip(String(read(decoder.io, 22)), '\0'))
        leg_side = safe_side(read(decoder.io, UInt8))
        leg_underlying_id = read(decoder.io, UInt32)
        leg_instrument_class = safe_instrument_class(read(decoder.io, UInt8))
        leg_ratio_qty_numerator = read(decoder.io, UInt32)
        leg_ratio_qty_denominator = read(decoder.io, UInt32)
        leg_ratio_price_numerator = read(decoder.io, UInt32)
        leg_ratio_price_denominator = read(decoder.io, UInt32)
        leg_price = read(decoder.io, Int64)
        leg_delta = read(decoder.io, Int64)
        _ = read(decoder.io, 8)  # Reserved for alignment
        
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

# DBN Encoder
mutable struct DBNEncoder
    io::IO
    base_io::IO  # Original IO before compression wrapper
    metadata::Metadata
    compressed_buffer::Union{IOBuffer,Nothing}
end

DBNEncoder(io::IO, metadata::Metadata) = DBNEncoder(io, io, metadata, nothing)

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

function write_record_header(io::IO, hd::RecordHeader)
    write(io, hd.length)
    write(io, UInt8(hd.rtype))
    write(io, hd.publisher_id)
    write(io, hd.instrument_id)
    write(io, hd.ts_event)
end

# Helper function to write fixed-length strings with null padding
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
    end
end

# Add finalize function for encoder
function finalize_encoder(encoder::DBNEncoder)
    # For now, we don't use compression in write mode for simplicity
    # In the future, compression support could be added here
end

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

# Convenience functions
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
    end
    
    return records
end

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

# Price conversion utilities
function price_to_float(price::Int64, scale::Int32=FIXED_PRICE_SCALE)
    if price == UNDEF_PRICE
        return NaN
    end
    return Float64(price) / Float64(scale)
end

function float_to_price(value::Float64, scale::Int32=FIXED_PRICE_SCALE)
    if isnan(value) || isinf(value)
        return UNDEF_PRICE
    end
    return Int64(round(value * Float64(scale)))
end

# Timestamp utilities
struct DBNTimestamp
    seconds::Int64      # Unix epoch seconds
    nanoseconds::Int32  # Nanoseconds within the second (0-999_999_999)
end

function DBNTimestamp(ns::Int64)
    if ns == UNDEF_TIMESTAMP
        return DBNTimestamp(UNDEF_TIMESTAMP, 0)
    end
    seconds = ns ÷ 1_000_000_000
    nanoseconds = Int32(ns % 1_000_000_000)
    return DBNTimestamp(seconds, nanoseconds)
end

function to_nanoseconds(ts::DBNTimestamp)
    if ts.seconds == UNDEF_TIMESTAMP
        return UNDEF_TIMESTAMP
    end
    return ts.seconds * 1_000_000_000 + ts.nanoseconds
end

function ts_to_datetime(ts::Int64)
    if ts == UNDEF_TIMESTAMP
        return nothing
    end
    # Returns DateTime with millisecond precision and separate nanosecond component
    dbn_ts = DBNTimestamp(ts)
    dt = unix2datetime(Float64(dbn_ts.seconds) + dbn_ts.nanoseconds / 1_000_000_000)
    return (datetime=dt, nanoseconds=dbn_ts.nanoseconds)
end

function datetime_to_ts(dt::DateTime, nanoseconds::Int32=0)
    # Convert DateTime to nanoseconds, preserving additional precision
    seconds = Int64(round(datetime2unix(dt)))
    return seconds * 1_000_000_000 + nanoseconds
end

# Alternative: Use Dates.Time for nanosecond precision within a day
function ts_to_date_time(ts::Int64)
    if ts == UNDEF_TIMESTAMP
        return nothing
    end
    dbn_ts = DBNTimestamp(ts)
    
    # Get the date part
    dt_seconds = unix2datetime(Float64(dbn_ts.seconds))
    date_part = Date(dt_seconds)
    
    # Get time within the day with nanosecond precision
    seconds_in_day = dbn_ts.seconds % 86400
    time_ns = seconds_in_day * 1_000_000_000 + dbn_ts.nanoseconds
    time_part = Dates.Time(Dates.Nanosecond(time_ns))
    
    return (date=date_part, time=time_part, timestamp=dbn_ts)
end

function date_time_to_ts(date::Date, time::Dates.Time)
    # Convert date to seconds since epoch
    dt = DateTime(date)
    date_seconds = Int64(round(datetime2unix(dt)))
    
    # Extract nanoseconds from time
    time_ns = Dates.value(time)  # Total nanoseconds since midnight
    
    return date_seconds * 1_000_000_000 + time_ns
end

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
    # Create metadata with placeholder timestamps
    metadata = Metadata(
        DBN_VERSION,
        dataset,
        schema,
        typemax(Int64),  # Will update with first record
        typemin(Int64),  # Will update with last record
        0,
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
    
    return DBNStreamWriter(encoder, 0, typemax(Int64), typemin(Int64), 
                          auto_flush, flush_interval, 0)
end

function write_record!(writer::DBNStreamWriter, record)
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
    
    # Update header with final timestamps and count
    seekstart(writer.encoder.io)
    
    # Update metadata
    writer.encoder.metadata = Metadata(
        writer.encoder.metadata.version,
        writer.encoder.metadata.dataset,
        writer.encoder.metadata.schema,
        writer.first_ts,
        writer.last_ts,
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
    
    # Stream compress the file
    open(output_file, "w") do out_io
        encoder = DBNEncoder(out_io, compressed_metadata)
        write_header(encoder)
        
        # Stream through input file
        for record in DBNStream(input_file)
            write_record(encoder, record)
        end
        
        finalize_encoder(encoder)
    end
    
    # Optionally delete original
    if delete_original
        rm(input_file)
    end
    
    # Return compression stats
    original_size = filesize(input_file)
    compressed_size = filesize(output_file)
    compression_ratio = 1.0 - (compressed_size / original_size)
    
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

end  # module DBN
