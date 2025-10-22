# Phase 6: Compression Testing

@testset "Phase 6: Compression Features" begin
    
    @testset "Compressed File Reading" begin
        @testset "Auto-detection of compressed files" begin
            # Test automatic detection by file extension
            compressed_files = [
                "test/data/test_data.trades.v3.dbn.zst",
                "test/data/test_data.mbp-1.v3.dbn.zst", 
                "test/data/test_data.mbo.v3.dbn.zst",
                "test/data/test_data.ohlcv-1s.v3.dbn.zst"
            ]
            
            for file in compressed_files
                if isfile(file)
                    @test_nowarn begin
                        records = read_dbn(file)
                        @test length(records) > 0
                        println("Successfully read $(length(records)) records from $file")
                    end
                end
            end
        end
        
        @testset "Zstd magic number detection" begin
            # Test detection by magic bytes regardless of extension
            test_file = "test/data/test_data.trades.v3.dbn.zst"
            if isfile(test_file)
                # Copy to file without .zst extension to test magic byte detection
                temp_file = tempname()
                cp(test_file, temp_file)
                
                try
                    @test_nowarn begin
                        records = read_dbn(temp_file)
                        @test length(records) > 0
                    end
                finally
                    safe_rm(temp_file)
                end
            end
        end
        
        @testset "Compare compressed vs uncompressed content" begin
            # Test that compressed and uncompressed versions have identical content
            test_pairs = [
                ("test/data/test_data.trades.dbn", "test/data/test_data.trades.v3.dbn.zst"),
                ("test/data/test_data.mbp-1.dbn", "test/data/test_data.mbp-1.v3.dbn.zst"),
                ("test/data/test_data.ohlcv-1s.dbn", "test/data/test_data.ohlcv-1s.v3.dbn.zst")
            ]
            
            for (uncompressed, compressed) in test_pairs
                if isfile(uncompressed) && isfile(compressed)
                    records_uncomp = read_dbn(uncompressed)
                    records_comp = read_dbn(compressed)
                    
                    @test length(records_uncomp) == length(records_comp)
                    
                    # Compare first few records in detail
                    for i in 1:min(5, length(records_uncomp))
                        @test typeof(records_uncomp[i]) == typeof(records_comp[i])
                        # Test that timestamps match
                        if hasproperty(records_uncomp[i], :hd) && hasproperty(records_uncomp[i].hd, :ts_event)
                            @test records_uncomp[i].hd.ts_event == records_comp[i].hd.ts_event
                        end
                    end
                end
            end
        end
    end
    
    @testset "compress_dbn_file Function" begin
        @testset "Basic compression functionality" begin
            # Create test data
            test_input = tempname()
            test_output = tempname()
            
            try
                # Create simple test file
                metadata = Metadata(
                    3, "XNAS", Schema.TRADES, 1640995200000000000, 1640995260000000000, 
                    nothing, SType.RAW_SYMBOL, SType.RAW_SYMBOL, false,
                    ["AAPL"], String[], String[], Tuple{String,String,Int64,Int64}[]
                )
                
                # Create sample records
                records = []
                for i in 1:10
                    hd = RecordHeader(40, RType.MBP_0_MSG, 1, 12345, 1640995200000000000 + i*1000000000)
                    trade = TradeMsg(hd, 150000000000, 100, Action.TRADE, Side.BID, 0, 0, 
                                   1640995200000000000 + i*1000000000, 0, UInt32(i))
                    push!(records, trade)
                end
                
                # Write test file
                write_dbn(test_input, metadata, records)
                
                # Test compression
                @test_nowarn begin
                    stats = compress_dbn_file(test_input, test_output)
                    
                    @test haskey(stats, :original_size)
                    @test haskey(stats, :compressed_size) 
                    @test haskey(stats, :compression_ratio)
                    @test haskey(stats, :space_saved)
                    
                    @test stats.original_size > 0
                    @test stats.compressed_size > 0
                    @test stats.space_saved >= 0
                    @test 0.0 <= stats.compression_ratio <= 1.0
                    
                    println("Compression stats: $(stats)")
                end
                
                # Verify compressed file can be read
                @test_nowarn begin
                    compressed_records = read_dbn(test_output)
                    @test length(compressed_records) == length(records)
                end
                
            finally
                safe_rm(test_input)
                safe_rm(test_output)
            end
        end
        
        @testset "Compression with delete_original option" begin
            test_input = tempname()
            test_output = tempname()
            
            try
                # Create minimal test file
                metadata = Metadata(
                    3, "TEST", Schema.TRADES, 1640995200000000000, 1640995260000000000,
                    nothing, SType.RAW_SYMBOL, SType.RAW_SYMBOL, false,
                    ["TEST"], String[], String[], Tuple{String,String,Int64,Int64}[]
                )
                write_dbn(test_input, metadata, [])
                
                @test isfile(test_input)
                
                # Compress with delete_original=true
                stats = compress_dbn_file(test_input, test_output, delete_original=true)
                
                @test !isfile(test_input)  # Original should be deleted
                @test isfile(test_output)   # Compressed file should exist
                
            finally
                safe_rm(test_input)
                safe_rm(test_output)
            end
        end
        
        @testset "Compression error handling" begin
            # Test with non-existent input file
            @test_throws SystemError compress_dbn_file("nonexistent.dbn", "output.dbn.zst")
            
            # Test with invalid output directory
            test_input = tempname()
            try
                metadata = Metadata(
                    3, "TEST", Schema.TRADES, 1640995200000000000, 1640995260000000000,
                    nothing, SType.RAW_SYMBOL, SType.RAW_SYMBOL, false,
                    ["TEST"], String[], String[], Tuple{String,String,Int64,Int64}[]
                )
                write_dbn(test_input, metadata, [])
                
                @test_throws SystemError compress_dbn_file(test_input, "/invalid/path/output.dbn.zst")
                
            finally
                safe_rm(test_input)
            end
        end
    end
    
    @testset "compress_daily_files Function" begin
        @testset "Batch compression functionality" begin
            temp_dir = mktempdir()
            
            try
                # Create test files for a specific date
                test_date = Date("2024-01-15")
                date_str = "2024-01-15"
                
                test_files = [
                    joinpath(temp_dir, "$(date_str)_trades.dbn"),
                    joinpath(temp_dir, "$(date_str)_mbp1.dbn"),
                    joinpath(temp_dir, "$(date_str)_ohlcv.dbn")
                ]
                
                # Create test metadata and records
                metadata = Metadata(
                    3, "TEST", Schema.TRADES, 1640995200000000000, 1640995260000000000,
                    nothing, SType.RAW_SYMBOL, SType.RAW_SYMBOL, false,
                    ["TEST"], String[], String[], Tuple{String,String,Int64,Int64}[]
                )
                
                records = [
                    TradeMsg(
                        RecordHeader(40, RType.MBP_0_MSG, 1, 12345, 1640995200000000000),
                        150000000000, 100, Action.TRADE, Side.BID, 0, 0, 
                        1640995200000000000, 0, UInt32(1)
                    )
                ]
                
                # Write test files
                for file in test_files
                    write_dbn(file, metadata, records)
                end
                
                # Test batch compression
                results = compress_daily_files(test_date, temp_dir)
                
                @test length(results) == length(test_files)
                
                for (i, result) in enumerate(results)
                    if result !== nothing
                        @test haskey(result, :original_size)
                        @test haskey(result, :compressed_size)
                        @test result.original_size > 0
                        
                        # Check compressed file exists
                        compressed_file = replace(test_files[i], ".dbn" => ".dbn.zst")
                        @test isfile(compressed_file)
                        
                        # Original should be deleted (delete_original=true by default)
                        @test !isfile(test_files[i])
                    end
                end
                
            finally
                rm(temp_dir, recursive=true, force=true)
            end
        end
        
        @testset "Pattern matching for daily files" begin
            temp_dir = mktempdir()
            
            try
                test_date = Date("2024-02-20")
                date_str = "2024-02-20"
                
                # Create files that should match
                matching_files = [
                    joinpath(temp_dir, "$(date_str)_data.dbn"),
                    joinpath(temp_dir, "symbols_$(date_str).dbn")
                ]
                
                # Create files that should NOT match
                non_matching_files = [
                    joinpath(temp_dir, "$(date_str)_data.txt"),  # Wrong extension
                    joinpath(temp_dir, "2024-02-21_data.dbn"),  # Wrong date
                    joinpath(temp_dir, "other_$(date_str).csv") # Wrong extension
                ]
                
                metadata = Metadata(
                    3, "TEST", Schema.TRADES, 1640995200000000000, 1640995260000000000,
                    nothing, SType.RAW_SYMBOL, SType.RAW_SYMBOL, false,
                    ["TEST"], String[], String[], Tuple{String,String,Int64,Int64}[]
                )
                
                # Create all files
                for file in vcat(matching_files, non_matching_files)
                    if endswith(file, ".dbn")
                        write_dbn(file, metadata, [])
                    else
                        touch(file)
                    end
                end
                
                # Test compression - should only process matching files
                results = compress_daily_files(test_date, temp_dir)
                
                # Should only process .dbn files with the date
                @test length(results) == length(matching_files)
                
                # Check that only matching files were processed
                for file in matching_files
                    compressed_file = replace(file, ".dbn" => ".dbn.zst")
                    @test isfile(compressed_file)
                    @test !isfile(file)  # Original deleted
                end
                
                # Non-matching files should still exist
                for file in non_matching_files
                    @test isfile(file)
                end
                
            finally
                rm(temp_dir, recursive=true, force=true)
            end
        end
    end
    
    @testset "Compression Stats and File Size Verification" begin
        @testset "Compression ratio calculations" begin
            test_input = tempname()
            test_output = tempname()
            
            try
                # Create test file with repetitive data (should compress well)
                metadata = Metadata(
                    3, "REPEAT", Schema.TRADES, 1640995200000000000, 1640995260000000000,
                    nothing, SType.RAW_SYMBOL, SType.RAW_SYMBOL, false,
                    ["AAPL"], String[], String[], Tuple{String,String,Int64,Int64}[]
                )
                
                # Create many similar records (should compress well)
                records = []
                for i in 1:1000
                    hd = RecordHeader(40, RType.MBP_0_MSG, 1, 12345, 1640995200000000000 + i*1000000)
                    trade = TradeMsg(hd, 150000000000, 100, Action.TRADE, Side.BID, 0, 0, 
                                   1640995200000000000 + i*1000000, 0, UInt32(i))
                    push!(records, trade)
                end
                
                write_dbn(test_input, metadata, records)
                
                original_size = filesize(test_input)
                @test original_size > 0
                
                stats = compress_dbn_file(test_input, test_output)
                
                # Verify stats accuracy
                @test stats.original_size == original_size
                @test stats.compressed_size == filesize(test_output)
                @test stats.space_saved == (original_size - stats.compressed_size)
                @test stats.compression_ratio ≈ (1.0 - stats.compressed_size / original_size)
                
                # For repetitive data, we should get decent compression
                @test stats.compression_ratio > 0.1  # At least 10% compression
                @test stats.space_saved > 0
                
                println("Compression achieved: $(round(stats.compression_ratio * 100, digits=2))%")
                println("Space saved: $(stats.space_saved) bytes")
                
            finally
                safe_rm(test_input)
                safe_rm(test_output)
            end
        end
        
        @testset "File size comparisons" begin
            # Test with existing compressed test data
            test_pairs = [
                ("test/data/test_data.trades.dbn", "test/data/test_data.trades.v3.dbn.zst"),
                ("test/data/test_data.ohlcv-1s.dbn", "test/data/test_data.ohlcv-1s.v3.dbn.zst")
            ]
            
            for (uncompressed_file, compressed_file) in test_pairs
                if isfile(uncompressed_file) && isfile(compressed_file)
                    original_size = filesize(uncompressed_file)
                    compressed_size = filesize(compressed_file)
                    
                    @test original_size > 0
                    @test compressed_size > 0
                    @test compressed_size < original_size  # Compression should reduce size
                    
                    ratio = 1.0 - (compressed_size / original_size)
                    @test ratio > 0.0  # Should achieve some compression
                    
                    println("File: $(basename(uncompressed_file))")
                    println("  Original: $(original_size) bytes")
                    println("  Compressed: $(compressed_size) bytes") 
                    println("  Ratio: $(round(ratio * 100, digits=2))%")
                end
            end
        end
    end
    
    @testset "Error Handling and Edge Cases" begin
        @testset "Corrupted compressed files" begin
            # Create a file with invalid zstd header
            corrupted_file = tempname()
            try
                open(corrupted_file, "w") do io
                    # Write fake zstd magic bytes followed by garbage
                    write(io, UInt8[0x28, 0xB5, 0x2F, 0xFD])  # Zstd magic
                    write(io, rand(UInt8, 100))  # Random garbage
                end
                
                @test_throws Exception read_dbn(corrupted_file)
                
            finally
                safe_rm(corrupted_file)
            end
        end
        
        @testset "Empty file compression" begin
            test_input = tempname()
            test_output = tempname()
            
            try
                # Create empty DBN file
                metadata = Metadata(
                    3, "EMPTY", Schema.TRADES, 1640995200000000000, 1640995260000000000,
                    nothing, SType.RAW_SYMBOL, SType.RAW_SYMBOL, false,
                    [], String[], String[], Tuple{String,String,Int64,Int64}[]
                )
                write_dbn(test_input, metadata, [])
                
                @test_nowarn begin
                    stats = compress_dbn_file(test_input, test_output)
                    @test stats.original_size > 0  # Should have header at least
                    @test stats.compressed_size > 0
                end
                
                # Should be able to read compressed empty file
                records = read_dbn(test_output)
                @test length(records) == 0
                
            finally
                safe_rm(test_input)
                safe_rm(test_output)
            end
        end
        
        @testset "Mixed record type compression" begin
            test_input = tempname()
            test_output = tempname()
            
            try
                metadata = Metadata(
                    3, "MIXED", Schema.MBO, 1640995200000000000, 1640995260000000000,
                    nothing, SType.RAW_SYMBOL, SType.RAW_SYMBOL, false,
                    ["MIXED"], String[], String[], Tuple{String,String,Int64,Int64}[]
                )
                
                # Create mixed record types
                records = []
                
                # MBO record
                mbo_hd = RecordHeader(56, RType.MBO_MSG, 1, 12345, 1640995200000000000)
                mbo = MBOMsg(mbo_hd, 98765, 150000000000, 100, 0, 1, Action.ADD, Side.BID,
                           1640995200000000000, 0, UInt32(1))
                push!(records, mbo)
                
                # Trade record  
                trade_hd = RecordHeader(40, RType.MBP_0_MSG, 1, 12345, 1640995201000000000)
                trade = TradeMsg(trade_hd, 150000000000, 100, Action.TRADE, Side.BID, 0, 0,
                               1640995201000000000, 0, UInt32(2))
                push!(records, trade)
                
                write_dbn(test_input, metadata, records)
                
                @test_nowarn begin
                    stats = compress_dbn_file(test_input, test_output)
                    @test stats.original_size > 0
                    @test stats.compressed_size > 0
                end
                
                # Verify all record types preserved
                compressed_records = read_dbn(test_output)
                @test length(compressed_records) == 2
                @test isa(compressed_records[1], MBOMsg)
                @test isa(compressed_records[2], TradeMsg)
                
            finally
                safe_rm(test_input)
                safe_rm(test_output)
            end
        end
    end
    
end