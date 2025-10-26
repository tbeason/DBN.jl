module CompatibilityUtils

using DBN
using Test
using JSON3
using StructTypes
using DataFrames
using CSV: CSV
using Dates

# Path to the Rust DBN CLI executable (cross-platform)
const DBN_CLI_PATH = if Sys.iswindows()
    joinpath(homedir(), "dbn-workspace", "dbn", "target", "release", "dbn.exe")
else
    joinpath(homedir(), "dbn-workspace", "dbn", "target", "release", "dbn")
end

# Path to test data directory (cross-platform)
const TEST_DATA_DIR = joinpath(homedir(), "dbn-workspace", "dbn", "tests", "data")

"""
    run_dbn_cli(args::Vector{String})

Run the DBN CLI with the given arguments and return the output.
"""
function run_dbn_cli(args::Vector{String})
    if !isfile(DBN_CLI_PATH)
        error("DBN CLI not found at $DBN_CLI_PATH. Please build the Rust implementation first.")
    end
    
    cmd = Cmd([DBN_CLI_PATH; args])
    try
        output = read(cmd, String)
        return output
    catch e
        if isa(e, Base.IOError)
            error("Failed to run DBN CLI: $(e.msg)")
        else
            rethrow(e)
        end
    end
end

"""
    compare_binary_files(file1::String, file2::String)

Compare two files byte-for-byte.
"""
function compare_binary_files(file1::String, file2::String)
    if !isfile(file1) || !isfile(file2)
        return false
    end
    
    content1 = read(file1)
    content2 = read(file2)
    
    return content1 == content2
end

"""
    compare_json_output(julia_output::String, rust_output::String; tolerance=1e-9)

Compare JSON outputs from Julia and Rust implementations, allowing for floating-point tolerance.
"""
function compare_json_output(julia_output::String, rust_output::String; tolerance=1e-9)
    # Parse JSON lines
    julia_lines = filter(!isempty, split(julia_output, '\n'))
    rust_lines = filter(!isempty, split(rust_output, '\n'))
    
    if length(julia_lines) != length(rust_lines)
        @warn "Different number of records: Julia=$(length(julia_lines)), Rust=$(length(rust_lines))"
        return false
    end
    
    for (i, (jl_line, rs_line)) in enumerate(zip(julia_lines, rust_lines))
        jl_obj = JSON3.read(jl_line)
        rs_obj = JSON3.read(rs_line)
        
        if !compare_json_objects(jl_obj, rs_obj, tolerance)
            @warn "Mismatch at record $i"
            @warn "Julia: $jl_line"
            @warn "Rust: $rs_line"
            return false
        end
    end
    
    return true
end

"""
    compare_json_objects(obj1, obj2, tolerance)

Recursively compare two JSON objects with floating-point tolerance.
"""
function compare_json_objects(obj1, obj2, tolerance)
    if typeof(obj1) != typeof(obj2)
        return false
    end
    
    if isa(obj1, Dict)
        if keys(obj1) != keys(obj2)
            return false
        end
        for key in keys(obj1)
            if !compare_json_objects(obj1[key], obj2[key], tolerance)
                return false
            end
        end
        return true
    elseif isa(obj1, Array)
        if length(obj1) != length(obj2)
            return false
        end
        for (v1, v2) in zip(obj1, obj2)
            if !compare_json_objects(v1, v2, tolerance)
                return false
            end
        end
        return true
    elseif isa(obj1, Number) && isa(obj2, Number)
        return abs(obj1 - obj2) <= tolerance
    else
        return obj1 == obj2
    end
end

"""
    compare_csv_output(julia_output::String, rust_output::String; tolerance=1e-9)

Compare CSV outputs from Julia and Rust implementations.
"""
function compare_csv_output(julia_output::String, rust_output::String; tolerance=1e-9)
    # Read CSV data
    julia_df = CSV.read(IOBuffer(julia_output), DataFrame)
    rust_df = CSV.read(IOBuffer(rust_output), DataFrame)
    
    # Check dimensions
    if size(julia_df) != size(rust_df)
        @warn "Different dimensions: Julia=$(size(julia_df)), Rust=$(size(rust_df))"
        return false
    end
    
    # Check column names
    if names(julia_df) != names(rust_df)
        @warn "Different column names: Julia=$(names(julia_df)), Rust=$(names(rust_df))"
        return false
    end
    
    # Compare values
    for col in names(julia_df)
        julia_col = julia_df[!, col]
        rust_col = rust_df[!, col]
        
        for (i, (jv, rv)) in enumerate(zip(julia_col, rust_col))
            if isa(jv, Number) && isa(rv, Number)
                if abs(jv - rv) > tolerance
                    @warn "Mismatch in column $col, row $i: Julia=$jv, Rust=$rv"
                    return false
                end
            elseif jv != rv
                @warn "Mismatch in column $col, row $i: Julia=$jv, Rust=$rv"
                return false
            end
        end
    end
    
    return true
end

"""
    test_round_trip(test_file::String, output_dir::String)

Test round-trip compatibility: Julia reads → writes → Rust reads → validates.
"""
function test_round_trip(test_file::String, output_dir::String)
    mkpath(output_dir)
    
    # Read with Julia
    metadata, records = DBN.read_dbn_with_metadata(test_file)
    
    # Write with Julia
    julia_output = joinpath(output_dir, "julia_output.dbn")
    DBN.write_dbn(julia_output, metadata, records)
    
    # Read with Rust and convert to JSON
    rust_json = run_dbn_cli([julia_output, "--json"])
    
    # Parse Rust JSON back into Julia objects and compare
    rust_lines = filter(!isempty, split(rust_json, '\n'))
    
    if length(rust_lines) != length(records)
        @warn "Different number of records: Julia=$(length(records)), Rust=$(length(rust_lines))"
        return false
    end
    
    # Compare each record
    for (i, (julia_record, rust_line)) in enumerate(zip(records, rust_lines))
        try
            # Parse Rust JSON back to Julia struct
            rust_record = parse_rust_json_record(rust_line)
            
            # Compare the actual structs (excluding the length field which Rust doesn't serialize)
            if !records_equal(julia_record, rust_record)
                @warn "Mismatch at record $i"
                return false
            end
        catch e
            @warn "Failed to parse Rust JSON at record $i: $e"
            return false
        end
    end
    
    return true
end

"""
    test_file_compatibility(test_file::String)

Test that Julia can correctly read a file and produce the same output as Rust.
"""
function test_file_compatibility(test_file::String)
    # Read with Rust and convert to JSON
    rust_json = run_dbn_cli([test_file, "--json"])
    
    # Read with Julia
    metadata, julia_records = DBN.read_dbn_with_metadata(test_file)
    
    # Parse Rust JSON and compare with Julia records
    rust_lines = filter(!isempty, split(rust_json, '\n'))
    
    if length(rust_lines) != length(julia_records)
        @warn "Different number of records: Julia=$(length(julia_records)), Rust=$(length(rust_lines))"
        return false
    end
    
    # Compare each record by parsing Rust JSON back to Julia structs
    for (i, (julia_record, rust_line)) in enumerate(zip(julia_records, rust_lines))
        try
            # Parse Rust JSON back to Julia struct
            @debug "About to call parse_rust_json_record with line $i"
            # Use invokelatest to handle world age issues
            rust_record = Base.invokelatest(parse_rust_json_record, rust_line)
            @debug "Successfully parsed record $i"
            
            # Compare the actual structs
            if !records_equal(julia_record, rust_record)
                @warn "Mismatch at record $i"
                # Debug output
                @warn "Julia record: $julia_record"
                @warn "Rust JSON: $rust_line"
                return false
            end
        catch e
            @warn "Failed to parse Rust JSON at record $i: $e"
            @warn "Rust JSON: $rust_line"
            return false
        end
    end
    
    return true
end

"""
    benchmark_read_performance(test_file::String; iterations=10)

Benchmark read performance between Julia and Rust implementations.
"""
function benchmark_read_performance(test_file::String; iterations=10)
    # Julia benchmark
    julia_times = Float64[]
    for _ in 1:iterations
        t = @elapsed DBN.read_dbn(test_file)
        push!(julia_times, t)
    end
    julia_avg = mean(julia_times)
    
    # Rust benchmark (convert to JSON to force full read)
    rust_times = Float64[]
    for _ in 1:iterations
        t = @elapsed run_dbn_cli([test_file, "--json", "-o", "/dev/null"])
        push!(rust_times, t)
    end
    rust_avg = mean(rust_times)
    
    return (julia=julia_avg, rust=rust_avg, ratio=julia_avg/rust_avg)
end

"""
    get_test_files(pattern::String="*.dbn")

Get all test DBN files matching the pattern.
"""
function get_test_files(pattern::String="*.dbn")
    if !isdir(TEST_DATA_DIR)
        error("Test data directory not found: $TEST_DATA_DIR")
    end

    files = String[]
    for (root, dirs, filenames) in walkdir(TEST_DATA_DIR)
        for filename in filenames
            # Convert glob pattern to regex
            pattern_regex = replace(pattern, "*" => ".*")
            if occursin(Regex(pattern_regex), filename)
                push!(files, joinpath(root, filename))
            end
        end
    end
    
    return sort(files)
end

# Helper function for mean calculation
mean(x) = sum(x) / length(x)

# Helper function to safely parse Int64 fields that may contain UInt64::max sentinel values
function safe_parse_int64(s::String)
    try
        return parse(Int64, s)
    catch OverflowError
        # Rust uses UInt64::max (18446744073709551615) as UNDEF_TIMESTAMP sentinel
        # When read as UInt64 and reinterpreted as Int64, this becomes -1
        # So we convert to -1 to match the binary representation
        return Int64(-1)
    end
end

function parse_bool_from_json(value)
    if isa(value, Bool)
        return value
    elseif isa(value, String)
        # Handle string representations: "Y"/"N", "true"/"false", or single-byte char
        if value == "Y" || value == "y" || value == "true"
            return true
        elseif value == "N" || value == "n" || value == "false"
            return false
        else
            # Convert string to UInt8 and check if non-zero
            byte_val = UInt8(value[1])
            return byte_val != 0x00
        end
    else
        # For numeric types, convert to bool (non-zero = true)
        return value != 0
    end
end

# Helper function to create MBP10 levels tuple
function create_mbp10_levels_from_json(json_levels::Vector)
    return ntuple(10) do i
        if i <= length(json_levels)
            level_dict = json_levels[i]
            DBN.BidAskPair(
                parse(Int64, level_dict["bid_px"]),
                parse(Int64, level_dict["ask_px"]),
                UInt32(level_dict["bid_sz"]),
                UInt32(level_dict["ask_sz"]),
                UInt32(get(level_dict, "bid_ct", 0)),
                UInt32(get(level_dict, "ask_ct", 0))
            )
        else
            DBN.BidAskPair(0, 0, 0, 0, 0, 0)
        end
    end
end

"""
    records_equal(r1, r2)

Compare two records for equality, ignoring the length field in RecordHeader.
"""
function records_equal(r1, r2)
    # If they're not the same type, they're not equal
    if typeof(r1) != typeof(r2)
        return false
    end
    
    # Compare all fields except for the header length
    for field in fieldnames(typeof(r1))
        if field == :hd
            # For header, compare all fields except length
            hd1, hd2 = getfield(r1, :hd), getfield(r2, :hd)
            for hd_field in fieldnames(typeof(hd1))
                if hd_field != :length  # Skip length field
                    if getfield(hd1, hd_field) != getfield(hd2, hd_field)
                        return false
                    end
                end
            end
        else
            # For other fields, direct comparison
            if getfield(r1, field) != getfield(r2, field)
                return false
            end
        end
    end
    
    return true
end

"""
    parse_rust_json_record(rust_json_str::String)

Parse a Rust DBN JSON record into the appropriate Julia struct.
"""
function parse_rust_json_record(rust_json_str)
    @debug "parse_rust_json_record called with input of type $(typeof(rust_json_str))"
    # Convert to string if needed and parse the JSON into a dictionary
    json_str = String(rust_json_str)
    json_dict = JSON3.read(json_str, Dict{String, Any})
    
    # Extract header info
    hd_dict = json_dict["hd"]
    rtype_val = hd_dict["rtype"]
    rtype = DBN.RType.T(rtype_val)
    
    # Determine record type and size
    # Note: record_size is the body size (sizeof struct excluding header)
    # The length field in the binary includes both header (16 bytes) and body
    record_body_size = get_record_size_for_rtype(rtype)
    total_record_size = record_body_size + 16  # Add header size
    length = UInt8(total_record_size ÷ DBN.LENGTH_MULTIPLIER)
    
    # Create RecordHeader
    hd = DBN.RecordHeader(
        length,
        rtype,
        UInt16(hd_dict["publisher_id"]),
        UInt32(hd_dict["instrument_id"]),
        parse(UInt64, hd_dict["ts_event"])  # ts_event is string in Rust JSON
    )
    
    # Parse based on record type
    if rtype == DBN.RType.MBP_0_MSG
        return DBN.TradeMsg(
            hd,
            parse(Int64, json_dict["price"]),  # Price is string in Rust JSON
            UInt32(json_dict["size"]),
            action_from_string(json_dict["action"]),
            side_from_string(json_dict["side"]),
            UInt8(json_dict["flags"]),
            UInt8(json_dict["depth"]),
            parse(Int64, json_dict["ts_recv"]),  # ts_recv is string in Rust JSON
            Int32(json_dict["ts_in_delta"]),
            UInt32(json_dict["sequence"])
        )
    elseif rtype == DBN.RType.MBP_1_MSG
        # Parse levels array for MBP-1 messages
        levels_dict = json_dict["levels"][1]  # First level for MBP-1
        levels = DBN.BidAskPair(
            parse(Int64, levels_dict["bid_px"]),
            parse(Int64, levels_dict["ask_px"]),
            UInt32(levels_dict["bid_sz"]),
            UInt32(levels_dict["ask_sz"]),
            UInt32(get(levels_dict, "bid_ct", 0)),
            UInt32(get(levels_dict, "ask_ct", 0))
        )

        return DBN.MBP1Msg(
            hd,
            parse(Int64, json_dict["price"]),
            UInt32(json_dict["size"]),
            action_from_string(json_dict["action"]),
            side_from_string(json_dict["side"]),
            UInt8(json_dict["flags"]),
            UInt8(get(json_dict, "depth", 0)),  # Default depth to 0 if missing
            parse(Int64, json_dict["ts_recv"]),
            Int32(json_dict["ts_in_delta"]),
            UInt32(get(json_dict, "sequence", 0)),  # Default sequence to 0 if missing
            levels
        )
    elseif rtype == DBN.RType.CMBP_1_MSG
        # Parse levels array for CMBP-1 messages (consolidated market-by-price)
        levels_dict = json_dict["levels"][1]  # First level
        levels = DBN.BidAskPair(
            parse(Int64, levels_dict["bid_px"]),
            parse(Int64, levels_dict["ask_px"]),
            UInt32(levels_dict["bid_sz"]),
            UInt32(levels_dict["ask_sz"]),
            # CMBP uses bid_pb/ask_pb (publisher count) instead of bid_ct/ask_ct
            UInt32(get(levels_dict, "bid_pb", 0)),
            UInt32(get(levels_dict, "ask_pb", 0))
        )

        return DBN.CMBP1Msg(
            hd,
            parse(Int64, json_dict["price"]),
            UInt32(json_dict["size"]),
            action_from_string(json_dict["action"]),
            side_from_string(json_dict["side"]),
            UInt8(json_dict["flags"]),
            UInt8(get(json_dict, "depth", 0)),  # Default depth to 0 if missing
            parse(Int64, json_dict["ts_recv"]),
            Int32(json_dict["ts_in_delta"]),
            UInt32(get(json_dict, "sequence", 0)),  # Default sequence to 0 if missing (CMBP may not have sequence)
            levels
        )
    elseif rtype == DBN.RType.MBP_10_MSG
        # Parse all 10 levels from the JSON
        json_levels = get(json_dict, "levels", [])

        # Use helper function to avoid world age issues
        levels = create_mbp10_levels_from_json(json_levels)

        return DBN.MBP10Msg(
            hd,
            parse(Int64, json_dict["price"]),
            UInt32(json_dict["size"]),
            action_from_string(json_dict["action"]),
            side_from_string(json_dict["side"]),
            UInt8(json_dict["flags"]),
            UInt8(json_dict["depth"]),
            parse(Int64, json_dict["ts_recv"]),
            Int32(json_dict["ts_in_delta"]),
            UInt32(get(json_dict, "sequence", 0)),  # Default sequence to 0 if missing
            levels
        )
    elseif rtype == DBN.RType.MBO_MSG
        return DBN.MBOMsg(
            hd,
            parse(UInt64, json_dict["order_id"]),
            parse(Int64, json_dict["price"]),
            UInt32(json_dict["size"]),
            UInt8(json_dict["flags"]),
            UInt16(json_dict["channel_id"]),
            action_from_string(json_dict["action"]),
            side_from_string(json_dict["side"]),
            parse(Int64, json_dict["ts_recv"]),
            Int32(json_dict["ts_in_delta"]),
            UInt32(json_dict["sequence"])
        )
    elseif rtype == DBN.RType.OHLCV_1S_MSG || rtype == DBN.RType.OHLCV_1M_MSG || 
           rtype == DBN.RType.OHLCV_1H_MSG || rtype == DBN.RType.OHLCV_1D_MSG
        return DBN.OHLCVMsg(
            hd,
            parse(Int64, json_dict["open"]),
            parse(Int64, json_dict["high"]),
            parse(Int64, json_dict["low"]),
            parse(Int64, json_dict["close"]),
            parse(UInt64, json_dict["volume"])
        )
    elseif rtype == DBN.RType.STATUS_MSG
        # Parse all StatusMsg fields
        return DBN.StatusMsg(
            hd,
            parse(UInt64, json_dict["ts_recv"]),
            UInt16(json_dict["action"]),
            UInt16(json_dict["reason"]),
            UInt16(json_dict["trading_event"]),
            UInt8(json_dict["is_trading"][1]),  # Convert single char to UInt8
            UInt8(json_dict["is_quoting"][1]),  # Convert single char to UInt8
            UInt8(json_dict["is_short_sell_restricted"][1])  # Convert single char to UInt8
        )
    elseif rtype == DBN.RType.INSTRUMENT_DEF_MSG
        # Parse InstrumentDefMsg - this is complex, so we'll parse the key fields
        # Note: Many fields may be missing or default in JSON output
        return DBN.InstrumentDefMsg(
            hd,
            safe_parse_int64(get(json_dict, "ts_recv", "0")),
            safe_parse_int64(get(json_dict, "min_price_increment", "0")),
            safe_parse_int64(get(json_dict, "display_factor", "0")),
            safe_parse_int64(get(json_dict, "expiration", "0")),
            safe_parse_int64(get(json_dict, "activation", "0")),
            safe_parse_int64(get(json_dict, "high_limit_price", "0")),
            safe_parse_int64(get(json_dict, "low_limit_price", "0")),
            safe_parse_int64(get(json_dict, "max_price_variation", "0")),
            safe_parse_int64(get(json_dict, "trading_reference_price", "0")),  # v2 only
            safe_parse_int64(get(json_dict, "unit_of_measure_qty", "0")),
            safe_parse_int64(get(json_dict, "min_price_increment_amount", "0")),
            safe_parse_int64(get(json_dict, "price_ratio", "0")),
            Int32(get(json_dict, "inst_attrib_value", 0)),
            UInt32(get(json_dict, "underlying_id", 0)),
            UInt64(get(json_dict, "raw_instrument_id", 0)),
            Int32(get(json_dict, "market_depth_implied", 0)),
            Int32(get(json_dict, "market_depth", 0)),
            UInt32(get(json_dict, "market_segment_id", 0)),
            UInt32(get(json_dict, "max_trade_vol", 0)),
            Int32(get(json_dict, "min_lot_size", 0)),
            Int32(get(json_dict, "min_lot_size_block", 0)),
            Int32(get(json_dict, "min_lot_size_round_lot", 0)),
            UInt32(get(json_dict, "min_trade_vol", 0)),
            Int32(get(json_dict, "contract_multiplier", 0)),
            Int32(get(json_dict, "decay_quantity", 0)),
            Int32(get(json_dict, "original_contract_size", 0)),
            UInt16(get(json_dict, "trading_reference_date", 0)),  # v2 only
            Int16(get(json_dict, "appl_id", 0)),
            UInt16(get(json_dict, "maturity_year", 0)),
            UInt16(get(json_dict, "decay_start_date", 0)),
            UInt16(get(json_dict, "channel_id", 0)),
            String(get(json_dict, "currency", "")),
            String(get(json_dict, "settl_currency", "")),
            String(get(json_dict, "secsubtype", "")),
            String(get(json_dict, "raw_symbol", "")),
            String(get(json_dict, "group", "")),
            String(get(json_dict, "exchange", "")),
            String(get(json_dict, "asset", "")),
            String(get(json_dict, "cfi", "")),
            String(get(json_dict, "security_type", "")),
            String(get(json_dict, "unit_of_measure", "")),
            String(get(json_dict, "underlying", "")),
            String(get(json_dict, "strike_price_currency", "")),
            haskey(json_dict, "instrument_class") ? DBN.safe_instrument_class(UInt8(json_dict["instrument_class"][1])) : DBN.InstrumentClass.OTHER,
            safe_parse_int64(get(json_dict, "strike_price", "0")),
            Char(get(json_dict, "match_algorithm", " ")[1]),
            UInt8(get(json_dict, "md_security_trading_status", 0)),  # v2 only
            UInt8(get(json_dict, "main_fraction", 0)),
            UInt8(get(json_dict, "price_display_format", 0)),
            UInt8(get(json_dict, "settl_price_type", 0)),  # v2 only
            UInt8(get(json_dict, "sub_fraction", 0)),
            UInt8(get(json_dict, "underlying_product", 0)),
            Char(get(json_dict, "security_update_action", " ")[1]),
            UInt8(get(json_dict, "maturity_month", 0)),
            UInt8(get(json_dict, "maturity_day", 0)),
            UInt8(get(json_dict, "maturity_week", 0)),
            parse_bool_from_json(get(json_dict, "user_defined_instrument", false)),
            Int8(get(json_dict, "contract_multiplier_unit", 0)),
            Int8(get(json_dict, "flow_schedule_type", 0)),
            UInt8(get(json_dict, "tick_rule", 0)),
            UInt16(get(json_dict, "leg_count", 0)),
            UInt16(get(json_dict, "leg_index", 0)),
            UInt32(get(json_dict, "leg_instrument_id", 0)),
            String(get(json_dict, "leg_raw_symbol", "")),
            haskey(json_dict, "leg_side") ? side_from_string(json_dict["leg_side"]) : DBN.Side.NONE,
            UInt32(get(json_dict, "leg_underlying_id", 0)),
            haskey(json_dict, "leg_instrument_class") ? DBN.safe_instrument_class(UInt8(json_dict["leg_instrument_class"][1])) : DBN.InstrumentClass.OTHER,
            UInt32(get(json_dict, "leg_ratio_qty_numerator", 0)),
            UInt32(get(json_dict, "leg_ratio_qty_denominator", 0)),
            UInt32(get(json_dict, "leg_ratio_price_numerator", 0)),
            UInt32(get(json_dict, "leg_ratio_price_denominator", 0)),
            safe_parse_int64(get(json_dict, "leg_price", "0")),
            safe_parse_int64(get(json_dict, "leg_delta", "0"))
        )
    # BBO message types
    elseif rtype == DBN.RType.BBO_1S_MSG
        # Parse levels for BBO messages
        levels_dict = json_dict["levels"][1]
        levels = DBN.BidAskPair(
            parse(Int64, levels_dict["bid_px"]),
            parse(Int64, levels_dict["ask_px"]),
            UInt32(levels_dict["bid_sz"]),
            UInt32(levels_dict["ask_sz"]),
            UInt32(get(levels_dict, "bid_ct", get(levels_dict, "bid_pb", 0))),
            UInt32(get(levels_dict, "ask_ct", get(levels_dict, "ask_pb", 0)))
        )

        return DBN.BBO1sMsg(
            hd,
            parse(Int64, json_dict["price"]),
            UInt32(json_dict["size"]),
            get(json_dict, "action", nothing) === nothing ? DBN.Action.NONE : action_from_string(json_dict["action"]),
            side_from_string(json_dict["side"]),
            UInt8(json_dict["flags"]),
            UInt8(get(json_dict, "depth", 0)),
            parse(Int64, json_dict["ts_recv"]),
            Int32(get(json_dict, "ts_in_delta", 0)),
            UInt32(get(json_dict, "sequence", 0)),
            levels
        )
    elseif rtype == DBN.RType.BBO_1M_MSG
        # Parse levels for BBO messages
        levels_dict = json_dict["levels"][1]
        levels = DBN.BidAskPair(
            parse(Int64, levels_dict["bid_px"]),
            parse(Int64, levels_dict["ask_px"]),
            UInt32(levels_dict["bid_sz"]),
            UInt32(levels_dict["ask_sz"]),
            UInt32(get(levels_dict, "bid_ct", get(levels_dict, "bid_pb", 0))),
            UInt32(get(levels_dict, "ask_ct", get(levels_dict, "ask_pb", 0)))
        )

        return DBN.BBO1mMsg(
            hd,
            parse(Int64, json_dict["price"]),
            UInt32(json_dict["size"]),
            get(json_dict, "action", nothing) === nothing ? DBN.Action.NONE : action_from_string(json_dict["action"]),
            side_from_string(json_dict["side"]),
            UInt8(json_dict["flags"]),
            UInt8(get(json_dict, "depth", 0)),
            parse(Int64, json_dict["ts_recv"]),
            Int32(get(json_dict, "ts_in_delta", 0)),
            UInt32(get(json_dict, "sequence", 0)),
            levels
        )
    else
        error("Unsupported record type for JSON parsing: $rtype ($(UInt8(rtype)))")
    end
end

# Helper to get record size from rtype
function get_record_size_for_rtype(rtype::DBN.RType.T)
    if rtype == DBN.RType.MBP_0_MSG
        return sizeof(DBN.TradeMsg)
    elseif rtype == DBN.RType.MBP_1_MSG || rtype == DBN.RType.CMBP_1_MSG
        return sizeof(DBN.MBP1Msg)
    elseif rtype == DBN.RType.MBP_10_MSG
        return sizeof(DBN.MBP10Msg)
    elseif rtype == DBN.RType.MBO_MSG
        return sizeof(DBN.MBOMsg)
    elseif rtype == DBN.RType.OHLCV_1S_MSG || rtype == DBN.RType.OHLCV_1M_MSG || 
           rtype == DBN.RType.OHLCV_1H_MSG || rtype == DBN.RType.OHLCV_1D_MSG
        return sizeof(DBN.OHLCVMsg)
    elseif rtype == DBN.RType.STATUS_MSG
        return sizeof(DBN.StatusMsg)
    elseif rtype == DBN.RType.INSTRUMENT_DEF_MSG
        return sizeof(DBN.InstrumentDefMsg)
    elseif rtype == DBN.RType.BBO_1S_MSG
        return sizeof(DBN.BBO1sMsg)
    elseif rtype == DBN.RType.BBO_1M_MSG
        return sizeof(DBN.BBO1mMsg)
    else
        return 0  # Unknown, will need to handle
    end
end

# Convert action string to Action enum
function action_from_string(s::String)
    if s == "A"
        return DBN.Action.ADD
    elseif s == "C"
        return DBN.Action.CANCEL
    elseif s == "M"
        return DBN.Action.MODIFY
    elseif s == "T"
        return DBN.Action.TRADE
    elseif s == "F"
        return DBN.Action.FILL
    else
        error("Unknown action: $s")
    end
end

# Convert side string to Side enum
function side_from_string(s::String)
    if s == "A"
        return DBN.Side.ASK
    elseif s == "B"
        return DBN.Side.BID
    elseif s == "N"
        return DBN.Side.NONE
    else
        error("Unknown side: $s")
    end
end

end # module