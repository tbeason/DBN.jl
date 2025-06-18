#!/usr/bin/env julia

"""
Debug script to test just the header writing.
"""

using DBN

function write_header_only()
    println("=== Writing header-only file ===")
    
    metadata = DBN.Metadata(
        UInt8(3),                          # version
        "TEST",                            # dataset  
        DBN.Schema.MBP_1,                  # schema
        Int64(1000000000),                 # start_ts
        Int64(2000000000),                 # end_ts
        UInt64(0),                         # limit (no records)
        DBN.SType.RAW_SYMBOL,              # stype_in
        DBN.SType.RAW_SYMBOL,              # stype_out
        false,                             # ts_out
        String[],                          # symbols
        String[],                          # partial
        String[],                          # not_found
        Tuple{String, String, Int64, Int64}[]  # mappings
    )
    
    # Manually write just the header
    filename = "header_only.dbn"
    open(filename, "w") do f
        encoder = DBN.DBNEncoder(f, metadata)
        DBN.write_header(encoder)
        # Don't write any records
        DBN.finalize_encoder(encoder)
    end
    
    println("Created header-only file: $filename")
    println("File size: $(filesize(filename)) bytes")
    
    return filename
end

function test_header_file(filename)
    println("\n=== Testing header-only file ===")
    
    # Test with Rust CLI
    cli_path = "/workspace/dbn/target/release/dbn"
    try
        println("Testing with Rust CLI...")
        result = read(`$cli_path $filename --json`, String)
        println("✅ Rust CLI result: '$result'")
        if isempty(strip(result))
            println("✅ Empty result is expected for file with no records")
        end
    catch e
        println("❌ Rust CLI failed: $e")
    end
    
    # Test Julia read
    try
        println("Testing with Julia...")
        metadata, records = DBN.read_dbn_with_metadata(filename)
        println("✅ Julia read successful")
        println("Metadata: $metadata") 
        println("Records: $(length(records))")
    catch e
        println("❌ Julia read failed: $e")
    end
end

function compare_headers()
    println("\n=== Comparing with reference header ===")
    
    # Read reference file and our file
    ref_file = "/workspace/dbn/tests/data/test_data.trades.dbn"
    our_file = "header_only.dbn"
    
    if !isfile(ref_file)
        println("❌ Reference file not found")
        return
    end
    
    ref_data = read(ref_file)
    our_data = read(our_file)
    
    println("Reference file size: $(length(ref_data)) bytes")
    println("Our file size: $(length(our_data)) bytes")
    
    # Compare headers byte by byte
    println("\nByte-by-byte header comparison:")
    min_len = min(length(ref_data), length(our_data))
    
    differences = 0
    for i in 1:min_len
        if ref_data[i] != our_data[i]
            differences += 1
            if differences <= 10  # Show first 10 differences
                println("Difference at byte $i: ref=$(ref_data[i]) (0x$(string(ref_data[i], base=16, pad=2))) vs ours=$(our_data[i]) (0x$(string(our_data[i], base=16, pad=2)))")
            end
        end
    end
    
    if differences == 0
        println("✅ Headers match perfectly for first $min_len bytes")
    else
        println("❌ Found $differences differences in headers")
    end
    
    # Show the structure
    println("\nHeader structure analysis:")
    println("Bytes 0-3: Magic + version")
    println("  Ref: $(String(ref_data[1:3])) + v$(ref_data[4])")
    println("  Ours: $(String(our_data[1:3])) + v$(our_data[4])")
    
    if length(ref_data) >= 8 && length(our_data) >= 8
        ref_meta_len = reinterpret(UInt32, ref_data[5:8])[1]
        our_meta_len = reinterpret(UInt32, our_data[5:8])[1]
        println("Bytes 4-7: Metadata length")
        println("  Ref: $ref_meta_len")
        println("  Ours: $our_meta_len")
    end
end

function main()
    # Clean up
    for f in ["header_only.dbn"]
        if isfile(f)
            rm(f)
        end
    end
    
    file = write_header_only()
    test_header_file(file)
    compare_headers()
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end