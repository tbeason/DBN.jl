#!/usr/bin/env julia

"""
Debug script to test writing a single record and examine the binary output.
"""

using DBN

function create_single_record_file()
    println("=== Creating single record file ===")
    
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
    
    trade = DBN.TradeMsg(
        DBN.RecordHeader(
            UInt8(sizeof(DBN.TradeMsg)),       # length (should be 48 bytes)
            DBN.RType.MBP_1_MSG,               # rtype
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
    println("RecordHeader size: $(sizeof(DBN.RecordHeader)) bytes")
    
    # Write the file
    filename = "single_record.dbn"
    DBN.write_dbn(filename, metadata, [trade])
    
    println("Created file: $filename")
    println("File size: $(filesize(filename)) bytes")
    
    return filename, trade
end

function examine_record_binary(filename, expected_trade)
    println("\n=== Examining record binary structure ===")
    
    data = read(filename)
    println("Total file size: $(length(data)) bytes")
    
    # Find where records start (after header)
    # Header = magic(3) + version(1) + metadata_length(4) + metadata
    if length(data) < 8
        println("❌ File too short to contain header")
        return
    end
    
    metadata_length = reinterpret(UInt32, data[5:8])[1]
    println("Metadata length: $metadata_length bytes")
    
    header_total_size = 4 + 4 + metadata_length  # magic+version + length + metadata
    println("Header total size: $header_total_size bytes")
    
    if length(data) <= header_total_size
        println("❌ File contains only header, no records")
        return
    end
    
    # Extract record data
    record_start = header_total_size + 1
    record_data = data[record_start:end]
    println("Record data size: $(length(record_data)) bytes")
    
    println("Record bytes (hex):")
    for (i, byte) in enumerate(record_data)
        print(string(byte, base=16, pad=2))
        if i % 16 == 0
            println()
        elseif i % 4 == 0
            print(" ")
        end
    end
    println()
    
    # Parse record header manually
    if length(record_data) >= 15  # Record header size
        record_length = record_data[1]
        record_type = record_data[2]
        publisher_id = reinterpret(UInt16, record_data[3:4])[1]
        instrument_id = reinterpret(UInt32, record_data[5:8])[1]
        ts_event = reinterpret(UInt64, record_data[9:16])[1]
        
        println("\nParsed record header:")
        println("  Length: $record_length (expected: $(sizeof(DBN.TradeMsg)))")
        println("  Type: $record_type (expected: $(UInt8(DBN.RType.MBP_1_MSG)))")
        println("  Publisher ID: $publisher_id")
        println("  Instrument ID: $instrument_id")
        println("  TS Event: $ts_event")
        
        # Check if length matches expected size
        if record_length * 4 != sizeof(DBN.TradeMsg)  # Length is in units of 4 bytes
            println("⚠️  Record length mismatch!")
            println("    Length field: $record_length * 4 = $(record_length * 4) bytes")
            println("    TradeMsg size: $(sizeof(DBN.TradeMsg)) bytes")
        end
    end
end

function test_file(filename)
    println("\n=== Testing file compatibility ===")
    
    # Test Julia read
    try
        println("Testing Julia read...")
        metadata, records = DBN.read_dbn_with_metadata(filename)
        println("✅ Julia read successful")
        println("Records count: $(length(records))")
        if length(records) > 0
            println("First record: $(records[1])")
        end
    catch e
        println("❌ Julia read failed: $e")
        println("This suggests the file format is invalid")
    end
    
    # Test Rust CLI
    cli_path = "/workspace/dbn/target/release/dbn"
    try
        println("Testing Rust CLI...")
        result = read(`$cli_path $filename --json`, String)
        if isempty(strip(result))
            println("❌ Rust CLI returned empty result")
        else
            println("✅ Rust CLI result: $result")
        end
    catch e
        println("❌ Rust CLI failed: $e")
    end
end

function compare_with_reference()
    println("\n=== Comparing with reference record ===")
    
    ref_file = "/workspace/dbn/tests/data/test_data.trades.dbn"
    our_file = "single_record.dbn"
    
    if !isfile(ref_file)
        println("❌ Reference file not found")
        return
    end
    
    # Read reference file and extract its first record
    try
        ref_metadata, ref_records = DBN.read_dbn_with_metadata(ref_file)
        println("Reference file has $(length(ref_records)) records")
        
        if length(ref_records) > 0
            println("Reference first record: $(ref_records[1])")
            println("Reference record type: $(typeof(ref_records[1]))")
        end
    catch e
        println("❌ Could not read reference file: $e")
    end
end

function main()
    # Clean up
    for f in ["single_record.dbn"]
        if isfile(f)
            rm(f)
        end
    end
    
    filename, trade = create_single_record_file()
    examine_record_binary(filename, trade)
    test_file(filename)
    compare_with_reference()
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end