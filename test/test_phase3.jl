# Phase 3: Utility Function Testing

using Dates

@testset "Phase 3: Utility Function Testing" begin
    
    @testset "Price conversion functions" begin
        @testset "price_to_float" begin
            # Test normal prices
            @test price_to_float(10050000000) ≈ 10.05
            @test price_to_float(1000000000) ≈ 1.0
            @test price_to_float(500000000) ≈ 0.5
            @test price_to_float(0) ≈ 0.0
            @test price_to_float(-1000000000) ≈ -1.0
            
            # Test with custom scale
            @test price_to_float(10050, Int32(1000)) ≈ 10.05
            @test price_to_float(1000, Int32(100)) ≈ 10.0
            
            # Test with UNDEF_PRICE
            @test isnan(price_to_float(UNDEF_PRICE))
            
            # Test edge cases (avoid typemax since it's UNDEF_PRICE)
            large_price = typemax(Int64) ÷ 2
            @test price_to_float(large_price, FIXED_PRICE_SCALE) ≈ Float64(large_price) / Float64(FIXED_PRICE_SCALE)
            @test price_to_float(typemin(Int64), FIXED_PRICE_SCALE) ≈ Float64(typemin(Int64)) / Float64(FIXED_PRICE_SCALE)
        end
        
        @testset "float_to_price" begin
            # Test normal values
            @test float_to_price(10.05) == 10050000000
            @test float_to_price(1.0) == 1000000000
            @test float_to_price(0.5) == 500000000
            @test float_to_price(0.0) == 0
            @test float_to_price(-1.0) == -1000000000
            
            # Test with custom scale
            @test float_to_price(10.05, Int32(1000)) == 10050
            @test float_to_price(10.0, Int32(100)) == 1000
            
            # Test with NaN and Inf
            @test float_to_price(NaN) == UNDEF_PRICE
            @test float_to_price(Inf) == UNDEF_PRICE
            @test float_to_price(-Inf) == UNDEF_PRICE
            
            # Test rounding
            @test float_to_price(10.0546) == 10054600000
            @test float_to_price(10.0545) == 10054500000
        end
        
        @testset "price_to_float and float_to_price round-trip" begin
            test_prices = [0, 1000000000, 10050000000, 999999999, -1000000000]
            for price in test_prices
                @test float_to_price(price_to_float(price)) == price
            end
            
            test_floats = [0.0, 1.0, 10.05, 0.999999999, -1.0]
            for value in test_floats
                @test price_to_float(float_to_price(value)) ≈ value
            end
        end
    end
    
    @testset "Timestamp conversion functions" begin
        @testset "DBNTimestamp constructor" begin
            # Test normal timestamp
            ts = DBNTimestamp(1640995200123456789)
            @test ts.seconds == 1640995200
            @test ts.nanoseconds == 123456789
            
            # Test with UNDEF_TIMESTAMP
            ts_undef = DBNTimestamp(UNDEF_TIMESTAMP)
            @test ts_undef.seconds == UNDEF_TIMESTAMP
            @test ts_undef.nanoseconds == 0
            
            # Test zero timestamp
            ts_zero = DBNTimestamp(0)
            @test ts_zero.seconds == 0
            @test ts_zero.nanoseconds == 0
            
            # Test edge cases
            ts_max_ns = DBNTimestamp(999999999)
            @test ts_max_ns.seconds == 0
            @test ts_max_ns.nanoseconds == 999999999
            
            ts_one_sec = DBNTimestamp(1000000000)
            @test ts_one_sec.seconds == 1
            @test ts_one_sec.nanoseconds == 0
        end
        
        @testset "to_nanoseconds" begin
            # Test normal timestamp
            ts = DBNTimestamp(1640995200, 123456789)
            @test to_nanoseconds(ts) == 1640995200123456789
            
            # Test with UNDEF_TIMESTAMP
            ts_undef = DBNTimestamp(UNDEF_TIMESTAMP, 0)
            @test to_nanoseconds(ts_undef) == UNDEF_TIMESTAMP
            
            # Test zero values
            ts_zero = DBNTimestamp(0, 0)
            @test to_nanoseconds(ts_zero) == 0
            
            # Test maximum nanoseconds
            ts_max = DBNTimestamp(1640995200, 999999999)
            @test to_nanoseconds(ts_max) == 1640995200999999999
        end
        
        @testset "DBNTimestamp and to_nanoseconds round-trip" begin
            test_timestamps = [
                0,
                1000000000,  # 1 second
                1640995200123456789,  # Typical timestamp
                999999999,  # Max nanoseconds in first second
                typemax(Int64) ÷ 2  # Large but safe value
            ]
            
            for ts_ns in test_timestamps
                if ts_ns != UNDEF_TIMESTAMP
                    @test to_nanoseconds(DBNTimestamp(ts_ns)) == ts_ns
                end
            end
        end
        
        @testset "ts_to_datetime" begin
            # Test normal timestamp
            result = ts_to_datetime(1640995200123456789)
            @test result !== nothing
            @test result.datetime isa DateTime
            @test result.nanoseconds == 123456789
            
            # Test with UNDEF_TIMESTAMP
            @test ts_to_datetime(UNDEF_TIMESTAMP) === nothing
            
            # Test zero timestamp (Unix epoch)
            result_epoch = ts_to_datetime(0)
            @test result_epoch !== nothing
            @test result_epoch.datetime == DateTime(1970, 1, 1, 0, 0, 0)
            @test result_epoch.nanoseconds == 0
            
            # Test timestamp with only seconds
            result_sec = ts_to_datetime(1640995200000000000)
            @test result_sec !== nothing
            @test result_sec.nanoseconds == 0
        end
        
        @testset "datetime_to_ts" begin
            # Test normal datetime
            dt = DateTime(2022, 1, 1, 12, 0, 0)
            ts = datetime_to_ts(dt, Int32(0))
            @test ts > 0
            
            # Test with nanoseconds
            ts_with_ns = datetime_to_ts(dt, Int32(123456789))
            @test ts_with_ns == ts + 123456789
            
            # Test epoch
            epoch_dt = DateTime(1970, 1, 1, 0, 0, 0)
            epoch_ts = datetime_to_ts(epoch_dt, Int32(0))
            @test epoch_ts == 0
        end
        
        @testset "ts_to_date_time" begin
            # Test normal timestamp
            result = ts_to_date_time(1640995200123456789)
            @test result !== nothing
            @test result.date isa Date
            @test result.time isa Dates.Time
            @test result.timestamp isa DBNTimestamp
            
            # Test with UNDEF_TIMESTAMP
            @test ts_to_date_time(UNDEF_TIMESTAMP) === nothing
            
            # Test epoch
            result_epoch = ts_to_date_time(0)
            @test result_epoch !== nothing
            @test result_epoch.date == Date(1970, 1, 1)
            @test result_epoch.time == Dates.Time(0, 0, 0)
        end
        
        @testset "date_time_to_ts" begin
            # Test normal date and time
            date = Date(2022, 1, 1)
            time = Dates.Time(12, 30, 45, 123, 456, 789)
            ts = date_time_to_ts(date, time)
            @test ts > 0
            
            # Test epoch
            epoch_date = Date(1970, 1, 1)
            epoch_time = Dates.Time(0, 0, 0)
            epoch_ts = date_time_to_ts(epoch_date, epoch_time)
            @test epoch_ts == 0
            
            # Test midnight
            midnight = Dates.Time(0, 0, 0)
            ts_midnight = date_time_to_ts(date, midnight)
            @test ts_midnight % (24 * 60 * 60 * 1_000_000_000) == 0
        end
        
        @testset "Timestamp conversion round-trips" begin
            # Test datetime round-trip
            original_ts = 1640995200123456789
            result = ts_to_datetime(original_ts)
            if result !== nothing
                # Note: We lose nanosecond precision in DateTime, so we add it back
                reconstructed_ts = datetime_to_ts(result.datetime, result.nanoseconds)
                @test reconstructed_ts == original_ts
            end
            
            # Test date_time round-trip
            original_ts2 = 1640995200123456789
            result2 = ts_to_date_time(original_ts2)
            if result2 !== nothing
                reconstructed_ts2 = date_time_to_ts(result2.date, result2.time)
                @test reconstructed_ts2 == original_ts2
            end
        end
    end
    
    @testset "Constants validation" begin
        @test DBN_VERSION == 3
        @test FIXED_PRICE_SCALE == Int32(1_000_000_000)
        @test UNDEF_PRICE == typemax(Int64)
        @test UNDEF_ORDER_SIZE == typemax(UInt32)
        @test UNDEF_TIMESTAMP == typemax(Int64)
        
        # Test that constants are sensible
        @test FIXED_PRICE_SCALE > 0
        @test UNDEF_PRICE > 0
        @test UNDEF_ORDER_SIZE > 0
        @test UNDEF_TIMESTAMP > 0
    end
    
    @testset "Edge cases and boundary values" begin
        @testset "Price conversion edge cases" begin
            # Test very small values
            @test price_to_float(1) ≈ 1e-9
            @test float_to_price(1e-9) == 1
            
            # Test precision limits
            small_price = 1000000  # 0.001 dollars
            @test price_to_float(small_price) ≈ 0.001
            @test float_to_price(price_to_float(small_price)) == small_price
        end
        
        @testset "Timestamp edge cases" begin
            # Test large timestamps near type limits (but not max which is UNDEF)
            large_ts = typemax(Int64) ÷ 2
            dbn_ts = DBNTimestamp(large_ts)
            @test to_nanoseconds(dbn_ts) == large_ts
            
            # Test negative timestamps (before Unix epoch)
            negative_ts = -1000000000  # 1 second before epoch
            dbn_ts_neg = DBNTimestamp(negative_ts)
            @test to_nanoseconds(dbn_ts_neg) == negative_ts
        end
    end
end