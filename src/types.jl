# DBN types, enums, and data structures

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

# Basic structures
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

struct BidAskPair
    bid_px::Int64
    ask_px::Int64
    bid_sz::UInt32
    ask_sz::UInt32
    bid_ct::UInt32
    ask_ct::UInt32
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

# Helper functions for safe enum conversion
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