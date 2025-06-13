

@testset "Phase 8: Missing Functionality Testing" begin
    
    @testset "DBNStream Iterator Tests" begin
        # Create a test file with multiple records
        test_file = tempname() * ".dbn"
        
        # Write test data
        metadata = Metadata(
            UInt8(DBN_VERSION),
            "TEST.BASIC",
            Schema.TRADES,
            1609459200000000000,  # 2021-01-01 00:00:00 UTC
            1609459260000000000,  # 2021-01-01 00:01:00 UTC
            UInt64(0),
            SType.RAW_SYMBOL,
            SType.RAW_SYMBOL,
            false,
            ["AAPL", "MSFT"],
            String[],
            String[],
            Tuple{String,String,Int64,Int64}[]
        )
        
        records = [
            TradeMsg(
                RecordHeader(UInt8(40), RType.MBP_0_MSG, UInt16(1), UInt32(1), 1609459200000000000),
                1500000000000,  # $150.00
                100,
                Action.TRADE,
                Side.BID,
                0x00,
                0,
                1609459200000000000,
                0,
                1
            ),
            TradeMsg(
                RecordHeader(UInt8(40), RType.MBP_0_MSG, UInt16(1), UInt32(2), 1609459210000000000),
                1510000000000,  # $151.00
                200,
                Action.TRADE,
                Side.ASK,
                0x00,
                0,
                1609459210000000000,
                0,
                2
            ),
            TradeMsg(
                RecordHeader(UInt8(40), RType.MBP_0_MSG, UInt16(1), UInt32(1), 1609459220000000000),
                1520000000000,  # $152.00
                150,
                Action.TRADE,
                Side.BID,
                0x00,
                0,
                1609459220000000000,
                0,
                3
            )
        ]
        
        # Write the test file
        write_dbn(test_file, metadata, records)
        
        @testset "Basic Iterator Functionality" begin
            stream = DBNStream(test_file)
            
            # Test that DBNStream is iterable
            @test stream isa DBNStream
            @test Base.IteratorSize(typeof(stream)) == Base.SizeUnknown()
            @test Base.eltype(typeof(stream)) == Any
            
            # Test iteration
            collected_records = collect(stream)
            @test length(collected_records) == 3
            
            # Verify records match what we wrote
            for (i, record) in enumerate(collected_records)
                @test record isa TradeMsg
                @test record.hd.instrument_id == records[i].hd.instrument_id
                @test record.hd.ts_event == records[i].hd.ts_event
                @test record.price == records[i].price
                @test record.size == records[i].size
                @test record.action == records[i].action
                @test record.side == records[i].side
            end
        end
        
        @testset "Iterator with for loop" begin
            # Test using for loop syntax
            record_count = 0
            total_volume = 0
            
            for record in DBNStream(test_file)
                record_count += 1
                if record isa TradeMsg
                    total_volume += record.size
                end
            end
            
            @test record_count == 3
            @test total_volume == 450  # 100 + 200 + 150
        end
        
        @testset "Iterator with empty file" begin
            empty_file = tempname() * ".dbn"
            empty_metadata = Metadata(
                UInt8(DBN_VERSION),
                "TEST.EMPTY",
                Schema.TRADES,
                0, 0, UInt64(0),
                SType.RAW_SYMBOL, SType.RAW_SYMBOL, false,
                String[], String[], String[], Tuple{String,String,Int64,Int64}[]
            )
            
            write_dbn(empty_file, empty_metadata, [])
            
            stream = DBNStream(empty_file)
            collected = collect(stream)
            @test length(collected) == 0
            
            # Clean up
            rm(empty_file, force=true)
        end
        
        # TODO: Fix compressed file streaming
        # @testset "Iterator with compressed file" begin
        #     # Create a compressed version
        #     compressed_file = test_file * ".zst"
        #     compress_dbn_file(test_file, compressed_file)
        #     
        #     # Test iterator works with compressed files
        #     stream = DBNStream(compressed_file)
        #     collected_records = collect(stream)
        #     @test length(collected_records) == 3
        #     
        #     # Verify first record
        #     @test collected_records[1] isa TradeMsg
        #     @test collected_records[1].price == 1500000000000
        #     
        #     # Clean up
        #     rm(compressed_file, force=true)
        # end
        
        @testset "Iterator state management" begin
            # Test manual iteration
            stream = DBNStream(test_file)
            state = iterate(stream)
            @test state !== nothing
            
            record1, iter_state = state
            @test record1 isa TradeMsg
            
            state = iterate(stream, iter_state)
            @test state !== nothing
            
            record2, iter_state = state
            @test record2 isa TradeMsg
            @test record2.hd.ts_event != record1.hd.ts_event
            
            state = iterate(stream, iter_state)
            @test state !== nothing
            
            record3, iter_state = state
            @test record3 isa TradeMsg
            
            # Should be at end now
            state = iterate(stream, iter_state)
            @test state === nothing
        end
        
        # Clean up
        rm(test_file, force=true)
    end
    
    @testset "Error/System Message Write Operations" begin
        test_file = tempname() * ".dbn"
        
        metadata = Metadata(
            UInt8(DBN_VERSION),
            "TEST.MSGS",
            Schema.TRADES,
            1609459200000000000,
            1609459260000000000,
            UInt64(0),
            SType.RAW_SYMBOL,
            SType.RAW_SYMBOL,
            false,
            String[],
            String[],
            String[],
            Tuple{String,String,Int64,Int64}[]
        )
        
        @testset "ErrorMsg Write/Read" begin
            # Create an ErrorMsg
            err_text = "Connection timeout occurred"
            err_length = UInt8(16 + length(err_text) + 1)  # header + message + null terminator
            error_msg = ErrorMsg(
                RecordHeader(err_length, RType.ERROR_MSG, UInt16(0), UInt32(0), 1609459200000000000),
                err_text
            )
            
            # Write and read back
            write_dbn(test_file, metadata, [error_msg])
            records = read_dbn(test_file)
            
            @test length(records) == 1
            @test records[1] isa ErrorMsg
            @test records[1].hd.rtype == RType.ERROR_MSG
            @test records[1].err == "Connection timeout occurred"
            
            rm(test_file, force=true)
        end
        
        @testset "SymbolMappingMsg Write/Read" begin
            # Create a SymbolMappingMsg
            in_symbol = "AAPL.NASDAQ"
            out_symbol = "12345"
            # Length: header(16) + stype_in(1) + pad(3) + len(2) + in_symbol + stype_out(1) + pad(3) + len(2) + out_symbol + timestamps(16)
            sym_length = UInt8(16 + 1 + 3 + 2 + length(in_symbol) + 1 + 3 + 2 + length(out_symbol) + 16)
            symbol_mapping = SymbolMappingMsg(
                RecordHeader(sym_length, RType.SYMBOL_MAPPING_MSG, UInt16(0), UInt32(0), 1609459200000000000),
                SType.RAW_SYMBOL,
                in_symbol,
                SType.INSTRUMENT_ID,
                out_symbol,
                1609459200000000000,
                1609459260000000000
            )
            
            # Write and read back
            write_dbn(test_file, metadata, [symbol_mapping])
            records = read_dbn(test_file)
            
            @test length(records) == 1
            @test records[1] isa SymbolMappingMsg
            @test records[1].hd.rtype == RType.SYMBOL_MAPPING_MSG
            @test records[1].stype_in == SType.RAW_SYMBOL
            @test records[1].stype_in_symbol == "AAPL.NASDAQ"
            @test records[1].stype_out == SType.INSTRUMENT_ID
            @test records[1].stype_out_symbol == "12345"
            
            rm(test_file, force=true)
        end
        
        @testset "SystemMsg Write/Read" begin
            # Create a SystemMsg
            msg_text = "Market open notification"
            code_text = "OPEN"
            msg_length = UInt8(16 + length(msg_text) + 1 + length(code_text) + 1)  # header + msg + null + code + null
            system_msg = SystemMsg(
                RecordHeader(msg_length, RType.SYSTEM_MSG, UInt16(0), UInt32(0), 1609459200000000000),
                msg_text,
                code_text
            )
            
            # Write and read back
            write_dbn(test_file, metadata, [system_msg])
            records = read_dbn(test_file)
            
            @test length(records) == 1
            @test records[1] isa SystemMsg
            @test records[1].hd.rtype == RType.SYSTEM_MSG
            @test records[1].msg == "Market open notification"
            @test records[1].code == "OPEN"
            
            rm(test_file, force=true)
        end
        
        @testset "Mixed Message Types Write/Read" begin
            # Test writing multiple message types together
            messages = [
                ErrorMsg(
                    RecordHeader(UInt8(16 + 10 + 1), RType.ERROR_MSG, UInt16(0), UInt32(0), 1609459200000000000),
                    "Test error"
                ),
                SystemMsg(
                    RecordHeader(UInt8(16 + 19 + 1 + 4 + 1), RType.SYSTEM_MSG, UInt16(0), UInt32(0), 1609459210000000000),
                    "Test system message",
                    "TEST"
                ),
                SymbolMappingMsg(
                    RecordHeader(UInt8(16 + 1 + 3 + 2 + 4 + 1 + 3 + 2 + 3 + 16), RType.SYMBOL_MAPPING_MSG, UInt16(0), UInt32(0), 1609459220000000000),
                    SType.RAW_SYMBOL,
                    "TEST",
                    SType.INSTRUMENT_ID,
                    "999",
                    1609459200000000000,
                    1609459260000000000
                )
            ]
            
            write_dbn(test_file, metadata, messages)
            records = read_dbn(test_file)
            
            @test length(records) == 3
            @test records[1] isa ErrorMsg
            @test records[2] isa SystemMsg
            @test records[3] isa SymbolMappingMsg
            
            # Verify order is preserved
            @test records[1].hd.ts_event < records[2].hd.ts_event
            @test records[2].hd.ts_event < records[3].hd.ts_event
            
            rm(test_file, force=true)
        end
    end
    
    @testset "Batch Compression Tests" begin
        # Create a temporary directory for test files
        test_dir = mktempdir()
        
        try
            # Create test files for a specific date
            test_date = Date("2024-01-15")
            date_str = "2024-01-15"
            
            # Create sample metadata
            metadata = Metadata(
                UInt8(DBN_VERSION),
                "TEST.BATCH",
                Schema.TRADES,
                1609459200000000000,
                1609459260000000000,
                UInt64(0),
                SType.RAW_SYMBOL,
                SType.RAW_SYMBOL,
                false,
                ["AAPL"],
                String[],
                String[],
                Tuple{String,String,Int64,Int64}[]
            )
            
            # Create test records
            record = TradeMsg(
                RecordHeader(UInt8(40), RType.MBP_0_MSG, UInt16(1), UInt32(1), 1609459200000000000),
                1500000000000,
                100,
                Action.TRADE,
                Side.BID,
                0x00,
                0,
                1609459200000000000,
                0,
                1
            )
            
            # Create multiple test files with the date pattern
            test_files = [
                joinpath(test_dir, "$(date_str)_trades.dbn"),
                joinpath(test_dir, "$(date_str)_mbp1.dbn"), 
                joinpath(test_dir, "$(date_str)_ohlcv.dbn")
            ]
            
            for file in test_files
                write_dbn(file, metadata, [record])
            end
            
            # Also create a file that shouldn't match the pattern
            other_file = joinpath(test_dir, "2024-01-16_trades.dbn")
            write_dbn(other_file, metadata, [record])
            
            @testset "compress_daily_files basic functionality" begin
                # Test compressing files for the specific date
                results = compress_daily_files(test_date, test_dir)
                
                # Should have compressed 3 files (not the 2024-01-16 file)
                @test length(results) == 3
                
                # Check that compressed files exist
                for file in test_files
                    compressed_file = replace(file, ".dbn" => ".dbn.zst")
                    @test isfile(compressed_file)
                    @test !isfile(file)  # Original should be deleted
                end
                
                # Check that the other date file was not touched
                @test isfile(other_file)
                
                # Verify compression results
                for result in results
                    @test result !== nothing
                    @test haskey(result, :original_size)
                    @test haskey(result, :compressed_size)
                    @test haskey(result, :compression_ratio)
                    @test haskey(result, :space_saved)
                    @test result[:compression_ratio] > 0
                    @test result[:space_saved] > 0
                end
            end
            
            @testset "compress_daily_files with custom pattern" begin
                # Create more test files
                additional_files = [
                    joinpath(test_dir, "custom_$(date_str)_data.dbn"),
                    joinpath(test_dir, "symbols_$(date_str).dbn")
                ]
                
                for file in additional_files
                    write_dbn(file, metadata, [record])
                end
                
                # Test with custom pattern - need to create regex dynamically
                custom_pattern = Regex(".*" * date_str * ".*\\.dbn\$")
                results = compress_daily_files(test_date, test_dir, pattern=custom_pattern)
                
                # Should compress all files containing the date
                @test length(results) == 2
                
                # Check compressed files exist
                for file in additional_files
                    compressed_file = replace(file, ".dbn" => ".dbn.zst")
                    @test isfile(compressed_file)
                    @test !isfile(file)
                end
            end
            
            @testset "compress_daily_files with no matching files" begin
                # Test with a date that has no files
                future_date = Date("2025-01-01")
                results = compress_daily_files(future_date, test_dir)
                
                # Should return empty results
                @test length(results) == 0
            end
            
            @testset "compress_daily_files error handling" begin
                # Create a file with invalid content
                bad_file = joinpath(test_dir, "$(date_str)_bad.dbn")
                open(bad_file, "w") do f
                    write(f, "invalid content")
                end
                
                # This should handle the error gracefully
                results = compress_daily_files(test_date, test_dir)
                
                # Should have one failed result (nothing)
                failed_count = count(r -> r === nothing, results)
                @test failed_count == 1
            end
            
        finally
            # Clean up the test directory
            rm(test_dir, recursive=true, force=true)
        end
    end
end