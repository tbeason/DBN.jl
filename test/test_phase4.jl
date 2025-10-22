# Phase 4: Basic Read/Write Testing (No Compression)

include("test_utils.jl")

@testset "Phase 4: Basic Read/Write Testing (No Compression)" begin

    # Helper function to create test metadata
    function create_test_metadata()
        return Metadata(
            UInt8(DBN_VERSION),      # version
            "TEST.ITCH",             # dataset
            Schema.TRADES,           # schema
            1640995200000000000,     # start_ts
            1640995260000000000,     # end_ts
            UInt64(1000),            # limit
            SType.RAW_SYMBOL,        # stype_in
            SType.RAW_SYMBOL,        # stype_out
            false,                   # ts_out
            ["AAPL", "MSFT"],        # symbols
            String[],                # partial
            String[],                # not_found
            Tuple{String,String,Int64,Int64}[]  # mappings
        )
    end
    
    # Helper function to create test TradeMsg
    function create_test_trade_msg()
        hd = RecordHeader(10, RType.MBP_0_MSG, 1, 12345, 1640995200000000000)  # 10 units = 40 bytes
        return TradeMsg(
            hd,                      # hd
            10055000000,             # price
            250,                     # size
            Action.TRADE,            # action
            Side.NONE,               # side
            0x02,                    # flags
            0,                       # depth
            1640995200000000001,     # ts_recv
            1000,                    # ts_in_delta
            12346                    # sequence
        )
    end
    
    @testset "Minimal DBN file writer test" begin
        temp_file = tempname() * ".dbn"
        
        try
            @testset "Write DBN header" begin
                metadata = create_test_metadata()
                
                # Test writing header
                open(temp_file, "w") do f
                    encoder = DBNEncoder(f, metadata)
                    write_header(encoder)
                    finalize_encoder(encoder)
                end
                
                @test isfile(temp_file)
                @test filesize(temp_file) > 0
            end
            
            @testset "Write a single TradeMsg record" begin
                metadata = create_test_metadata()
                trade_msg = create_test_trade_msg()
                
                # Write header and single record
                write_dbn(temp_file, metadata, [trade_msg])
                
                @test isfile(temp_file)
                @test filesize(temp_file) > 100  # Should be more than just header
            end
            
            @testset "Verify file is created" begin
                @test isfile(temp_file)
                
                # Check that file has proper DBN magic bytes
                open(temp_file, "r") do f
                    magic = read(f, 3)
                    @test magic == b"DBN"
                    
                    version = read(f, UInt8)
                    @test version == DBN_VERSION
                end
            end
            
        finally
            # Clean up
            safe_rm(temp_file)
        end
    end
    
    @testset "Minimal DBN file reader test" begin
        temp_file = tempname() * ".dbn"
        
        try
            # First write a test file
            metadata = create_test_metadata()
            trade_msg = create_test_trade_msg()
            write_dbn(temp_file, metadata, [trade_msg])
            
            @testset "Read the file created above" begin
                records = read_dbn(temp_file)
                @test length(records) == 1
                @test records[1] isa TradeMsg
            end
            
            @testset "Verify header is parsed correctly" begin
                open(temp_file, "r") do f
                    decoder = DBNDecoder(f)
                    read_header!(decoder)
                    
                    @test decoder.metadata !== nothing
                    @test decoder.metadata.version == DBN_VERSION
                    @test decoder.metadata.dataset == "TEST.ITCH"
                    @test decoder.metadata.schema == Schema.TRADES
                    @test length(decoder.metadata.symbols) == 2
                    @test decoder.metadata.symbols[1] == "AAPL"
                    @test decoder.metadata.symbols[2] == "MSFT"
                end
            end
            
            @testset "Verify record is read correctly" begin
                records = read_dbn(temp_file)
                trade_record = records[1]
                original_trade = create_test_trade_msg()
                
                @test DBN.record_length_bytes(trade_record.hd) == DBN.record_length_bytes(original_trade.hd)
                @test trade_record.hd.rtype == original_trade.hd.rtype
                @test trade_record.hd.publisher_id == original_trade.hd.publisher_id
                @test trade_record.hd.instrument_id == original_trade.hd.instrument_id
                @test trade_record.hd.ts_event == original_trade.hd.ts_event
                
                @test trade_record.price == original_trade.price
                @test trade_record.size == original_trade.size
                @test trade_record.action == original_trade.action
                @test trade_record.side == original_trade.side
                @test trade_record.flags == original_trade.flags
                @test trade_record.depth == original_trade.depth
                @test trade_record.ts_recv == original_trade.ts_recv
                @test trade_record.ts_in_delta == original_trade.ts_in_delta
                @test trade_record.sequence == original_trade.sequence
            end

        finally
            safe_rm(temp_file)
        end
    end

    @testset "Round-trip testing (write then read)" begin
        temp_file = tempname() * ".dbn"
        
        try
            @testset "Write multiple record types" begin
                metadata = create_test_metadata()
                
                # Create different message types
                hd1 = RecordHeader(40, RType.MBP_0_MSG, 1, 12345, 1640995200000000000)
                trade_msg = TradeMsg(hd1, 10055000000, 250, Action.TRADE, Side.NONE, 0x02, 0, 1640995200000000001, 1000, 12346)
                
                hd2 = RecordHeader(50, RType.MBO_MSG, 1, 12345, 1640995200000000002)
                mbo_msg = MBOMsg(hd2, 9876543210, 10050000000, 100, 0x01, 1, Action.ADD, Side.BID, 1640995200000000003, 2000, 12347)
                
                hd3 = RecordHeader(30, RType.OHLCV_1S_MSG, 1, 12345, 1640995200000000004)
                ohlcv_msg = OHLCVMsg(hd3, 10050000000, 10070000000, 10040000000, 10065000000, 125000)
                
                records = [trade_msg, mbo_msg, ohlcv_msg]
                write_dbn(temp_file, metadata, records)
                
                @test isfile(temp_file)
                @test filesize(temp_file) > 200  # Should be substantial
            end
            
            @testset "Read them back" begin
                records = read_dbn(temp_file)
                @test length(records) == 3
                @test records[1] isa TradeMsg
                @test records[2] isa MBOMsg
                @test records[3] isa OHLCVMsg
            end
            
            @testset "Verify data integrity" begin
                records = read_dbn(temp_file)
                
                # Test TradeMsg integrity
                trade_record = records[1]
                @test trade_record.hd.rtype == RType.MBP_0_MSG
                @test trade_record.price == 10055000000
                @test trade_record.size == 250
                @test trade_record.action == Action.TRADE
                @test trade_record.side == Side.NONE
                
                # Test MBOMsg integrity
                mbo_record = records[2]
                @test mbo_record.hd.rtype == RType.MBO_MSG
                @test mbo_record.order_id == 9876543210
                @test mbo_record.price == 10050000000
                @test mbo_record.size == 100
                @test mbo_record.action == Action.ADD
                @test mbo_record.side == Side.BID
                
                # Test OHLCVMsg integrity
                ohlcv_record = records[3]
                @test ohlcv_record.hd.rtype == RType.OHLCV_1S_MSG
                @test ohlcv_record.open == 10050000000
                @test ohlcv_record.high == 10070000000
                @test ohlcv_record.low == 10040000000
                @test ohlcv_record.close == 10065000000
                @test ohlcv_record.volume == 125000
            end

        finally
            safe_rm(temp_file)
        end
    end

    @testset "DBNEncoder and DBNDecoder direct testing" begin
        temp_file = tempname() * ".dbn"
        
        try
            @testset "Direct encoder usage" begin
                metadata = create_test_metadata()
                trade_msg = create_test_trade_msg()
                
                open(temp_file, "w") do f
                    encoder = DBNEncoder(f, metadata)
                    write_header(encoder)
                    write_record(encoder, trade_msg)
                    finalize_encoder(encoder)
                end
                
                @test isfile(temp_file)
                @test filesize(temp_file) > 50
            end
            
            @testset "Direct decoder usage" begin
                open(temp_file, "r") do f
                    decoder = DBNDecoder(f)
                    read_header!(decoder)
                    
                    # Verify metadata was read correctly
                    @test decoder.metadata.dataset == "TEST.ITCH"
                    @test decoder.metadata.schema == Schema.TRADES
                    
                    # Read the record
                    record = read_record(decoder)
                    @test record isa TradeMsg
                    @test record.price == 10055000000
                    
                    # Try to read another record (should be nothing)
                    next_record = read_record(decoder)
                    @test next_record === nothing
                end
            end

        finally
            safe_rm(temp_file)
        end
    end

    @testset "Error handling and edge cases" begin
        @testset "Writing to invalid path" begin
            invalid_path = "/invalid/nonexistent/path/test.dbn"
            metadata = create_test_metadata()
            trade_msg = create_test_trade_msg()
            
            @test_throws Exception write_dbn(invalid_path, metadata, [trade_msg])
        end
        
        @testset "Reading nonexistent file" begin
            nonexistent_file = "nonexistent_file.dbn"
            @test_throws Exception read_dbn(nonexistent_file)
        end
        
        @testset "Reading invalid DBN file" begin
            temp_file = tempname() * ".dbn"

            try
                # Write invalid magic bytes
                open(temp_file, "w") do f
                    write(f, b"INVALID")
                end

                @test_throws Exception read_dbn(temp_file)

            finally
                safe_rm(temp_file)
            end
        end
        
        @testset "Empty file handling" begin
            temp_file = tempname() * ".dbn"

            try
                # Create empty file
                touch(temp_file)
                @test_throws Exception read_dbn(temp_file)

            finally
                safe_rm(temp_file)
            end
        end
    end
    
    @testset "Different metadata configurations" begin
        temp_file = tempname() * ".dbn"
        
        try
            @testset "Different schema types" begin
                schemas_to_test = [Schema.MBO, Schema.TRADES, Schema.OHLCV_1S, Schema.STATUS]
                
                for schema in schemas_to_test
                    metadata = Metadata(
                        UInt8(DBN_VERSION), "TEST.DATA", schema,
                        1640995200000000000, 1640995260000000000, UInt64(1000),
                        SType.RAW_SYMBOL, SType.RAW_SYMBOL,
                        false, ["TEST"], String[], String[],
                        Tuple{String,String,Int64,Int64}[]
                    )
                    
                    trade_msg = create_test_trade_msg()
                    write_dbn(temp_file, metadata, [trade_msg])
                    
                    # Read it back and verify schema
                    open(temp_file, "r") do f
                        decoder = DBNDecoder(f)
                        read_header!(decoder)
                        @test decoder.metadata.schema == schema
                    end
                end
            end
            
            @testset "Different symbol configurations" begin
                # Test with no symbols
                metadata_no_symbols = Metadata(
                    UInt8(DBN_VERSION), "TEST.DATA", Schema.TRADES,
                    1640995200000000000, 1640995260000000000, UInt64(1000),
                    SType.RAW_SYMBOL, SType.RAW_SYMBOL,
                    false, String[], String[], String[],
                    Tuple{String,String,Int64,Int64}[]
                )
                
                trade_msg = create_test_trade_msg()
                write_dbn(temp_file, metadata_no_symbols, [trade_msg])
                
                records = read_dbn(temp_file)
                @test length(records) == 1
                
                # Test with many symbols
                many_symbols = ["SYM$i" for i in 1:50]
                metadata_many_symbols = Metadata(
                    UInt8(DBN_VERSION), "TEST.DATA", Schema.TRADES,
                    1640995200000000000, 1640995260000000000, UInt64(1000),
                    SType.RAW_SYMBOL, SType.RAW_SYMBOL,
                    false, many_symbols, String[], String[],
                    Tuple{String,String,Int64,Int64}[]
                )
                
                write_dbn(temp_file, metadata_many_symbols, [trade_msg])
                
                open(temp_file, "r") do f
                    decoder = DBNDecoder(f)
                    read_header!(decoder)
                    @test length(decoder.metadata.symbols) == 50
                    @test decoder.metadata.symbols[1] == "SYM1"
                    @test decoder.metadata.symbols[50] == "SYM50"
                end
            end

        finally
            safe_rm(temp_file)
        end
    end
end