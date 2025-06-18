#!/usr/bin/env julia

"""
Debug script to test the fixed record writing.
"""

using DBN

function create_corrected_record_file()
    println("=== Creating corrected record file ===")
    
    metadata = DBN.Metadata(
        UInt8(3),                          # version
        "TEST",                            # dataset  
        DBN.Schema.MBP_1,                  # schema
        Int64(1000000000),                 # start_ts
        Int64(2000000000),                 # end_ts
        UInt64(1),                         # limit
        DBN.SType.RAW_SYMBOL,              # stype_in
        DBN.SType.RAW_SYMBOL,              # stype_out
        false,                             # ts_out
        String[],                          # symbols
        String[],                          # partial
        String[],                          # not_found
        Tuple{String, String, Int64, Int64}[]  # mappings
    )
    
    # Use the same record type as the reference file
    trade = DBN.TradeMsg(
        DBN.RecordHeader(
            UInt8(sizeof(DBN.TradeMsg)),       # length in bytes (will be converted to 4-byte units)
            DBN.RType.MBP_0_MSG,               # Use same type as reference file 
            UInt16(1),                         # publisher_id
            UInt32(100),                       # instrument_id
            UInt64(1500000000)                 # ts_event
        ),                                     # hd
        Int64(1234500000),                     # price ($123.45)
        UInt32(100),                           # size
        DBN.Action.TRADE,                      # action
        DBN.Side.BID,                          # side
        UInt8(0),                              # flags
        UInt8(0),                              # depth
        Int64(1500000000),                     # ts_recv
        Int32(0),                              # ts_in_delta
        UInt32(1)                              # sequence
    )
    
    println("TradeMsg size: $(sizeof(DBN.TradeMsg)) bytes")
    println("Expected length field: $(sizeof(DBN.TradeMsg) ÷ 4)")
    
    # Write the file
    filename = "corrected_record.dbn"
    DBN.write_dbn(filename, metadata, [trade])
    
    println("Created file: $filename")
    println("File size: $(filesize(filename)) bytes")
    
    return filename
end

function examine_corrected_record(filename)
    println("\n=== Examining corrected record ===")
    
    data = read(filename)
    
    # Find record start
    metadata_length = reinterpret(UInt32, data[5:8])[1]
    header_total_size = 4 + 4 + metadata_length
    record_start = header_total_size + 1
    record_data = data[record_start:end]
    
    println("Record data size: $(length(record_data)) bytes")
    
    if length(record_data) >= 16
        record_length = record_data[1]
        record_type = record_data[2]
        
        println("Record header:")
        println("  Length: $record_length (in 4-byte units = $(record_length * 4) bytes)")
        println("  Type: $record_type")
        
        expected_length = sizeof(DBN.TradeMsg) ÷ 4
        if record_length == expected_length
            println("✅ Length field is correct!")
        else
            println("❌ Length field mismatch: got $record_length, expected $expected_length")
        end
    end
end

function test_corrected_file(filename)
    println("\n=== Testing corrected file ===")
    
    # Test Julia read
    try
        println("Testing Julia read...")
        metadata, records = DBN.read_dbn_with_metadata(filename)
        println("✅ Julia read successful!")
        println("Records count: $(length(records))")
        if length(records) > 0
            println("First record: $(records[1])")
        end
    catch e
        println("❌ Julia read failed: $e")
    end
    
    # Test Rust CLI
    cli_path = "/workspace/dbn/target/release/dbn"
    try
        println("Testing Rust CLI...")
        result = read(`$cli_path $filename --json`, String)
        if isempty(strip(result))
            println("❌ Rust CLI returned empty result")
        else
            println("✅ Rust CLI result:")
            println(result)
        end
    catch e
        println("❌ Rust CLI failed: $e")
    end
end

function main()
    # Clean up
    for f in ["corrected_record.dbn"]
        if isfile(f)
            rm(f)
        end
    end
    
    filename = create_corrected_record_file()
    examine_corrected_record(filename)
    test_corrected_file(filename)
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end