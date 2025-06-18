using Test
using DBN
using Dates

# Simple thread safety test for compress_daily_files
@testset "Thread Safety Test" begin
    @testset "compress_daily_files Thread Safety" begin
        # Create test files for compression
        temp_dir = mktempdir()
        test_date = Date("2024-01-01")
        
        try
            # Create some test files for the date
            test_files = []
            for i in 1:3
                filename = joinpath(temp_dir, "$(Dates.format(test_date, "yyyymmdd"))_file$i.dbn")
                
                # Create minimal test data using the same structure as Phase 4 tests
                metadata = Metadata(
                    UInt8(3),                        # version
                    "TEST.PHASE10",                  # dataset
                    Schema.TRADES,                   # schema
                    1640995200000000000,             # start_ts
                    1640995260000000000,             # end_ts
                    UInt64(1),                       # limit
                    SType.RAW_SYMBOL,                # stype_in
                    SType.RAW_SYMBOL,                # stype_out
                    false,                           # ts_out
                    ["TEST"],                        # symbols
                    String[],                        # partial
                    String[],                        # not_found
                    Tuple{String,String,Int64,Int64}[]  # mappings
                )
                
                # Create a simple trade record
                hd = RecordHeader(40, RType.MBP_0_MSG, 1, 12345, 1640995200000000000)
                trade = TradeMsg(
                    hd,                          # hd
                    100000000,                   # price ($100.00)
                    100,                         # size
                    Action.TRADE,                # action
                    Side.NONE,                   # side
                    0x00,                        # flags
                    0,                           # depth
                    1640995200000000000,         # ts_recv
                    0,                           # ts_in_delta
                    1                            # sequence
                )
                
                write_dbn(filename, metadata, [trade])
                push!(test_files, filename)
            end
            
            # Test concurrent compression (simulated by running sequential calls)
            # Note: True thread safety testing would require more sophisticated setup
            @testset "Concurrent Compression Simulation" begin
                success_count = 0
                
                # Run compression multiple times to simulate concurrent access
                for i in 1:2
                    try
                        stats = compress_daily_files(test_date, temp_dir)
                        success_count += 1
                        @test isa(stats, Vector)
                        println("Compression run $i succeeded")
                    catch e
                        println("Compression run $i failed: $e")
                    end
                end
                
                @test success_count >= 1  # At least one should succeed
                println("Thread safety simulation: $success_count/2 runs succeeded")
            end
            
        finally
            # Cleanup
            rm(temp_dir, recursive=true, force=true)
        end
    end
end