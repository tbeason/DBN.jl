# Phase 2: Struct and Type Testing

@testset "Phase 2: Struct and Type Testing" begin
    
    @testset "Simple struct creation" begin
        # Test RecordHeader creation
        @testset "RecordHeader" begin
            hd = RecordHeader(40, RType.TRADE_MSG, 1, 12345, 1640995200000000000)
            @test hd.length == 40
            @test hd.rtype == RType.TRADE_MSG
            @test hd.publisher_id == 1
            @test hd.instrument_id == 12345
            @test hd.ts_event == 1640995200000000000
        end
        
        # Test BidAskPair creation
        @testset "BidAskPair" begin
            pair = BidAskPair(10050000000, 10060000000, 100, 200, 5, 3)
            @test pair.bid_px == 10050000000
            @test pair.ask_px == 10060000000
            @test pair.bid_sz == 100
            @test pair.ask_sz == 200
            @test pair.bid_ct == 5
            @test pair.ask_ct == 3
        end
        
        # Test VersionUpgradePolicy creation
        @testset "VersionUpgradePolicy" begin
            policy = VersionUpgradePolicy(0)
            @test policy.upgrade_policy == 0
        end
        
        # Test DatasetCondition creation
        @testset "DatasetCondition" begin
            condition = DatasetCondition(0, 1640995200000000000, 1640995260000000000, 1000)
            @test condition.last_ts_out == 0
            @test condition.start_ts == 1640995200000000000
            @test condition.end_ts == 1640995260000000000
            @test condition.limit == 1000
        end
    end
    
    @testset "Metadata struct creation" begin
        symbols = ["AAPL", "MSFT", "GOOGL"]
        partial = String[]
        not_found = String[]
        mappings = Tuple{String,String,Int64,Int64}[]
        
        metadata = Metadata(
            DBN_VERSION,           # version
            "XNAS.ITCH",              # dataset
            Schema.TRADES,        # schema
            1640995200000000000,      # start
            1640995260000000000,      # end_ts
            1000,                     # limit
            Compression.NONE,     # compression
            SType.RAW_SYMBOL,     # stype_in
            SType.RAW_SYMBOL,     # stype_out
            false,                    # ts_out
            symbols,                  # symbols
            partial,                  # partial
            not_found,                # not_found
            mappings                  # mappings
        )
        
        @test metadata.version == DBN_VERSION
        @test metadata.dataset == "XNAS.ITCH"
        @test metadata.schema == Schema.TRADES
        @test metadata.start_ts == 1640995200000000000
        @test metadata.end_ts == 1640995260000000000
        @test metadata.limit == 1000
        @test metadata.compression == Compression.NONE
        @test metadata.stype_in == SType.RAW_SYMBOL
        @test metadata.stype_out == SType.RAW_SYMBOL
        @test metadata.ts_out == false
        @test metadata.symbols == symbols
        @test length(metadata.partial) == 0
        @test length(metadata.not_found) == 0
        @test length(metadata.mappings) == 0
    end
    
    @testset "Message type struct creation" begin
        # Common record header for all messages
        hd = RecordHeader(40, RType.TRADE_MSG, 1, 12345, 1640995200000000000)
        
        @testset "MBOMsg" begin
            msg = MBOMsg(
                hd,                      # hd
                9876543210,              # order_id
                10050000000,             # price
                100,                     # size
                0x01,                    # flags
                1,                       # channel_id
                Action.ADD,          # action
                Side.BID,            # side
                1640995200000000001,     # ts_recv
                1000,                    # ts_in_delta
                12345                    # sequence
            )
            
            @test msg.hd == hd
            @test msg.order_id == 9876543210
            @test msg.price == 10050000000
            @test msg.size == 100
            @test msg.flags == 0x01
            @test msg.channel_id == 1
            @test msg.action == Action.ADD
            @test msg.side == Side.BID
            @test msg.ts_recv == 1640995200000000001
            @test msg.ts_in_delta == 1000
            @test msg.sequence == 12345
        end
        
        @testset "TradeMsg" begin
            msg = TradeMsg(
                hd,                      # hd
                10055000000,             # price
                250,                     # size
                Action.TRADE,        # action
                Side.NONE,           # side
                0x02,                    # flags
                0,                       # depth
                1640995200000000002,     # ts_recv
                2000,                    # ts_in_delta
                12346                    # sequence
            )
            
            @test msg.hd == hd
            @test msg.price == 10055000000
            @test msg.size == 250
            @test msg.action == Action.TRADE
            @test msg.side == Side.NONE
            @test msg.flags == 0x02
            @test msg.depth == 0
            @test msg.ts_recv == 1640995200000000002
            @test msg.ts_in_delta == 2000
            @test msg.sequence == 12346
        end
        
        @testset "MBP1Msg" begin
            levels = BidAskPair(10050000000, 10060000000, 100, 200, 5, 3)
            
            msg = MBP1Msg(
                hd,                      # hd
                10055000000,             # price
                150,                     # size
                Action.MODIFY,       # action
                Side.ASK,            # side
                0x04,                    # flags
                1,                       # depth
                1640995200000000003,     # ts_recv
                3000,                    # ts_in_delta
                12347,                   # sequence
                levels                   # levels
            )
            
            @test msg.hd == hd
            @test msg.price == 10055000000
            @test msg.size == 150
            @test msg.action == Action.MODIFY
            @test msg.side == Side.ASK
            @test msg.flags == 0x04
            @test msg.depth == 1
            @test msg.ts_recv == 1640995200000000003
            @test msg.ts_in_delta == 3000
            @test msg.sequence == 12347
            @test msg.levels == levels
        end
        
        @testset "MBP10Msg" begin
            # Create 10 bid-ask pairs
            levels = ntuple(10) do i
                BidAskPair(
                    10050000000 - (i-1)*1000000,  # bid decreasing
                    10060000000 + (i-1)*1000000,  # ask increasing
                    100 + i*10,                   # bid size
                    200 + i*10,                   # ask size
                    5 + i,                        # bid count
                    3 + i                         # ask count
                )
            end
            
            msg = MBP10Msg(
                hd,                      # hd
                10055000000,             # price
                175,                     # size
                Action.CLEAR,        # action
                Side.BID,            # side
                0x08,                    # flags
                2,                       # depth
                1640995200000000004,     # ts_recv
                4000,                    # ts_in_delta
                12348,                   # sequence
                levels                   # levels
            )
            
            @test msg.hd == hd
            @test msg.price == 10055000000
            @test msg.size == 175
            @test msg.action == Action.CLEAR
            @test msg.side == Side.BID
            @test msg.flags == 0x08
            @test msg.depth == 2
            @test msg.ts_recv == 1640995200000000004
            @test msg.ts_in_delta == 4000
            @test msg.sequence == 12348
            @test length(msg.levels) == 10
            @test msg.levels[1].bid_px == 10050000000
            @test msg.levels[10].ask_px == 10069000000
        end
        
        @testset "OHLCVMsg" begin
            msg = OHLCVMsg(
                hd,                      # hd
                10050000000,             # open
                10070000000,             # high
                10040000000,             # low
                10065000000,             # close
                125000                   # volume
            )
            
            @test msg.hd == hd
            @test msg.open == 10050000000
            @test msg.high == 10070000000
            @test msg.low == 10040000000
            @test msg.close == 10065000000
            @test msg.volume == 125000
        end
        
        @testset "StatusMsg" begin
            msg = StatusMsg(
                hd,                      # hd
                1640995200000000005,     # ts_recv
                1,                       # action
                0,                       # reason
                2,                       # trading_event
                true,                    # is_trading
                true,                    # is_quoting
                false                    # is_short_sell_restricted
            )
            
            @test msg.hd == hd
            @test msg.ts_recv == 1640995200000000005
            @test msg.action == 1
            @test msg.reason == 0
            @test msg.trading_event == 2
            @test msg.is_trading == true
            @test msg.is_quoting == true
            @test msg.is_short_sell_restricted == false
        end
        
        @testset "ImbalanceMsg" begin
            msg = ImbalanceMsg(
                hd,                      # hd
                1640995200000000006,     # ts_recv
                10055000000,             # ref_price
                1640995230000000000,     # auction_time
                1000,                    # cont_size
                5000,                    # auction_size
                2000,                    # imbalance_size
                Side.BID,            # imbalance_side
                10056000000              # clearing_price
            )
            
            @test msg.hd == hd
            @test msg.ts_recv == 1640995200000000006
            @test msg.ref_price == 10055000000
            @test msg.auction_time == 1640995230000000000
            @test msg.cont_size == 1000
            @test msg.auction_size == 5000
            @test msg.imbalance_size == 2000
            @test msg.imbalance_side == Side.BID
            @test msg.clearing_price == 10056000000
        end
        
        @testset "StatMsg (DBN v3)" begin
            msg = StatMsg(
                hd,                      # hd
                1640995200000000007,     # ts_recv
                1640995200000000000,     # ts_ref
                10055000000,             # price
                9876543210123456,        # quantity (now Int64 in v3)
                12349,                   # sequence
                5000,                    # ts_in_delta
                1,                       # stat_type
                1,                       # channel_id
                2,                       # update_action
                0x01                     # stat_flags
            )
            
            @test msg.hd == hd
            @test msg.ts_recv == 1640995200000000007
            @test msg.ts_ref == 1640995200000000000
            @test msg.price == 10055000000
            @test msg.quantity == 9876543210123456  # Test large 64-bit value
            @test msg.sequence == 12349
            @test msg.ts_in_delta == 5000
            @test msg.stat_type == 1
            @test msg.channel_id == 1
            @test msg.update_action == 2
            @test msg.stat_flags == 0x01
        end
        
        @testset "InstrumentDefMsg (DBN v3)" begin
            msg = InstrumentDefMsg(
                hd,                          # hd
                1640995200000000008,         # ts_recv
                1000000,                     # min_price_increment
                1000000000,                  # display_factor
                1672531200000000000,         # expiration
                1640995200000000000,         # activation
                15000000000,                 # high_limit_price
                5000000000,                  # low_limit_price
                1000000000,                  # max_price_variation
                100,                         # unit_of_measure_qty
                1000000,                     # min_price_increment_amount
                1000000000,                  # price_ratio
                0,                           # inst_attrib_value
                0,                           # underlying_id
                9876543210123456789,         # raw_instrument_id (now UInt64 in v3)
                0,                           # market_depth_implied
                10,                          # market_depth
                1,                           # market_segment_id
                1000000,                     # max_trade_vol
                1,                           # min_lot_size
                100,                         # min_lot_size_block
                1,                           # min_lot_size_round_lot
                1,                           # min_trade_vol
                1,                           # contract_multiplier
                0,                           # decay_quantity
                100,                         # original_contract_size
                1,                           # appl_id
                2024,                        # maturity_year
                0,                           # decay_start_date
                1,                           # channel_id
                "USD",                       # currency
                "USD",                       # settl_currency
                "CS",                        # secsubtype
                "AAPL",                      # raw_symbol
                "TECH",                      # group
                "XNAS",                      # exchange
                "AAPL.NASDAQ",               # asset (expanded to 11 bytes in v3)
                "ESTVPS",                    # cfi
                "CS",                        # security_type
                "Shares",                    # unit_of_measure
                "",                          # underlying
                "",                          # strike_price_currency
                InstrumentClass.STOCK,   # instrument_class
                0,                           # strike_price
                'P',                         # match_algorithm
                2,                           # main_fraction
                0,                           # price_display_format
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
                0,                           # leg_count
                0,                           # leg_index
                0,                           # leg_instrument_id
                "",                          # leg_raw_symbol
                Side.NONE,               # leg_side
                0,                           # leg_underlying_id
                InstrumentClass.STOCK,   # leg_instrument_class
                0,                           # leg_ratio_qty_numerator
                0,                           # leg_ratio_qty_denominator
                0,                           # leg_ratio_price_numerator
                0,                           # leg_ratio_price_denominator
                0,                           # leg_price
                0                            # leg_delta
            )
            
            @test msg.hd == hd
            @test msg.ts_recv == 1640995200000000008
            @test msg.raw_instrument_id == 9876543210123456789  # Test UInt64 value
            @test msg.currency == "USD"
            @test msg.raw_symbol == "AAPL"
            @test msg.asset == "AAPL.NASDAQ"  # Test expanded asset field
            @test msg.instrument_class == InstrumentClass.STOCK
            @test msg.leg_count == 0  # Test new strategy leg fields
            @test msg.leg_side == Side.NONE
            @test msg.leg_instrument_class == InstrumentClass.STOCK
        end
    end
end