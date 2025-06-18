using Test
using DBN
using Dates
using JSON

# Include the compatibility utilities
include("compatibility_utils.jl")
using .CompatibilityUtils

@testset "DBN.jl Compatibility Tests" begin
    
    # Check if Rust CLI is available
    if !isfile(CompatibilityUtils.DBN_CLI_PATH)
        @warn "Rust DBN CLI not found. Skipping compatibility tests. Build with: cd /workspace/dbn/rust/dbn-cli && cargo build --release"
        return
    end
    
    @testset "Binary Format Compatibility" begin
        @testset "Read Rust-generated files" begin
            # Test various schemas
            test_patterns = [
                ("trades", ".*trades.*\\.dbn"),
                ("mbo", ".*mbo.*\\.dbn"),
                ("mbp-1", ".*mbp-1.*\\.dbn"),
                ("mbp-10", ".*mbp-10.*\\.dbn"),
                ("ohlcv", ".*ohlcv.*\\.dbn"),
                ("definition", ".*definition.*\\.dbn"),
                ("statistics", ".*statistics.*\\.dbn"),
                ("status", ".*status.*\\.dbn"),
                ("imbalance", ".*imbalance.*\\.dbn")
            ]
            
            for (schema_name, pattern) in test_patterns
                @testset "$schema_name schema" begin
                    files = CompatibilityUtils.get_test_files(pattern)
                    if isempty(files)
                        @warn "No test files found for pattern: $pattern"
                        continue
                    end
                    
                    for file in files
                        # Skip compressed files for now
                        if endswith(file, ".zst")
                            continue
                        end
                        
                        @test CompatibilityUtils.test_file_compatibility(file)
                    end
                end
            end
        end
    end
    
    @testset "Message Type Compatibility" begin
        # Test specific message types
        mktempdir() do tmpdir
            @testset "TradeMsg" begin
                # Create a trade message
                metadata = DBN.Metadata(
                    version=3,
                    dataset="TEST",
                    schema=DBN.RType.MBP_1_MSG,
                    start=DBN.DBNTimestamp(1000000000),
                    end_=DBN.DBNTimestamp(2000000000),
                    limit=1,
                    stype=DBN.SType.RAW_SYMBOL,
                    symbols=String[]
                )
                
                trade = DBN.TradeMsg(
                    hd=DBN.RecordHeader(
                        length=UInt8(sizeof(DBN.TradeMsg)),
                        rtype=DBN.RType.MBP_1_MSG,
                        publisher_id=1,
                        instrument_id=100,
                        ts_event=1500000000
                    ),
                    price=1234500000,  # $123.45
                    size=100,
                    action=DBN.Action.TRADE,
                    side=DBN.Side.BID,
                    flags=0,
                    depth=0,
                    ts_recv=1500000000,
                    ts_in_delta=0,
                    sequence=1
                )
                
                # Write and test round-trip
                output_file = joinpath(tmpdir, "trade_test.dbn")
                DBN.write_dbn(output_file, metadata, [trade])
                
                # Verify Rust can read it
                rust_output = CompatibilityUtils.run_dbn_cli([output_file, "--json"])
                @test !isempty(rust_output)
                @test contains(rust_output, "\"price\":1234500000")
            end
            
            @testset "MBOMsg" begin
                metadata = DBN.Metadata(
                    version=3,
                    dataset="TEST",
                    schema=DBN.RType.MBO_MSG,
                    start=DBN.DBNTimestamp(1000000000),
                    end_=DBN.DBNTimestamp(2000000000),
                    limit=1,
                    stype=DBN.SType.RAW_SYMBOL,
                    symbols=String[]
                )
                
                mbo = DBN.MBOMsg(
                    hd=DBN.RecordHeader(
                        length=UInt8(sizeof(DBN.MBOMsg)),
                        rtype=DBN.RType.MBO_MSG,
                        publisher_id=1,
                        instrument_id=100,
                        ts_event=1500000000
                    ),
                    order_id=999,
                    price=1234500000,
                    size=50,
                    flags=DBN.FLAG_LAST,
                    channel_id=1,
                    action=DBN.Action.ADD,
                    side=DBN.Side.ASK,
                    ts_recv=1500000000,
                    ts_in_delta=0,
                    sequence=1
                )
                
                output_file = joinpath(tmpdir, "mbo_test.dbn")
                DBN.write_dbn(output_file, metadata, [mbo])
                
                rust_output = CompatibilityUtils.run_dbn_cli([output_file, "--json"])
                @test !isempty(rust_output)
                @test contains(rust_output, "\"order_id\":999")
            end
            
            @testset "OHLCVMsg" begin
                metadata = DBN.Metadata(
                    version=3,
                    dataset="TEST",
                    schema=DBN.RType.OHLCV_1S_MSG,
                    start=DBN.DBNTimestamp(1000000000),
                    end_=DBN.DBNTimestamp(2000000000),
                    limit=1,
                    stype=DBN.SType.RAW_SYMBOL,
                    symbols=String[]
                )
                
                ohlcv = DBN.OHLCVMsg(
                    hd=DBN.RecordHeader(
                        length=UInt8(sizeof(DBN.OHLCVMsg)),
                        rtype=DBN.RType.OHLCV_1S_MSG,
                        publisher_id=1,
                        instrument_id=100,
                        ts_event=1500000000
                    ),
                    open=1000000000,
                    high=1100000000,
                    low=900000000,
                    close=1050000000,
                    volume=1000
                )
                
                output_file = joinpath(tmpdir, "ohlcv_test.dbn")
                DBN.write_dbn(output_file, metadata, [ohlcv])
                
                rust_output = CompatibilityUtils.run_dbn_cli([output_file, "--json"])
                @test !isempty(rust_output)
                @test contains(rust_output, "\"open\":1000000000")
            end
        end
    end
    
    @testset "Encoding Compatibility" begin
        # Test CSV and JSON encoding compatibility
        test_files = CompatibilityUtils.get_test_files(".*trades.*\\.dbn")
        if isempty(test_files)
            @warn "No trades files found for encoding compatibility tests"
            return
        end
        test_file = first(test_files)
        
        mktempdir() do tmpdir
            @testset "CSV Export" begin
                # Export with Julia
                julia_csv_file = joinpath(tmpdir, "julia_export.csv")
                DBN.dbn_to_csv(test_file, julia_csv_file)
                julia_csv = read(julia_csv_file, String)
                
                # Export with Rust
                rust_csv = CompatibilityUtils.run_dbn_cli([test_file, "--csv"])
                
                @test CompatibilityUtils.compare_csv_output(julia_csv, rust_csv)
            end
            
            @testset "JSON Export" begin
                # Export with Julia
                julia_json_file = joinpath(tmpdir, "julia_export.json")
                DBN.dbn_to_json(test_file, julia_json_file)
                julia_json = read(julia_json_file, String)
                
                # Export with Rust
                rust_json = CompatibilityUtils.run_dbn_cli([test_file, "--json"])
                
                @test CompatibilityUtils.compare_json_output(julia_json, rust_json)
            end
        end
    end
    
    @testset "Compression Compatibility" begin
        # Test Zstd compression compatibility
        compressed_files = filter(f -> endswith(f, ".zst"), CompatibilityUtils.get_test_files())
        
        if !isempty(compressed_files)
            test_file = first(compressed_files)
            
            @testset "Read compressed files" begin
                # Both implementations should produce same output
                @test CompatibilityUtils.test_file_compatibility(test_file)
            end
            
            mktempdir() do tmpdir
                @testset "Write compressed files" begin
                    # Create test data
                    metadata = DBN.Metadata(
                        version=3,
                        dataset="TEST",
                        schema=DBN.RType.MBP_1_MSG,
                        start=DBN.DBNTimestamp(1000000000),
                        end_=DBN.DBNTimestamp(2000000000),
                        limit=1,
                        stype=DBN.SType.RAW_SYMBOL,
                        symbols=String[]
                    )
                    
                    trade = DBN.TradeMsg(
                        hd=DBN.RecordHeader(
                            length=UInt8(sizeof(DBN.TradeMsg)),
                            rtype=DBN.RType.MBP_1_MSG,
                            publisher_id=1,
                            instrument_id=100,
                            ts_event=1500000000
                        ),
                        price=1234500000,
                        size=100,
                        action=DBN.Action.TRADE,
                        side=DBN.Side.BID,
                        flags=0,
                        depth=0,
                        ts_recv=1500000000,
                        ts_in_delta=0,
                        sequence=1
                    )
                    
                    # Write compressed file
                    compressed_file = joinpath(tmpdir, "test.dbn.zst")
                    DBN.write_dbn(compressed_file, metadata, [trade])
                    
                    # Verify Rust can read it
                    rust_output = CompatibilityUtils.run_dbn_cli([compressed_file, "--json"])
                    @test !isempty(rust_output)
                    @test contains(rust_output, "\"price\":1234500000")
                end
            end
        end
    end
    
    @testset "DBN Version Compatibility" begin
        # Test files from different DBN versions
        for version in [1, 2, 3]
            version_files = filter(f -> contains(f, "v$version"), CompatibilityUtils.get_test_files())
            
            if !isempty(version_files)
                @testset "DBN v$version" begin
                    test_file = first(version_files)
                    @test CompatibilityUtils.test_file_compatibility(test_file)
                end
            end
        end
    end
    
    @testset "Metadata Compatibility" begin
        # Test metadata extraction
        test_files = CompatibilityUtils.get_test_files(".*trades.*\\.dbn")
        if isempty(test_files)
            @warn "No trades files found for metadata compatibility tests"
            return
        end
        test_file = first(test_files)
        
        # Get metadata with Rust
        rust_metadata = CompatibilityUtils.run_dbn_cli([test_file, "--json", "--metadata"])
        
        # Get metadata with Julia
        metadata, _ = DBN.read_dbn(test_file)
        julia_metadata = JSON.json(metadata)
        
        # Both should have similar structure
        @test contains(rust_metadata, "\"version\"")
        @test contains(rust_metadata, "\"dataset\"")
        @test contains(julia_metadata, "\"version\"")
        @test contains(julia_metadata, "\"dataset\"")
    end
    
    @testset "Edge Cases" begin
        mktempdir() do tmpdir
            @testset "Empty file" begin
                # Create empty DBN file
                metadata = DBN.Metadata(
                    version=3,
                    dataset="TEST",
                    schema=DBN.RType.MBP_1_MSG,
                    start=DBN.DBNTimestamp(1000000000),
                    end_=DBN.DBNTimestamp(1000000000),
                    limit=0,
                    stype=DBN.SType.RAW_SYMBOL,
                    symbols=String[]
                )
                
                empty_file = joinpath(tmpdir, "empty.dbn")
                DBN.write_dbn(empty_file, metadata, [])
                
                # Rust should handle empty file
                rust_output = CompatibilityUtils.run_dbn_cli([empty_file, "--json"])
                @test isempty(strip(rust_output))
            end
            
            @testset "Single record" begin
                metadata = DBN.Metadata(
                    version=3,
                    dataset="TEST",
                    schema=DBN.RType.MBP_1_MSG,
                    start=DBN.DBNTimestamp(1000000000),
                    end_=DBN.DBNTimestamp(2000000000),
                    limit=1,
                    stype=DBN.SType.RAW_SYMBOL,
                    symbols=String[]
                )
                
                trade = DBN.TradeMsg(
                    hd=DBN.RecordHeader(
                        length=UInt8(sizeof(DBN.TradeMsg)),
                        rtype=DBN.RType.MBP_1_MSG,
                        publisher_id=1,
                        instrument_id=100,
                        ts_event=1500000000
                    ),
                    price=1234500000,
                    size=100,
                    action=DBN.Action.TRADE,
                    side=DBN.Side.BID,
                    flags=0,
                    depth=0,
                    ts_recv=1500000000,
                    ts_in_delta=0,
                    sequence=1
                )
                
                single_file = joinpath(tmpdir, "single.dbn")
                DBN.write_dbn(single_file, metadata, [trade])
                
                @test CompatibilityUtils.test_round_trip(single_file, tmpdir)
            end
        end
    end
    
    @testset "Streaming Compatibility" begin
        # Test streaming reads
        test_files = CompatibilityUtils.get_test_files(".*trades.*\\.dbn")
        if isempty(test_files)
            @warn "No trades files found for streaming compatibility tests"
            return
        end
        test_file = first(test_files)
        
        # Stream with Julia
        julia_records = []
        for record in DBN.DBNStream(test_file)
            push!(julia_records, record)
        end
        
        # Get all records with Rust
        rust_json = CompatibilityUtils.run_dbn_cli([test_file, "--json"])
        rust_lines = filter(!isempty, split(rust_json, '\n'))
        
        @test length(julia_records) == length(rust_lines)
    end
    
    @testset "Performance Comparison" begin
        # Only run on reasonably sized files
        test_files = filter(f -> !endswith(f, ".zst") && filesize(f) < 10_000_000, 
                           CompatibilityUtils.get_test_files())
        
        if !isempty(test_files)
            test_file = first(test_files)
            perf = CompatibilityUtils.benchmark_read_performance(test_file, iterations=5)
            
            @info "Performance comparison for $(basename(test_file)):" julia=perf.julia rust=perf.rust ratio=perf.ratio
            
            # Julia should be within reasonable range of Rust performance
            @test perf.ratio < 10.0  # Julia should not be more than 10x slower
        end
    end
end