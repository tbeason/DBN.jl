#!/usr/bin/env julia

"""
Demonstration script for DBN.jl compatibility with the official Rust implementation.
This script shows basic compatibility testing capabilities.
"""

using DBN
using JSON

# Include the compatibility utilities
include("test/compatibility_utils.jl")
using .CompatibilityUtils

function main()
    println("=== DBN.jl Compatibility Demonstration ===")
    
    # Check if Rust CLI is available
    if !isfile(CompatibilityUtils.DBN_CLI_PATH)
        println("❌ Rust DBN CLI not found at $(CompatibilityUtils.DBN_CLI_PATH)")
        println("To build it, run: cd /workspace/dbn/rust/dbn-cli && cargo build --release")
        return
    end
    
    println("✅ Rust DBN CLI found")
    
    # Get available test files
    test_files = CompatibilityUtils.get_test_files(".*\\.dbn")
    uncompressed_files = filter(f -> !endswith(f, ".zst"), test_files)
    
    if isempty(test_files)
        println("❌ No DBN test files found")
        return
    end
    
    println("📁 Found $(length(test_files)) test files ($(length(uncompressed_files)) uncompressed)")
    
    # Test 1: Basic file reading compatibility
    println("\n🔍 Test 1: Basic file reading compatibility")
    
    test_file = first(uncompressed_files)
    println("Testing with: $(basename(test_file))")
    
    try
        # Read with Julia
        metadata, records = DBN.read_dbn_with_metadata(test_file)
        println("  Julia: Read $(length(records)) records")
        
        # Read with Rust CLI (convert to JSON to count records)
        rust_output = CompatibilityUtils.run_dbn_cli([test_file, "--json"])
        rust_lines = filter(!isempty, split(rust_output, '\n'))
        println("  Rust: Read $(length(rust_lines)) records")
        
        if length(records) == length(rust_lines)
            println("  ✅ Record counts match")
        else
            println("  ❌ Record count mismatch")
        end
        
    catch e
        println("  ❌ Error reading file: $e")
    end
    
    # Test 2: Round-trip compatibility  
    println("\n🔄 Test 2: Round-trip compatibility (Julia write → Rust read)")
    
    mktempdir() do tmpdir
        try
            # Create simple test data
            metadata = DBN.Metadata(
                UInt8(3),                          # version
                "TEST",                            # dataset
                DBN.Schema.TRADES,                 # schema - use TRADES for TradeMsg
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
                    DBN.RType.MBP_0_MSG,               # rtype - use MBP_0_MSG for trades
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
            
            # Write with Julia
            julia_file = joinpath(tmpdir, "julia_test.dbn")
            DBN.write_dbn(julia_file, metadata, [trade])
            println("  Julia: Wrote test file")
            
            # Try to read with Rust
            rust_output = CompatibilityUtils.run_dbn_cli([julia_file, "--json"])
            if !isempty(rust_output) && contains(rust_output, "\"price\":\"1234500000\"")
                println("  ✅ Rust successfully read Julia-generated file")
            else
                println("  ❌ Rust could not read Julia-generated file properly")
                println("  Rust output: $rust_output")
            end
            
        catch e
            println("  ❌ Round-trip test failed: $e")
        end
    end
    
    # Test 3: Compression compatibility
    println("\n📦 Test 3: Compression compatibility")
    
    compressed_files = filter(f -> endswith(f, ".zst") && !contains(f, "frag"), test_files)
    if !isempty(compressed_files)
        test_file = first(compressed_files)
        println("Testing with: $(basename(test_file))")
        
        try
            # Read compressed file with Julia
            metadata, records = DBN.read_dbn_with_metadata(test_file)
            println("  Julia: Read $(length(records)) records from compressed file")
            
            # Read with Rust
            rust_output = CompatibilityUtils.run_dbn_cli([test_file, "--json"])
            rust_lines = filter(!isempty, split(rust_output, '\n'))
            println("  Rust: Read $(length(rust_lines)) records from compressed file")
            
            if length(records) == length(rust_lines)
                println("  ✅ Compressed file compatibility confirmed")
            else
                println("  ❌ Compressed file record count mismatch")
            end
            
        catch e
            println("  ❌ Compression test failed: $e")
        end
    else
        println("  ⚠️  No compressed test files found")
    end
    
    # Test 4: Format support
    println("\n📊 Test 4: Format support")
    
    test_file = first(uncompressed_files)
    
    # Test CSV export
    try
        julia_csv_file = joinpath(pwd(), "test_output.csv")
        DBN.dbn_to_csv(test_file, julia_csv_file)
        
        rust_csv = CompatibilityUtils.run_dbn_cli([test_file, "--csv"])
        
        if isfile(julia_csv_file) && !isempty(rust_csv)
            println("  ✅ Both implementations support CSV export")
            rm(julia_csv_file)  # cleanup
        else
            println("  ❌ CSV export compatibility issue")
        end
    catch e
        println("  ❌ CSV test failed: $e")
    end
    
    # Test JSON export
    try
        julia_json_file = joinpath(pwd(), "test_output.json")
        DBN.dbn_to_json(test_file, julia_json_file)
        
        rust_json = CompatibilityUtils.run_dbn_cli([test_file, "--json"])
        
        if isfile(julia_json_file) && !isempty(rust_json)
            println("  ✅ Both implementations support JSON export")
            rm(julia_json_file)  # cleanup
        else
            println("  ❌ JSON export compatibility issue")
        end
    catch e
        println("  ❌ JSON test failed: $e")
    end
    
    # Test 5: Performance comparison
    println("\n⚡ Test 5: Performance comparison")
    
    try
        test_file = first(filter(f -> filesize(f) < 1_000_000, uncompressed_files))  # Use smaller file
        
        # Benchmark Julia
        julia_time = @elapsed DBN.read_dbn_with_metadata(test_file)
        
        # Benchmark Rust (approximate) - output to temp file
        rust_time = mktempdir() do tmpdir
            @elapsed CompatibilityUtils.run_dbn_cli([test_file, "--json", "-o", joinpath(tmpdir, "output.json")])
        end
        
        ratio = julia_time / rust_time
        println("  Julia read time: $(round(julia_time * 1000, digits=2)) ms")
        println("  Rust read time: $(round(rust_time * 1000, digits=2)) ms")
        println("  Ratio (Julia/Rust): $(round(ratio, digits=2))x")
        
        if ratio < 5.0
            println("  ✅ Performance within acceptable range")
        else
            println("  ⚠️  Julia significantly slower than Rust")
        end
        
    catch e
        println("  ❌ Performance test failed: $e")
    end
    
    println("\n=== Compatibility Demonstration Complete ===")
    println("For comprehensive testing, run: julia --project=. test/test_compatibility.jl")
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end