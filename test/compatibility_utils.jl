module CompatibilityUtils

using DBN
using Test
using JSON3
using StructTypes
using DataFrames
using CSV: CSV
using Dates

# Path to the Rust DBN CLI executable
const DBN_CLI_PATH = "/workspace/dbn/target/release/dbn"

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
    test_data_dir = "/workspace/dbn/tests/data"
    if !isdir(test_data_dir)
        error("Test data directory not found: $test_data_dir")
    end
    
    files = String[]
    for (root, dirs, filenames) in walkdir(test_data_dir)
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
    record_size = get_record_size_for_rtype(rtype)
    length = UInt8(record_size ÷ DBN.LENGTH_MULTIPLIER)
    
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
    elseif rtype == DBN.RType.MBP_1_MSG || rtype == DBN.RType.CMBP_1_MSG
        # Parse levels array for MBP-1 messages
        levels_dict = json_dict["levels"][1]  # First level for MBP-1
        levels = DBN.BidAskPair(
            parse(Int64, levels_dict["bid_px"]),
            parse(Int64, levels_dict["ask_px"]),
            UInt32(levels_dict["bid_sz"]),
            UInt32(levels_dict["ask_sz"]),
            # CMBP_1_MSG uses bid_pb/ask_pb instead of bid_ct/ask_ct
            UInt32(get(levels_dict, "bid_ct", get(levels_dict, "bid_pb", 0))),
            UInt32(get(levels_dict, "ask_ct", get(levels_dict, "ask_pb", 0)))
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
    elseif rtype == DBN.RType.MBP_10_MSG
        # For MBP_10_MSG, we only need the first level (top-of-book)
        # Create a simple 10-tuple with the first level and pad with zeros
        first_level = if haskey(json_dict, "levels") && !isempty(json_dict["levels"])
            level_dict = json_dict["levels"][1]  # First level is top-of-book
            DBN.BidAskPair(
                parse(Int64, level_dict["bid_px"]),
                parse(Int64, level_dict["ask_px"]),
                UInt32(level_dict["bid_sz"]),
                UInt32(level_dict["ask_sz"]),
                UInt32(get(level_dict, "bid_ct", get(level_dict, "bid_pb", 0))),
                UInt32(get(level_dict, "ask_ct", get(level_dict, "ask_pb", 0)))
            )
        else
            DBN.BidAskPair(0, 0, 0, 0, 0, 0)
        end
        
        # Create NTuple{10,BidAskPair} with first level and padding
        levels = (first_level, 
                 DBN.BidAskPair(0, 0, 0, 0, 0, 0), DBN.BidAskPair(0, 0, 0, 0, 0, 0),
                 DBN.BidAskPair(0, 0, 0, 0, 0, 0), DBN.BidAskPair(0, 0, 0, 0, 0, 0),
                 DBN.BidAskPair(0, 0, 0, 0, 0, 0), DBN.BidAskPair(0, 0, 0, 0, 0, 0),
                 DBN.BidAskPair(0, 0, 0, 0, 0, 0), DBN.BidAskPair(0, 0, 0, 0, 0, 0),
                 DBN.BidAskPair(0, 0, 0, 0, 0, 0))
        
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
        return DBN.MBOMsg(
            hd,
            parse(UInt64, json_dict["order_id"]),
            parse(Int64, json_dict["price"]),
            UInt32(json_dict["size"]),
            UInt8(json_dict["flags"]),
            UInt8(json_dict["channel_id"]),
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
    # Add more record types as needed
    elseif rtype == DBN.RType.BBO_1M_MSG
        # Parse levels for BBO messages (similar to MBP-1)
        levels_dict = json_dict["levels"][1]  # First level
        levels = DBN.BidAskPair(
            parse(Int64, levels_dict["bid_px"]),
            parse(Int64, levels_dict["ask_px"]),
            UInt32(levels_dict["bid_sz"]),
            UInt32(levels_dict["ask_sz"]),
            UInt32(get(levels_dict, "bid_ct", get(levels_dict, "bid_pb", 0))),
            UInt32(get(levels_dict, "ask_ct", get(levels_dict, "ask_pb", 0)))
        )
        
        return DBN.MBP1Msg(  # Use MBP1Msg for BBO as they have similar structure
            hd,
            parse(Int64, json_dict["price"]),
            UInt32(json_dict["size"]),
            DBN.Action.NONE,  # BBO may not have action field
            side_from_string(json_dict["side"]),
            UInt8(json_dict["flags"]),
            UInt8(0),  # depth for BBO
            parse(Int64, json_dict["ts_recv"]),
            Int32(0),  # ts_in_delta not present in BBO
            UInt32(get(json_dict, "sequence", 0)),  # Default sequence to 0 if missing
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
    elseif rtype == DBN.RType.BBO_1M_MSG
        return sizeof(DBN.MBP1Msg)  # Use MBP1Msg size for BBO
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