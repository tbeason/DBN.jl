# DBN types, enums, and data structures

# Constants
"""The current DBN format version supported by this implementation."""
const DBN_VERSION = 3

"""Fixed-point price scaling factor for converting between integer and float prices."""
const FIXED_PRICE_SCALE = Int32(1_000_000_000)

"""Sentinel value indicating an undefined or missing price."""
const UNDEF_PRICE = typemax(Int64)

"""Sentinel value indicating an undefined or missing order size."""
const UNDEF_ORDER_SIZE = typemax(UInt32)

"""Sentinel value indicating an undefined or missing timestamp."""
const UNDEF_TIMESTAMP = typemax(Int64)

"""Multiplier for converting the length field to bytes in record headers."""
const LENGTH_MULTIPLIER = 4

# Enums using EnumX for better namespace management

"""
    Schema

DBN data schemas representing different types of market data.

# Values
- `MBO`: Market-by-order data
- `MBP_1`: Market-by-price with book depth 1 (TBBO)
- `MBP_10`: Market-by-price with book depth 10
- `TBBO`: Top-of-book bid/offer
- `TRADES`: Trade messages only
- `OHLCV_1S`: OHLCV data at 1-second intervals
- `OHLCV_1M`: OHLCV data at 1-minute intervals
- `OHLCV_1H`: OHLCV data at 1-hour intervals
- `OHLCV_1D`: OHLCV data at 1-day intervals
- `DEFINITION`: Instrument definition data
- `STATISTICS`: Market statistics
- `STATUS`: Exchange status messages
- `IMBALANCE`: Order imbalance data
- `CBBO`: Consolidated best bid/offer
- `CBBO_1S`: Consolidated BBO at 1-second intervals
- `CBBO_1M`: Consolidated BBO at 1-minute intervals
- `CMBP_1`: Consolidated market-by-price depth 1
- `TCBBO`: Trade-consolidated BBO
- `BBO_1S`: BBO at 1-second intervals
- `BBO_1M`: BBO at 1-minute intervals
"""
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
    MIX = 0xFFFF
end

"""
    Compression

Compression algorithms supported for DBN files.

# Values
- `NONE`: No compression
- `ZSTD`: Zstandard compression
"""
@enumx Compression::UInt8 begin
    NONE = 0
    ZSTD = 1
end

"""
    Encoding

Output encoding formats for market data.

# Values
- `DBN`: Databento Binary Encoding
- `CSV`: Comma-separated values
- `JSON`: JavaScript Object Notation
"""
@enumx Encoding::UInt8 begin
    DBN = 0
    CSV = 1
    JSON = 2
end

"""
    SType

Symbol types for identifying instruments in DBN data.

# Values
- `INSTRUMENT_ID`: Numeric instrument identifier
- `RAW_SYMBOL`: Raw symbol string from exchange
- `CONTINUOUS`: Continuous contract symbol
- `PARENT`: Parent symbol for derived instruments
"""
@enumx SType::UInt8 begin
    INSTRUMENT_ID = 0
    RAW_SYMBOL = 1
    CONTINUOUS = 2
    PARENT = 3
end

"""
    RType

Record types for different kinds of market data messages in DBN format.

# Values
- `MBP_0_MSG`: Trades (book depth 0)
- `MBP_1_MSG`: TBBO/MBP-1 (book depth 1)
- `MBP_10_MSG`: MBP-10 (book depth 10)
- `STATUS_MSG`: Exchange status record
- `INSTRUMENT_DEF_MSG`: Instrument definition record
- `IMBALANCE_MSG`: Order imbalance record
- `ERROR_MSG`: Error record from live gateway
- `SYMBOL_MAPPING_MSG`: Symbol mapping record from live gateway
- `SYSTEM_MSG`: Non-error record from live gateway
- `STAT_MSG`: Statistics record from publisher
- `OHLCV_1S_MSG`: OHLCV at 1-second cadence
- `OHLCV_1M_MSG`: OHLCV at 1-minute cadence
- `OHLCV_1H_MSG`: OHLCV at hourly cadence
- `OHLCV_1D_MSG`: OHLCV at daily cadence
- `MBO_MSG`: Market-by-order record
- `CMBP_1_MSG`: Consolidated market-by-price with book depth 1
- `CBBO_1S_MSG`: Consolidated market-by-price with book depth 1 at 1-second cadence
- `CBBO_1M_MSG`: Consolidated market-by-price with book depth 1 at 1-minute cadence
- `TCBBO_MSG`: Consolidated market-by-price with book depth 1 (trades only)
- `BBO_1S_MSG`: Market-by-price with book depth 1 at 1-second cadence
- `BBO_1M_MSG`: Market-by-price with book depth 1 at 1-minute cadence
"""
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

"""
    Action

Market actions that can be applied to orders or trades.

# Values
- `ADD`: Insert a new order into the book
- `MODIFY`: Change an order's price and/or size
- `CANCEL`: Fully or partially cancel an order from the book
- `CLEAR`: Remove all resting orders for the instrument
- `TRADE`: An aggressing order traded. Does not affect the book
- `FILL`: A resting order was filled. Does not affect the book
- `NONE`: No action: does not affect the book, but may carry flags or other information
"""
@enumx Action::UInt8 begin
    ADD = UInt8('A')      # Insert a new order into the book
    MODIFY = UInt8('M')   # Change an order's price and/or size
    CANCEL = UInt8('C')   # Fully or partially cancel an order from the book
    CLEAR = UInt8('R')    # Remove all resting orders for the instrument
    TRADE = UInt8('T')    # An aggressing order traded. Does not affect the book
    FILL = UInt8('F')     # A resting order was filled. Does not affect the book
    NONE = UInt8('N')     # No action: does not affect the book, but may carry flags or other information
end

"""
    Side

Market sides for orders and trades.

# Values
- `ASK`: Ask/offer side (sell orders)
- `BID`: Bid side (buy orders)
- `NONE`: No specific side or not applicable
"""
@enumx Side::UInt8 begin
    ASK = UInt8('A')
    BID = UInt8('B')
    NONE = UInt8('N')
end

"""
    InstrumentClass

Classification of financial instruments.

# Values
- `STOCK`: Equity instruments
- `OPTION`: Option contracts
- `FUTURE`: Futures contracts
- `FX`: Foreign exchange
- `BOND`: Fixed income securities
- `MIXED_SPREAD`: Mixed spread instruments
- `COMMODITY`: Commodity instruments
- `INDEX`: Index instruments
- `CURRENCY`: Currency instruments
- `SWAP`: Swap instruments
- `OTHER`: Other/unknown instrument types
- `UNKNOWN_0`, `UNKNOWN_45`: Numeric fallback values for unknown classes
"""
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

"""
    VersionUpgradePolicy

Encapsulates the version upgrade policy for DBN files.

# Fields
- `upgrade_policy::UInt8`: Policy for handling version upgrades
"""
struct VersionUpgradePolicy
    upgrade_policy::UInt8
end

"""
    DatasetCondition

Conditions and constraints for a dataset.

# Fields
- `last_ts_out::Int64`: Last timestamp output
- `start_ts::Int64`: Dataset start timestamp
- `end_ts::Int64`: Dataset end timestamp
- `limit::UInt64`: Record limit for the dataset
"""
struct DatasetCondition
    last_ts_out::Int64
    start_ts::Int64
    end_ts::Int64
    limit::UInt64
end

"""
    Metadata

Metadata information for a DBN dataset.

# Fields
- `version::UInt8`: DBN format version
- `dataset::String`: Dataset identifier
- `schema::Schema.T`: Data schema type
- `start_ts::Int64`: Start timestamp for the data
- `end_ts::Union{Int64,Nothing}`: End timestamp (can be null)
- `limit::Union{UInt64,Nothing}`: Record count limit (can be null)
- `stype_in::Union{SType.T,Nothing}`: Input symbol type (can be null)
- `stype_out::SType.T`: Output symbol type
- `ts_out::Bool`: Whether timestamps are included in output
- `symbols::Vector{String}`: List of symbols in the dataset
- `partial::Vector{String}`: Partially available symbols
- `not_found::Vector{String}`: Symbols that were not found
- `mappings::Vector{Tuple{String,String,Int64,Int64}}`: Symbol mappings with time ranges
"""
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

"""
    DBNHeader

Complete header information for a DBN file.

# Fields
- `version_upgrade_policy::VersionUpgradePolicy`: Version handling policy
- `dataset_condition::DatasetCondition`: Dataset conditions and constraints
- `metadata::Metadata`: Dataset metadata
"""
struct DBNHeader
    version_upgrade_policy::VersionUpgradePolicy
    dataset_condition::DatasetCondition
    metadata::Metadata
end

"""
    RecordHeader

Standard header present in all DBN record types.

# Fields
- `length::UInt8`: Length of the record in 4-byte units (multiply by LENGTH_MULTIPLIER for bytes)
- `rtype::RType.T`: Record type identifier
- `publisher_id::UInt16`: Publisher/venue identifier
- `instrument_id::UInt32`: Instrument identifier
- `ts_event::Int64`: Event timestamp in nanoseconds since Unix epoch
"""
struct RecordHeader
    length::UInt8
    rtype::RType.T
    publisher_id::UInt16
    instrument_id::UInt32
    ts_event::Int64
end

"""
    record_length_bytes(hd::RecordHeader)

Get the actual record length in bytes from a RecordHeader.
The length field stores 4-byte units, so multiply by LENGTH_MULTIPLIER.
"""
record_length_bytes(hd::RecordHeader) = hd.length * LENGTH_MULTIPLIER

"""
    BidAskPair

Bid and ask price/size information for market data.

# Fields
- `bid_px::Int64`: Bid price (scaled by FIXED_PRICE_SCALE)
- `ask_px::Int64`: Ask price (scaled by FIXED_PRICE_SCALE)
- `bid_sz::UInt32`: Bid size/quantity
- `ask_sz::UInt32`: Ask size/quantity
- `bid_ct::UInt32`: Number of bid orders
- `ask_ct::UInt32`: Number of ask orders
"""
struct BidAskPair
    bid_px::Int64
    ask_px::Int64
    bid_sz::UInt32
    ask_sz::UInt32
    bid_ct::UInt32
    ask_ct::UInt32
end

# Timestamp utilities

"""
    DBNTimestamp

High-precision timestamp representation with nanosecond accuracy.

# Fields
- `seconds::Int64`: Unix epoch seconds
- `nanoseconds::Int32`: Nanoseconds within the second (0-999_999_999)
"""
struct DBNTimestamp
    seconds::Int64      # Unix epoch seconds
    nanoseconds::Int32  # Nanoseconds within the second (0-999_999_999)
end

"""
    DBNTimestamp(ns::Int64)

Construct a DBNTimestamp from nanoseconds since Unix epoch.

# Arguments
- `ns::Int64`: Nanoseconds since Unix epoch

# Returns
- `DBNTimestamp`: Timestamp split into seconds and nanoseconds components
"""
function DBNTimestamp(ns::Int64)
    if ns == UNDEF_TIMESTAMP
        return DBNTimestamp(UNDEF_TIMESTAMP, 0)
    end
    seconds = ns ÷ 1_000_000_000
    nanoseconds = Int32(ns % 1_000_000_000)
    return DBNTimestamp(seconds, nanoseconds)
end

"""
    to_nanoseconds(ts::DBNTimestamp)

Convert a DBNTimestamp back to nanoseconds since Unix epoch.

# Arguments
- `ts::DBNTimestamp`: Timestamp to convert

# Returns
- `Int64`: Nanoseconds since Unix epoch, or UNDEF_TIMESTAMP if undefined
"""
function to_nanoseconds(ts::DBNTimestamp)
    if ts.seconds == UNDEF_TIMESTAMP
        return UNDEF_TIMESTAMP
    end
    return ts.seconds * 1_000_000_000 + ts.nanoseconds
end

"""
    ts_to_datetime(ts::Int64)

Convert a nanosecond timestamp to DateTime with nanosecond precision information.

# Arguments
- `ts::Int64`: Nanoseconds since Unix epoch

# Returns
- `NamedTuple`: Contains `datetime` (DateTime) and `nanoseconds` (Int32), or `nothing` if undefined
"""
function ts_to_datetime(ts::Int64)
    if ts == UNDEF_TIMESTAMP
        return nothing
    end
    # Returns DateTime with millisecond precision and separate nanosecond component
    dbn_ts = DBNTimestamp(ts)
    dt = unix2datetime(Float64(dbn_ts.seconds) + dbn_ts.nanoseconds / 1_000_000_000)
    return (datetime=dt, nanoseconds=dbn_ts.nanoseconds)
end

"""
    datetime_to_ts(dt::DateTime, nanoseconds::Int32=0)

Convert a DateTime with optional nanosecond precision to nanosecond timestamp.

# Arguments
- `dt::DateTime`: DateTime to convert
- `nanoseconds::Int32`: Additional nanoseconds within the second (default: 0)

# Returns
- `Int64`: Nanoseconds since Unix epoch
"""
function datetime_to_ts(dt::DateTime, nanoseconds::Union{Int32,Int64}=0)
    # Convert DateTime to nanoseconds, preserving additional precision
    seconds = Int64(round(datetime2unix(dt)))
    return seconds * 1_000_000_000 + nanoseconds
end

"""
    ts_to_date_time(ts::Int64)

Convert a nanosecond timestamp to separate Date and Time components with full nanosecond precision.

# Arguments
- `ts::Int64`: Nanoseconds since Unix epoch

# Returns
- `NamedTuple`: Contains `date` (Date), `time` (Time), and `timestamp` (DBNTimestamp), or `nothing` if undefined
"""
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

"""
    date_time_to_ts(date::Date, time::Dates.Time)

Convert separate Date and Time components to nanosecond timestamp.

# Arguments
- `date::Date`: Date component
- `time::Dates.Time`: Time component with nanosecond precision

# Returns
- `Int64`: Nanoseconds since Unix epoch
"""
function date_time_to_ts(date::Date, time::Dates.Time)
    # Convert date to seconds since epoch
    dt = DateTime(date)
    date_seconds = Int64(round(datetime2unix(dt)))
    
    # Extract nanoseconds from time
    time_ns = Dates.value(time)  # Total nanoseconds since midnight
    
    return date_seconds * 1_000_000_000 + time_ns
end

# Price conversion utilities

"""
    price_to_float(price::Int64, scale::Int32=FIXED_PRICE_SCALE)

Convert a fixed-point price to floating-point representation.

# Arguments
- `price::Int64`: Fixed-point price value
- `scale::Int32`: Scaling factor (default: FIXED_PRICE_SCALE)

# Returns
- `Float64`: Floating-point price, or NaN if price is UNDEF_PRICE
"""
function price_to_float(price::Int64, scale::Int32=FIXED_PRICE_SCALE)
    if price == UNDEF_PRICE
        return NaN
    end
    return Float64(price) / Float64(scale)
end

"""
    float_to_price(value::Float64, scale::Int32=FIXED_PRICE_SCALE)

Convert a floating-point price to fixed-point representation.

# Arguments
- `value::Float64`: Floating-point price
- `scale::Int32`: Scaling factor (default: FIXED_PRICE_SCALE)

# Returns
- `Int64`: Fixed-point price, or UNDEF_PRICE if value is NaN or infinite
"""
function float_to_price(value::Float64, scale::Int32=FIXED_PRICE_SCALE)
    if isnan(value) || isinf(value)
        return UNDEF_PRICE
    end
    return Int64(round(value * Float64(scale)))
end

# Helper functions for safe enum conversion

"""
    safe_action(raw_val::UInt8)

Safely convert a raw byte value to an Action enum, with fallback handling.

# Arguments
- `raw_val::UInt8`: Raw action value from DBN data

# Returns
- `Action.T`: Corresponding Action enum value, or Action.TRADE as fallback
"""
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

"""
    safe_side(raw_val::UInt8)

Safely convert a raw byte value to a Side enum, with fallback handling.

# Arguments
- `raw_val::UInt8`: Raw side value from DBN data

# Returns
- `Side.T`: Corresponding Side enum value, or Side.NONE as fallback
"""
function safe_side(raw_val::UInt8)
    try
        return Side.T(raw_val)
    catch ArgumentError
        @warn "Unknown Side value: $raw_val, using NONE as default"
        return Side.NONE
    end
end

"""
    safe_instrument_class(raw_val::UInt8)

Safely convert a raw byte value to an InstrumentClass enum, with fallback handling.

# Arguments
- `raw_val::UInt8`: Raw instrument class value from DBN data

# Returns
- `InstrumentClass.T`: Corresponding InstrumentClass enum value, or InstrumentClass.OTHER as fallback
"""
function safe_instrument_class(raw_val::UInt8)
    try
        return InstrumentClass.T(raw_val)
    catch ArgumentError
        @warn "Unknown InstrumentClass value: $raw_val, using OTHER as default"
        return InstrumentClass.OTHER
    end
end