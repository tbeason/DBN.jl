# DBN message type definitions

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