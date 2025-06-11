"""
    DBN.jl

    DBN.jl is a Julia package for reading and writing Databento Binary Encoding (DBN) files.
"""
module DBN

using Dates
using CRC32c
using CodecZstd
using TranscodingStreams
using EnumX

export DBNDecoder, DBNEncoder, read_dbn, write_dbn
export Metadata, DBNHeader, RecordHeader, DBNTimestamp
export MBOMsg, TradeMsg, MBP1Msg, MBP10Msg, OHLCVMsg, StatusMsg, ImbalanceMsg, StatMsg
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
    MBO_MSG = 0x00
    TRADE_MSG = 0x01
    MBP_1_MSG = 0x02
    MBP_10_MSG = 0x03
    OHLCV_MSG = 0x11
    STATUS_MSG = 0x12
    INSTRUMENT_DEF_MSG = 0x13
    IMBALANCE_MSG = 0x14
    STAT_MSG = 0x15
    ERROR_MSG = 0x16
    SYMBOL_MAPPING_MSG = 0x17
    SYSTEM_MSG = 0x18
end

@enumx Action::UInt8 begin
    ADD = UInt8('A')
    CANCEL = UInt8('C')
    MODIFY = UInt8('F')
    TRADE = UInt8('T')
    FILL = UInt8('E')
    CLEAR = UInt8('R')
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
    start_ts::Int64  # renamed from 'start' for consistency with end_ts
    end_ts::Int64  # renamed from 'end' which is a reserved keyword
    limit::UInt64
    compression::Compression.T
    stype_in::SType.T
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
    ts_recv::Int64
    action::UInt16
    reason::UInt16
    trading_event::UInt16
    is_trading::Bool
    is_quoting::Bool
    is_short_sell_restricted::Bool
end

struct ImbalanceMsg
    hd::RecordHeader
    ts_recv::Int64
    ref_price::Int64
    auction_time::Int64
    cont_size::Int32
    auction_size::Int32
    imbalance_size::Int32
    imbalance_side::Side.T
    clearing_price::Int64
end

struct StatMsg
    hd::RecordHeader
    ts_recv::Int64
    ts_ref::Int64
    price::Int64
    quantity::Int64  # Expanded to 64 bits in DBN v3
    sequence::UInt32
    ts_in_delta::Int32
    stat_type::UInt16
    channel_id::UInt8
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

# DBN Decoder
mutable struct DBNDecoder
    io::IO
    base_io::IO  # Original IO before compression wrapper
    header::Union{DBNHeader,Nothing}
    metadata::Union{Metadata,Nothing}
    upgrade_policy::UInt8
end

DBNDecoder(io::IO) = DBNDecoder(io, io, nothing, nothing, 0)

function read_header!(decoder::DBNDecoder)
    # Read magic bytes "DBN\0"
    magic = read(decoder.io, 4)
    if magic != b"DBN\0"
        error("Invalid DBN file: wrong magic bytes")
    end
    
    # Read version
    version = read(decoder.io, UInt8)
    if version != DBN_VERSION
        error("Unsupported DBN version: $version")
    end
    
    # Read dataset length and dataset
    dataset_len = read(decoder.io, UInt16)
    dataset = String(read(decoder.io, dataset_len))
    
    # Read schema
    schema_val = read(decoder.io, UInt16)
    schema = Schema.T(schema_val)
    
    # Read timestamps
    start_ts = read(decoder.io, Int64)
    end_ts = read(decoder.io, Int64)
    
    # Read limit
    limit = read(decoder.io, UInt64)
    
    # Read compression
    compression = Compression.T(read(decoder.io, UInt8))
    
    # Read stype
    stype_in = SType.T(read(decoder.io, UInt8))
    stype_out = SType.T(read(decoder.io, UInt8))
    
    # Read ts_out
    ts_out = read(decoder.io, Bool)
    
    # Read symbol count
    symbol_count = read(decoder.io, UInt32)
    
    # Read symbols
    symbols = String[]
    for _ in 1:symbol_count
        sym_len = read(decoder.io, UInt16)
        push!(symbols, String(read(decoder.io, sym_len)))
    end
    
    # Read partial symbols
    partial_count = read(decoder.io, UInt32)
    partial = String[]
    for _ in 1:partial_count
        sym_len = read(decoder.io, UInt16)
        push!(partial, String(read(decoder.io, sym_len)))
    end
    
    # Read not found symbols
    not_found_count = read(decoder.io, UInt32)
    not_found = String[]
    for _ in 1:not_found_count
        sym_len = read(decoder.io, UInt16)
        push!(not_found, String(read(decoder.io, sym_len)))
    end
    
    # Read mappings
    mappings_count = read(decoder.io, UInt32)
    mappings = Tuple{String,String,Int64,Int64}[]
    for _ in 1:mappings_count
        raw_len = read(decoder.io, UInt16)
        raw = String(read(decoder.io, raw_len))
        mapped_len = read(decoder.io, UInt16)
        mapped = String(read(decoder.io, mapped_len))
        start_ts = read(decoder.io, Int64)
        end_ts = read(decoder.io, Int64)
        push!(mappings, (raw, mapped, start_ts, end_ts))
    end
    
    # Skip to metadata start
    metadata_len = read(decoder.io, UInt32)
    _ = read(decoder.io, 4)  # Reserved bytes
    _ = read(decoder.io, 8)  # 8-byte alignment padding for DBN v3
    
    decoder.metadata = Metadata(
        version, dataset, schema, start_ts, end_ts, limit,
        compression, stype_in, stype_out, ts_out,
        symbols, partial, not_found, mappings
    )
    
    decoder.header = DBNHeader(
        VersionUpgradePolicy(decoder.upgrade_policy),
        DatasetCondition(0, start_ts, end_ts, limit),
        decoder.metadata
    )
    
    # If compressed, wrap the IO stream with Zstd decompressor
    if compression == Compression.ZSTD
        # Save position after header
        header_end_pos = position(decoder.io)
        
        # Read the rest of the file
        compressed_data = read(decoder.io)
        
        # Create a decompression stream
        decompressed_io = IOBuffer(transcode(ZstdDecompressor, compressed_data))
        
        # Replace decoder's IO with the decompressed stream
        decoder.io = decompressed_io
    end
end

function read_record_header(io::IO)
    length = read(io, UInt8)
    rtype = RType.T(read(io, UInt8))
    publisher_id = read(io, UInt16)
    instrument_id = read(io, UInt32)
    ts_event = read(io, Int64)
    
    RecordHeader(length, rtype, publisher_id, instrument_id, ts_event)
end

function read_record(decoder::DBNDecoder)
    if eof(decoder.io)
        return nothing
    end
    
    hd = read_record_header(decoder.io)
    
    if hd.rtype == RType.MBO_MSG
        order_id = read(decoder.io, UInt64)
        price = read(decoder.io, Int64)
        size = read(decoder.io, UInt32)
        flags = read(decoder.io, UInt8)
        channel_id = read(decoder.io, UInt8)
        action = Action.T(read(decoder.io, UInt8))
        side = Side.T(read(decoder.io, UInt8))
        ts_recv = read(decoder.io, Int64)
        ts_in_delta = read(decoder.io, Int32)
        sequence = read(decoder.io, UInt32)
        return MBOMsg(hd, order_id, price, size, flags, channel_id, action, side, ts_recv, ts_in_delta, sequence)
        
    elseif hd.rtype == RType.TRADE_MSG
        price = read(decoder.io, Int64)
        size = read(decoder.io, UInt32)
        action = Action.T(read(decoder.io, UInt8))
        side = Side.T(read(decoder.io, UInt8))
        flags = read(decoder.io, UInt8)
        depth = read(decoder.io, UInt8)
        ts_recv = read(decoder.io, Int64)
        ts_in_delta = read(decoder.io, Int32)
        sequence = read(decoder.io, UInt32)
        return TradeMsg(hd, price, size, action, side, flags, depth, ts_recv, ts_in_delta, sequence)
        
    elseif hd.rtype == RType.MBP_1_MSG
        price = read(decoder.io, Int64)
        size = read(decoder.io, UInt32)
        action = Action.T(read(decoder.io, UInt8))
        side = Side.T(read(decoder.io, UInt8))
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
        action = Action.T(read(decoder.io, UInt8))
        side = Side.T(read(decoder.io, UInt8))
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
        
    elseif hd.rtype == RType.OHLCV_MSG
        open = read(decoder.io, Int64)
        high = read(decoder.io, Int64)
        low = read(decoder.io, Int64)
        close = read(decoder.io, Int64)
        volume = read(decoder.io, UInt64)
        return OHLCVMsg(hd, open, high, low, close, volume)
        
    elseif hd.rtype == RType.STATUS_MSG
        ts_recv = read(decoder.io, Int64)
        action = read(decoder.io, UInt16)
        reason = read(decoder.io, UInt16)
        trading_event = read(decoder.io, UInt16)
        is_trading = read(decoder.io, Bool)
        is_quoting = read(decoder.io, Bool)
        is_short_sell_restricted = read(decoder.io, Bool)
        _ = read(decoder.io, 5)  # Reserved
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
        
        instrument_class = InstrumentClass.T(read(decoder.io, UInt8))
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
        leg_side = Side.T(read(decoder.io, UInt8))
        leg_underlying_id = read(decoder.io, UInt32)
        leg_instrument_class = InstrumentClass.T(read(decoder.io, UInt8))
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
        ts_recv = read(decoder.io, Int64)
        ref_price = read(decoder.io, Int64)
        auction_time = read(decoder.io, Int64)
        cont_size = read(decoder.io, Int32)
        auction_size = read(decoder.io, Int32)
        imbalance_size = read(decoder.io, Int32)
        imbalance_side = Side.T(read(decoder.io, UInt8))
        _ = read(decoder.io, 3)  # Reserved
        clearing_price = read(decoder.io, Int64)
        return ImbalanceMsg(hd, ts_recv, ref_price, auction_time, cont_size, auction_size, imbalance_size, imbalance_side, clearing_price)
        
    elseif hd.rtype == RType.STAT_MSG
        ts_recv = read(decoder.io, Int64)
        ts_ref = read(decoder.io, Int64)
        price = read(decoder.io, Int64)
        quantity = read(decoder.io, Int64)
        sequence = read(decoder.io, UInt32)
        ts_in_delta = read(decoder.io, Int32)
        stat_type = read(decoder.io, UInt16)
        channel_id = read(decoder.io, UInt8)
        update_action = read(decoder.io, UInt8)
        stat_flags = read(decoder.io, UInt8)
        _ = read(decoder.io, 3)  # Reserved
        return StatMsg(hd, ts_recv, ts_ref, price, quantity, sequence, ts_in_delta, stat_type, channel_id, update_action, stat_flags)
        
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
    
    # Write magic bytes
    write(io, b"DBN\0")
    
    # Write version
    write(io, UInt8(DBN_VERSION))
    
    # Write dataset
    write(io, UInt16(length(encoder.metadata.dataset)))
    write(io, encoder.metadata.dataset)
    
    # Write schema
    write(io, UInt16(encoder.metadata.schema))
    
    # Write timestamps
    write(io, encoder.metadata.start_ts)
    write(io, encoder.metadata.end_ts)
    
    # Write limit
    write(io, encoder.metadata.limit)
    
    # Write compression
    write(io, UInt8(encoder.metadata.compression))
    
    # Write stype
    write(io, UInt8(encoder.metadata.stype_in))
    write(io, UInt8(encoder.metadata.stype_out))
    
    # Write ts_out
    write(io, encoder.metadata.ts_out)
    
    # Write symbols
    write(io, UInt32(length(encoder.metadata.symbols)))
    for sym in encoder.metadata.symbols
        write(io, UInt16(length(sym)))
        write(io, sym)
    end
    
    # Write partial symbols
    write(io, UInt32(length(encoder.metadata.partial)))
    for sym in encoder.metadata.partial
        write(io, UInt16(length(sym)))
        write(io, sym)
    end
    
    # Write not found symbols
    write(io, UInt32(length(encoder.metadata.not_found)))
    for sym in encoder.metadata.not_found
        write(io, UInt16(length(sym)))
        write(io, sym)
    end
    
    # Write mappings
    write(io, UInt32(length(encoder.metadata.mappings)))
    for (raw, mapped, start_ts, end_ts) in encoder.metadata.mappings
        write(io, UInt16(length(raw)))
        write(io, raw)
        write(io, UInt16(length(mapped)))
        write(io, mapped)
        write(io, start_ts)
        write(io, end_ts)
    end
    
    # Write metadata length (placeholder for now)
    write(io, UInt32(0))
    write(io, UInt32(0))  # Reserved
    write(io, zeros(UInt8, 8))  # 8-byte alignment padding for DBN v3
    
    # If using compression, set up compressed buffer
    if encoder.metadata.compression == Compression.ZSTD
        encoder.compressed_buffer = IOBuffer()
        encoder.io = encoder.compressed_buffer
    end
end

function write_record_header(io::IO, hd::RecordHeader)
    write(io, hd.length)
    write(io, UInt8(hd.rtype))
    write(io, hd.publisher_id)
    write(io, hd.instrument_id)
    write(io, hd.ts_event)
end

function write_record(encoder::DBNEncoder, record)
    io = encoder.io
    
    if isa(record, MBOMsg)
        write_record_header(io, record.hd)
        write(io, record.order_id)
        write(io, record.price)
        write(io, record.size)
        write(io, record.flags)
        write(io, record.channel_id)
        write(io, UInt8(record.action))
        write(io, UInt8(record.side))
        write(io, record.ts_recv)
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
        write(io, zeros(UInt8, 5))  # Reserved
        
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
        
        # Write fixed-length strings
        write(io, rpad(record.currency, 4, '\0'))
        write(io, rpad(record.settl_currency, 4, '\0'))
        write(io, rpad(record.secsubtype, 6, '\0'))
        write(io, rpad(record.raw_symbol, 22, '\0'))
        write(io, rpad(record.group, 21, '\0'))
        write(io, rpad(record.exchange, 5, '\0'))
        write(io, rpad(record.asset, 11, '\0'))  # Expanded to 11 bytes in v3
        write(io, rpad(record.cfi, 7, '\0'))
        write(io, rpad(record.security_type, 7, '\0'))
        write(io, rpad(record.unit_of_measure, 31, '\0'))
        write(io, rpad(record.underlying, 21, '\0'))
        write(io, rpad(record.strike_price_currency, 4, '\0'))
        
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
        write(io, rpad(record.leg_raw_symbol, 22, '\0'))
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
        write(io, record.cont_size)
        write(io, record.auction_size)
        write(io, record.imbalance_size)
        write(io, UInt8(record.imbalance_side))
        write(io, zeros(UInt8, 3))  # Reserved
        write(io, record.clearing_price)
        
    elseif isa(record, StatMsg)
        write_record_header(io, record.hd)
        write(io, record.ts_recv)
        write(io, record.ts_ref)
        write(io, record.price)
        write(io, record.quantity)
        write(io, record.sequence)
        write(io, record.ts_in_delta)
        write(io, record.stat_type)
        write(io, record.channel_id)
        write(io, record.update_action)
        write(io, record.stat_flags)
        write(io, zeros(UInt8, 3))  # Reserved
    end
end

# Add finalize function for encoder
function finalize_encoder(encoder::DBNEncoder)
    if encoder.metadata.compression == Compression.ZSTD && encoder.compressed_buffer !== nothing
        # Get the uncompressed data
        uncompressed_data = take!(encoder.compressed_buffer)
        
        # Compress the data
        compressed_data = transcode(ZstdCompressor, uncompressed_data)
        
        # Write compressed data to the base IO
        write(encoder.base_io, compressed_data)
    end
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
    open(filename, "r") do f
        decoder = DBNDecoder(f)
        read_header!(decoder)
        
        while !eof(decoder.io)
            record = read_record(decoder)
            if record !== nothing
                push!(records, record)
            end
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
        Compression.NONE,  # No compression for streaming
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
        writer.encoder.metadata.compression,
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
        Compression.ZSTD,  # Enable compression
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
