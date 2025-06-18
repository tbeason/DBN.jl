"""
Export functionality for converting DBN data to other formats.
"""

using CSV
using JSON3
using Parquet2
using DataFrames

"""
    dbn_to_csv(input_file, output_file)

Convert a DBN file to CSV format.

# Arguments
- `input_file::String`: Path to input DBN file
- `output_file::String`: Path to output CSV file

# Example
```julia
dbn_to_csv("data.dbn", "data.csv")
```
"""
function dbn_to_csv(input_file::String, output_file::String)
    metadata, records = read_dbn_with_metadata(input_file)
    df = records_to_dataframe(records)
    CSV.write(output_file, df)
    return df
end

"""
    dbn_to_json(input_file, output_file; pretty=false)

Convert a DBN file to JSON format.

# Arguments
- `input_file::String`: Path to input DBN file
- `output_file::String`: Path to output JSON file
- `pretty::Bool`: Whether to pretty-print the JSON (default: false)

# Example
```julia
dbn_to_json("data.dbn", "data.json", pretty=true)
```
"""
function dbn_to_json(input_file::String, output_file::String; pretty=false)
    metadata, records = read_dbn_with_metadata(input_file)
    
    # Convert records to JSON-serializable format
    json_records = []
    for record in records
        push!(json_records, record_to_dict(record))
    end
    
    # Create output structure
    output = Dict(
        "metadata" => metadata_to_dict(metadata),
        "records" => json_records
    )
    
    # Write JSON
    if pretty
        JSON3.pretty(open(output_file, "w"), output)
    else
        JSON3.write(output_file, output)
    end
    
    return output
end

"""
    dbn_to_parquet(input_file, output_file)

Convert a DBN file to Parquet format.

# Arguments
- `input_file::String`: Path to input DBN file
- `output_file::String`: Path to output Parquet file

# Example
```julia
dbn_to_parquet("data.dbn", "data.parquet")
```
"""
function dbn_to_parquet(input_file::String, output_file::String)
    metadata, records = read_dbn_with_metadata(input_file)
    df = records_to_dataframe(records)
    Parquet2.writefile(output_file, df)
    return df
end

"""
    records_to_dataframe(records)

Convert DBN records to a DataFrame.
"""
function records_to_dataframe(records::Vector)
    if isempty(records)
        return DataFrame()
    end
    
    # Get the type of the first record to determine schema
    record_type = typeof(records[1])
    
    # Check if all records are the same type
    all_same_type = all(r -> typeof(r) == record_type, records)
    
    if all_same_type
        # Create type-specific conversion
        if record_type <: TradeMsg
            return trades_to_dataframe(convert(Vector{TradeMsg}, records))
        elseif record_type <: MBOMsg
            return mbo_to_dataframe(convert(Vector{MBOMsg}, records))
        elseif record_type <: MBP1Msg
            return mbp1_to_dataframe(convert(Vector{MBP1Msg}, records))
        elseif record_type <: MBP10Msg
            return mbp10_to_dataframe(convert(Vector{MBP10Msg}, records))
        elseif record_type <: OHLCVMsg
            return ohlcv_to_dataframe(convert(Vector{OHLCVMsg}, records))
        elseif record_type <: StatusMsg
            return status_to_dataframe(convert(Vector{StatusMsg}, records))
        elseif record_type <: ImbalanceMsg
            return imbalance_to_dataframe(convert(Vector{ImbalanceMsg}, records))
        elseif record_type <: StatMsg
            return stat_to_dataframe(convert(Vector{StatMsg}, records))
        elseif record_type <: InstrumentDefMsg
            return instrument_def_to_dataframe(convert(Vector{InstrumentDefMsg}, records))
        else
            # For unknown types, use generic mixed approach
            return mixed_records_to_dataframe(records)
        end
    else
        # For mixed record types, create a generic structure
        return mixed_records_to_dataframe(records)
    end
end

function trades_to_dataframe(records::Vector{TradeMsg})
    DataFrame(
        ts_event = [r.hd.ts_event for r in records],
        ts_recv = [r.ts_recv for r in records],
        instrument_id = [r.hd.instrument_id for r in records],
        publisher_id = [r.hd.publisher_id for r in records],
        price = [price_to_float(r.price) for r in records],
        size = [r.size for r in records],
        action = [string(r.action) for r in records],
        side = [string(r.side) for r in records],
        flags = [r.flags for r in records],
        depth = [r.depth for r in records],
        ts_in_delta = [r.ts_in_delta for r in records],
        sequence = [r.sequence for r in records]
    )
end

function mbo_to_dataframe(records::Vector{MBOMsg})
    DataFrame(
        ts_event = [r.hd.ts_event for r in records],
        ts_recv = [r.ts_recv for r in records],
        instrument_id = [r.hd.instrument_id for r in records],
        publisher_id = [r.hd.publisher_id for r in records],
        order_id = [r.order_id for r in records],
        price = [price_to_float(r.price) for r in records],
        size = [r.size for r in records],
        flags = [r.flags for r in records],
        channel_id = [r.channel_id for r in records],
        action = [string(r.action) for r in records],
        side = [string(r.side) for r in records],
        ts_in_delta = [r.ts_in_delta for r in records],
        sequence = [r.sequence for r in records]
    )
end

function mbp1_to_dataframe(records::Vector{MBP1Msg})
    DataFrame(
        ts_event = [r.hd.ts_event for r in records],
        ts_recv = [r.ts_recv for r in records],
        instrument_id = [r.hd.instrument_id for r in records],
        publisher_id = [r.hd.publisher_id for r in records],
        bid_price = [price_to_float(r.bid_px_00) for r in records],
        ask_price = [price_to_float(r.ask_px_00) for r in records],
        bid_size = [r.bid_sz_00 for r in records],
        ask_size = [r.ask_sz_00 for r in records],
        bid_ct = [r.bid_ct_00 for r in records],
        ask_ct = [r.ask_ct_00 for r in records],
        flags = [r.flags for r in records],
        ts_in_delta = [r.ts_in_delta for r in records],
        sequence = [r.sequence for r in records],
        action = [string(r.action) for r in records],
        side = [string(r.side) for r in records]
    )
end

function mbp10_to_dataframe(records::Vector{MBP10Msg})
    # For MBP10, we need to expand the levels
    rows = []
    for record in records
        # Add each level as a separate row
        levels = [
            (record.bid_px_00, record.ask_px_00, record.bid_sz_00, record.ask_sz_00, record.bid_ct_00, record.ask_ct_00),
            (record.bid_px_01, record.ask_px_01, record.bid_sz_01, record.ask_sz_01, record.bid_ct_01, record.ask_ct_01),
            (record.bid_px_02, record.ask_px_02, record.bid_sz_02, record.ask_sz_02, record.bid_ct_02, record.ask_ct_02),
            (record.bid_px_03, record.ask_px_03, record.bid_sz_03, record.ask_sz_03, record.bid_ct_03, record.ask_ct_03),
            (record.bid_px_04, record.ask_px_04, record.bid_sz_04, record.ask_sz_04, record.bid_ct_04, record.ask_ct_04),
            (record.bid_px_05, record.ask_px_05, record.bid_sz_05, record.ask_sz_05, record.bid_ct_05, record.ask_ct_05),
            (record.bid_px_06, record.ask_px_06, record.bid_sz_06, record.ask_sz_06, record.bid_ct_06, record.ask_ct_06),
            (record.bid_px_07, record.ask_px_07, record.bid_sz_07, record.ask_sz_07, record.bid_ct_07, record.ask_ct_07),
            (record.bid_px_08, record.ask_px_08, record.bid_sz_08, record.ask_sz_08, record.bid_ct_08, record.ask_ct_08),
            (record.bid_px_09, record.ask_px_09, record.bid_sz_09, record.ask_sz_09, record.bid_ct_09, record.ask_ct_09)
        ]
        
        for (level, (bid_px, ask_px, bid_sz, ask_sz, bid_ct, ask_ct)) in enumerate(levels)
            push!(rows, (
                ts_event = record.hd.ts_event,
                ts_recv = record.ts_recv,
                instrument_id = record.hd.instrument_id,
                publisher_id = record.hd.publisher_id,
                level = level - 1,  # 0-indexed
                bid_price = price_to_float(bid_px),
                ask_price = price_to_float(ask_px),
                bid_size = bid_sz,
                ask_size = ask_sz,
                bid_ct = bid_ct,
                ask_ct = ask_ct,
                flags = record.flags,
                ts_in_delta = record.ts_in_delta,
                sequence = record.sequence,
                action = string(Action.T(record.action)),
                side = string(record.side)
            ))
        end
    end
    
    return DataFrame(rows)
end

function ohlcv_to_dataframe(records::Vector{OHLCVMsg})
    DataFrame(
        ts_event = [r.hd.ts_event for r in records],
        ts_recv = [r.ts_recv for r in records],
        instrument_id = [r.hd.instrument_id for r in records],
        publisher_id = [r.hd.publisher_id for r in records],
        open = [price_to_float(r.open) for r in records],
        high = [price_to_float(r.high) for r in records],
        low = [price_to_float(r.low) for r in records],
        close = [price_to_float(r.close) for r in records],
        volume = [r.volume for r in records]
    )
end

function status_to_dataframe(records::Vector{StatusMsg})
    DataFrame(
        ts_event = [r.hd.ts_event for r in records],
        ts_recv = [r.ts_recv for r in records],
        instrument_id = [r.hd.instrument_id for r in records],
        publisher_id = [r.hd.publisher_id for r in records],
        ts_in_delta = [r.ts_in_delta for r in records],
        sequence = [r.sequence for r in records],
        action = [string(Action.T(r.action)) for r in records]
    )
end

function imbalance_to_dataframe(records::Vector{ImbalanceMsg})
    DataFrame(
        ts_event = [r.hd.ts_event for r in records],
        ts_recv = [r.ts_recv for r in records],
        instrument_id = [r.hd.instrument_id for r in records],
        publisher_id = [r.hd.publisher_id for r in records],
        ref_price = [price_to_float(r.ref_price) for r in records],
        auction_price = [price_to_float(r.auction_price) for r in records],
        cont_book_clr_price = [price_to_float(r.cont_book_clr_price) for r in records],
        auct_interest_clr_price = [price_to_float(r.auct_interest_clr_price) for r in records],
        paired_qty = [r.paired_qty for r in records],
        total_imbalance_qty = [r.total_imbalance_qty for r in records],
        market_imbalance_qty = [r.market_imbalance_qty for r in records],
        unpaired_qty = [r.unpaired_qty for r in records],
        auction_type = [r.auction_type for r in records],
        side = [string(r.side) for r in records],
        auction_status = [r.auction_status for r in records],
        freeze_status = [r.freeze_status for r in records],
        num_extensions = [r.num_extensions for r in records],
        unpaired_side = [string(r.unpaired_side) for r in records],
        significant_imbalance = [r.significant_imbalance for r in records],
        ts_in_delta = [r.ts_in_delta for r in records],
        sequence = [r.sequence for r in records]
    )
end

function stat_to_dataframe(records::Vector{StatMsg})
    DataFrame(
        ts_event = [r.hd.ts_event for r in records],
        ts_recv = [r.ts_recv for r in records],
        instrument_id = [r.hd.instrument_id for r in records],
        publisher_id = [r.hd.publisher_id for r in records],
        stat_type = [r.stat_type for r in records],
        stat_value = [r.stat_value for r in records],
        flags = [r.flags for r in records],
        ts_in_delta = [r.ts_in_delta for r in records],
        sequence = [r.sequence for r in records]
    )
end

function instrument_def_to_dataframe(records::Vector{InstrumentDefMsg})
    DataFrame(
        ts_event = [r.hd.ts_event for r in records],
        ts_recv = [r.ts_recv for r in records],
        instrument_id = [r.hd.instrument_id for r in records],
        publisher_id = [r.hd.publisher_id for r in records],
        raw_symbol = [strip_nulls(String(r.raw_symbol)) for r in records],
        group = [strip_nulls(String(r.group)) for r in records],
        exchange = [strip_nulls(String(r.exchange)) for r in records],
        asset = [strip_nulls(String(r.asset)) for r in records],
        cfi = [strip_nulls(String(r.cfi)) for r in records],
        security_type = [strip_nulls(String(r.security_type)) for r in records],
        currency = [strip_nulls(String(r.currency)) for r in records],
        instrument_class = [string(r.instrument_class) for r in records],
        strike_price = [price_to_float(r.strike_price) for r in records],
        multiplier = [r.multiplier for r in records],
        expiration = [r.expiration for r in records],
        activation = [r.activation for r in records],
        high_limit_price = [price_to_float(r.high_limit_price) for r in records],
        low_limit_price = [price_to_float(r.low_limit_price) for r in records],
        max_price_variation = [price_to_float(r.max_price_variation) for r in records],
        trading_reference_price = [price_to_float(r.trading_reference_price) for r in records],
        unit_of_measure_qty = [price_to_float(r.unit_of_measure_qty) for r in records],
        min_price_increment = [price_to_float(r.min_price_increment) for r in records],
        min_price_increment_amount = [price_to_float(r.min_price_increment_amount) for r in records],
        price_ratio = [price_to_float(r.price_ratio) for r in records],
        inst_attrib_value = [r.inst_attrib_value for r in records],
        underlying_id = [r.underlying_id for r in records],
        raw_instrument_id = [r.raw_instrument_id for r in records],
        market_depth_implied = [r.market_depth_implied for r in records],
        market_depth = [r.market_depth for r in records],
        market_segment_id = [r.market_segment_id for r in records],
        max_trade_vol = [r.max_trade_vol for r in records],
        min_lot_size = [r.min_lot_size for r in records],
        min_lot_size_block = [r.min_lot_size_block for r in records],
        min_lot_size_round_lot = [r.min_lot_size_round_lot for r in records],
        min_trade_vol = [r.min_trade_vol for r in records],
        contract_multiplier = [r.contract_multiplier for r in records],
        contract_multiplier_unit = [r.contract_multiplier_unit for r in records],
        flow_schedule_type = [r.flow_schedule_type for r in records],
        min_price_increment_portfolio_type = [r.min_price_increment_portfolio_type for r in records],
        user_defined_instrument = [r.user_defined_instrument for r in records],
        trading_reference_date = [r.trading_reference_date for r in records],
        ts_in_delta = [r.ts_in_delta for r in records],
        sequence = [r.sequence for r in records]
    )
end

function mixed_records_to_dataframe(records::Vector)
    # For mixed record types, create a generic structure with common fields
    DataFrame(
        record_type = [string(typeof(r)) for r in records],
        ts_event = [hasproperty(r, :hd) ? r.hd.ts_event : missing for r in records],
        instrument_id = [hasproperty(r, :hd) ? r.hd.instrument_id : missing for r in records],
        publisher_id = [hasproperty(r, :hd) ? r.hd.publisher_id : missing for r in records]
    )
end

"""
    record_to_dict(record)

Convert a DBN record to a dictionary for JSON serialization.
"""
function record_to_dict(record)
    dict = Dict{String, Any}()
    dict["record_type"] = string(typeof(record))
    
    # Use reflection to get all fields
    for field in fieldnames(typeof(record))
        value = getfield(record, field)
        if isa(value, RecordHeader)
            dict[string(field)] = record_header_to_dict(value)
        elseif isa(value, NTuple{N, UInt8} where N)
            # Convert byte arrays to strings
            dict[string(field)] = strip_nulls(String(collect(value)))
        else
            dict[string(field)] = value
        end
    end
    
    return dict
end

function record_header_to_dict(hd::RecordHeader)
    return Dict(
        "length" => hd.length,
        "rtype" => hd.rtype,
        "publisher_id" => hd.publisher_id,
        "instrument_id" => hd.instrument_id,
        "ts_event" => hd.ts_event
    )
end

"""
    metadata_to_dict(metadata)

Convert metadata to a dictionary for JSON serialization.
"""
function metadata_to_dict(metadata::Metadata)
    return Dict(
        "version" => metadata.version,
        "dataset" => metadata.dataset,
        "schema" => string(metadata.schema),
        "start_ts" => metadata.start_ts,
        "end_ts" => metadata.end_ts,
        "limit" => metadata.limit,
        "stype_in" => string(metadata.stype_in),
        "stype_out" => string(metadata.stype_out),
        "ts_out" => metadata.ts_out,
        "symbols" => metadata.symbols,
        "partial" => metadata.partial,
        "not_found" => metadata.not_found,
        "mappings" => metadata.mappings
    )
end

"""
    strip_nulls(s)

Remove null bytes from a string.
"""
function strip_nulls(s::String)
    return replace(s, '\0' => "")
end