using Test
using DBN
using Dates

@testset "Phase 9: Edge Cases and Error Handling" begin
    
    @testset "Invalid/Corrupted Files" begin
        @testset "Corrupted DBN header" begin
            # Create a file with invalid magic bytes
            corrupted_file = tempname() * ".dbn"
            try
                open(corrupted_file, "w") do io
                    write(io, b"INVALID_MAGIC")
                    write(io, zeros(UInt8, 100))  # Random data
                end
                
                @test_throws ErrorException read_dbn(corrupted_file)
                @test_throws ErrorException DBNDecoder(corrupted_file)
            finally
                safe_rm(corrupted_file)
            end
        end
        
        @testset "Truncated header" begin
            # Create a file with incomplete header
            truncated_file = tempname() * ".dbn"
            try
                open(truncated_file, "w") do io
                    write(io, b"DBN\x02")  # Only write 4 bytes of header
                end
                
                @test_throws Exception read_dbn(truncated_file)
            finally
                safe_rm(truncated_file)
            end
        end
        
        @testset "Invalid version" begin
            # Create a file with unsupported version
            invalid_version_file = tempname() * ".dbn"
            try
                open(invalid_version_file, "w") do io
                    # Write DBN header with invalid version (255)
                    write(io, b"DBN")
                    write(io, UInt8(255))  # Invalid version
                    write(io, zeros(UInt8, 100))  # Pad with zeros
                end
                
                @test_throws Exception read_dbn(invalid_version_file)
            finally
                safe_rm(invalid_version_file)
            end
        end
    end
    
    @testset "Empty Files" begin
        @testset "Completely empty file" begin
            empty_file = tempname() * ".dbn"
            try
                touch(empty_file)  # Create empty file
                
                @test_throws Exception read_dbn(empty_file)
                @test_throws Exception DBNDecoder(empty_file)
            finally
                safe_rm(empty_file)
            end
        end
        
        @testset "File with only header (no records)" begin
            header_only_file = tempname() * ".dbn"
            try
                metadata = Metadata(
                    UInt8(3),                    # version
                    "TEST",                      # dataset
                    Schema.TRADES,               # schema
                    1000000000,                  # start_ts
                    2000000000,                  # end_ts
                    UInt64(0),                   # limit
                    SType.RAW_SYMBOL,            # stype_in
                    SType.INSTRUMENT_ID,         # stype_out
                    false,                       # ts_out
                    String[],                    # symbols
                    String[],                    # partial
                    String[],                    # not_found
                    Tuple{String,String,Int64,Int64}[]  # mappings
                )
                
                # Create a header-only file using write_dbn with empty records
                write_dbn(header_only_file, metadata, TradeMsg[])
                
                # Should be able to read header-only file
                records = read_dbn(header_only_file)
                @test isempty(records)
                
                # Streaming should also work
                stream_records = collect(DBNStream(header_only_file))
                @test isempty(stream_records)
            finally
                safe_rm(header_only_file)
            end
        end
    end
    
    @testset "Boundary Values" begin
        @testset "Price boundaries" begin
            price_boundary_file = tempname() * ".dbn"
            try
                metadata = Metadata(
                    UInt8(3),                    # version
                    "TEST",                      # dataset
                    Schema.TRADES,               # schema
                    1000000000,                  # start_ts
                    2000000000,                  # end_ts
                    UInt64(0),                   # limit
                    SType.RAW_SYMBOL,            # stype_in
                    SType.INSTRUMENT_ID,         # stype_out
                    false,                       # ts_out
                    String[],                    # symbols
                    String[],                    # partial
                    String[],                    # not_found
                    Tuple{String,String,Int64,Int64}[]  # mappings
                )
                
                # Test with various price boundaries
                prices = [
                    0,  # Zero price
                    1,  # Minimum non-zero
                    typemax(Int64),  # Max price
                    UNDEF_PRICE,  # Undefined price
                    -1000000000  # Negative price (valid in some markets)
                ]
                
                trades = TradeMsg[]
                for (i, price) in enumerate(prices)
                    trade = TradeMsg(
                        RecordHeader(
                            UInt8(sizeof(TradeMsg) ÷ DBN.LENGTH_MULTIPLIER),
                            RType.MBP_0_MSG,
                            UInt16(1),
                            UInt32(i),
                            1500000000
                        ),
                        price,               # price
                        UInt32(100),         # size
                        Action.ADD,          # action
                        Side.BID,            # side
                        UInt8(0),            # flags
                        UInt8(0),            # depth
                        Int64(1500000000),   # ts_recv
                        Int32(0),            # ts_in_delta
                        UInt32(i)            # sequence
                    )
                    push!(trades, trade)
                end
                
                # Write and read back
                write_dbn(price_boundary_file, metadata, trades)
                records = read_dbn(price_boundary_file)
                @test length(records) == length(prices)
                
                for (i, record) in enumerate(records)
                    @test record.price == prices[i]
                    
                    # Test price conversion functions
                    if prices[i] == UNDEF_PRICE
                        @test isnan(price_to_float(record.price))
                    else
                        float_price = price_to_float(record.price)
                        @test !isnan(float_price)
                        # Round-trip conversion should preserve value (within precision)
                        @test abs(float_to_price(float_price) - record.price) <= 1
                    end
                end
            finally
                safe_rm(price_boundary_file)
            end
        end
        
        @testset "Timestamp boundaries" begin
            timestamp_file = tempname() * ".dbn"
            try
                metadata = Metadata(
                    UInt8(3),                    # version
                    "TEST",                      # dataset
                    Schema.TRADES,               # schema
                    0,                           # start_ts (min timestamp)
                    typemax(Int64),              # end_ts (max timestamp)
                    UInt64(0),                   # limit
                    SType.RAW_SYMBOL,            # stype_in
                    SType.INSTRUMENT_ID,         # stype_out
                    false,                       # ts_out
                    String[],                    # symbols
                    String[],                    # partial
                    String[],                    # not_found
                    Tuple{String,String,Int64,Int64}[]  # mappings
                )
                
                # Test with various timestamp boundaries
                timestamps = [
                    0,  # Unix epoch
                    typemax(Int64),  # Max int64
                    1_000_000_000_000_000_000,  # 1 second in nanoseconds
                    UNDEF_TIMESTAMP  # Undefined timestamp
                ]
                
                trades = TradeMsg[]
                for (i, ts) in enumerate(timestamps)
                    trade = TradeMsg(
                        RecordHeader(
                            UInt8(sizeof(TradeMsg) ÷ DBN.LENGTH_MULTIPLIER),
                            RType.MBP_0_MSG,
                            UInt16(1),
                            UInt32(i),
                            ts
                        ),
                        Int64(100000000),    # price
                        UInt32(100),         # size
                        Action.ADD,          # action
                        Side.BID,            # side
                        UInt8(0),            # flags
                        UInt8(0),            # depth
                        ts,                  # ts_recv
                        Int32(0),            # ts_in_delta
                        UInt32(i)            # sequence
                    )
                    push!(trades, trade)
                end
                
                # Write and read back
                write_dbn(timestamp_file, metadata, trades)
                records = read_dbn(timestamp_file)
                @test length(records) == length(timestamps)
                
                for (i, record) in enumerate(records)
                    @test record.hd.ts_event == timestamps[i]
                    @test record.ts_recv == timestamps[i]
                end
            finally
                safe_rm(timestamp_file)
            end
        end
    end
    
    @testset "Mixed Record Types" begin
        mixed_file = tempname() * ".dbn"
        try
            metadata = Metadata(
                UInt8(3),                    # version
                "TEST",                      # dataset
                Schema.MBO,                  # schema
                1000000000,                  # start_ts
                2000000000,                  # end_ts
                UInt64(0),                   # limit
                SType.RAW_SYMBOL,            # stype_in
                SType.INSTRUMENT_ID,         # stype_out
                false,                       # ts_out
                String[],                    # symbols
                String[],                    # partial
                String[],                    # not_found
                Tuple{String,String,Int64,Int64}[]  # mappings
            )
            
            # Create different record types as vectors
            mbo = MBOMsg(
                RecordHeader(
                    UInt8(sizeof(MBOMsg) ÷ DBN.LENGTH_MULTIPLIER),
                    RType.MBO_MSG,
                    UInt16(1),
                    UInt32(100),
                    1100000000
                ),
                UInt64(1001),        # order_id
                Int64(100000000),    # price
                UInt32(100),         # size
                UInt8(0),            # flags
                UInt8(0),            # channel_id
                Action.ADD,          # action
                Side.BID,            # side
                Int64(1100000000),   # ts_recv
                Int32(0),            # ts_in_delta
                UInt32(1)            # sequence
            )
            
            trade = TradeMsg(
                RecordHeader(
                    UInt8(sizeof(TradeMsg) ÷ DBN.LENGTH_MULTIPLIER),
                    RType.MBP_0_MSG,
                    UInt16(1),
                    UInt32(100),
                    1200000000
                ),
                Int64(101000000),    # price
                UInt32(50),          # size
                Action.TRADE,        # action
                Side.ASK,            # side
                UInt8(0),            # flags
                UInt8(0),            # depth
                Int64(1200000000),   # ts_recv
                Int32(0),            # ts_in_delta
                UInt32(2)            # sequence
            )
            
            status = StatusMsg(
                RecordHeader(
                    UInt8(sizeof(StatusMsg) ÷ DBN.LENGTH_MULTIPLIER),
                    RType.STATUS_MSG,
                    UInt16(1),
                    UInt32(100),
                    1300000000
                ),
                UInt64(1300000000),  # ts_recv
                UInt16(3),           # action (using raw value for HALT)
                UInt16(1),           # reason
                UInt16(2),           # trading_event
                UInt8(0),            # is_trading
                UInt8(0),            # is_quoting
                UInt8(0)             # is_short_sell_restricted
            )
            
            # For now, just test with compatible record types (MBO and Trade work well together)
            records = [mbo, trade]  # Mixed MBO and Trade messages
            
            # Write using the unified write function
            write_dbn(mixed_file, metadata, records)
            
            # Read back and verify mixed types
            read_records = read_dbn(mixed_file)
            @test length(read_records) == 2
            
            # Check record types
            @test read_records[1] isa MBOMsg
            @test read_records[2] isa TradeMsg
            
            # Verify timestamps are in order
            @test read_records[1].hd.ts_event < read_records[2].hd.ts_event
            
            # Test streaming with mixed types
            stream_records = collect(DBNStream(mixed_file))
            @test length(stream_records) == 2
            @test typeof(stream_records[1]) == typeof(read_records[1])
            @test typeof(stream_records[2]) == typeof(read_records[2])
        finally
            safe_rm(mixed_file)
        end
    end
    
    @testset "Very Large Files" begin
        @testset "File with many records" begin
            large_file = tempname() * ".dbn"
            try
                metadata = Metadata(
                    UInt8(3),                    # version
                    "TEST",                      # dataset
                    Schema.TRADES,               # schema
                    1000000000,                  # start_ts
                    2000000000,                  # end_ts
                    UInt64(0),                   # limit
                    SType.RAW_SYMBOL,            # stype_in
                    SType.INSTRUMENT_ID,         # stype_out
                    false,                       # ts_out
                    String[],                    # symbols
                    String[],                    # partial
                    String[],                    # not_found
                    Tuple{String,String,Int64,Int64}[]  # mappings
                )
                
                # Write a large number of records
                num_records = 1000  # Reduced for faster testing
                trades = TradeMsg[]
                for i in 1:num_records
                    trade = TradeMsg(
                        RecordHeader(
                            UInt8(sizeof(TradeMsg) ÷ DBN.LENGTH_MULTIPLIER),
                            RType.MBP_0_MSG,
                            UInt16(1),
                            UInt32(i % 100 + 1),
                            1000000000 + i * 1000
                        ),
                        Int64(100000000 + i),    # price
                        UInt32(i % 1000 + 1),    # size
                        Action.TRADE,            # action
                        i % 2 == 0 ? Side.BID : Side.ASK,  # side
                        UInt8(0),                # flags
                        UInt8(0),                # depth
                        Int64(1000000000 + i * 1000),  # ts_recv
                        Int32(0),                # ts_in_delta
                        UInt32(i)                # sequence
                    )
                    push!(trades, trade)
                end
                
                # Write all at once
                write_dbn(large_file, metadata, trades)
                
                # Test streaming read (more memory efficient)
                count = 0
                for record in DBNStream(large_file)
                    count += 1
                    @test record isa TradeMsg
                    @test record.sequence == count
                end
                @test count == num_records
                
                # Test file size is reasonable
                file_size = filesize(large_file)
                expected_size = 300 + num_records * sizeof(TradeMsg)  # Approximate header size + records
                @test file_size > expected_size * 0.9  # Within 10% of expected
                @test file_size < expected_size * 1.1
            finally
                safe_rm(large_file)
            end
        end
    end
    
    @testset "Write Permission Errors" begin
        @testset "Read-only directory" begin
            # This test might not work in all environments
            # Try to write to a system directory
            readonly_paths = ["/", "/etc", "/usr"]
            
            for path in readonly_paths
                if isdir(path) && !Sys.iswindows()  # Skip on Windows
                    readonly_file = joinpath(path, "test_dbn_readonly.dbn")
                    
                    metadata = Metadata(
                        UInt8(3),                    # version
                        "TEST",                      # dataset
                        Schema.TRADES,               # schema
                        1000000000,                  # start_ts
                        2000000000,                  # end_ts
                        UInt64(0),                   # limit
                        SType.RAW_SYMBOL,            # stype_in
                        SType.INSTRUMENT_ID,         # stype_out
                        false,                       # ts_out
                        String[],                    # symbols
                        String[],                    # partial
                        String[],                    # not_found
                        Tuple{String,String,Int64,Int64}[]  # mappings
                    )
                    
                    # Should throw an error when trying to write
                    @test_throws Exception write_dbn(readonly_file, metadata, TradeMsg[])
                    break  # Only need one successful test
                end
            end
        end
    end
end