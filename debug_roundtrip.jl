#!/usr/bin/env julia

"""
Debug script to investigate round-trip compatibility issues.
Creates minimal DBN files and examines the binary output.
"""

using DBN

function create_minimal_test_file()
    println("=== Creating minimal test file ===")
    
    # Create the simplest possible valid DBN file
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
            UInt8(sizeof(DBN.TradeMsg)),       # length
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
    
    println("Metadata: $metadata")
    println("Trade message: $trade")
    
    # Write the file
    output_file = "minimal_test.dbn"
    DBN.write_dbn(output_file, metadata, [trade])
    
    println("Created file: $output_file")
    println("File size: $(filesize(output_file)) bytes")
    
    return output_file
end

function examine_file_binary(filename)
    println("\n=== Binary examination of $filename ===")
    
    # Read first 100 bytes and display as hex
    data = read(filename)
    println("File size: $(length(data)) bytes")
    println("First 100 bytes (hex):")
    
    for i in 1:min(100, length(data))
        print(string(data[i], base=16, pad=2))
        if i % 16 == 0
            println()
        elseif i % 4 == 0
            print(" ")
        end
    end
    println()
    
    # Try to identify DBN magic bytes
    if length(data) >= 4
        magic = data[1:4]
        println("Magic bytes: $(String(magic)) ($(magic))")
    end
    
    return data
end

function test_with_rust_cli(filename)
    println("\n=== Testing with Rust CLI ===")
    
    cli_path = "/workspace/dbn/target/release/dbn"
    if !isfile(cli_path)
        println("❌ Rust CLI not found")
        return
    end
    
    # Try to read with verbose output
    try
        println("Running: $cli_path $filename --json")
        result = read(`$cli_path $filename --json`, String)
        println("✅ Rust CLI output:")
        println(result)
        
        if isempty(strip(result))
            println("⚠️ Empty output from Rust CLI")
        end
    catch e
        println("❌ Rust CLI failed:")
        println(e)
        
        # Try to get more detailed error
        try
            run(pipeline(`$cli_path $filename --json`, stderr="rust_error.log"))
        catch
            if isfile("rust_error.log")
                error_content = read("rust_error.log", String)
                println("Error details: $error_content")
            end
        end
    end
end

function test_julia_read_back(filename)
    println("\n=== Testing Julia read-back ===")
    
    try
        metadata, records = DBN.read_dbn_with_metadata(filename)
        println("✅ Julia can read back the file")
        println("Metadata: $metadata")
        println("Records: $(length(records))")
        for (i, record) in enumerate(records)
            println("Record $i: $record")
        end
    catch e
        println("❌ Julia cannot read back the file:")
        println(e)
    end
end

function compare_with_reference_file()
    println("\n=== Comparing with reference file ===")
    
    # Find a simple reference file
    ref_files = [
        "/workspace/dbn/tests/data/test_data.trades.dbn",
        "/workspace/dbn/tests/data/test_data.mbp-1.dbn"
    ]
    
    ref_file = nothing
    for f in ref_files
        if isfile(f)
            ref_file = f
            break
        end
    end
    
    if ref_file === nothing
        println("❌ No reference file found")
        return
    end
    
    println("Using reference file: $ref_file")
    
    # Examine reference file structure
    ref_data = examine_file_binary(ref_file)
    
    # Compare headers
    julia_data = read("minimal_test.dbn")
    
    println("\nHeader comparison:")
    println("Reference file first 50 bytes:")
    for i in 1:min(50, length(ref_data))
        print(string(ref_data[i], base=16, pad=2), " ")
        if i % 16 == 0; println(); end
    end
    println()
    
    println("Julia file first 50 bytes:")
    for i in 1:min(50, length(julia_data))
        print(string(julia_data[i], base=16, pad=2), " ")
        if i % 16 == 0; println(); end
    end
    println()
end

function main()
    println("=== DBN Round-trip Compatibility Debug ===")
    
    # Clean up any existing test files
    for f in ["minimal_test.dbn", "rust_error.log"]
        if isfile(f)
            rm(f)
        end
    end
    
    # Create and examine our test file
    test_file = create_minimal_test_file()
    julia_data = examine_file_binary(test_file)
    
    # Test Julia read-back
    test_julia_read_back(test_file)
    
    # Test with Rust CLI
    test_with_rust_cli(test_file)
    
    # Compare with reference file
    compare_with_reference_file()
    
    println("\n=== Debug Summary ===")
    println("This script helps identify where the compatibility breaks.")
    println("Check the binary output and error messages above.")
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end