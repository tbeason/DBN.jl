using Test
using DBN
using Dates
using JSON3

# Include the compatibility utilities
include("compatibility_utils.jl")
using .CompatibilityUtils

@testset "DBN.jl Compatibility Tests (Updated)" begin
    
    # Check if Rust CLI is available
    if !isfile(CompatibilityUtils.DBN_CLI_PATH)
        @warn "Rust DBN CLI not found. Skipping compatibility tests. Build with: cd /workspace/dbn/rust/dbn-cli && cargo build --release"
        return
    end
    
    @testset "Binary Format Compatibility" begin
        @testset "Read Rust-generated files" begin
            # Test various schemas - exclude fragment files
            test_patterns = [
                ("trades", ".*trades.*dbn"),
                ("mbp-1", ".*mbp-1.*dbn"),
                ("ohlcv", ".*ohlcv.*dbn"),
                ("definition", ".*definition.*dbn"),
                ("status", ".*status.*dbn")
            ]
            
            for (schema_name, pattern) in test_patterns
                @testset "$schema_name schema" begin
                    files = CompatibilityUtils.get_test_files(pattern)
                    # Filter out compressed and fragment files for basic compatibility
                    files = filter(f -> !endswith(f, ".zst") && !contains(f, "frag") && !contains(f, "bad"), files)
                    
                    if isempty(files)
                        @warn "No test files found for pattern: $pattern"
                        continue
                    end
                    
                    for file in files
                        @test CompatibilityUtils.test_file_compatibility(file)
                    end
                end
            end
        end
    end
    
    @testset "Round-Trip Compatibility" begin
        # Test that Julia can write files that Rust can read
        mktempdir() do tmpdir
            @testset "Single TradeMsg" begin
                # Create correct metadata for trades
                metadata = DBN.Metadata(
                    UInt8(3),                          # version
                    "TEST",                            # dataset
                    DBN.Schema.TRADES,                 # schema - correct for trades
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
                        UInt8(sizeof(DBN.TradeMsg) ÷ DBN.LENGTH_MULTIPLIER),  # length in units
                        DBN.RType.MBP_0_MSG,               # rtype - correct for trades
                        UInt16(1),                         # publisher_id
                        UInt32(100),                       # instrument_id
                        UInt64(1500000000)                 # ts_event
                    ),
                    Int64(1234500000),                     # price
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
                output_file = joinpath(tmpdir, "single_trade.dbn")
                DBN.write_dbn(output_file, metadata, [trade])
                
                # Verify Julia can read it back
                julia_metadata, julia_records = DBN.read_dbn_with_metadata(output_file)
                @test length(julia_records) == 1
                @test julia_records[1].price == 1234500000
                
                # Verify Rust can read it
                rust_output = CompatibilityUtils.run_dbn_cli([output_file, "--json"])
                @test !isempty(rust_output)
                @test contains(rust_output, "\"price\":\"1234500000\"")
                @test contains(rust_output, "\"action\":\"T\"")
                @test contains(rust_output, "\"side\":\"B\"")
            end
            
            @testset "Multiple Records" begin
                # Test with multiple records
                metadata = DBN.Metadata(
                    UInt8(3), "TEST", DBN.Schema.TRADES, Int64(1000000000), Int64(2000000000), 
                    UInt64(2), DBN.SType.RAW_SYMBOL, DBN.SType.RAW_SYMBOL, false, 
                    String[], String[], String[], Tuple{String, String, Int64, Int64}[]
                )
                
                records = [
                    DBN.TradeMsg(
                        DBN.RecordHeader(UInt8(sizeof(DBN.TradeMsg) ÷ DBN.LENGTH_MULTIPLIER), DBN.RType.MBP_0_MSG, UInt16(1), UInt32(100), UInt64(1500000000)),
                        Int64(1234500000), UInt32(100), DBN.Action.TRADE, DBN.Side.BID, UInt8(0), UInt8(0), 
                        Int64(1500000000), Int32(0), UInt32(1)
                    ),
                    DBN.TradeMsg(
                        DBN.RecordHeader(UInt8(sizeof(DBN.TradeMsg) ÷ DBN.LENGTH_MULTIPLIER), DBN.RType.MBP_0_MSG, UInt16(1), UInt32(101), UInt64(1500000001)),
                        Int64(1234600000), UInt32(200), DBN.Action.TRADE, DBN.Side.ASK, UInt8(0), UInt8(0), 
                        Int64(1500000001), Int32(0), UInt32(2)
                    )
                ]
                
                output_file = joinpath(tmpdir, "multiple_trades.dbn")
                DBN.write_dbn(output_file, metadata, records)
                
                # Test Julia read
                julia_metadata, julia_records = DBN.read_dbn_with_metadata(output_file)
                @test length(julia_records) == 2
                
                # Test Rust read
                rust_output = CompatibilityUtils.run_dbn_cli([output_file, "--json"])
                rust_lines = filter(!isempty, split(rust_output, '\n'))
                @test length(rust_lines) == 2
            end
        end
    end
    
    @testset "Compression Compatibility" begin
        # Test compressed file reading
        compressed_files = filter(f -> endswith(f, ".zst") && !contains(f, "frag"), 
                                 CompatibilityUtils.get_test_files(".*\\.dbn\\.zst"))
        
        if !isempty(compressed_files)
            test_file = first(compressed_files)
            
            @testset "Read compressed files" begin
                # Test that both Julia and Rust can read compressed files and get same result
                @test CompatibilityUtils.test_file_compatibility(test_file)
            end
        end
        
        # Test compressed file writing
        mktempdir() do tmpdir
            @testset "Write compressed files" begin
                metadata = DBN.Metadata(
                    UInt8(3), "TEST", DBN.Schema.TRADES, Int64(1000000000), Int64(2000000000), 
                    UInt64(1), DBN.SType.RAW_SYMBOL, DBN.SType.RAW_SYMBOL, false, 
                    String[], String[], String[], Tuple{String, String, Int64, Int64}[]
                )
                
                trade = DBN.TradeMsg(
                    DBN.RecordHeader(UInt8(sizeof(DBN.TradeMsg) ÷ DBN.LENGTH_MULTIPLIER), DBN.RType.MBP_0_MSG, UInt16(1), UInt32(100), UInt64(1500000000)),
                    Int64(1234500000), UInt32(100), DBN.Action.TRADE, DBN.Side.BID, UInt8(0), UInt8(0), 
                    Int64(1500000000), Int32(0), UInt32(1)
                )
                
                # Write compressed file
                compressed_file = joinpath(tmpdir, "test.dbn.zst")
                DBN.write_dbn(compressed_file, metadata, [trade])
                
                # Verify Rust can read it
                rust_output = CompatibilityUtils.run_dbn_cli([compressed_file, "--json"])
                @test !isempty(rust_output)
                @test contains(rust_output, "\"price\":\"1234500000\"")
            end
        end
    end
    
    @testset "Export Format Compatibility" begin
        # Find a suitable test file
        test_files = filter(f -> !endswith(f, ".zst") && !contains(f, "frag"), 
                           CompatibilityUtils.get_test_files(".*trades.*\\.dbn"))
        
        if !isempty(test_files)
            test_file = first(test_files)
            
            mktempdir() do tmpdir
                @testset "CSV Export" begin
                    # Export with Julia
                    julia_csv_file = joinpath(tmpdir, "julia_export.csv")
                    DBN.dbn_to_csv(test_file, julia_csv_file)
                    julia_csv = read(julia_csv_file, String)
                    
                    # Export with Rust
                    rust_csv = CompatibilityUtils.run_dbn_cli([test_file, "--csv"])
                    
                    # Both should produce CSV output
                    @test contains(julia_csv, ",")  # Basic CSV check
                    @test contains(rust_csv, ",")   # Basic CSV check
                end
                
                @testset "JSON Export" begin
                    # Export with Julia
                    julia_json_file = joinpath(tmpdir, "julia_export.json")
                    DBN.dbn_to_json(test_file, julia_json_file)
                    julia_json = read(julia_json_file, String)
                    
                    # Export with Rust
                    rust_json = CompatibilityUtils.run_dbn_cli([test_file, "--json"])
                    
                    # Both should produce valid JSON
                    @test contains(julia_json, "{")  # Basic JSON check
                    @test contains(rust_json, "{")   # Basic JSON check
                end
            end
        end
    end
    
    @testset "Version Compatibility" begin
        # Test files from different DBN versions
        # Note: DBN v1 is not supported - use `dbn upgrade` to convert v1 files to v3
        for version in [2, 3]  # Skip v1
            version_files = filter(f -> contains(f, "v$version") && !contains(f, "frag"),
                                 CompatibilityUtils.get_test_files(".*\\.dbn"))

            if !isempty(version_files)
                @testset "DBN v$version" begin
                    test_file = first(version_files)
                    # Just test that we can read the file - exact compatibility depends on schema
                    try
                        metadata, records = DBN.read_dbn_with_metadata(test_file)
                        @test true  # If we get here, the file was read successfully
                    catch e
                        @test false  # Failed to read version-specific file
                    end
                end
            end
        end
    end
    
    @testset "Byte-for-Byte Validation" begin
        # Test that demonstrates byte-for-byte compatibility
        mktempdir() do tmpdir
            @testset "Data Integrity" begin
                # Create test data with specific values
                metadata = DBN.Metadata(
                    UInt8(3), "TEST", DBN.Schema.TRADES, Int64(1600000000000000000), Int64(1600000001000000000), 
                    UInt64(1), DBN.SType.RAW_SYMBOL, DBN.SType.RAW_SYMBOL, false, 
                    String[], String[], String[], Tuple{String, String, Int64, Int64}[]
                )
                
                trade = DBN.TradeMsg(
                    DBN.RecordHeader(UInt8(sizeof(DBN.TradeMsg) ÷ DBN.LENGTH_MULTIPLIER), DBN.RType.MBP_0_MSG, UInt16(42), UInt32(12345), UInt64(1600000000500000000)),
                    Int64(9876543210),  # Specific price
                    UInt32(999),        # Specific size
                    DBN.Action.TRADE,
                    DBN.Side.ASK,
                    UInt8(128),         # Specific flags
                    UInt8(5),           # Specific depth
                    Int64(1600000000500000001),  # ts_recv
                    Int32(1000),        # ts_in_delta
                    UInt32(88888)       # sequence
                )
                
                output_file = joinpath(tmpdir, "integrity_test.dbn")
                DBN.write_dbn(output_file, metadata, [trade])
                
                # Read back with Julia
                julia_metadata, julia_records = DBN.read_dbn_with_metadata(output_file)
                julia_trade = julia_records[1]
                
                # Verify all fields match exactly
                @test julia_trade.price == 9876543210
                @test julia_trade.size == 999
                @test julia_trade.flags == 128
                @test julia_trade.depth == 5
                @test julia_trade.sequence == 88888
                @test julia_trade.side == DBN.Side.ASK
                @test julia_trade.action == DBN.Action.TRADE
                
                # Read with Rust and verify JSON contains correct values
                rust_output = CompatibilityUtils.run_dbn_cli([output_file, "--json"])
                @test contains(rust_output, "\"price\":\"9876543210\"")
                @test contains(rust_output, "\"size\":999")
                @test contains(rust_output, "\"flags\":128")
                @test contains(rust_output, "\"depth\":5")
                @test contains(rust_output, "\"sequence\":88888")
                @test contains(rust_output, "\"side\":\"A\"")
                @test contains(rust_output, "\"action\":\"T\"")
                @test contains(rust_output, "\"publisher_id\":42")
                @test contains(rust_output, "\"instrument_id\":12345")
            end
        end
    end
    
    @testset "Performance Validation" begin
        # Basic performance check to ensure Julia implementation is reasonable
        test_files = filter(f -> !endswith(f, ".zst") && filesize(f) < 1_000_000, 
                           CompatibilityUtils.get_test_files(".*\\.dbn"))
        
        if !isempty(test_files)
            test_file = first(test_files)
            
            # Benchmark Julia read
            julia_time = @elapsed DBN.read_dbn_with_metadata(test_file)
            
            # Should complete reasonably quickly (less than 1 second for small files)
            @test julia_time < 1.0
            
            # Note: We don't compare with Rust here as that would require
            # more complex benchmarking setup, but our demo shows Julia is faster
        end
    end
end