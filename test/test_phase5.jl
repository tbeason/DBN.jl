# Phase 5: Record Type Read/Write Testing

@testset "Phase 5: Record Type Read/Write Testing" begin

    # Helper function to create test metadata
    function create_test_metadata(schema::Schema.T)
        return Metadata(
            UInt8(DBN_VERSION),      # version
            "TEST.DATA",             # dataset
            schema,                  # schema
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
    
    @testset "MBOMsg serialization/deserialization" begin
        metadata = create_test_metadata(Schema.MBO)
        temp_file = tempname() * ".dbn"
        
        try
            # Create test MBO message
            hd = RecordHeader(55, RType.MBO_MSG, 1, 12345, 1640995200000000000)
            original_msg = MBOMsg(
                hd,                      # hd
                9876543210987654,        # order_id
                10055000000,             # price
                500,                     # size
                0x01,                    # flags
                2,                       # channel_id
                Action.ADD,              # action
                Side.BID,                # side
                1640995200000000001,     # ts_recv
                1500,                    # ts_in_delta
                98765                    # sequence
            )
            
            # Write and read back
            write_dbn(temp_file, metadata, [original_msg])
            records = read_dbn(temp_file)
            
            @test length(records) == 1
            @test records[1] isa MBOMsg
            
            read_msg = records[1]
            @test read_msg.hd.rtype == RType.MBO_MSG
            @test read_msg.order_id == original_msg.order_id
            @test read_msg.price == original_msg.price
            @test read_msg.size == original_msg.size
            @test read_msg.flags == original_msg.flags
            @test read_msg.channel_id == original_msg.channel_id
            @test read_msg.action == original_msg.action
            @test read_msg.side == original_msg.side
            @test read_msg.ts_recv == original_msg.ts_recv
            @test read_msg.ts_in_delta == original_msg.ts_in_delta
            @test read_msg.sequence == original_msg.sequence
            
        finally
            safe_rm(temp_file)
        end
    end
    
    @testset "TradeMsg serialization/deserialization" begin
        metadata = create_test_metadata(Schema.TRADES)
        temp_file = tempname() * ".dbn"
        
        try
            # Create test Trade message
            hd = RecordHeader(45, RType.MBP_0_MSG, 2, 54321, 1640995200000000100)
            original_msg = TradeMsg(
                hd,                      # hd
                10075000000,             # price
                1000,                    # size
                Action.TRADE,            # action
                Side.NONE,               # side
                0x04,                    # flags
                1,                       # depth
                1640995200000000101,     # ts_recv
                2000,                    # ts_in_delta
                87654                    # sequence
            )
            
            # Write and read back
            write_dbn(temp_file, metadata, [original_msg])
            records = read_dbn(temp_file)
            
            @test length(records) == 1
            @test records[1] isa TradeMsg
            
            read_msg = records[1]
            @test read_msg.hd.rtype == RType.MBP_0_MSG
            @test read_msg.price == original_msg.price
            @test read_msg.size == original_msg.size
            @test read_msg.action == original_msg.action
            @test read_msg.side == original_msg.side
            @test read_msg.flags == original_msg.flags
            @test read_msg.depth == original_msg.depth
            @test read_msg.ts_recv == original_msg.ts_recv
            @test read_msg.ts_in_delta == original_msg.ts_in_delta
            @test read_msg.sequence == original_msg.sequence
            
        finally
            safe_rm(temp_file)
        end
    end
    
    @testset "MBP1Msg serialization/deserialization" begin
        metadata = create_test_metadata(Schema.MBP_1)
        temp_file = tempname() * ".dbn"
        
        try
            # Create test MBP1 message
            hd = RecordHeader(65, RType.MBP_1_MSG, 1, 11111, 1640995200000000200)
            levels = BidAskPair(10050000000, 10060000000, 200, 300, 8, 5)
            
            original_msg = MBP1Msg(
                hd,                      # hd
                10055000000,             # price
                250,                     # size
                Action.MODIFY,           # action
                Side.ASK,                # side
                0x08,                    # flags
                2,                       # depth
                1640995200000000201,     # ts_recv
                3000,                    # ts_in_delta
                76543,                   # sequence
                levels                   # levels
            )
            
            # Write and read back
            write_dbn(temp_file, metadata, [original_msg])
            records = read_dbn(temp_file)
            
            @test length(records) == 1
            @test records[1] isa MBP1Msg
            
            read_msg = records[1]
            @test read_msg.hd.rtype == RType.MBP_1_MSG
            @test read_msg.price == original_msg.price
            @test read_msg.size == original_msg.size
            @test read_msg.action == original_msg.action
            @test read_msg.side == original_msg.side
            @test read_msg.flags == original_msg.flags
            @test read_msg.depth == original_msg.depth
            @test read_msg.ts_recv == original_msg.ts_recv
            @test read_msg.ts_in_delta == original_msg.ts_in_delta
            @test read_msg.sequence == original_msg.sequence
            
            # Test BidAskPair levels
            @test read_msg.levels.bid_px == levels.bid_px
            @test read_msg.levels.ask_px == levels.ask_px
            @test read_msg.levels.bid_sz == levels.bid_sz
            @test read_msg.levels.ask_sz == levels.ask_sz
            @test read_msg.levels.bid_ct == levels.bid_ct
            @test read_msg.levels.ask_ct == levels.ask_ct
            
        finally
            safe_rm(temp_file)
        end
    end
    
    @testset "MBP10Msg serialization/deserialization" begin
        metadata = create_test_metadata(Schema.MBP_10)
        temp_file = tempname() * ".dbn"
        
        try
            # Create test MBP10 message with 10 levels
            hd = RecordHeader(250, RType.MBP_10_MSG, 1, 22222, 1640995200000000300)
            levels = ntuple(10) do i
                BidAskPair(
                    10050000000 - (i-1)*1000000,  # bid decreasing
                    10060000000 + (i-1)*1000000,  # ask increasing
                    100 + i*50,                   # bid size
                    150 + i*60,                   # ask size
                    3 + i,                        # bid count
                    2 + i                         # ask count
                )
            end
            
            original_msg = MBP10Msg(
                hd,                      # hd
                10055000000,             # price
                400,                     # size
                Action.CLEAR,            # action
                Side.BID,                # side
                0x10,                    # flags
                5,                       # depth
                1640995200000000301,     # ts_recv
                4000,                    # ts_in_delta
                65432,                   # sequence
                levels                   # levels
            )
            
            # Write and read back
            write_dbn(temp_file, metadata, [original_msg])
            records = read_dbn(temp_file)
            
            @test length(records) == 1
            @test records[1] isa MBP10Msg
            
            read_msg = records[1]
            @test read_msg.hd.rtype == RType.MBP_10_MSG
            @test read_msg.price == original_msg.price
            @test read_msg.size == original_msg.size
            @test read_msg.action == original_msg.action
            @test read_msg.side == original_msg.side
            @test read_msg.flags == original_msg.flags
            @test read_msg.depth == original_msg.depth
            @test read_msg.ts_recv == original_msg.ts_recv
            @test read_msg.ts_in_delta == original_msg.ts_in_delta
            @test read_msg.sequence == original_msg.sequence
            
            # Test all 10 levels
            @test length(read_msg.levels) == 10
            for i in 1:10
                @test read_msg.levels[i].bid_px == levels[i].bid_px
                @test read_msg.levels[i].ask_px == levels[i].ask_px
                @test read_msg.levels[i].bid_sz == levels[i].bid_sz
                @test read_msg.levels[i].ask_sz == levels[i].ask_sz
                @test read_msg.levels[i].bid_ct == levels[i].bid_ct
                @test read_msg.levels[i].ask_ct == levels[i].ask_ct
            end
            
        finally
            safe_rm(temp_file)
        end
    end
    
    @testset "OHLCVMsg serialization/deserialization" begin
        metadata = create_test_metadata(Schema.OHLCV_1S)
        temp_file = tempname() * ".dbn"
        
        try
            # Create test OHLCV message
            hd = RecordHeader(14, RType.OHLCV_1S_MSG, 3, 33333, 1640995200000000400)
            original_msg = OHLCVMsg(
                hd,                      # hd
                10040000000,             # open
                10080000000,             # high
                10030000000,             # low
                10070000000,             # close
                250000                   # volume
            )
            
            # Write and read back
            write_dbn(temp_file, metadata, [original_msg])
            records = read_dbn(temp_file)
            
            @test length(records) == 1
            @test records[1] isa OHLCVMsg
            
            read_msg = records[1]
            @test read_msg.hd.rtype == RType.OHLCV_1S_MSG
            @test read_msg.open == original_msg.open
            @test read_msg.high == original_msg.high
            @test read_msg.low == original_msg.low
            @test read_msg.close == original_msg.close
            @test read_msg.volume == original_msg.volume
            
        finally
            safe_rm(temp_file)
        end
    end
    
    @testset "StatusMsg serialization/deserialization" begin
        metadata = create_test_metadata(Schema.STATUS)
        temp_file = tempname() * ".dbn"
        
        try
            # Create test Status message
            hd = RecordHeader(10, RType.STATUS_MSG, 1, 44444, 1640995200000000500)
            original_msg = StatusMsg(
                hd,                      # hd
                1640995200000000501,     # ts_recv
                5,                       # action
                2,                       # reason
                10,                      # trading_event
                UInt8('Y'),              # is_trading (c_char)
                UInt8('N'),              # is_quoting (c_char)
                UInt8('Y')               # is_short_sell_restricted (c_char)
            )
            
            # Write and read back
            write_dbn(temp_file, metadata, [original_msg])
            records = read_dbn(temp_file)
            
            @test length(records) == 1
            @test records[1] isa StatusMsg
            
            read_msg = records[1]
            @test read_msg.hd.rtype == RType.STATUS_MSG
            @test read_msg.ts_recv == original_msg.ts_recv
            @test read_msg.action == original_msg.action
            @test read_msg.reason == original_msg.reason
            @test read_msg.trading_event == original_msg.trading_event
            @test read_msg.is_trading == original_msg.is_trading
            @test read_msg.is_quoting == original_msg.is_quoting
            @test read_msg.is_short_sell_restricted == original_msg.is_short_sell_restricted
            
        finally
            safe_rm(temp_file)
        end
    end
    
    @testset "ImbalanceMsg serialization/deserialization" begin
        metadata = create_test_metadata(Schema.IMBALANCE)
        temp_file = tempname() * ".dbn"
        
        try
            # Create test Imbalance message with full DBN v3 structure
            hd = RecordHeader(28, RType.IMBALANCE_MSG, 2, 55555, 1640995200000000600)
            original_msg = ImbalanceMsg(
                hd,                      # hd
                1640995200000000601,     # ts_recv
                10065000000,             # ref_price
                1640995230000000000,     # auction_time
                10066000000,             # cont_book_clr_price
                10067000000,             # auct_interest_clr_price
                10068000000,             # ssr_filling_price
                10069000000,             # ind_match_price
                10070000000,             # upper_collar
                10060000000,             # lower_collar
                5000,                    # paired_qty
                15000,                   # total_imbalance_qty
                8000,                    # market_imbalance_qty
                2000,                    # unpaired_qty
                UInt8('O'),              # auction_type
                Side.ASK,                # side
                UInt8(1),                # auction_status
                UInt8(0),                # freeze_status
                UInt8(0),                # num_extensions
                UInt8('A'),              # unpaired_side
                UInt8('N')               # significant_imbalance
            )
            
            # Write and read back
            write_dbn(temp_file, metadata, [original_msg])
            records = read_dbn(temp_file)
            
            @test length(records) == 1
            @test records[1] isa ImbalanceMsg
            
            read_msg = records[1]
            @test read_msg.hd.rtype == RType.IMBALANCE_MSG
            @test read_msg.ts_recv == original_msg.ts_recv
            @test read_msg.ref_price == original_msg.ref_price
            @test read_msg.auction_time == original_msg.auction_time
            @test read_msg.cont_book_clr_price == original_msg.cont_book_clr_price
            @test read_msg.auct_interest_clr_price == original_msg.auct_interest_clr_price
            @test read_msg.total_imbalance_qty == original_msg.total_imbalance_qty
            @test read_msg.side == original_msg.side
            
        finally
            safe_rm(temp_file)
        end
    end
    
    @testset "StatMsg serialization/deserialization (DBN v3)" begin
        metadata = create_test_metadata(Schema.STATISTICS)
        temp_file = tempname() * ".dbn"
        
        try
            # Create test Stat message with v3 features
            hd = RecordHeader(20, RType.STAT_MSG, 1, 66666, 1640995200000000700)
            original_msg = StatMsg(
                hd,                      # hd
                1640995200000000701,     # ts_recv
                1640995200000000000,     # ts_ref
                10055000000,             # price
                123456789012345678,      # quantity (64-bit in v3)
                54321,                   # sequence
                5500,                    # ts_in_delta
                8,                       # stat_type
                3,                       # channel_id
                1,                       # update_action
                0x20                     # stat_flags
            )
            
            # Write and read back
            write_dbn(temp_file, metadata, [original_msg])
            records = read_dbn(temp_file)
            
            @test length(records) == 1
            @test records[1] isa StatMsg
            
            read_msg = records[1]
            @test read_msg.hd.rtype == RType.STAT_MSG
            @test read_msg.ts_recv == original_msg.ts_recv
            @test read_msg.ts_ref == original_msg.ts_ref
            @test read_msg.price == original_msg.price
            @test read_msg.quantity == original_msg.quantity  # Test 64-bit quantity
            @test read_msg.sequence == original_msg.sequence
            @test read_msg.ts_in_delta == original_msg.ts_in_delta
            @test read_msg.stat_type == original_msg.stat_type
            @test read_msg.channel_id == original_msg.channel_id
            @test read_msg.update_action == original_msg.update_action
            @test read_msg.stat_flags == original_msg.stat_flags
            
        finally
            safe_rm(temp_file)
        end
    end
    
    @testset "InstrumentDefMsg serialization/deserialization (DBN v3)" begin
        metadata = create_test_metadata(Schema.DEFINITION)
        temp_file = tempname() * ".dbn"
        
        try
            # Create test InstrumentDef message with v3 features
            hd = RecordHeader(130, RType.INSTRUMENT_DEF_MSG, 1, 77777, 1640995200000000800)
            original_msg = InstrumentDefMsg(
                hd,                          # hd
                1640995200000000801,         # ts_recv
                1000000,                     # min_price_increment
                1000000000,                  # display_factor
                1672531200000000000,         # expiration
                1640995200000000000,         # activation
                15000000000,                 # high_limit_price
                5000000000,                  # low_limit_price
                1000000000,                  # max_price_variation
                0,                           # trading_reference_price (v2 only)
                100,                         # unit_of_measure_qty
                1000000,                     # min_price_increment_amount
                1000000000,                  # price_ratio
                5,                           # inst_attrib_value
                12345,                       # underlying_id
                987654321098765432,          # raw_instrument_id (64-bit in v3)
                0,                           # market_depth_implied
                10,                          # market_depth
                2,                           # market_segment_id
                1000000,                     # max_trade_vol
                1,                           # min_lot_size
                100,                         # min_lot_size_block
                1,                           # min_lot_size_round_lot
                10,                          # min_trade_vol
                100,                         # contract_multiplier
                0,                           # decay_quantity
                100,                         # original_contract_size
                0,                           # trading_reference_date (v2 only)
                10,                          # appl_id
                2025,                        # maturity_year
                0,                           # decay_start_date
                5,                           # channel_id
                "USD",                       # currency
                "USD",                       # settl_currency
                "CS",                        # secsubtype
                "TSLA",                      # raw_symbol
                "AUTO",                      # group
                "XNAS",                      # exchange
                "TSLA.NASDAQ",               # asset (11 bytes in v3)
                "ESTVPS",                    # cfi
                "CS",                        # security_type
                "Shares",                    # unit_of_measure
                "",                          # underlying
                "",                          # strike_price_currency
                InstrumentClass.STOCK,       # instrument_class
                0,                           # strike_price
                'P',                         # match_algorithm
                0,                           # md_security_trading_status (v2 only)
                2,                           # main_fraction
                0,                           # price_display_format
                0,                           # settl_price_type (v2 only)
                0,                           # sub_fraction
                0,                           # underlying_product
                'A',                         # security_update_action
                0,                           # maturity_month
                0,                           # maturity_day
                0,                           # maturity_week
                false,                       # user_defined_instrument
                0,                           # contract_multiplier_unit
                0,                           # flow_schedule_type
                0,                           # tick_rule
                # New strategy leg fields in DBN v3
                2,                           # leg_count
                1,                           # leg_index
                88888,                       # leg_instrument_id
                "LEG1",                      # leg_raw_symbol
                Side.BID,                    # leg_side
                99999,                       # leg_underlying_id
                InstrumentClass.OPTION,      # leg_instrument_class
                1,                           # leg_ratio_qty_numerator
                2,                           # leg_ratio_qty_denominator
                3,                           # leg_ratio_price_numerator
                4,                           # leg_ratio_price_denominator
                10025000000,                 # leg_price
                500000000                    # leg_delta
            )
            
            # Write and read back
            write_dbn(temp_file, metadata, [original_msg])
            records = read_dbn(temp_file)
            
            @test length(records) == 1
            @test records[1] isa InstrumentDefMsg
            
            read_msg = records[1]
            @test read_msg.hd.rtype == RType.INSTRUMENT_DEF_MSG
            @test read_msg.ts_recv == original_msg.ts_recv
            @test read_msg.raw_instrument_id == original_msg.raw_instrument_id  # Test 64-bit field
            @test read_msg.currency == original_msg.currency
            @test read_msg.raw_symbol == original_msg.raw_symbol
            @test read_msg.asset == original_msg.asset  # Test expanded 11-byte field
            @test read_msg.instrument_class == original_msg.instrument_class
            
            # Test new v3 strategy leg fields
            @test read_msg.leg_count == original_msg.leg_count
            @test read_msg.leg_index == original_msg.leg_index
            @test read_msg.leg_instrument_id == original_msg.leg_instrument_id
            @test read_msg.leg_raw_symbol == original_msg.leg_raw_symbol
            @test read_msg.leg_side == original_msg.leg_side
            @test read_msg.leg_underlying_id == original_msg.leg_underlying_id
            @test read_msg.leg_instrument_class == original_msg.leg_instrument_class
            @test read_msg.leg_ratio_qty_numerator == original_msg.leg_ratio_qty_numerator
            @test read_msg.leg_ratio_qty_denominator == original_msg.leg_ratio_qty_denominator
            @test read_msg.leg_ratio_price_numerator == original_msg.leg_ratio_price_numerator
            @test read_msg.leg_ratio_price_denominator == original_msg.leg_ratio_price_denominator
            @test read_msg.leg_price == original_msg.leg_price
            @test read_msg.leg_delta == original_msg.leg_delta
            
        finally
            safe_rm(temp_file)
        end
    end
    
    @testset "Mixed record types in single file" begin
        metadata = create_test_metadata(Schema.MBO)  # Use MBO schema for mixed content
        temp_file = tempname() * ".dbn"
        
        try
            # Create multiple different message types
            hd1 = RecordHeader(55, RType.MBO_MSG, 1, 11111, 1640995200000000000)
            mbo_msg = MBOMsg(hd1, 1111111111, 10050000000, 100, 0x01, 1, Action.ADD, Side.BID, 1640995200000000001, 1000, 1001)
            
            hd2 = RecordHeader(45, RType.MBP_0_MSG, 1, 11111, 1640995200000000002)
            trade_msg = TradeMsg(hd2, 10055000000, 200, Action.TRADE, Side.NONE, 0x02, 0, 1640995200000000003, 2000, 1002)
            
            hd3 = RecordHeader(14, RType.OHLCV_1S_MSG, 1, 11111, 1640995200000000004)
            ohlcv_msg = OHLCVMsg(hd3, 10050000000, 10060000000, 10040000000, 10055000000, 50000)
            
            records_to_write = [mbo_msg, trade_msg, ohlcv_msg]
            
            # Write and read back
            write_dbn(temp_file, metadata, records_to_write)
            read_records = read_dbn(temp_file)
            
            @test length(read_records) == 3
            @test read_records[1] isa MBOMsg
            @test read_records[2] isa TradeMsg
            @test read_records[3] isa OHLCVMsg
            
            # Verify record order and basic data
            @test read_records[1].order_id == mbo_msg.order_id
            @test read_records[2].price == trade_msg.price
            @test read_records[3].volume == ohlcv_msg.volume
            
        finally
            safe_rm(temp_file)
        end
    end
    
    @testset "Large dataset with many records" begin
        metadata = create_test_metadata(Schema.TRADES)
        temp_file = tempname() * ".dbn"
        
        try
            # Create 1000 trade records
            records_to_write = []
            base_ts = 1640995200000000000
            
            for i in 1:1000
                hd = RecordHeader(45, RType.MBP_0_MSG, 1, 12345, base_ts + i * 1000000)
                trade_msg = TradeMsg(
                    hd,
                    10050000000 + i * 1000,     # varying price
                    100 + i,                     # varying size
                    Action.TRADE,
                    Side.NONE,
                    0x01,
                    0,
                    base_ts + i * 1000000 + 500000,
                    1000 + i,
                    i
                )
                push!(records_to_write, trade_msg)
            end
            
            # Write and read back
            write_dbn(temp_file, metadata, records_to_write)
            read_records = read_dbn(temp_file)
            
            @test length(read_records) == 1000
            
            # Verify first and last records
            @test read_records[1].price == 10050001000
            @test read_records[1].size == 101
            @test read_records[1].sequence == 1
            
            @test read_records[1000].price == 10051000000
            @test read_records[1000].size == 1100
            @test read_records[1000].sequence == 1000
            
            # Verify all records are TradeMsg
            @test all(r isa TradeMsg for r in read_records)
            
        finally
            safe_rm(temp_file)
        end
    end
    
    @testset "MBO v3 file reading" begin
        # Test reading actual MBO v3 files from test data
        @testset "Uncompressed MBO v3" begin
            file = joinpath(@__DIR__, "data", "test_data.mbo.v3.dbn")
            if isfile(file)
                records = read_dbn(file)
                @test length(records) == 2
                @test all(r isa MBOMsg for r in records)
                
                # First record
                r1 = records[1]
                @test r1.order_id == 3722750000000
                @test r1.action == Action.CANCEL
                @test r1.side == Side.ASK
                @test r1.size == 1
                @test r1.hd.publisher_id == 1
                @test r1.hd.instrument_id == 5482
                
                # Second record
                r2 = records[2]
                @test r2.order_id == 3723000000000
                @test r2.action == Action.CANCEL
                @test r2.side == Side.ASK
                @test r2.sequence == r1.sequence + 1
            end
        end
        
        @testset "Compressed MBO v3" begin
            file = joinpath(@__DIR__, "data", "test_data.mbo.v3.dbn.zst")
            if isfile(file)
                records = read_dbn(file)
                @test length(records) == 2
                @test all(r isa MBOMsg for r in records)
                
                # Should match uncompressed data
                r1 = records[1]
                @test r1.order_id == 3722750000000
                @test r1.action == Action.CANCEL
                @test r1.side == Side.ASK
            end
        end
    end
    
    @testset "OHLCV message tests" begin
        @testset "OHLCV structure and reading" begin
            # Test all OHLCV cadences
            test_files = [
                ("test_data.ohlcv-1s.dbn", RType.OHLCV_1S_MSG, Schema.OHLCV_1S),
                ("test_data.ohlcv-1m.dbn", RType.OHLCV_1M_MSG, Schema.OHLCV_1M),
                ("test_data.ohlcv-1h.dbn", RType.OHLCV_1H_MSG, Schema.OHLCV_1H),
                ("test_data.ohlcv-1d.dbn", RType.OHLCV_1D_MSG, Schema.OHLCV_1D),
            ]
            
            for (filename, expected_rtype, expected_schema) in test_files
                file = joinpath(@__DIR__, "data", filename)
                if isfile(file)
                    @testset "$filename" begin
                        records = read_dbn(file)
                        
                        if length(records) > 0
                            @test all(r isa OHLCVMsg for r in records)
                            @test all(r.hd.rtype == expected_rtype for r in records)
                            
                            # Check first record has valid OHLCV data
                            r = records[1]
                            @test r.high >= r.low
                            @test r.open >= r.low && r.open <= r.high
                            @test r.close >= r.low && r.close <= r.high
                            @test r.volume >= 0
                        end
                    end
                end
            end
        end
        
        @testset "OHLCV v2 vs v3 compatibility" begin
            v2_file = joinpath(@__DIR__, "data", "test_data.ohlcv-1s.dbn")
            v3_file = joinpath(@__DIR__, "data", "test_data.ohlcv-1s.v3.dbn.zst")
            
            if isfile(v2_file) && isfile(v3_file)
                v2_records = read_dbn(v2_file)
                v3_records = read_dbn(v3_file)
                
                @test length(v2_records) == length(v3_records)
                
                if length(v2_records) > 0
                    # Compare first record
                    r2 = v2_records[1]
                    r3 = v3_records[1]
                    
                    @test r2.open == r3.open
                    @test r2.high == r3.high
                    @test r2.low == r3.low
                    @test r2.close == r3.close
                    @test r2.volume == r3.volume
                end
            end
        end
        
        @testset "OHLCV write and read back" begin
            metadata = create_test_metadata(Schema.OHLCV_1S)
            temp_file = tempname() * ".dbn"
            
            try
                # Create test OHLCV messages
                hd1 = RecordHeader(14, RType.OHLCV_1S_MSG, 1, 5482, 1609160400000000000)
                ohlcv1 = OHLCVMsg(hd1, 100000000000, 105000000000, 99000000000, 102000000000, 1500)
                
                hd2 = RecordHeader(14, RType.OHLCV_1S_MSG, 1, 5482, 1609160401000000000)
                ohlcv2 = OHLCVMsg(hd2, 102000000000, 103000000000, 101000000000, 101500000000, 800)
                
                # Write and read back
                write_dbn(temp_file, metadata, [ohlcv1, ohlcv2])
                records = read_dbn(temp_file)
                
                @test length(records) == 2
                @test all(r isa OHLCVMsg for r in records)
                
                # Verify data integrity
                @test records[1].open == 100000000000
                @test records[1].high == 105000000000
                @test records[1].low == 99000000000
                @test records[1].close == 102000000000
                @test records[1].volume == 1500
                
                @test records[2].open == 102000000000
                @test records[2].close == 101500000000
                @test records[2].volume == 800
                
            finally
                if isfile(temp_file)
                    safe_rm(temp_file)
                end
            end
        end
    end
    
    @testset "MBP message tests" begin
        @testset "MBP-1 structure and reading" begin
            # Test MBP-1 files
            test_files = [
                ("test_data.mbp-1.dbn", RType.MBP_1_MSG, Schema.MBP_1),
                ("test_data.mbp-1.v3.dbn.zst", RType.MBP_1_MSG, Schema.MBP_1),
            ]
            
            for (filename, expected_rtype, expected_schema) in test_files
                file = joinpath(@__DIR__, "data", filename)
                if isfile(file)
                    @testset "$filename" begin
                        records = read_dbn(file)
                        
                        if length(records) > 0
                            @test all(r isa MBP1Msg for r in records)
                            @test all(r.hd.rtype == expected_rtype for r in records)
                            
                            # Check first record has valid MBP data
                            r = records[1]
                            @test r.price > 0
                            @test r.size > 0
                            @test r.action in [Action.ADD, Action.MODIFY, Action.CANCEL, Action.CLEAR, Action.TRADE]
                            @test r.side in [Side.BID, Side.ASK, Side.NONE]
                            
                            # Check BidAskPair structure (32 bytes total)
                            level = r.levels
                            @test typeof(level) == BidAskPair
                            @test level.bid_px >= 0
                            @test level.ask_px >= 0
                            @test level.bid_sz >= 0
                            @test level.ask_sz >= 0
                            @test level.bid_ct >= 0
                            @test level.ask_ct >= 0
                            
                            # Verify record size matches length field
                            expected_size = DBN.record_length_bytes(r.hd)
                            @test expected_size == 80  # 16 (header) + 32 (MBP data) + 32 (BidAskPair)
                        end
                    end
                end
            end
        end
        
        @testset "MBP-10 structure and reading" begin
            # Test MBP-10 files
            test_files = [
                ("test_data.mbp-10.dbn", RType.MBP_10_MSG, Schema.MBP_10),
                ("test_data.mbp-10.v3.dbn.zst", RType.MBP_10_MSG, Schema.MBP_10),
            ]
            
            for (filename, expected_rtype, expected_schema) in test_files
                file = joinpath(@__DIR__, "data", filename)
                if isfile(file)
                    @testset "$filename" begin
                        records = read_dbn(file)
                        
                        if length(records) > 0
                            @test all(r isa MBP10Msg for r in records)
                            @test all(r.hd.rtype == expected_rtype for r in records)
                            
                            # Check first record has valid MBP data
                            r = records[1]
                            @test r.price > 0
                            @test r.size > 0
                            @test r.action in [Action.ADD, Action.MODIFY, Action.CANCEL, Action.CLEAR, Action.TRADE]
                            @test r.side in [Side.BID, Side.ASK, Side.NONE]
                            
                            # Check all 10 BidAskPair levels
                            @test length(r.levels) == 10
                            for (i, level) in enumerate(r.levels)
                                @test typeof(level) == BidAskPair
                                @test level.bid_px >= 0
                                @test level.ask_px >= 0
                                @test level.bid_sz >= 0
                                @test level.ask_sz >= 0
                                @test level.bid_ct >= 0
                                @test level.ask_ct >= 0
                            end
                            
                            # Verify record size matches length field  
                            expected_size = DBN.record_length_bytes(r.hd)
                            @test expected_size == 368  # 16 (header) + 32 (MBP data) + 320 (10 × 32-byte BidAskPairs)
                        end
                    end
                end
            end
        end
        
        @testset "MBP v2 vs v3 compatibility" begin
            # MBP-1 comparison
            v2_file = joinpath(@__DIR__, "data", "test_data.mbp-1.dbn")
            v3_file = joinpath(@__DIR__, "data", "test_data.mbp-1.v3.dbn.zst")
            
            if isfile(v2_file) && isfile(v3_file)
                @testset "MBP-1 v2 vs v3" begin
                    v2_records = read_dbn(v2_file)
                    v3_records = read_dbn(v3_file)
                    
                    @test length(v2_records) == length(v3_records)
                    
                    if length(v2_records) > 0
                        # Compare first record
                        r2 = v2_records[1]
                        r3 = v3_records[1]
                        
                        @test r2.price == r3.price
                        @test r2.size == r3.size
                        @test r2.action == r3.action
                        @test r2.side == r3.side
                        @test r2.levels.bid_px == r3.levels.bid_px
                        @test r2.levels.ask_px == r3.levels.ask_px
                        @test r2.levels.bid_sz == r3.levels.bid_sz
                        @test r2.levels.ask_sz == r3.levels.ask_sz
                    end
                end
            end
            
            # MBP-10 comparison
            v2_file = joinpath(@__DIR__, "data", "test_data.mbp-10.dbn")
            v3_file = joinpath(@__DIR__, "data", "test_data.mbp-10.v3.dbn.zst")
            
            if isfile(v2_file) && isfile(v3_file)
                @testset "MBP-10 v2 vs v3" begin
                    v2_records = read_dbn(v2_file)
                    v3_records = read_dbn(v3_file)
                    
                    @test length(v2_records) == length(v3_records)
                    
                    if length(v2_records) > 0
                        # Compare first record
                        r2 = v2_records[1]
                        r3 = v3_records[1]
                        
                        @test r2.price == r3.price
                        @test r2.size == r3.size
                        @test r2.action == r3.action
                        @test r2.side == r3.side
                        
                        # Compare all 10 levels
                        for i in 1:10
                            @test r2.levels[i].bid_px == r3.levels[i].bid_px
                            @test r2.levels[i].ask_px == r3.levels[i].ask_px
                            @test r2.levels[i].bid_sz == r3.levels[i].bid_sz
                            @test r2.levels[i].ask_sz == r3.levels[i].ask_sz
                        end
                    end
                end
            end
        end
        
        @testset "MBP write and read back" begin
            @testset "MBP-1 roundtrip" begin
                metadata = create_test_metadata(Schema.MBP_1)
                temp_file = tempname() * ".dbn"
                
                try
                    # Create test MBP-1 messages
                    hd1 = RecordHeader(20, RType.MBP_1_MSG, 1, 5482, 1609160400000000000)
                    level1 = BidAskPair(3720250000000, 3720500000000, 24, 11, 15, 9)
                    mbp1_1 = MBP1Msg(hd1, 3720500000000, 1, Action.ADD, Side.ASK, 0x80, 0, 1609160400006136329, 17214, 1170362, level1)
                    
                    hd2 = RecordHeader(20, RType.MBP_1_MSG, 1, 5482, 1609160400000001000)
                    level2 = BidAskPair(3720000000000, 3720750000000, 31, 34, 12, 8)
                    mbp1_2 = MBP1Msg(hd2, 3720750000000, 2, Action.MODIFY, Side.BID, 0x40, 1, 1609160400006136330, 17215, 1170363, level2)
                    
                    # Write and read back
                    write_dbn(temp_file, metadata, [mbp1_1, mbp1_2])
                    records = read_dbn(temp_file)
                    
                    @test length(records) == 2
                    @test all(r isa MBP1Msg for r in records)
                    
                    # Verify data integrity
                    @test records[1].price == 3720500000000
                    @test records[1].levels.bid_px == 3720250000000
                    @test records[1].levels.ask_px == 3720500000000
                    @test records[1].levels.bid_sz == 24
                    @test records[1].levels.ask_sz == 11
                    
                    @test records[2].price == 3720750000000
                    @test records[2].action == Action.MODIFY
                    @test records[2].side == Side.BID
                    
                finally
                    if isfile(temp_file)
                        safe_rm(temp_file)
                    end
                end
            end
            
            @testset "MBP-10 roundtrip" begin
                metadata = create_test_metadata(Schema.MBP_10)
                temp_file = tempname() * ".dbn"
                
                try
                    # Create test MBP-10 message with realistic levels
                    hd = RecordHeader(92, RType.MBP_10_MSG, 1, 5482, 1609160400000000000)
                    levels = ntuple(10) do i
                        bid_px = 3720250000000 - (i-1) * 250000000  # decreasing bids
                        ask_px = 3720500000000 + (i-1) * 250000000  # increasing asks
                        bid_sz = UInt32(20 + i * 5)
                        ask_sz = UInt32(15 + i * 3) 
                        bid_ct = UInt32(10 + i)
                        ask_ct = UInt32(8 + i)
                        BidAskPair(bid_px, ask_px, bid_sz, ask_sz, bid_ct, ask_ct)
                    end
                    
                    mbp10 = MBP10Msg(hd, 3722750000000, 1, Action.CANCEL, Side.ASK, 0x80, 9, 1609160400000704060, 22993, 1170352, levels)
                    
                    # Write and read back
                    write_dbn(temp_file, metadata, [mbp10])
                    records = read_dbn(temp_file)
                    
                    @test length(records) == 1
                    @test records[1] isa MBP10Msg
                    
                    # Verify data integrity
                    r = records[1]
                    @test r.price == 3722750000000
                    @test r.action == Action.CANCEL
                    @test r.side == Side.ASK
                    @test length(r.levels) == 10
                    
                    # Check first and last levels
                    @test r.levels[1].bid_px == 3720250000000
                    @test r.levels[1].ask_px == 3720500000000
                    @test r.levels[10].bid_px == 3720250000000 - 9 * 250000000
                    @test r.levels[10].ask_px == 3720500000000 + 9 * 250000000
                    
                finally
                    if isfile(temp_file)
                        safe_rm(temp_file)
                    end
                end
            end
        end
    end
    
    @testset "Trades message tests" begin
        @testset "Trades structure and reading" begin
            # Test Trades files
            test_files = [
                ("test_data.trades.dbn", RType.MBP_0_MSG, Schema.TRADES),
                ("test_data.trades.v1.dbn.zst", RType.MBP_0_MSG, Schema.TRADES),
                ("test_data.trades.v2.dbn.zst", RType.MBP_0_MSG, Schema.TRADES),
                ("test_data.trades.v3.dbn.zst", RType.MBP_0_MSG, Schema.TRADES),
            ]
            
            for (filename, expected_rtype, expected_schema) in test_files
                file = joinpath(@__DIR__, "data", filename)
                if isfile(file)
                    @testset "$filename" begin
                        records = read_dbn(file)
                        
                        if length(records) > 0
                            @test all(r isa TradeMsg for r in records)
                            @test all(r.hd.rtype == expected_rtype for r in records)
                            
                            # Check first record has valid Trade data
                            r = records[1]
                            @test r.price > 0
                            @test r.size > 0
                            @test r.action == Action.TRADE  # Trades should always have TRADE action
                            @test r.side in [Side.BID, Side.ASK, Side.NONE]
                            @test r.depth == 0  # Trades typically have depth 0
                            
                            # Verify record size matches length field (48 bytes total)
                            expected_size = DBN.record_length_bytes(r.hd)
                            @test expected_size == 48  # 16 (header) + 32 (trade data)
                        end
                    end
                end
            end
        end
        
        @testset "Trades v1/v2/v3 compatibility" begin
            # Test compatibility across versions
            test_pairs = [
                ("test_data.trades.dbn", "test_data.trades.v2.dbn.zst"),
                ("test_data.trades.v2.dbn.zst", "test_data.trades.v3.dbn.zst"),
            ]
            
            for (file1, file2) in test_pairs
                path1 = joinpath(@__DIR__, "data", file1)
                path2 = joinpath(@__DIR__, "data", file2)
                
                if isfile(path1) && isfile(path2)
                    @testset "$file1 vs $file2" begin
                        records1 = read_dbn(path1)
                        records2 = read_dbn(path2)
                        
                        @test length(records1) == length(records2)
                        
                        if length(records1) > 0
                            # Compare first record
                            r1 = records1[1]
                            r2 = records2[1]
                            
                            @test r1.price == r2.price
                            @test r1.size == r2.size
                            @test r1.action == r2.action
                            @test r1.side == r2.side
                            @test r1.flags == r2.flags
                            @test r1.depth == r2.depth
                            @test r1.ts_recv == r2.ts_recv
                            @test r1.ts_in_delta == r2.ts_in_delta
                            @test r1.sequence == r2.sequence
                        end
                    end
                end
            end
        end
        
        @testset "Trades write and read back" begin
            @testset "Single trade roundtrip" begin
                metadata = create_test_metadata(Schema.TRADES)
                temp_file = tempname() * ".dbn"
                
                try
                    # Create test Trade message matching real data format
                    hd = RecordHeader(12, RType.MBP_0_MSG, 1, 5482, 1609160400098821953)
                    trade_msg = TradeMsg(
                        hd,                      # hd
                        3720250000000,          # price ($3720.25)
                        5,                      # size
                        Action.TRADE,           # action
                        Side.ASK,               # side
                        0x81,                   # flags (129)
                        0,                      # depth
                        1609160400099150057,    # ts_recv
                        19251,                  # ts_in_delta
                        1170380                 # sequence
                    )
                    
                    # Write and read back
                    write_dbn(temp_file, metadata, [trade_msg])
                    records = read_dbn(temp_file)
                    
                    @test length(records) == 1
                    @test records[1] isa TradeMsg
                    
                    # Verify data integrity
                    r = records[1]
                    @test r.price == trade_msg.price
                    @test r.size == trade_msg.size
                    @test r.action == trade_msg.action
                    @test r.side == trade_msg.side
                    @test r.flags == trade_msg.flags
                    @test r.depth == trade_msg.depth
                    @test r.ts_recv == trade_msg.ts_recv
                    @test r.ts_in_delta == trade_msg.ts_in_delta
                    @test r.sequence == trade_msg.sequence
                    
                finally
                    if isfile(temp_file)
                        safe_rm(temp_file)
                    end
                end
            end
            
            @testset "Multiple trades roundtrip" begin
                metadata = create_test_metadata(Schema.TRADES)
                temp_file = tempname() * ".dbn"
                
                try
                    # Create multiple trade messages with varying data
                    trades = []
                    base_ts = 1609160400098821953
                    base_price = 3720000000000  # $3720.00
                    
                    for i in 1:10
                        hd = RecordHeader(12, RType.MBP_0_MSG, 1, 5482, base_ts + i * 1000000)
                        trade = TradeMsg(
                            hd,
                            base_price + i * 250000000,  # increment price by $0.25
                            10 + i * 5,                  # varying size
                            Action.TRADE,
                            i % 2 == 0 ? Side.BID : Side.ASK,  # alternate sides
                            UInt8(0x80 + i % 8),        # varying flags
                            0,                           # depth always 0 for trades
                            base_ts + i * 1000000 + 100000,  # ts_recv slightly after ts_event
                            15000 + i * 1000,           # varying ts_in_delta
                            1170000 + i                 # incrementing sequence
                        )
                        push!(trades, trade)
                    end
                    
                    # Write and read back
                    write_dbn(temp_file, metadata, trades)
                    records = read_dbn(temp_file)
                    
                    @test length(records) == 10
                    @test all(r isa TradeMsg for r in records)
                    
                    # Verify all data matches
                    for (orig, read) in zip(trades, records)
                        @test orig.price == read.price
                        @test orig.size == read.size
                        @test orig.action == read.action
                        @test orig.side == read.side
                        @test orig.flags == read.flags
                        @test orig.sequence == read.sequence
                    end
                    
                    # Verify price progression
                    @test records[1].price == base_price + 250000000  # $3720.25
                    @test records[10].price == base_price + 10 * 250000000  # $3722.50
                    
                    # Verify size progression
                    @test records[1].size == 15
                    @test records[10].size == 60
                    
                finally
                    if isfile(temp_file)
                        safe_rm(temp_file)
                    end
                end
            end
            
            @testset "Trades with different actions and sides" begin
                metadata = create_test_metadata(Schema.TRADES)
                temp_file = tempname() * ".dbn"
                
                try
                    # Test different combinations of actions and sides
                    test_cases = [
                        (Action.TRADE, Side.BID),
                        (Action.TRADE, Side.ASK),
                        (Action.TRADE, Side.NONE),
                        (Action.FILL, Side.BID),
                        (Action.FILL, Side.ASK),
                    ]
                    
                    trades = []
                    for (i, (action, side)) in enumerate(test_cases)
                        hd = RecordHeader(12, RType.MBP_0_MSG, 1, 5482, 1609160400000000000 + i * 1000000)
                        trade = TradeMsg(
                            hd,
                            3720000000000 + i * 1000000000,  # varying prices
                            100 + i * 10,                    # varying sizes
                            action,
                            side,
                            UInt8(0x80),                     # standard flags
                            0,                               # depth
                            1609160400000000000 + i * 1000000 + 50000,
                            20000,
                            1000000 + i
                        )
                        push!(trades, trade)
                    end
                    
                    # Write and read back
                    write_dbn(temp_file, metadata, trades)
                    records = read_dbn(temp_file)
                    
                    @test length(records) == length(test_cases)
                    
                    # Verify each action/side combination
                    for (i, ((expected_action, expected_side), record)) in enumerate(zip(test_cases, records))
                        @test record.action == expected_action
                        @test record.side == expected_side
                        @test record.size == 100 + i * 10
                    end
                    
                finally
                    if isfile(temp_file)
                        safe_rm(temp_file)
                    end
                end
            end
        end
    end
    
    @testset "BBO message tests" begin
        @testset "BBO structure and reading" begin
            # Test different BBO file types
            test_files = [
                ("test_data.tbbo.dbn", RType.MBP_1_MSG, Schema.TBBO),
                ("test_data.tbbo.v2.dbn.zst", RType.MBP_1_MSG, Schema.TBBO),
                ("test_data.cbbo-1s.dbn", RType.CBBO_1S_MSG, Schema.CBBO_1S),
                ("test_data.cbbo-1s.v2.dbn.zst", RType.CBBO_1S_MSG, Schema.CBBO_1S),
                ("test_data.bbo-1s.dbn", RType.BBO_1S_MSG, Schema.BBO_1S),
                ("test_data.bbo-1s.v2.dbn.zst", RType.BBO_1S_MSG, Schema.BBO_1S),
                ("test_data.bbo-1s.v3.dbn.zst", RType.BBO_1S_MSG, Schema.BBO_1S),
                ("test_data.bbo-1m.v3.dbn.zst", RType.BBO_1M_MSG, Schema.BBO_1M),
            ]
            
            for (filename, expected_rtype, expected_schema) in test_files
                file = joinpath(@__DIR__, "data", filename)
                if isfile(file)
                    @testset "$filename" begin
                        records = read_dbn(file)
                        
                        if length(records) > 0
                            # Check record type based on RType
                            if expected_rtype == RType.MBP_1_MSG
                                @test all(r isa MBP1Msg for r in records)
                            elseif expected_rtype == RType.CBBO_1S_MSG
                                @test all(r isa CBBO1sMsg for r in records)
                            elseif expected_rtype == RType.BBO_1S_MSG
                                @test all(r isa BBO1sMsg for r in records)
                            elseif expected_rtype == RType.BBO_1M_MSG
                                @test all(r isa BBO1mMsg for r in records)
                            end
                            
                            @test all(r.hd.rtype == expected_rtype for r in records)
                            
                            # Check first record has valid BBO data
                            r = records[1]
                            @test r.price > 0
                            @test r.size > 0
                            @test r.side in [Side.BID, Side.ASK, Side.NONE]
                            
                            # BBO messages typically use NONE action
                            if hasproperty(r, :action)
                                @test r.action in [Action.NONE, Action.TRADE, Action.MODIFY]
                            end
                            
                            # Check BidAskPair levels
                            if hasproperty(r, :levels)
                                @test typeof(r.levels) == BidAskPair
                                @test r.levels.bid_px >= 0
                                @test r.levels.ask_px >= 0
                                @test r.levels.bid_sz >= 0
                                @test r.levels.ask_sz >= 0
                            end
                            
                            # Verify record size matches length field (80 bytes total)
                            expected_size = DBN.record_length_bytes(r.hd)
                            @test expected_size == 80  # 16 (header) + 32 (BBO data) + 32 (BidAskPair)
                        end
                    end
                end
            end
        end
        
        @testset "BBO v2 vs v3 compatibility" begin
            # Test BBO compatibility across versions
            v2_file = joinpath(@__DIR__, "data", "test_data.bbo-1s.v2.dbn.zst")
            v3_file = joinpath(@__DIR__, "data", "test_data.bbo-1s.v3.dbn.zst")
            
            if isfile(v2_file) && isfile(v3_file)
                @testset "BBO-1s v2 vs v3" begin
                    v2_records = read_dbn(v2_file)
                    v3_records = read_dbn(v3_file)
                    
                    @test length(v2_records) == length(v3_records)
                    
                    if length(v2_records) > 0
                        # Compare first record
                        r2 = v2_records[1]
                        r3 = v3_records[1]
                        
                        @test r2.price == r3.price
                        @test r2.size == r3.size
                        @test r2.side == r3.side
                        @test r2.flags == r3.flags
                        @test r2.ts_recv == r3.ts_recv
                        @test r2.sequence == r3.sequence
                        @test r2.levels.bid_px == r3.levels.bid_px
                        @test r2.levels.ask_px == r3.levels.ask_px
                        @test r2.levels.bid_sz == r3.levels.bid_sz
                        @test r2.levels.ask_sz == r3.levels.ask_sz
                    end
                end
            end
        end
        
        @testset "BBO write and read back" begin
            @testset "CBBO-1s roundtrip" begin
                metadata = create_test_metadata(Schema.CBBO_1S)
                temp_file = tempname() * ".dbn"
                
                try
                    # Create test CBBO-1s message
                    hd = RecordHeader(20, RType.CBBO_1S_MSG, 1, 5482, 1609113599045849637)
                    level = BidAskPair(3702250000000, 3702750000000, 18, 13, 12, 8)
                    cbbo_msg = CBBO1sMsg(
                        hd,                      # hd
                        3702500000000,          # price ($3702.5)
                        2,                      # size
                        Action.NONE,            # action
                        Side.ASK,               # side
                        0xa8,                   # flags (168)
                        0,                      # depth
                        1609113600000000000,    # ts_recv
                        500000000,              # ts_in_delta
                        145799,                 # sequence
                        level                   # levels
                    )
                    
                    # Write and read back
                    write_dbn(temp_file, metadata, [cbbo_msg])
                    records = read_dbn(temp_file)
                    
                    @test length(records) == 1
                    @test records[1] isa CBBO1sMsg
                    
                    # Verify data integrity
                    r = records[1]
                    @test r.price == cbbo_msg.price
                    @test r.size == cbbo_msg.size
                    @test r.action == cbbo_msg.action
                    @test r.side == cbbo_msg.side
                    @test r.flags == cbbo_msg.flags
                    @test r.ts_recv == cbbo_msg.ts_recv
                    @test r.sequence == cbbo_msg.sequence
                    @test r.levels.bid_px == cbbo_msg.levels.bid_px
                    @test r.levels.ask_px == cbbo_msg.levels.ask_px
                    
                finally
                    if isfile(temp_file)
                        safe_rm(temp_file)
                    end
                end
            end
            
            @testset "BBO-1s roundtrip" begin
                metadata = create_test_metadata(Schema.BBO_1S)
                temp_file = tempname() * ".dbn"
                
                try
                    # Create test BBO-1s message
                    hd = RecordHeader(20, RType.BBO_1S_MSG, 1, 5482, 1609113599045849637)
                    level = BidAskPair(3702250000000, 3702750000000, 18, 13, 12, 8)
                    bbo_msg = BBO1sMsg(
                        hd,                      # hd
                        3702500000000,          # price ($3702.5)
                        2,                      # size
                        Action.NONE,            # action
                        Side.ASK,               # side
                        0xa8,                   # flags (168)
                        0,                      # depth
                        1609113600000000000,    # ts_recv
                        500000000,              # ts_in_delta
                        145799,                 # sequence
                        level                   # levels
                    )
                    
                    # Write and read back
                    write_dbn(temp_file, metadata, [bbo_msg])
                    records = read_dbn(temp_file)
                    
                    @test length(records) == 1
                    @test records[1] isa BBO1sMsg
                    
                    # Verify data integrity
                    r = records[1]
                    @test r.price == bbo_msg.price
                    @test r.size == bbo_msg.size
                    @test r.action == bbo_msg.action
                    @test r.side == bbo_msg.side
                    @test r.flags == bbo_msg.flags
                    @test r.ts_recv == bbo_msg.ts_recv
                    @test r.sequence == bbo_msg.sequence
                    @test r.levels.bid_px == bbo_msg.levels.bid_px
                    @test r.levels.ask_px == bbo_msg.levels.ask_px
                    
                finally
                    if isfile(temp_file)
                        safe_rm(temp_file)
                    end
                end
            end
            
            @testset "TBBO roundtrip (MBP1Msg)" begin
                metadata = create_test_metadata(Schema.TBBO)
                temp_file = tempname() * ".dbn"
                
                try
                    # TBBO uses MBP1Msg structure
                    hd = RecordHeader(20, RType.MBP_1_MSG, 1, 5482, 1609160400098821953)
                    level = BidAskPair(3720250000000, 3720500000000, 26, 7, 15, 9)
                    tbbo_msg = MBP1Msg(
                        hd,                      # hd
                        3720250000000,          # price ($3720.25)
                        5,                      # size
                        Action.TRADE,           # action
                        Side.ASK,               # side
                        0x81,                   # flags (129)
                        0,                      # depth
                        1609160400099150057,    # ts_recv
                        19251,                  # ts_in_delta
                        1170380,                # sequence
                        level                   # levels
                    )
                    
                    # Write and read back
                    write_dbn(temp_file, metadata, [tbbo_msg])
                    records = read_dbn(temp_file)
                    
                    @test length(records) == 1
                    @test records[1] isa MBP1Msg
                    
                    # Verify data integrity
                    r = records[1]
                    @test r.price == tbbo_msg.price
                    @test r.size == tbbo_msg.size
                    @test r.action == tbbo_msg.action
                    @test r.side == tbbo_msg.side
                    @test r.levels.bid_px == tbbo_msg.levels.bid_px
                    @test r.levels.ask_px == tbbo_msg.levels.ask_px
                    
                finally
                    if isfile(temp_file)
                        safe_rm(temp_file)
                    end
                end
            end
            
            @testset "Multiple BBO types in one file" begin
                metadata = create_test_metadata(Schema.BBO_1S)
                temp_file = tempname() * ".dbn"
                
                try
                    # Create multiple BBO messages with different timestamps
                    bbo_msgs = []
                    base_ts = 1609113599000000000
                    base_price = 3702000000000
                    
                    for i in 1:5
                        hd = RecordHeader(20, RType.BBO_1S_MSG, 1, 5482, base_ts + i * 1000000000)
                        level = BidAskPair(
                            base_price + i * 250000000,      # bid price
                            base_price + (i + 1) * 250000000, # ask price  
                            15 + i * 2,                       # bid size
                            10 + i * 3,                       # ask size
                            8 + i,                            # bid count
                            6 + i                             # ask count
                        )
                        
                        bbo_msg = BBO1sMsg(
                            hd,
                            base_price + i * 500000000,  # price between bid/ask
                            UInt32(i * 2),               # varying size
                            Action.NONE,
                            i % 2 == 0 ? Side.BID : Side.ASK,  # alternate sides
                            UInt8(0xa0 + i),            # varying flags
                            UInt8(0),                    # depth
                            base_ts + i * 1000000000 + 100000000,
                            Int32(500000000 + i * 100000000),  # varying ts_in_delta
                            UInt32(145000 + i),         # incrementing sequence
                            level
                        )
                        push!(bbo_msgs, bbo_msg)
                    end
                    
                    # Write and read back
                    write_dbn(temp_file, metadata, bbo_msgs)
                    records = read_dbn(temp_file)
                    
                    @test length(records) == 5
                    @test all(r isa BBO1sMsg for r in records)
                    
                    # Verify progression
                    for (i, (orig, read)) in enumerate(zip(bbo_msgs, records))
                        @test orig.price == read.price
                        @test orig.size == read.size
                        @test orig.side == read.side
                        @test orig.sequence == read.sequence
                    end
                    
                    # Check price progression
                    @test records[1].price == base_price + 500000000     # $3702.50
                    @test records[5].price == base_price + 5 * 500000000 # $3705.00
                    
                finally
                    if isfile(temp_file)
                        safe_rm(temp_file)
                    end
                end
            end
        end
    end
    
    @testset "Zstd compression tests" begin
        @testset "Auto-detection of compressed files" begin
            # Test that we can read compressed files with and without .zst extension
            compressed_file = joinpath(@__DIR__, "data", "test_data.mbo.v3.dbn.zst")
            
            if isfile(compressed_file)
                # Copy to a file without .zst extension
                temp_file = tempname() * ".dbn"
                try
                    cp(compressed_file, temp_file)
                    
                    # Should auto-detect compression by magic bytes
                    records = read_dbn(temp_file)
                    @test length(records) == 2
                    @test all(r isa MBOMsg for r in records)
                    
                finally
                    if isfile(temp_file)
                        safe_rm(temp_file)
                    end
                end
            end
        end
        
        @testset "Streaming decompression" begin
            # Test that we can stream large compressed files
            compressed_file = joinpath(@__DIR__, "data", "test_data.mbp-10.v3.dbn.zst")
            
            if isfile(compressed_file)
                # Use DBNDecoder directly to test streaming
                decoder = DBNDecoder(compressed_file)
                try
                    count = 0
                    while !eof(decoder.io)
                        record = read_record(decoder)
                        if record !== nothing
                            count += 1
                            @test record isa MBP10Msg
                        end
                    end
                    @test count > 0
                finally
                    if decoder.io !== decoder.base_io
                        close(decoder.io)
                    end
                    close(decoder.base_io)
                end
            end
        end
    end
end