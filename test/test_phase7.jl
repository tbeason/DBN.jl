

@testset "Phase 7: Streaming Writer Testing" begin
    
    @testset "Test DBNStreamWriter creation" begin
        # Test basic creation
        mktempdir() do tmpdir
            output_file = joinpath(tmpdir, "stream_writer_test.dbn")
            
            # Create writer with default settings
            writer = DBN.DBNStreamWriter(output_file, "XNAS", DBN.Schema.TRADES)
            @test writer.record_count == 0
            @test writer.first_ts == typemax(Int64)
            @test writer.last_ts == 0
            @test writer.auto_flush == true
            @test writer.flush_interval == 1000
            @test writer.last_flush_count == 0
            
            # Close the writer
            DBN.close_writer!(writer)
            
            # Verify file was created
            @test isfile(output_file)
            
            # Test creation with custom parameters
            output_file2 = joinpath(tmpdir, "stream_writer_custom.dbn")
            writer2 = DBN.DBNStreamWriter(output_file2, "XBTS", DBN.Schema.MBO, 
                                    symbols=["AAPL", "MSFT"],
                                    auto_flush=false,
                                    flush_interval=500)
            @test writer2.auto_flush == false
            @test writer2.flush_interval == 500
            @test writer2.encoder.metadata.symbols == ["AAPL", "MSFT"]
            @test writer2.encoder.metadata.dataset == "XBTS"
            @test writer2.encoder.metadata.schema == DBN.Schema.MBO
            
            DBN.close_writer!(writer2)
        end
    end
    
    @testset "Test write_record! with timestamp tracking" begin
        mktempdir() do tmpdir
            output_file = joinpath(tmpdir, "timestamp_tracking.dbn")
            
            writer = DBN.DBNStreamWriter(output_file, "XNAS", DBN.Schema.TRADES)
            
            # Create test trade messages with different timestamps
            ts1 = Int64(1700000000000000000)  # First timestamp
            ts2 = Int64(1700000001000000000)  # Second timestamp (1 second later)
            ts3 = Int64(1700000002000000000)  # Third timestamp (2 seconds later)
            
            trade1 = DBN.TradeMsg(
                DBN.RecordHeader(128, DBN.RType.MBP_0_MSG, 1, 0x00, ts1),
                100000000,  # price (10.0)
                100,        # size
                DBN.Action.TRADE,
                DBN.Side.ASK,
                0x00,       # flags
                0,          # depth
                ts1,        # ts_recv
                10000,      # ts_in_delta
                1           # sequence
            )
            
            trade2 = DBN.TradeMsg(
                DBN.RecordHeader(128, DBN.RType.MBP_0_MSG, 1, 0x00, ts2),
                101000000,  # price (10.1)
                200,
                DBN.Action.TRADE,
                DBN.Side.BID,
                0x00,
                0,
                ts2,
                10000,
                2
            )
            
            trade3 = DBN.TradeMsg(
                DBN.RecordHeader(128, DBN.RType.MBP_0_MSG, 1, 0x00, ts3),
                102000000,  # price (10.2)
                150,
                DBN.Action.TRADE,
                DBN.Side.ASK,
                0x00,
                0,
                ts3,
                10000,
                3
            )
            
            # Write records and verify timestamp tracking
            DBN.write_record!(writer, trade1)
            @test writer.record_count == 1
            @test writer.first_ts == ts1
            @test writer.last_ts == ts1
            
            DBN.write_record!(writer, trade2)
            @test writer.record_count == 2
            @test writer.first_ts == ts1  # Should remain the first
            @test writer.last_ts == ts2   # Should update to the latest
            
            DBN.write_record!(writer, trade3)
            @test writer.record_count == 3
            @test writer.first_ts == ts1  # Should still be the first
            @test writer.last_ts == ts3   # Should be the latest
            
            DBN.close_writer!(writer)
            
            # Read back and verify metadata timestamps
            records = DBN.read_dbn(output_file)
            @test length(records) == 3
            
            # Read metadata
            open(output_file, "r") do io
                decoder = DBN.DBNDecoder(io)
                DBN.read_header!(decoder)
                @test decoder.metadata.start_ts == ts1
                @test decoder.metadata.end_ts == ts3
                @test decoder.metadata.limit == 3
            end
        end
    end
    
    @testset "Test auto-flush functionality" begin
        mktempdir() do tmpdir
            output_file = joinpath(tmpdir, "auto_flush_test.dbn")
            
            # Create writer with small flush interval for testing
            writer = DBN.DBNStreamWriter(output_file, "XNAS", DBN.Schema.MBO,
                                   auto_flush=true,
                                   flush_interval=5)
            
            # Create a test MBO message
            mbo_msg = DBN.MBOMsg(
                DBN.RecordHeader(48, DBN.RType.MBO_MSG, 1, 0x00, Int64(1700000000000000000)),
                123456,     # order_id
                100000000,  # price
                100,        # size
                0x00,       # flags
                0,          # channel_id
                DBN.Action.ADD,
                DBN.Side.BID,
                Int64(1700000000000000000),  # ts_recv
                10000,      # ts_in_delta
                1           # sequence
            )
            
            # Write 4 records - should not trigger flush yet
            for i in 1:4
                DBN.write_record!(writer, mbo_msg)
            end
            @test writer.last_flush_count == 0
            
            # Write 5th record - should trigger flush
            DBN.write_record!(writer, mbo_msg)
            @test writer.last_flush_count == 5
            
            # Write 4 more records
            for i in 1:4
                DBN.write_record!(writer, mbo_msg)
            end
            @test writer.last_flush_count == 5  # Should not have flushed again
            
            # Write 10th record - should trigger another flush
            DBN.write_record!(writer, mbo_msg)
            @test writer.last_flush_count == 10
            
            DBN.close_writer!(writer)
            
            # Verify all records were written
            records = DBN.read_dbn(output_file)
            @test length(records) == 10
        end
    end
    
    @testset "Test close_writer! and header update" begin
        mktempdir() do tmpdir
            output_file = joinpath(tmpdir, "header_update_test.dbn")
            
            # Test with symbols - the parsing issue is now fixed
            writer = DBN.DBNStreamWriter(output_file, "XNAS", DBN.Schema.TRADES,
                                   symbols=["AAPL", "MSFT", "GOOGL"])
            
            # Create trades with different timestamps
            timestamps = [
                Int64(1700000000000000000),
                Int64(1700000005000000000),
                Int64(1700000003000000000),  # Out of order
                Int64(1700000010000000000),
                Int64(1700000001000000000)   # Very early timestamp
            ]
            
            for (i, ts) in enumerate(timestamps)
                trade = DBN.TradeMsg(
                    DBN.RecordHeader(128, DBN.RType.MBP_0_MSG, 1, 0x00, ts),
                    100000000 + i * 1000000,
                    100 + i,
                    DBN.Action.TRADE,
                    i % 2 == 0 ? DBN.Side.ASK : DBN.Side.BID,
                    0x00,
                    0,
                    ts,
                    10000,
                    UInt32(i)
                )
                DBN.write_record!(writer, trade)
            end
            
            # Verify timestamps before closing
            @test writer.first_ts == Int64(1700000000000000000)  # Earliest
            @test writer.last_ts == Int64(1700000010000000000)   # Latest
            @test writer.record_count == 5
            
            # Close and update header
            DBN.close_writer!(writer)
            
            # Read back and verify header was updated correctly
            open(output_file, "r") do io
                decoder = DBN.DBNDecoder(io)
                DBN.read_header!(decoder)
                metadata = decoder.metadata
                
                @test metadata.start_ts == Int64(1700000000000000000)
                @test metadata.end_ts == Int64(1700000010000000000)
                @test metadata.limit == 5
                @test metadata.symbols == ["AAPL", "MSFT", "GOOGL"]
                @test metadata.dataset == "XNAS"
                @test metadata.schema == DBN.Schema.TRADES
            end
            
            # Verify records are intact
            records = DBN.read_dbn(output_file)
            @test length(records) == 5
            
            # Verify timestamps in the read records
            timestamps_read = [r.hd.ts_event for r in records]
            @test sort(timestamps_read) == sort(timestamps)
        end
    end
    
    @testset "Test mixed record types with streaming writer" begin
        mktempdir() do tmpdir
            output_file = joinpath(tmpdir, "mixed_records_stream.dbn")
            
            writer = DBN.DBNStreamWriter(output_file, "GLBX", DBN.Schema.MBO)
            
            # Create different record types
            trade = DBN.TradeMsg(
                DBN.RecordHeader(128, DBN.RType.MBP_0_MSG, 1, 0x00, Int64(1700000000000000000)),
                100000000, 100, DBN.Action.TRADE, DBN.Side.ASK, 0x00, 0,
                Int64(1700000000000000000), 10000, 1
            )
            
            mbo = DBN.MBOMsg(
                DBN.RecordHeader(48, DBN.RType.MBO_MSG, 1, 0x00, Int64(1700000001000000000)),
                12345,      # order_id
                101000000,  # price
                200,        # size
                0x00,       # flags
                0,          # channel_id
                DBN.Action.ADD,
                DBN.Side.BID,
                Int64(1700000001000000000),  # ts_recv
                10000,      # ts_in_delta
                2           # sequence
            )
            
            mbp1 = DBN.MBP1Msg(
                DBN.RecordHeader(112, DBN.RType.MBP_1_MSG, 1, 0x00, Int64(1700000002000000000)),
                102000000, 300, DBN.Action.TRADE, DBN.Side.ASK, 0x00, 0,
                Int64(1700000002000000000), 10000, 3,
                DBN.BidAskPair(100000000, 105000000, 100, 150, 1, 2)
            )
            
            # Write mixed records
            DBN.write_record!(writer, trade)
            DBN.write_record!(writer, mbo)
            DBN.write_record!(writer, mbp1)
            DBN.write_record!(writer, trade)  # Another trade
            
            @test writer.record_count == 4
            @test writer.first_ts == Int64(1700000000000000000)
            @test writer.last_ts == Int64(1700000002000000000)
            
            DBN.close_writer!(writer)
            
            # Read back and verify
            records = DBN.read_dbn(output_file)
            @test length(records) == 4
            @test isa(records[1], DBN.TradeMsg)
            @test isa(records[2], DBN.MBOMsg)
            @test isa(records[3], DBN.MBP1Msg)
            @test isa(records[4], DBN.TradeMsg)
        end
    end
    
    @testset "Test streaming writer with no records" begin
        mktempdir() do tmpdir
            output_file = joinpath(tmpdir, "empty_stream.dbn")
            
            writer = DBN.DBNStreamWriter(output_file, "XNAS", DBN.Schema.TRADES)
            
            # Close immediately without writing any records
            DBN.close_writer!(writer)
            
            # File should still be created with header
            @test isfile(output_file)
            
            # Read back - should have no records but valid metadata
            open(output_file, "r") do io
                decoder = DBN.DBNDecoder(io)
                DBN.read_header!(decoder)
                @test decoder.metadata !== nothing
                @test decoder.metadata.limit === nothing  # 0 limit is treated as unlimited/nothing
                @test decoder.metadata.start_ts == 0  # Should be 0 for empty files
                @test decoder.metadata.end_ts === nothing  # Should be nothing for empty files
            end
            
            records = DBN.read_dbn(output_file)
            @test isempty(records)
        end
    end
    
    @testset "Test streaming writer error handling" begin
        mktempdir() do tmpdir
            output_file = joinpath(tmpdir, "error_test.dbn")
            
            writer = DBN.DBNStreamWriter(output_file, "XNAS", DBN.Schema.TRADES)
            
            # Write a valid record
            trade = DBN.TradeMsg(
                DBN.RecordHeader(128, DBN.RType.MBP_0_MSG, 1, 0x00, Int64(1700000000000000000)),
                100000000, 100, DBN.Action.TRADE, DBN.Side.ASK, 0x00, 0,
                Int64(1700000000000000000), 10000, 1
            )
            DBN.write_record!(writer, trade)
            
            # Close the writer
            DBN.close_writer!(writer)
            
            # Try to write after closing - should now throw IOError
            @test_throws Base.IOError DBN.write_record!(writer, trade)
            
            # Verify the first record was written correctly
            records = DBN.read_dbn(output_file)
            @test length(records) == 1
            @test isa(records[1], DBN.TradeMsg)
        end
    end
end

println("Phase 7 tests completed!")