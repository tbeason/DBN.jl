"""
Import functionality for converting other formats to DBN.
"""

using JSON3
using Parquet2
using DataFrames
using CSV

"""
    json_to_dbn(input_file, output_file)

Convert a JSON file to DBN format.

# Arguments
- `input_file::String`: Path to input JSON file
- `output_file::String`: Path to output DBN file

# JSON Format
Expects JSON with structure:
```json
{
  "metadata": { ... },
  "records": [ ... ]
}
```

Or JSONL format (one record per line).

# Example
```julia
json_to_dbn("data.json", "data.dbn")
```
"""
function json_to_dbn(input_file::String, output_file::String)
    # Read JSON file
    content = strip(read(input_file, String))
    
    # Try to parse as structured JSON first
    try
        data = JSON3.read(content, Dict{String, Any})
        if haskey(data, "metadata") && haskey(data, "records")
            return structured_json_to_dbn(data, output_file)
        end
    catch e
        @debug "Failed to parse as structured JSON: $e"
    end
    
    # Try JSONL format (one record per line)
    return jsonl_to_dbn(String(content), output_file)
end

"""
    structured_json_to_dbn(data, output_file)

Convert structured JSON (with metadata and records) to DBN.
"""
function structured_json_to_dbn(data::Dict, output_file::String)
    # Parse metadata
    metadata = dict_to_metadata(data["metadata"])
    
    # Parse records
    records = []
    for record_data in data["records"]
        record = parse_json_record(record_data)
        push!(records, record)
    end
    
    # Write DBN file
    write_dbn(output_file, metadata, records)
    return length(records)
end

"""
    jsonl_to_dbn(content, output_file; schema=nothing, dataset="", start_ts=0, end_ts=0)

Convert JSONL content (one record per line) to DBN.
"""
function jsonl_to_dbn(content::String, output_file::String; 
                      schema=nothing, dataset="", start_ts=0, end_ts=0)
    # Check if content is already a complete JSON object
    content = strip(content)
    if startswith(content, "{") && endswith(content, "}")
        try
            data = JSON3.read(content, Dict{String, Any})
            if haskey(data, "metadata") && haskey(data, "records")
                return structured_json_to_dbn(data, output_file)
            end
        catch e
            @debug "Not a structured JSON: $e"
        end
    end
    
    # Split into lines for JSONL processing
    lines = filter(line -> !isempty(strip(line)), split(content, '\n'))
    
    # Parse records
    records = []
    for line in lines
        line = strip(line)
        if isempty(line)
            continue
        end
        try
            # Try to parse each line as a complete JSON record
            record_data = JSON3.read(line, Dict{String, Any})
            record = parse_json_record(JSON3.write(record_data))
            push!(records, record)
        catch e
            @debug "Failed to parse JSON record: $e"
            @debug "Line: $line"
        end
    end
    
    if isempty(records)
        error("No valid records found in JSON input")
    end
    
    # Infer metadata if not provided
    if schema === nothing
        schema = infer_schema_from_records(records)
    end
    
    # Create minimal metadata
    metadata = Metadata(
        UInt8(3),                    # DBN version
        dataset,                     # dataset
        schema,                      # schema
        Int64(start_ts == 0 ? records[1].hd.ts_event : start_ts),  # start_ts
        Int64(end_ts == 0 ? records[end].hd.ts_event : end_ts),    # end_ts
        UInt64(length(records)),     # limit
        SType.RAW_SYMBOL,            # stype_in
        SType.RAW_SYMBOL,            # stype_out
        false,                       # ts_out
        String[],                    # symbols
        String[],                    # partial
        String[],                    # not_found
        Tuple{String, String, Int64, Int64}[]  # mappings
    )
    
    # Write DBN file
    write_dbn(output_file, metadata, records)
    return length(records)
end

"""
    parse_json_record(json_str)

Parse a JSON record string into the appropriate DBN struct.
This reuses the parsing logic from compatibility testing.
"""
function parse_json_record(json_dict::Dict)
    
    # Extract header info
    hd_dict = json_dict["hd"]
    rtype_val = hd_dict["rtype"]
    rtype = rtype_from_value(rtype_val)
    
    # Determine record size
    record_size = get_record_size_for_rtype(rtype)
    length = UInt8(record_size ÷ LENGTH_MULTIPLIER)
    
    # Create RecordHeader
    hd = RecordHeader(
        length,
        rtype,
        UInt16(hd_dict["publisher_id"]),
        UInt32(hd_dict["instrument_id"]),
        parse_timestamp(hd_dict["ts_event"])
    )
    
    # Parse based on record type
    if rtype == RType.MBP_0_MSG
        return TradeMsg(
            hd,
            parse_price(json_dict["price"]),
            UInt32(json_dict["size"]),
            action_from_value(json_dict["action"]),
            side_from_value(json_dict["side"]),
            UInt8(json_dict["flags"]),
            UInt8(json_dict["depth"]),
            parse_timestamp(json_dict["ts_recv"]),
            Int32(json_dict["ts_in_delta"]),
            UInt32(json_dict["sequence"])
        )
    elseif rtype == RType.MBP_1_MSG || rtype == RType.CMBP_1_MSG
        # Parse levels array for MBP-1 messages
        levels_dict = json_dict["levels"][1]  # First level
        levels = BidAskPair(
            parse_price(levels_dict["bid_px"]),
            parse_price(levels_dict["ask_px"]),
            UInt32(levels_dict["bid_sz"]),
            UInt32(levels_dict["ask_sz"]),
            UInt32(get(levels_dict, "bid_ct", get(levels_dict, "bid_pb", 0))),
            UInt32(get(levels_dict, "ask_ct", get(levels_dict, "ask_pb", 0)))
        )
        
        return MBP1Msg(
            hd,
            parse_price(json_dict["price"]),
            UInt32(json_dict["size"]),
            action_from_value(json_dict["action"]),
            side_from_value(json_dict["side"]),
            UInt8(json_dict["flags"]),
            UInt8(get(json_dict, "depth", 0)),
            parse_timestamp(json_dict["ts_recv"]),
            Int32(json_dict["ts_in_delta"]),
            UInt32(get(json_dict, "sequence", 0)),
            levels
        )
    elseif rtype == RType.MBP_10_MSG
        # Parse all 10 levels if available
        levels_array = get(json_dict, "levels", [])
        levels_tuple = create_mbp10_levels(levels_array)
        
        return MBP10Msg(
            hd,
            parse_price(json_dict["price"]),
            UInt32(json_dict["size"]),
            action_from_value(json_dict["action"]),
            side_from_value(json_dict["side"]),
            UInt8(json_dict["flags"]),
            UInt8(json_dict["depth"]),
            parse_timestamp(json_dict["ts_recv"]),
            Int32(json_dict["ts_in_delta"]),
            UInt32(get(json_dict, "sequence", 0)),
            levels_tuple
        )
    elseif rtype == RType.OHLCV_1S_MSG || rtype == RType.OHLCV_1M_MSG || 
           rtype == RType.OHLCV_1H_MSG || rtype == RType.OHLCV_1D_MSG
        return OHLCVMsg(
            hd,
            parse_price(json_dict["open"]),
            parse_price(json_dict["high"]),
            parse_price(json_dict["low"]),
            parse_price(json_dict["close"]),
            UInt64(json_dict["volume"])
        )
    elseif rtype == RType.STATUS_MSG
        return StatusMsg(
            hd,
            parse_timestamp(json_dict["ts_recv"]),
            UInt16(json_dict["action"]),
            UInt16(json_dict["reason"]),
            UInt16(json_dict["trading_event"]),
            parse_char_field(json_dict["is_trading"]),
            parse_char_field(json_dict["is_quoting"]),
            parse_char_field(json_dict["is_short_sell_restricted"])
        )
    elseif rtype == RType.MBO_MSG
        return MBOMsg(
            hd,
            parse_uint64(json_dict["order_id"]),
            parse_price(json_dict["price"]),
            UInt32(json_dict["size"]),
            UInt8(json_dict["flags"]),
            UInt8(json_dict["channel_id"]),
            action_from_value(json_dict["action"]),
            side_from_value(json_dict["side"]),
            parse_timestamp(json_dict["ts_recv"]),
            Int32(json_dict["ts_in_delta"]),
            UInt32(json_dict["sequence"])
        )
    else
        error("Unsupported record type for JSON parsing: $rtype ($(UInt8(rtype)))")
    end
end

"""
    parquet_to_dbn(input_file, output_file; schema=nothing, dataset="")

Convert a Parquet file to DBN format.

# Arguments
- `input_file::String`: Path to input Parquet file
- `output_file::String`: Path to output DBN file
- `schema`: DBN schema (will be inferred if not provided)
- `dataset::String`: Dataset name for metadata

# Example
```julia
parquet_to_dbn("data.parquet", "data.dbn", schema=Schema.TRADES, dataset="XNAS")
```
"""
function parquet_to_dbn(input_file::String, output_file::String; 
                        schema=nothing, dataset="")
    # Read Parquet file
    df = Parquet2.readfile(input_file) |> DataFrame
    
    # Convert DataFrame to records
    records = dataframe_to_records(df, schema)
    
    # Infer schema if not provided
    if schema === nothing
        schema = infer_schema_from_records(records)
    end
    
    # Create metadata
    metadata = create_metadata_from_dataframe(df, schema, dataset)
    
    # Write DBN file
    write_dbn(output_file, metadata, records)
    return length(records)
end

function parse_json_record(json_str::String)
    json_dict = JSON3.read(json_str, Dict{String, Any})
    return parse_json_record(json_dict)
end

"""
    csv_to_dbn(input_file, output_file; schema=nothing, dataset="")

Convert a CSV file to DBN format.

# Arguments
- `input_file::String`: Path to input CSV file
- `output_file::String`: Path to output DBN file
- `schema`: DBN schema (will be inferred if not provided)
- `dataset::String`: Dataset name for metadata

# Example
```julia
csv_to_dbn("data.csv", "data.dbn", schema=Schema.TRADES, dataset="XNAS")
```
"""
function csv_to_dbn(input_file::String, output_file::String; 
                    schema=nothing, dataset="")
    if schema === nothing
        throw(ArgumentError("schema parameter is required for CSV conversion"))
    end
    if isempty(dataset)
        throw(ArgumentError("dataset parameter is required for CSV conversion"))
    end
    
    # Read CSV file
    df = CSV.read(input_file, DataFrame;header=true,truestrings=["true","True","TRUE"], falsestrings=["false","False","FALSE"])
    
    # Convert DataFrame to records
    records = dataframe_to_records(df, schema)
    
    # Create metadata
    metadata = create_metadata_from_dataframe(df, schema, dataset)
    
    # Write DBN file
    write_dbn(output_file, metadata, records)
    return length(records)
end

# Helper functions

function parse_timestamp(ts)
    if isa(ts, String)
        return parse(Int64, ts)
    else
        return Int64(ts)
    end
end

function parse_price(price)
    if isa(price, String)
        return parse(Int64, price)
    else
        return Int64(price)
    end
end

function parse_uint64(val)
    if isa(val, String)
        return parse(UInt64, val)
    else
        return UInt64(val)
    end
end

function parse_char_field(field)
    if isa(field, String) && !isempty(field)
        return UInt8(field[1])
    else
        return UInt8(field)
    end
end

function rtype_from_value(val)
    if isa(val, String)
        return rtype_from_string(val)
    else
        return RType.T(UInt8(val))
    end
end

function rtype_from_string(s::String)
    if s == "MBP_0_MSG"
        return RType.MBP_0_MSG
    elseif s == "MBP_1_MSG"
        return RType.MBP_1_MSG
    elseif s == "MBP_10_MSG"
        return RType.MBP_10_MSG
    elseif s == "MBO_MSG"
        return RType.MBO_MSG
    elseif s == "STATUS_MSG"
        return RType.STATUS_MSG
    elseif s == "OHLCV_1S_MSG"
        return RType.OHLCV_1S_MSG
    elseif s == "OHLCV_1M_MSG"
        return RType.OHLCV_1M_MSG
    elseif s == "OHLCV_1H_MSG"
        return RType.OHLCV_1H_MSG
    elseif s == "OHLCV_1D_MSG"
        return RType.OHLCV_1D_MSG
    elseif s == "INSTRUMENT_DEF_MSG"
        return RType.INSTRUMENT_DEF_MSG
    elseif s == "IMBALANCE_MSG"
        return RType.IMBALANCE_MSG
    elseif s == "ERROR_MSG"
        return RType.ERROR_MSG
    elseif s == "SYMBOL_MAPPING_MSG"
        return RType.SYMBOL_MAPPING_MSG
    elseif s == "SYSTEM_MSG"
        return RType.SYSTEM_MSG
    elseif s == "STAT_MSG"
        return RType.STAT_MSG
    elseif s == "CMBP_1_MSG"
        return RType.CMBP_1_MSG
    elseif s == "CBBO_1S_MSG"
        return RType.CBBO_1S_MSG
    elseif s == "CBBO_1M_MSG"
        return RType.CBBO_1M_MSG
    elseif s == "TCBBO_MSG"
        return RType.TCBBO_MSG
    elseif s == "BBO_1S_MSG"
        return RType.BBO_1S_MSG
    elseif s == "BBO_1M_MSG"
        return RType.BBO_1M_MSG
    else
        error("Unknown record type: $s")
    end
end

function action_from_string(s::AbstractString)
    if s == "A" || s == "ADD"
        return Action.ADD
    elseif s == "C" || s == "CANCEL"
        return Action.CANCEL
    elseif s == "M" || s == "MODIFY"
        return Action.MODIFY
    elseif s == "T" || s == "TRADE"
        return Action.TRADE
    elseif s == "F" || s == "FILL"
        return Action.FILL
    else
        error("Unknown action: $s")
    end
end

function action_from_value(val)
    if isa(val, String)
        return action_from_string(val)
    else
        return Action.T(UInt8(val))
    end
end

function side_from_string(s::AbstractString)
    if s == "A" || s == "ASK"
        return Side.ASK
    elseif s == "B" || s == "BID"
        return Side.BID
    elseif s == "N" || s == "NONE"
        return Side.NONE
    else
        error("Unknown side: $s")
    end
end

function side_from_value(val)
    if isa(val, String)
        return side_from_string(val)
    else
        return Side.T(UInt8(val))
    end
end

function create_mbp10_levels(levels_array)
    # Create 10 levels, padding with zeros if needed
    padded_levels = []
    for i in 1:10
        if i <= length(levels_array)
            level = levels_array[i]
            push!(padded_levels, BidAskPair(
                parse_price(level["bid_px"]),
                parse_price(level["ask_px"]),
                UInt32(level["bid_sz"]),
                UInt32(level["ask_sz"]),
                UInt32(get(level, "bid_ct", get(level, "bid_pb", 0))),
                UInt32(get(level, "ask_ct", get(level, "ask_pb", 0)))
            ))
        else
            push!(padded_levels, BidAskPair(0, 0, 0, 0, 0, 0))
        end
    end
    return tuple(padded_levels...)
end

function get_record_size_for_rtype(rtype::RType.T)
    if rtype == RType.MBP_0_MSG
        return sizeof(TradeMsg)
    elseif rtype == RType.MBP_1_MSG || rtype == RType.CMBP_1_MSG
        return sizeof(MBP1Msg)
    elseif rtype == RType.MBP_10_MSG
        return sizeof(MBP10Msg)
    elseif rtype == RType.MBO_MSG
        return sizeof(MBOMsg)
    elseif rtype == RType.OHLCV_1S_MSG || rtype == RType.OHLCV_1M_MSG || 
           rtype == RType.OHLCV_1H_MSG || rtype == RType.OHLCV_1D_MSG
        return sizeof(OHLCVMsg)
    elseif rtype == RType.STATUS_MSG
        return sizeof(StatusMsg)
    else
        return 0
    end
end

function infer_schema_from_records(records)
    if isempty(records)
        return Schema.MIX
    end
    
    record_type = typeof(records[1])
    if record_type <: TradeMsg
        return Schema.TRADES
    elseif record_type <: MBP1Msg
        return Schema.MBP_1
    elseif record_type <: MBP10Msg
        return Schema.MBP_10
    elseif record_type <: MBOMsg
        return Schema.MBO
    elseif record_type <: OHLCVMsg
        return Schema.OHLCV_1S  # Default to 1S, could be more sophisticated
    elseif record_type <: StatusMsg
        return Schema.STATUS
    else
        return Schema.MIX
    end
end

function dataframe_to_records(df::DataFrame, schema=nothing)
    # Use schema if provided
    if schema == Schema.TRADES
        return dataframe_to_trade_records(df)
    elseif schema == Schema.MBO
        return dataframe_to_mbo_records(df)
    elseif schema in [Schema.MBP_1, Schema.TBBO]
        return dataframe_to_mbp1_records(df)
    elseif schema == Schema.MBP_10
        return dataframe_to_mbp10_records(df)
    elseif schema in [Schema.OHLCV_1S, Schema.OHLCV_1M, Schema.OHLCV_1H, Schema.OHLCV_1D]
        return dataframe_to_ohlcv_records(df)
    end
    
    # Infer record type from DataFrame columns
    col_names = names(df)
    if "order_id" in col_names
        return dataframe_to_mbo_records(df)
    elseif "bid_price" in col_names && "ask_price" in col_names
        if "level" in col_names
            return dataframe_to_mbp10_records(df)
        else
            return dataframe_to_mbp1_records(df)
        end
    elseif "open" in col_names && "high" in col_names && "low" in col_names && "close" in col_names
        return dataframe_to_ohlcv_records(df)
    elseif "price" in col_names && "size" in col_names
        return dataframe_to_trade_records(df)
    else
        error("Cannot infer record type from DataFrame columns: $(col_names)")
    end
end

function dataframe_to_trade_records(df::DataFrame)
    records = TradeMsg[]
    # println(df)
    for row in eachrow(df)
        # println(row)
        # Handle nested column names like "hd.ts_event"
        ts_event = haskey(row, "hd.ts_event") ? row["hd.ts_event"] : get(row, :ts_event, 0)
        publisher_id = haskey(row, "hd.publisher_id") ? row["hd.publisher_id"] : get(row, :publisher_id, 1)
        instrument_id = haskey(row, "hd.instrument_id") ? row["hd.instrument_id"] : get(row, :instrument_id, 0)
        
        hd = RecordHeader(
            UInt8(sizeof(TradeMsg) ÷ LENGTH_MULTIPLIER),
            RType.MBP_0_MSG,
            UInt16(publisher_id),
            UInt32(instrument_id),
            Int64(ts_event)
        )
        
        # Get record fields
        price_val = isa(row.price, String) ? parse(Float64, row.price) : Float64(row.price)
        ts_recv = haskey(row, :ts_recv) ? Int64(row.ts_recv) : Int64(ts_event)
        
        record = TradeMsg(
            hd,
            float_to_price(price_val),
            UInt32(row.size),
            action_from_string(row.action),
            side_from_string(row.side),
            UInt8(get(row, :flags, 0)),
            UInt8(get(row, :depth, 0)),
            ts_recv,
            Int32(get(row, :ts_in_delta, 0)),
            UInt32(get(row, :sequence, 0))
        )
        push!(records, record)
    end
    return records
end

function dataframe_to_mbo_records(df::DataFrame)
    records = MBOMsg[]
    for row in eachrow(df)
        hd = RecordHeader(
            UInt8(sizeof(MBOMsg) ÷ LENGTH_MULTIPLIER),
            RType.MBO_MSG,
            UInt16(get(row, :publisher_id, 1)),
            UInt32(row.instrument_id),
            Int64(row.ts_event)
        )
        
        record = MBOMsg(
            hd,
            UInt64(row.order_id),
            float_to_price(Float64(row.price)),
            UInt32(row.size),
            UInt8(get(row, :flags, 0)),
            UInt8(get(row, :channel_id, 0)),
            action_from_string(string(row.action)),
            side_from_string(string(row.side)),
            Int64(row.ts_recv),
            Int32(get(row, :ts_in_delta, 0)),
            UInt32(get(row, :sequence, 0))
        )
        push!(records, record)
    end
    return records
end

function dataframe_to_ohlcv_records(df::DataFrame)
    records = OHLCVMsg[]
    for row in eachrow(df)
        hd = RecordHeader(
            UInt8(sizeof(OHLCVMsg) ÷ LENGTH_MULTIPLIER),
            RType.OHLCV_1S_MSG,  # Default to 1S
            UInt16(get(row, :publisher_id, 1)),
            UInt32(row.instrument_id),
            Int64(row.ts_event)
        )
        
        record = OHLCVMsg(
            hd,
            float_to_price(Float64(row.open)),
            float_to_price(Float64(row.high)),
            float_to_price(Float64(row.low)),
            float_to_price(Float64(row.close)),
            UInt64(row.volume)
        )
        push!(records, record)
    end
    return records
end

function dataframe_to_mbp1_records(df::DataFrame)
    # Implementation for MBP1 records
    error("MBP1 DataFrame conversion not yet implemented")
end

function dataframe_to_mbp10_records(df::DataFrame)
    # Implementation for MBP10 records  
    error("MBP10 DataFrame conversion not yet implemented")
end

function create_metadata_from_dataframe(df::DataFrame, schema, dataset)
    # Find timestamp column (could be "ts_event" or "hd.ts_event")
    ts_col = if "hd.ts_event" in names(df)
        "hd.ts_event"
    elseif "ts_event" in names(df)
        "ts_event"
    else
        error("No timestamp column found in DataFrame")
    end
    
    start_ts = minimum(df[!, ts_col])
    end_ts = maximum(df[!, ts_col])
    
    return Metadata(
        UInt8(3),                    # DBN version
        dataset,                     # dataset
        schema,                      # schema
        start_ts,                    # start_ts
        end_ts,                      # end_ts
        UInt64(nrow(df)),           # limit
        SType.RAW_SYMBOL,           # stype_in
        SType.RAW_SYMBOL,           # stype_out
        false,                      # ts_out
        String[],                   # symbols
        String[],                   # partial
        String[],                   # not_found
        Tuple{String, String, Int64, Int64}[]  # mappings
    )
end

function dict_to_metadata(dict::Dict)
    return Metadata(
        UInt8(dict["version"]),
        string(dict["dataset"]),
        schema_from_value(dict["schema"]),
        parse_timestamp(dict["start_ts"]),
        parse_timestamp(dict["end_ts"]),
        UInt64(dict["limit"]),
        stype_from_value(dict["stype_in"]),
        stype_from_value(dict["stype_out"]),
        Bool(dict["ts_out"]),
        Vector{String}(dict["symbols"]),
        Vector{String}(dict["partial"]),
        Vector{String}(dict["not_found"]),
        Vector{Tuple{String, String, Int64, Int64}}(dict["mappings"])
    )
end

function schema_from_string(s::String)
    if s == "TRADES"
        return Schema.TRADES
    elseif s == "MBP_1"
        return Schema.MBP_1
    elseif s == "MBP_10"
        return Schema.MBP_10
    elseif s == "MBO"
        return Schema.MBO
    elseif s == "OHLCV_1S"
        return Schema.OHLCV_1S
    elseif s == "STATUS"
        return Schema.STATUS
    else
        return Schema.MIX
    end
end

function stype_from_string(s::String)
    if s == "RAW_SYMBOL"
        return SType.RAW_SYMBOL
    elseif s == "INSTRUMENT_ID"
        return SType.INSTRUMENT_ID
    else
        return SType.RAW_SYMBOL
    end
end

function schema_from_value(val)
    if isa(val, String)
        return schema_from_string(val)
    else
        return Schema.T(UInt16(val))
    end
end

function stype_from_value(val)
    if isa(val, String)
        return stype_from_string(val)
    else
        return SType.T(UInt8(val))
    end
end