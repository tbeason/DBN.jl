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
                rm(corrupted_file, force=true)
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
                rm(truncated_file, force=true)
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
                rm(invalid_version_file, force=true)
            end
        end
        
        @testset "Corrupted record data" begin
            # Create a file with valid header but corrupted record
            corrupted_record_file = tempname() * ".dbn"
            try
                # First create a valid file
                metadata = Metadata(
                    UInt8(3),                    # version
                    "TEST",                      # dataset
                    Schema.TRADES,                  # schema
                    1000000000,                  # start_ts
                    2000000000,                  # end_ts
                    UInt64(0),                   # limit
                    SType.RAW_SYMBOL,              # stype_in
                    SType.INSTRUMENT_ID,           # stype_out
                    false,                       # ts_out
                    String[],                    # symbols
                    String[],                    # partial
                    String[],                    # not_found
                    Tuple{String,String,Int64,Int64}[]  # mappings
                )
                
                encoder = DBNEncoder(corrupted_record_file, metadata)
                close_encoder!(encoder)
                
                # Now corrupt the file by appending invalid record data
                open(corrupted_record_file, "a") do io
                    # Write a record header with invalid size
                    header = RecordHeader(
                        length=999999,  # Impossibly large
                        rtype=RType.MBP_0_MSG,
                        publisher_id=1,
                        instrument_id=100,
                        ts_event=1000000000
                    )
                    write(io, header)
                    # Don't write the actual record data
                end
                
                # Try to read the corrupted file
                @test_throws Exception collect(DBNStream(corrupted_record_file))
            finally
                rm(corrupted_record_file, force=true)
            end
        end
        
        @testset "Invalid enum values" begin
            # Test that invalid enum values are handled gracefully
            invalid_enum_file = tempname() * ".dbn"
            try
                metadata = Metadata(
                    UInt8(3),                    # version
                    "TEST",                      # dataset
                    Schema.TRADES,                  # schema
                    1000000000,                  # start_ts
                    2000000000,                  # end_ts
                    UInt64(0),                   # limit
                    SType.RAW_SYMBOL,              # stype_in
                    SType.INSTRUMENT_ID,           # stype_out
                    false,                       # ts_out
                    String[],                    # symbols
                    String[],                    # partial
                    String[],                    # not_found
                    Tuple{String,String,Int64,Int64}[]  # mappings
                )
                
                encoder = DBNEncoder(invalid_enum_file, metadata)
                
                # Create a trade with invalid action value
                trade = TradeMsg(
                    hd=RecordHeader(
                        length=sizeof(TradeMsg),
                        rtype=RType.MBP_0_MSG,
                        publisher_id=1,
                        instrument_id=100,
                        ts_event=1500000000
                    ),
                    price=100000000,
                    size=100,
                    action=reinterpret(Action.T, 0xFF),  # Invalid action
                    side=Side.ASK,
                    flags=0,
                    depth=0,
                    ts_recv=1500000000,
                    ts_in_delta=0,
                    sequence=1,
                    _reserved=zeros(UInt8, 4)
                )
                
                write_record(encoder, trade)
                close_encoder!(encoder)
                
                # Should be able to read despite invalid enum
                records = read_dbn(invalid_enum_file)
                @test length(records) == 1
                @test records[1] isa TradeMsg
            finally
                rm(invalid_enum_file, force=true)
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
                rm(empty_file, force=true)
            end
        end
        
        @testset "File with only header (no records)" begin
            header_only_file = tempname() * ".dbn"
            try
                metadata = Metadata(
                    UInt8(3),                    # version
                    "TEST",                      # dataset
                    Schema.TRADES,                  # schema
                    1000000000,                  # start_ts
                    2000000000,                  # end_ts
                    UInt64(0),                   # limit
                    SType.RAW_SYMBOL,              # stype_in
                    SType.INSTRUMENT_ID,           # stype_out
                    false,                       # ts_out
                    String[],                    # symbols
                    String[],                    # partial
                    String[],                    # not_found
                    Tuple{String,String,Int64,Int64}[]  # mappings
                )
                
                encoder = DBNEncoder(header_only_file, metadata)
                close_encoder!(encoder)
                
                # Should be able to read header-only file
                records = read_dbn(header_only_file)
                @test isempty(records)
                
                # Streaming should also work
                stream_records = collect(DBNStream(header_only_file))
                @test isempty(stream_records)
            finally
                rm(header_only_file, force=true)
            end
        end
        
        @testset "Compressed empty file" begin
            empty_compressed = tempname() * ".dbn.zst"
            try
                metadata = Metadata(
                    UInt8(3),                    # version
                    "TEST",                      # dataset
                    Schema.TRADES,                  # schema
                    1000000000,                  # start_ts
                    2000000000,                  # end_ts
                    UInt64(0),                   # limit
                    SType.RAW_SYMBOL,              # stype_in
                    SType.INSTRUMENT_ID,           # stype_out
                    false,                       # ts_out
                    String[],                    # symbols
                    String[],                    # partial
                    String[],                    # not_found
                    Tuple{String,String,Int64,Int64}[]  # mappings
                )
                
                encoder = DBNEncoder(empty_compressed, metadata, compressed=true)
                close_encoder!(encoder)
                
                # Should handle compressed empty file
                records = read_dbn(empty_compressed)
                @test isempty(records)
            finally
                rm(empty_compressed, force=true)
            end
        end
    end
    
    @testset "Boundary Values" begin
        @testset "Timestamp boundaries" begin
            boundary_file = tempname() * ".dbn"
            try
                metadata = Metadata(
                    UInt8(3),                    # version
                    "TEST",                      # dataset
                    Schema.TRADES,                  # schema
                    0,                           # start_ts (min timestamp)
                    typemax(Int64),              # end_ts (max timestamp)
                    UInt64(0),                   # limit
                    SType.RAW_SYMBOL,              # stype_in
                    SType.INSTRUMENT_ID,           # stype_out
                    false,                       # ts_out
                    String[],                    # symbols
                    String[],                    # partial
                    String[],                    # not_found
                    Tuple{String,String,Int64,Int64}[]  # mappings
                )
                
                encoder = DBNEncoder(boundary_file, metadata)
                
                # Test with various timestamp boundaries
                timestamps = [
                    0,  # Unix epoch
                    typemax(Int64),  # Max int64
                    1_000_000_000_000_000_000,  # 1 second in nanoseconds
                    UNDEF_TIMESTAMP  # Undefined timestamp
                ]
                
                for (i, ts) in enumerate(timestamps)
                    trade = TradeMsg(
                        hd=RecordHeader(
                            length=sizeof(TradeMsg),
                            rtype=RType.MBP_0_MSG,
                            publisher_id=1,
                            instrument_id=UInt32(i),
                            ts_event=ts
                        ),
                        price=100000000,
                        size=100,
                        action=Action.ADD,
                        side=Side.BID_SIDE,
                        flags=0,
                        depth=0,
                        ts_recv=ts,
                        ts_in_delta=0,
                        sequence=UInt64(i),
                        _reserved=zeros(UInt8, 4)
                    )
                    write_record(encoder, trade)
                end
                
                close_encoder!(encoder)
                
                # Read back and verify
                records = read_dbn(boundary_file)
                @test length(records) == length(timestamps)
                
                for (i, record) in enumerate(records)
                    @test record.hd.ts_event == timestamps[i]
                    @test record.ts_recv == timestamps[i]
                end
            finally
                rm(boundary_file, force=true)
            end
        end
        
        @testset "Price boundaries" begin
            price_boundary_file = tempname() * ".dbn"
            try
                metadata = Metadata(
                    UInt8(3),                    # version
                    "TEST",                      # dataset
                    Schema.TRADES,                  # schema
                    1000000000,                  # start_ts
                    2000000000,                  # end_ts
                    UInt64(0),                   # limit
                    SType.RAW_SYMBOL,              # stype_in
                    SType.INSTRUMENT_ID,           # stype_out
                    false,                       # ts_out
                    String[],                    # symbols
                    String[],                    # partial
                    String[],                    # not_found
                    Tuple{String,String,Int64,Int64}[]  # mappings
                )
                
                encoder = DBNEncoder(price_boundary_file, metadata)
                
                # Test with various price boundaries
                prices = [
                    0,  # Zero price
                    1,  # Minimum non-zero
                    typemax(Int64),  # Max price
                    UNDEF_PRICE,  # Undefined price
                    -1000000000  # Negative price (valid in some markets)
                ]
                
                for (i, price) in enumerate(prices)
                    trade = TradeMsg(
                        hd=RecordHeader(
                            length=sizeof(TradeMsg),
                            rtype=RType.MBP_0_MSG,
                            publisher_id=1,
                            instrument_id=UInt32(i),
                            ts_event=1500000000
                        ),
                        price=price,
                        size=100,
                        action=Action.ADD,
                        side=Side.BID_SIDE,
                        flags=0,
                        depth=0,
                        ts_recv=1500000000,
                        ts_in_delta=0,
                        sequence=UInt64(i),
                        _reserved=zeros(UInt8, 4)
                    )
                    write_record(encoder, trade)
                end
                
                close_encoder!(encoder)
                
                # Read back and verify
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
                rm(price_boundary_file, force=true)
            end
        end
        
        @testset "Size and quantity boundaries" begin
            size_boundary_file = tempname() * ".dbn"
            try
                metadata = Metadata(
                    UInt8(3),                    # version
                    "TEST",                      # dataset
                    Schema.MBO,                     # schema
                    1000000000,                  # start_ts
                    2000000000,                  # end_ts
                    UInt64(0),                   # limit
                    SType.RAW_SYMBOL,              # stype_in
                    SType.INSTRUMENT_ID,           # stype_out
                    false,                       # ts_out
                    String[],                    # symbols
                    String[],                    # partial
                    String[],                    # not_found
                    Tuple{String,String,Int64,Int64}[]  # mappings
                )
                
                encoder = DBNEncoder(size_boundary_file, metadata)
                
                # Test with various size boundaries
                sizes = [
                    0,  # Zero size
                    1,  # Minimum size
                    typemax(UInt32),  # Max uint32
                    typemax(UInt32) - 1  # Near max
                ]
                
                for (i, size) in enumerate(sizes)
                    mbo = MBOMsg(
                        hd=RecordHeader(
                            length=sizeof(MBOMsg),
                            rtype=RType.MBO_MSG,
                            publisher_id=1,
                            instrument_id=UInt32(i),
                            ts_event=1500000000
                        ),
                        order_id=UInt64(i),
                        price=100000000,
                        size=size,
                        flags=0,
                        channel_id=0,
                        action=Action.ADD,
                        side=Side.BID_SIDE,
                        ts_recv=1500000000,
                        ts_in_delta=0,
                        sequence=UInt64(i)
                    )
                    write_record(encoder, mbo)
                end
                
                close_encoder!(encoder)
                
                # Read back and verify
                records = read_dbn(size_boundary_file)
                @test length(records) == length(sizes)
                
                for (i, record) in enumerate(records)
                    @test record.size == sizes[i]
                end
            finally
                rm(size_boundary_file, force=true)
            end
        end
        
        @testset "String field boundaries" begin
            string_boundary_file = tempname() * ".dbn"
            try
                metadata = Metadata(
                    UInt8(3),                    # version
                    "TEST",                      # dataset
                    Schema.DEFINITION,              # schema
                    1000000000,                  # start_ts
                    2000000000,                  # end_ts
                    UInt64(0),                   # limit
                    SType.RAW_SYMBOL,              # stype_in
                    SType.INSTRUMENT_ID,           # stype_out
                    false,                       # ts_out
                    String[],                    # symbols
                    String[],                    # partial
                    String[],                    # not_found
                    Tuple{String,String,Int64,Int64}[]  # mappings
                )
                
                encoder = DBNEncoder(string_boundary_file, metadata)
                
                # Test with various string scenarios
                test_strings = [
                    "",  # Empty string
                    "A",  # Single character
                    "A" ^ 21,  # Max length for many fields (21 chars)
                    "A" ^ 48,  # Max length for some fields (48 chars)
                    "💹📊📈",  # Unicode characters
                    "\x00\x01\x02",  # Binary data
                ]
                
                for (i, test_str) in enumerate(test_strings)
                    # Pad or truncate strings to fit field sizes
                    raw_symbol = rpad(test_str[1:min(length(test_str), 21)], 21, '\0')
                    currency = rpad("USD", 4, '\0')
                    
                    idef = InstrumentDefMsg(
                        hd=RecordHeader(
                            length=sizeof(InstrumentDefMsg),
                            rtype=RType.INSTRUMENT_DEF_MSG,
                            publisher_id=1,
                            instrument_id=UInt32(i),
                            ts_event=1500000000
                        ),
                        ts_recv=1500000000,
                        min_price_increment=1000,
                        display_factor=1000000000,
                        expiration=0,
                        activation=0,
                        high_limit_price=UNDEF_PRICE,
                        low_limit_price=UNDEF_PRICE,
                        max_price_variation=UNDEF_PRICE,
                        trading_reference_price=UNDEF_PRICE,
                        unit_of_measure_qty=1000000000,
                        min_price_increment_amount=1000,
                        price_ratio=1000000000,
                        inst_class=0,
                        match_algorithm=0,
                        md_security_trading_status=2,
                        main_fraction=0,
                        price_display_format=0,
                        settle_price_type=0,
                        sub_fraction=0,
                        underlying_product=0,
                        security_update_action=Action.ADD,
                        maturity_month=0,
                        maturity_day=0,
                        maturity_week=0,
                        user_defined_instrument=TriState.FALSE,
                        contract_multiplier_unit=0,
                        flow_schedule_type=0,
                        tick_rule=0,
                        _reserved=zeros(UInt8, 10),
                        instrument_class=0,
                        strike_price=UNDEF_PRICE,
                        transact_time=1500000000,
                        related_security_id=0,
                        _reserved2=zeros(UInt8, 28),
                        raw_symbol=raw_symbol,
                        _reserved3=zeros(UInt8, 8),
                        d_v_01=0,
                        spread_ratio=0.0,
                        currency=currency,
                        settl_currency=currency,
                        _reserved4=zeros(UInt8, 50),
                        legs=zeros(UInt8, sizeof(DBN.CFixedStr{1536}))
                    )
                    
                    write_record(encoder, idef)
                end
                
                close_encoder!(encoder)
                
                # Read back and verify
                records = read_dbn(string_boundary_file)
                @test length(records) == length(test_strings)
            finally
                rm(string_boundary_file, force=true)
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
                        Schema.TRADES,                  # schema
                        1000000000,                  # start_ts
                        2000000000,                  # end_ts
                        UInt64(0),                   # limit
                        SType.RAW_SYMBOL,              # stype_in
                        SType.INSTRUMENT_ID,           # stype_out
                        false,                       # ts_out
                        String[],                    # symbols
                        String[],                    # partial
                        String[],                    # not_found
                        Tuple{String,String,Int64,Int64}[]  # mappings
                    )
                    
                    # Should throw an error when trying to create encoder
                    try
                        @test_throws Exception DBNEncoder(readonly_file, metadata)
                    catch e
                        # Some systems might allow creation, so also check write_dbn
                        @test_throws Exception write_dbn(readonly_file, metadata, TradeMsg[])
                    end
                    break  # Only need one successful test
                end
            end
        end
        
        @testset "Write to existing read-only file" begin
            readonly_file = tempname() * ".dbn"
            try
                # Create a file and make it read-only
                touch(readonly_file)
                chmod(readonly_file, 0o444)  # Read-only
                
                metadata = Metadata(
                    UInt8(3),                    # version
                    "TEST",                      # dataset
                    Schema.TRADES,                  # schema
                    1000000000,                  # start_ts
                    2000000000,                  # end_ts
                    UInt64(0),                   # limit
                    SType.RAW_SYMBOL,              # stype_in
                    SType.INSTRUMENT_ID,           # stype_out
                    false,                       # ts_out
                    String[],                    # symbols
                    String[],                    # partial
                    String[],                    # not_found
                    Tuple{String,String,Int64,Int64}[]  # mappings
                )
                
                # Should fail to open for writing
                @test_throws Exception DBNEncoder(readonly_file, metadata)
            finally
                chmod(readonly_file, 0o644)  # Restore permissions
                rm(readonly_file, force=true)
            end
        end
    end
    
    @testset "Mixed Record Types" begin
        mixed_file = tempname() * ".dbn"
        try
            metadata = Metadata(
                UInt8(3),                    # version
                "TEST",                      # dataset
                Schema.MBO,                     # schema
                1000000000,                  # start_ts
                2000000000,                  # end_ts
                UInt64(0),                   # limit
                SType.RAW_SYMBOL,              # stype_in
                SType.INSTRUMENT_ID,           # stype_out
                false,                       # ts_out
                String[],                    # symbols
                String[],                    # partial
                String[],                    # not_found
                Tuple{String,String,Int64,Int64}[]  # mappings
            )
            
            encoder = DBNEncoder(mixed_file, metadata)
            
            # Write different record types
            # 1. MBO message
            mbo = MBOMsg(
                hd=RecordHeader(
                    length=sizeof(MBOMsg),
                    rtype=RType.MBO_MSG,
                    publisher_id=1,
                    instrument_id=100,
                    ts_event=1100000000
                ),
                order_id=1001,
                price=100000000,
                size=100,
                flags=0,
                channel_id=0,
                action=Action.ADD,
                side=Side.BID_SIDE,
                ts_recv=1100000000,
                ts_in_delta=0,
                sequence=1
            )
            write_record(encoder, mbo)
            
            # 2. Trade message
            trade = TradeMsg(
                hd=RecordHeader(
                    length=sizeof(TradeMsg),
                    rtype=RType.MBP_0_MSG,
                    publisher_id=1,
                    instrument_id=100,
                    ts_event=1200000000
                ),
                price=101000000,
                size=50,
                action=Action.TRADE,
                side=Side.ASK_SIDE,
                flags=0,
                depth=0,
                ts_recv=1200000000,
                ts_in_delta=0,
                sequence=2,
                _reserved=zeros(UInt8, 4)
            )
            write_record(encoder, trade)
            
            # 3. Status message
            status = StatusMsg(
                hd=RecordHeader(
                    length=sizeof(StatusMsg),
                    rtype=RType.STATUS_MSG,
                    publisher_id=1,
                    instrument_id=100,
                    ts_event=1300000000
                ),
                ts_recv=1300000000,
                action=Action.HALT,
                reason=1,
                trading_event=2,
                is_trading=TriState.FALSE,
                is_quoting=TriState.FALSE,
                is_short_sell_restricted=TriState.FALSE,
                _reserved=zeros(UInt8, 4)
            )
            write_record(encoder, status)
            
            # 4. Error message
            err_text = "Test error message"
            err_length = UInt8(16 + length(err_text) + 1)
            error_msg = ErrorMsg(
                RecordHeader(err_length, RType.ERROR_MSG, UInt16(0), UInt32(0), 1400000000),
                err_text
            )
            write_record(encoder, error_msg)
            
            # 5. System message
            sys_text = "System notification"
            sys_length = UInt8(16 + length(sys_text) + 1)
            system_msg = SystemMsg(
                RecordHeader(sys_length, RType.SYSTEM_MSG, UInt16(0), UInt32(0), 1500000000),
                sys_text
            )
            write_record(encoder, system_msg)
            
            close_encoder!(encoder)
            
            # Read back and verify mixed types
            records = read_dbn(mixed_file)
            @test length(records) == 5
            
            # Check record types
            @test records[1] isa MBOMsg
            @test records[2] isa TradeMsg
            @test records[3] isa StatusMsg
            @test records[4] isa ErrorMsg
            @test records[5] isa SystemMsg
            
            # Verify timestamps are in order
            @test records[1].hd.ts_event < records[2].hd.ts_event
            @test records[2].hd.ts_event < records[3].hd.ts_event
            @test records[3].hd.ts_event < records[4].hd.ts_event
            @test records[4].hd.ts_event < records[5].hd.ts_event
            
            # Test streaming with mixed types
            stream_records = collect(DBNStream(mixed_file))
            @test length(stream_records) == 5
            @test all(i -> typeof(stream_records[i]) == typeof(records[i]), 1:5)
        finally
            rm(mixed_file, force=true)
        end
    end
    
    @testset "Very Large Files" begin
        @testset "File with many records" begin
            large_file = tempname() * ".dbn"
            try
                metadata = Metadata(
                    UInt8(3),                    # version
                    "TEST",                      # dataset
                    Schema.TRADES,                  # schema
                    1000000000,                  # start_ts
                    2000000000,                  # end_ts
                    UInt64(0),                   # limit
                    SType.RAW_SYMBOL,              # stype_in
                    SType.INSTRUMENT_ID,           # stype_out
                    false,                       # ts_out
                    String[],                    # symbols
                    String[],                    # partial
                    String[],                    # not_found
                    Tuple{String,String,Int64,Int64}[]  # mappings
                )
                
                encoder = DBNEncoder(large_file, metadata)
                
                # Write a large number of records
                num_records = 10000
                for i in 1:num_records
                    trade = TradeMsg(
                        hd=RecordHeader(
                            length=sizeof(TradeMsg),
                            rtype=RType.MBP_0_MSG,
                            publisher_id=1,
                            instrument_id=UInt32(i % 100 + 1),
                            ts_event=1000000000 + i * 1000
                        ),
                        price=100000000 + i,
                        size=UInt32(i % 1000 + 1),
                        action=Action.TRADE,
                        side=i % 2 == 0 ? Side.BID_SIDE : Side.ASK_SIDE,
                        flags=0,
                        depth=0,
                        ts_recv=1000000000 + i * 1000,
                        ts_in_delta=0,
                        sequence=UInt64(i),
                        _reserved=zeros(UInt8, 4)
                    )
                    write_record(encoder, trade)
                end
                
                close_encoder!(encoder)
                
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
                expected_size = DBN.DBN_HEADER_SIZE + num_records * sizeof(TradeMsg)
                @test file_size ≈ expected_size atol=1000
            finally
                rm(large_file, force=true)
            end
        end
        
        @testset "Compressed large file" begin
            large_compressed = tempname() * ".dbn.zst"
            try
                metadata = Metadata(
                    UInt8(3),                    # version
                    "TEST",                      # dataset
                    Schema.TRADES,                  # schema
                    1000000000,                  # start_ts
                    2000000000,                  # end_ts
                    UInt64(0),                   # limit
                    SType.RAW_SYMBOL,              # stype_in
                    SType.INSTRUMENT_ID,           # stype_out
                    false,                       # ts_out
                    String[],                    # symbols
                    String[],                    # partial
                    String[],                    # not_found
                    Tuple{String,String,Int64,Int64}[]  # mappings
                )
                
                encoder = DBNEncoder(large_compressed, metadata, compressed=true)
                
                # Write many records with repetitive data (compresses well)
                num_records = 5000
                for i in 1:num_records
                    trade = TradeMsg(
                        hd=RecordHeader(
                            length=sizeof(TradeMsg),
                            rtype=RType.MBP_0_MSG,
                            publisher_id=1,
                            instrument_id=1,  # Same instrument
                            ts_event=1000000000 + i * 1000
                        ),
                        price=100000000,  # Same price
                        size=100,  # Same size
                        action=Action.TRADE,
                        side=Side.BID_SIDE,
                        flags=0,
                        depth=0,
                        ts_recv=1000000000 + i * 1000,
                        ts_in_delta=0,
                        sequence=UInt64(i),
                        _reserved=zeros(UInt8, 4)
                    )
                    write_record(encoder, trade)
                end
                
                close_encoder!(encoder)
                
                # Compressed file should be much smaller
                compressed_size = filesize(large_compressed)
                uncompressed_size = DBN.DBN_HEADER_SIZE + num_records * sizeof(TradeMsg)
                compression_ratio = compressed_size / uncompressed_size
                @test compression_ratio < 0.5  # Should achieve >50% compression
                
                # Verify can still read all records
                count = 0
                for record in DBNStream(large_compressed)
                    count += 1
                    @test record isa TradeMsg
                end
                @test count == num_records
            finally
                rm(large_compressed, force=true)
            end
        end
    end
    
    @testset "Special Edge Cases" begin
        @testset "File path edge cases" begin
            # Test with special characters in filename
            special_chars_file = tempname() * "_test file with spaces.dbn"
            try
                metadata = Metadata(
                    UInt8(3),                    # version
                    "TEST",                      # dataset
                    Schema.TRADES,                  # schema
                    1000000000,                  # start_ts
                    2000000000,                  # end_ts
                    UInt64(0),                   # limit
                    SType.RAW_SYMBOL,              # stype_in
                    SType.INSTRUMENT_ID,           # stype_out
                    false,                       # ts_out
                    String[],                    # symbols
                    String[],                    # partial
                    String[],                    # not_found
                    Tuple{String,String,Int64,Int64}[]  # mappings
                )
                
                # Should handle filenames with spaces
                write_dbn(special_chars_file, metadata, TradeMsg[])
                @test isfile(special_chars_file)
                
                records = read_dbn(special_chars_file)
                @test isempty(records)
            finally
                rm(special_chars_file, force=true)
            end
        end
        
        @testset "Concurrent access" begin
            # Test reading while writing (should fail gracefully)
            concurrent_file = tempname() * ".dbn"
            try
                metadata = Metadata(
                    UInt8(3),                    # version
                    "TEST",                      # dataset
                    Schema.TRADES,                  # schema
                    1000000000,                  # start_ts
                    2000000000,                  # end_ts
                    UInt64(0),                   # limit
                    SType.RAW_SYMBOL,              # stype_in
                    SType.INSTRUMENT_ID,           # stype_out
                    false,                       # ts_out
                    String[],                    # symbols
                    String[],                    # partial
                    String[],                    # not_found
                    Tuple{String,String,Int64,Int64}[]  # mappings
                )
                
                # Start writing
                writer = DBNStreamWriter(concurrent_file, "TEST", Schema.TRADES)
                
                # Try to read while writer is open (might fail or read partial data)
                try
                    decoder = DBNDecoder(concurrent_file)
                    # Might succeed but with incomplete data
                    close(decoder)
                catch e
                    # Expected - file might be locked or incomplete
                    @test e isa Exception
                end
                
                # Close writer
                close_writer!(writer)
                
                # Now should be able to read
                records = read_dbn(concurrent_file)
                @test records !== nothing
            finally
                rm(concurrent_file, force=true)
            end
        end
        
        @testset "Memory-mapped file handling" begin
            # Test with a file that's already memory-mapped
            mmap_file = tempname() * ".dbn"
            try
                # Create a valid DBN file
                metadata = Metadata(
                    UInt8(3),                    # version
                    "TEST",                      # dataset
                    Schema.TRADES,                  # schema
                    1000000000,                  # start_ts
                    2000000000,                  # end_ts
                    UInt64(0),                   # limit
                    SType.RAW_SYMBOL,              # stype_in
                    SType.INSTRUMENT_ID,           # stype_out
                    false,                       # ts_out
                    String[],                    # symbols
                    String[],                    # partial
                    String[],                    # not_found
                    Tuple{String,String,Int64,Int64}[]  # mappings
                )
                
                trade = TradeMsg(
                    hd=RecordHeader(
                        length=sizeof(TradeMsg),
                        rtype=RType.MBP_0_MSG,
                        publisher_id=1,
                        instrument_id=100,
                        ts_event=1500000000
                    ),
                    price=100000000,
                    size=100,
                    action=Action.TRADE,
                    side=Side.BID_SIDE,
                    flags=0,
                    depth=0,
                    ts_recv=1500000000,
                    ts_in_delta=0,
                    sequence=1,
                    _reserved=zeros(UInt8, 4)
                )
                
                write_dbn(mmap_file, metadata, [trade])
                
                # Multiple decoders should work
                decoder1 = DBNDecoder(mmap_file)
                decoder2 = DBNDecoder(mmap_file)
                
                @test decoder1.metadata.version == 3
                @test decoder2.metadata.version == 3
                
                close(decoder1)
                close(decoder2)
            finally
                rm(mmap_file, force=true)
            end
        end
    end
end