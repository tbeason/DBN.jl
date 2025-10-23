# DBN message type definitions

# Message Types

"""
    MBOMsg

Market-by-order message containing individual order information.

# Fields
- `hd::RecordHeader`: Standard record header
- `order_id::UInt64`: Unique order identifier
- `price::Int64`: Order price (scaled by FIXED_PRICE_SCALE)
- `size::UInt32`: Order size/quantity
- `flags::UInt8`: Order flags
- `channel_id::UInt8`: Channel identifier
- `action::Action.T`: Order action (ADD, MODIFY, CANCEL, etc.)
- `side::Side.T`: Order side (BID or ASK)
- `ts_recv::Int64`: Timestamp when message was received
- `ts_in_delta::Int32`: Delta from ts_event to gateway ingestion
- `sequence::UInt32`: Message sequence number
"""
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

"""
    TradeMsg

Trade execution message.

# Fields
- `hd::RecordHeader`: Standard record header
- `price::Int64`: Trade price (scaled by FIXED_PRICE_SCALE)
- `size::UInt32`: Trade size/quantity
- `action::Action.T`: Trade action
- `side::Side.T`: Aggressor side
- `flags::UInt8`: Trade flags
- `depth::UInt8`: Book depth
- `ts_recv::Int64`: Timestamp when message was received
- `ts_in_delta::Int32`: Delta from ts_event to gateway ingestion
- `sequence::UInt32`: Message sequence number
"""
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

"""
    MBP1Msg

Market-by-price message with book depth 1 (top-of-book).

# Fields
- `hd::RecordHeader`: Standard record header
- `price::Int64`: Price level (scaled by FIXED_PRICE_SCALE)
- `size::UInt32`: Size at this price level
- `action::Action.T`: Price level action
- `side::Side.T`: Price level side
- `flags::UInt8`: Message flags
- `depth::UInt8`: Book depth (always 1)
- `ts_recv::Int64`: Timestamp when message was received
- `ts_in_delta::Int32`: Delta from ts_event to gateway ingestion
- `sequence::UInt32`: Message sequence number
- `levels::BidAskPair`: Best bid and ask information
"""
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

"""
    MBP10Msg

Market-by-price message with book depth 10.

# Fields
- `hd::RecordHeader`: Standard record header
- `price::Int64`: Price level (scaled by FIXED_PRICE_SCALE)
- `size::UInt32`: Size at this price level
- `action::Action.T`: Price level action
- `side::Side.T`: Price level side
- `flags::UInt8`: Message flags
- `depth::UInt8`: Book depth (up to 10)
- `ts_recv::Int64`: Timestamp when message was received
- `ts_in_delta::Int32`: Delta from ts_event to gateway ingestion
- `sequence::UInt32`: Message sequence number
- `levels::NTuple{10,BidAskPair}`: Up to 10 levels of bid/ask information
"""
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

"""
    OHLCVMsg

Open, High, Low, Close, Volume (OHLCV) aggregated data message.

# Fields
- `hd::RecordHeader`: Standard record header
- `open::Int64`: Opening price (scaled by FIXED_PRICE_SCALE)
- `high::Int64`: Highest price (scaled by FIXED_PRICE_SCALE)
- `low::Int64`: Lowest price (scaled by FIXED_PRICE_SCALE)
- `close::Int64`: Closing price (scaled by FIXED_PRICE_SCALE)
- `volume::UInt64`: Total volume traded
"""
struct OHLCVMsg
    hd::RecordHeader
    open::Int64
    high::Int64
    low::Int64
    close::Int64
    volume::UInt64
end

"""
    StatusMsg

Exchange status and trading state message.

# Fields
- `hd::RecordHeader`: Standard record header
- `ts_recv::UInt64`: Timestamp when message was received
- `action::UInt16`: Status action code
- `reason::UInt16`: Reason for status change
- `trading_event::UInt16`: Trading event identifier
- `is_trading::UInt8`: Trading state (0=false, 1=true)
- `is_quoting::UInt8`: Quoting state (0=false, 1=true)
- `is_short_sell_restricted::UInt8`: Short sell restriction state (0=false, 1=true)
"""
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

"""
    ImbalanceMsg

Order imbalance information for auction periods.

# Fields
- `hd::RecordHeader`: Standard record header
- `ts_recv::Int64`: Timestamp when message was received
- `ref_price::Int64`: Reference price (scaled by FIXED_PRICE_SCALE)
- `auction_time::UInt64`: Auction time
- `cont_book_clr_price::Int64`: Continuous book clearing price
- `auct_interest_clr_price::Int64`: Auction interest clearing price
- `ssr_filling_price::Int64`: Short sale restriction filling price
- `ind_match_price::Int64`: Indicative match price
- `upper_collar::Int64`: Upper price collar
- `lower_collar::Int64`: Lower price collar
- `paired_qty::UInt32`: Paired quantity
- `total_imbalance_qty::UInt32`: Total imbalance quantity
- `market_imbalance_qty::UInt32`: Market imbalance quantity
- `unpaired_qty::UInt32`: Unpaired quantity
- `auction_type::UInt8`: Type of auction
- `side::Side.T`: Imbalance side
- `auction_status::UInt8`: Auction status
- `freeze_status::UInt8`: Freeze status
- `num_extensions::UInt8`: Number of extensions
- `unpaired_side::UInt8`: Unpaired side
- `significant_imbalance::UInt8`: Significant imbalance indicator
"""
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

"""
    StatMsg

Statistics message containing market statistics and derived data.

# Fields
- `hd::RecordHeader`: Standard record header
- `ts_recv::UInt64`: Timestamp when message was received
- `ts_ref::UInt64`: Reference timestamp
- `price::Int64`: Statistical price (scaled by FIXED_PRICE_SCALE)
- `quantity::Int64`: Statistical quantity (expanded to 64 bits in DBN v3)
- `sequence::UInt32`: Message sequence number
- `ts_in_delta::Int32`: Delta from ts_event to gateway ingestion
- `stat_type::UInt16`: Type of statistic
- `channel_id::UInt16`: Channel identifier (changed to UInt16 to match Rust)
- `update_action::UInt8`: Update action
- `stat_flags::UInt8`: Statistical flags
"""
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

"""
    ErrorMsg

Error message from live gateway.

# Fields
- `hd::RecordHeader`: Standard record header
- `err::String`: Error message text
"""
struct ErrorMsg
    hd::RecordHeader
    err::String
end

"""
    SymbolMappingMsg

Symbol mapping message from live gateway.

# Fields
- `hd::RecordHeader`: Standard record header
- `stype_in::SType.T`: Input symbol type
- `stype_in_symbol::String`: Input symbol string
- `stype_out::SType.T`: Output symbol type
- `stype_out_symbol::String`: Output symbol string
- `start_ts::Int64`: Mapping start timestamp
- `end_ts::Int64`: Mapping end timestamp
"""
struct SymbolMappingMsg
    hd::RecordHeader
    stype_in::SType.T
    stype_in_symbol::String
    stype_out::SType.T
    stype_out_symbol::String
    start_ts::Int64
    end_ts::Int64
end

"""
    SystemMsg

System message from live gateway.

# Fields
- `hd::RecordHeader`: Standard record header
- `msg::String`: System message text
- `code::String`: System message code
"""
struct SystemMsg
    hd::RecordHeader
    msg::String
    code::String
end

"""
    InstrumentDefMsg

Instrument definition message containing detailed information about financial instruments.

# Fields
- `hd::RecordHeader`: Standard record header
- `ts_recv::Int64`: Timestamp when message was received
- `min_price_increment::Int64`: Minimum price increment
- `display_factor::Int64`: Price display factor
- `expiration::Int64`: Expiration timestamp
- `activation::Int64`: Activation timestamp
- `high_limit_price::Int64`: High limit price
- `low_limit_price::Int64`: Low limit price
- `max_price_variation::Int64`: Maximum price variation
- `unit_of_measure_qty::Int64`: Unit of measure quantity
- `min_price_increment_amount::Int64`: Minimum price increment amount
- `price_ratio::Int64`: Price ratio
- `inst_attrib_value::Int32`: Instrument attribute value
- `underlying_id::UInt32`: Underlying instrument ID
- `raw_instrument_id::UInt64`: Raw instrument ID (expanded to 64 bits in DBN v3)
- `market_depth_implied::Int32`: Market depth implied
- `market_depth::Int32`: Market depth
- `market_segment_id::UInt32`: Market segment ID
- `max_trade_vol::UInt32`: Maximum trade volume
- `min_lot_size::Int32`: Minimum lot size
- `min_lot_size_block::Int32`: Minimum lot size block
- `min_lot_size_round_lot::Int32`: Minimum lot size round lot
- `min_trade_vol::UInt32`: Minimum trade volume
- `contract_multiplier::Int32`: Contract multiplier
- `decay_quantity::Int32`: Decay quantity
- `original_contract_size::Int32`: Original contract size
- `appl_id::Int16`: Application ID
- `maturity_year::UInt16`: Maturity year
- `decay_start_date::UInt16`: Decay start date
- `channel_id::UInt8`: Channel ID
- `currency::String`: Currency code
- `settl_currency::String`: Settlement currency
- `secsubtype::String`: Security subtype
- `raw_symbol::String`: Raw symbol
- `group::String`: Group identifier
- `exchange::String`: Exchange identifier
- `asset::String`: Asset identifier (expanded to 11 bytes in DBN v3)
- `cfi::String`: CFI code
- `security_type::String`: Security type
- `unit_of_measure::String`: Unit of measure
- `underlying::String`: Underlying identifier
- `strike_price_currency::String`: Strike price currency
- `instrument_class::InstrumentClass.T`: Instrument class
- `strike_price::Int64`: Strike price
- `match_algorithm::Char`: Match algorithm
- `main_fraction::UInt8`: Main fraction
- `price_display_format::UInt8`: Price display format
- `sub_fraction::UInt8`: Sub fraction
- `underlying_product::UInt8`: Underlying product
- `security_update_action::Char`: Security update action
- `maturity_month::UInt8`: Maturity month
- `maturity_day::UInt8`: Maturity day
- `maturity_week::UInt8`: Maturity week
- `user_defined_instrument::Bool`: User defined instrument flag
- `contract_multiplier_unit::Int8`: Contract multiplier unit
- `flow_schedule_type::Int8`: Flow schedule type
- `tick_rule::UInt8`: Tick rule
- `leg_count::UInt8`: Number of legs (new in DBN v3)
- `leg_index::UInt8`: Leg index (new in DBN v3)
- `leg_instrument_id::UInt32`: Leg instrument ID (new in DBN v3)
- `leg_raw_symbol::String`: Leg raw symbol (new in DBN v3)
- `leg_side::Side.T`: Leg side (new in DBN v3)
- `leg_underlying_id::UInt32`: Leg underlying ID (new in DBN v3)
- `leg_instrument_class::InstrumentClass.T`: Leg instrument class (new in DBN v3)
- `leg_ratio_qty_numerator::UInt32`: Leg ratio quantity numerator (new in DBN v3)
- `leg_ratio_qty_denominator::UInt32`: Leg ratio quantity denominator (new in DBN v3)
- `leg_ratio_price_numerator::UInt32`: Leg ratio price numerator (new in DBN v3)
- `leg_ratio_price_denominator::UInt32`: Leg ratio price denominator (new in DBN v3)
- `leg_price::Int64`: Leg price (new in DBN v3)
- `leg_delta::Int64`: Leg delta (new in DBN v3)
"""
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
    channel_id::UInt16  # uint16_t per Databento docs
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
    leg_count::UInt16  # uint16_t per Databento docs
    leg_index::UInt16  # uint16_t per Databento docs
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

"""
    CMBP1Msg

Consolidated market-by-price message with book depth 1.

# Fields
- `hd::RecordHeader`: Standard record header
- `price::Int64`: Price level (scaled by FIXED_PRICE_SCALE)
- `size::UInt32`: Size at this price level
- `action::Action.T`: Price level action
- `side::Side.T`: Price level side
- `flags::UInt8`: Message flags
- `depth::UInt8`: Book depth (always 1)
- `ts_recv::Int64`: Timestamp when message was received
- `ts_in_delta::Int32`: Delta from ts_event to gateway ingestion
- `sequence::UInt32`: Message sequence number
- `levels::BidAskPair`: Consolidated best bid and ask information
"""
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

"""
    CBBO1sMsg

Consolidated best bid/offer message at 1-second intervals.

# Fields
- `hd::RecordHeader`: Standard record header
- `price::Int64`: Price level (scaled by FIXED_PRICE_SCALE)
- `size::UInt32`: Size at this price level
- `action::Action.T`: Price level action
- `side::Side.T`: Price level side
- `flags::UInt8`: Message flags
- `depth::UInt8`: Book depth
- `ts_recv::Int64`: Timestamp when message was received
- `ts_in_delta::Int32`: Delta from ts_event to gateway ingestion
- `sequence::UInt32`: Message sequence number
- `levels::BidAskPair`: Consolidated BBO information
"""
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

"""
    CBBO1mMsg

Consolidated best bid/offer message at 1-minute intervals.

# Fields
- `hd::RecordHeader`: Standard record header
- `price::Int64`: Price level (scaled by FIXED_PRICE_SCALE)
- `size::UInt32`: Size at this price level
- `action::Action.T`: Price level action
- `side::Side.T`: Price level side
- `flags::UInt8`: Message flags
- `depth::UInt8`: Book depth
- `ts_recv::Int64`: Timestamp when message was received
- `ts_in_delta::Int32`: Delta from ts_event to gateway ingestion
- `sequence::UInt32`: Message sequence number
- `levels::BidAskPair`: Consolidated BBO information
"""
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

"""
    TCBBOMsg

Trade-consolidated best bid/offer message.

# Fields
- `hd::RecordHeader`: Standard record header
- `price::Int64`: Price level (scaled by FIXED_PRICE_SCALE)
- `size::UInt32`: Size at this price level
- `action::Action.T`: Price level action
- `side::Side.T`: Price level side
- `flags::UInt8`: Message flags
- `depth::UInt8`: Book depth
- `ts_recv::Int64`: Timestamp when message was received
- `ts_in_delta::Int32`: Delta from ts_event to gateway ingestion
- `sequence::UInt32`: Message sequence number
- `levels::BidAskPair`: Trade-consolidated BBO information
"""
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

"""
    BBO1sMsg

Best bid/offer message at 1-second intervals.

# Fields
- `hd::RecordHeader`: Standard record header
- `price::Int64`: Price level (scaled by FIXED_PRICE_SCALE)
- `size::UInt32`: Size at this price level
- `action::Action.T`: Price level action
- `side::Side.T`: Price level side
- `flags::UInt8`: Message flags
- `depth::UInt8`: Book depth
- `ts_recv::Int64`: Timestamp when message was received
- `ts_in_delta::Int32`: Delta from ts_event to gateway ingestion
- `sequence::UInt32`: Message sequence number
- `levels::BidAskPair`: BBO information
"""
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

"""
    BBO1mMsg

Best bid/offer message at 1-minute intervals.

# Fields
- `hd::RecordHeader`: Standard record header
- `price::Int64`: Price level (scaled by FIXED_PRICE_SCALE)
- `size::UInt32`: Size at this price level
- `action::Action.T`: Price level action
- `side::Side.T`: Price level side
- `flags::UInt8`: Message flags
- `depth::UInt8`: Book depth
- `ts_recv::Int64`: Timestamp when message was received
- `ts_in_delta::Int32`: Delta from ts_event to gateway ingestion
- `sequence::UInt32`: Message sequence number
- `levels::BidAskPair`: BBO information
"""
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


# StructTypes definitions for JSON serialization
# RecordHeader excludes length field (implementation detail, not semantic data)
StructTypes.StructType(::Type{RecordHeader}) = StructTypes.Struct()
StructTypes.excludes(::Type{RecordHeader}) = (:length,)


StructTypes.StructType(::Type{MBOMsg}) = StructTypes.Struct()
StructTypes.StructType(::Type{TradeMsg}) = StructTypes.Struct()
StructTypes.StructType(::Type{MBP1Msg}) = StructTypes.Struct()
StructTypes.StructType(::Type{MBP10Msg}) = StructTypes.Struct()
StructTypes.StructType(::Type{OHLCVMsg}) = StructTypes.Struct()
StructTypes.StructType(::Type{StatusMsg}) = StructTypes.Struct()
StructTypes.StructType(::Type{ImbalanceMsg}) = StructTypes.Struct()
StructTypes.StructType(::Type{StatMsg}) = StructTypes.Struct()
StructTypes.StructType(::Type{CMBP1Msg}) = StructTypes.Struct()
StructTypes.StructType(::Type{CBBO1sMsg}) = StructTypes.Struct()
StructTypes.StructType(::Type{CBBO1mMsg}) = StructTypes.Struct()
StructTypes.StructType(::Type{TCBBOMsg}) = StructTypes.Struct()
StructTypes.StructType(::Type{BBO1sMsg}) = StructTypes.Struct()
StructTypes.StructType(::Type{BBO1mMsg}) = StructTypes.Struct()
StructTypes.StructType(::Type{ErrorMsg}) = StructTypes.Struct()
StructTypes.StructType(::Type{SymbolMappingMsg}) = StructTypes.Struct()
StructTypes.StructType(::Type{SystemMsg}) = StructTypes.Struct()
StructTypes.StructType(::Type{InstrumentDefMsg}) = StructTypes.Struct()
StructTypes.StructType(::Type{BidAskPair}) = StructTypes.Struct()