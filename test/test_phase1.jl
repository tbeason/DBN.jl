# Phase 1: Basic Module Setup and Loading Tests

@testset "Phase 1: Basic Module Setup and Loading" begin
    
    @testset "Module loads without syntax errors" begin
        # The fact that we got here means the module loaded
        @test isdefined(Main, :DBN)
        @test DBN isa Module
    end
    
    @testset "All exports are properly defined" begin
        # Check each exported symbol
        exports = [
            # Core types
            :DBNDecoder, :DBNEncoder, :read_dbn, :write_dbn,
            :Metadata, :DBNHeader, :RecordHeader, :DBNTimestamp,
            # Message types
            :MBOMsg, :TradeMsg, :MBP1Msg, :MBP10Msg, :OHLCVMsg,
            :StatusMsg, :ImbalanceMsg, :StatMsg,
            :ErrorMsg, :SymbolMappingMsg, :SystemMsg, :InstrumentDefMsg,
            # Streaming support
            :DBNStream, :DBNStreamWriter, :write_record!, :close_writer!,
            # Compression utilities
            :compress_dbn_file, :compress_daily_files,
            # Enums
            :Schema, :Compression, :Encoding, :SType, :RType, :Action, :Side, :InstrumentClass,
            # Utility functions
            :price_to_float, :float_to_price, :ts_to_datetime, :datetime_to_ts, :ts_to_date_time, :date_time_to_ts, :to_nanoseconds,
            # Constants
            :DBN_VERSION, :FIXED_PRICE_SCALE, :UNDEF_PRICE, :UNDEF_ORDER_SIZE, :UNDEF_TIMESTAMP,
            # Helper structs
            :BidAskPair, :VersionUpgradePolicy, :DatasetCondition,
            # Low-level functions
            :write_header, :read_header!, :write_record, :read_record, :finalize_encoder
        ]
        
        for sym in exports
            @test isdefined(DBN, sym)
        end
    end
    
    @testset "All enums can be instantiated" begin
        # Test Schema enum
        @test Schema.MBO == Schema.T(0)
        @test Schema.MBP_1 == Schema.T(1)
        @test Schema.MBP_10 == Schema.T(2)
        @test Schema.TRADES == Schema.T(4)
        @test Schema.OHLCV_1S == Schema.T(5)
        @test Schema.DEFINITION == Schema.T(9)
        @test Schema.STATISTICS == Schema.T(10)
        @test Schema.STATUS == Schema.T(11)
        @test Schema.IMBALANCE == Schema.T(12)
        
        # Test Compression enum
        @test Compression.NONE == Compression.T(0)
        @test Compression.ZSTD == Compression.T(1)
        
        # Test Encoding enum
        @test Encoding.DBN == Encoding.T(0)
        @test Encoding.CSV == Encoding.T(1)
        @test Encoding.JSON == Encoding.T(2)
        
        # Test SType enum
        @test SType.INSTRUMENT_ID == SType.T(0)
        @test SType.RAW_SYMBOL == SType.T(1)
        @test SType.CONTINUOUS == SType.T(2)
        @test SType.PARENT == SType.T(3)
        
        # Test RType enum (DBN v3 values)
        @test RType.MBP_0_MSG == RType.T(0x00)        # Trades (book depth 0)
        @test RType.MBP_1_MSG == RType.T(0x01)        # TBBO/MBP-1 (book depth 1)
        @test RType.MBP_10_MSG == RType.T(0x0A)       # MBP-10 (book depth 10)
        @test RType.STATUS_MSG == RType.T(0x12)       # Exchange status record
        @test RType.INSTRUMENT_DEF_MSG == RType.T(0x13)  # Instrument definition record
        @test RType.IMBALANCE_MSG == RType.T(0x14)    # Order imbalance record
        @test RType.ERROR_MSG == RType.T(0x15)        # Error record from live gateway
        @test RType.SYMBOL_MAPPING_MSG == RType.T(0x16)  # Symbol mapping record from live gateway
        @test RType.SYSTEM_MSG == RType.T(0x17)       # Non-error record from live gateway
        @test RType.STAT_MSG == RType.T(0x18)         # Statistics record from publisher
        @test RType.OHLCV_1S_MSG == RType.T(0x20)     # OHLCV at 1-second cadence
        @test RType.OHLCV_1M_MSG == RType.T(0x21)     # OHLCV at 1-minute cadence
        @test RType.OHLCV_1H_MSG == RType.T(0x22)     # OHLCV at hourly cadence
        @test RType.OHLCV_1D_MSG == RType.T(0x23)     # OHLCV at daily cadence
        @test RType.MBO_MSG == RType.T(0xA0)          # Market-by-order record
        @test RType.CMBP_1_MSG == RType.T(0xB1)       # Consolidated market-by-price with book depth 1
        @test RType.CBBO_1S_MSG == RType.T(0xC0)      # Consolidated market-by-price with book depth 1 at 1-second cadence
        @test RType.CBBO_1M_MSG == RType.T(0xC1)      # Consolidated market-by-price with book depth 1 at 1-minute cadence
        @test RType.TCBBO_MSG == RType.T(0xC2)        # Consolidated market-by-price with book depth 1 (trades only)
        @test RType.BBO_1S_MSG == RType.T(0xC3)       # Market-by-price with book depth 1 at 1-second cadence
        @test RType.BBO_1M_MSG == RType.T(0xC4)       # Market-by-price with book depth 1 at 1-minute cadence
        
        # Test Action enum
        @test Action.ADD == Action.T(UInt8('A'))
        @test Action.CANCEL == Action.T(UInt8('C'))
        @test Action.MODIFY == Action.T(UInt8('M'))
        @test Action.TRADE == Action.T(UInt8('T'))
        @test Action.FILL == Action.T(UInt8('F'))
        @test Action.CLEAR == Action.T(UInt8('R'))
        
        # Test Side enum
        @test Side.ASK == Side.T(UInt8('A'))
        @test Side.BID == Side.T(UInt8('B'))
        @test Side.NONE == Side.T(UInt8('N'))
        
        # Test InstrumentClass enum
        @test InstrumentClass.STOCK == InstrumentClass.T(UInt8('K'))
        @test InstrumentClass.OPTION == InstrumentClass.T(UInt8('O'))
        @test InstrumentClass.FUTURE == InstrumentClass.T(UInt8('F'))
        @test InstrumentClass.FX == InstrumentClass.T(UInt8('X'))
        @test InstrumentClass.BOND == InstrumentClass.T(UInt8('B'))
    end
    
    @testset "Constants are defined" begin
        @test DBN_VERSION == 3
        @test FIXED_PRICE_SCALE == Int32(1_000_000_000)
        @test UNDEF_PRICE == typemax(Int64)
        @test UNDEF_ORDER_SIZE == typemax(UInt32)
        @test UNDEF_TIMESTAMP == typemax(Int64)
    end
    
end