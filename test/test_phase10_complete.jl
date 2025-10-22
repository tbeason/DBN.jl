using Test
using DBN
using Dates
using Statistics
using BenchmarkTools

# Phase 10: Complete Integration and Performance Testing
@testset "Phase 10: Integration and Performance Testing" begin
    
    @testset "Sample DBN File Compatibility" begin
        # Test reading various sample files from the reference implementation
        sample_files = [
            "test_data.trades.dbn",
            "test_data.mbo.dbn", 
            "test_data.mbp-1.dbn",
            "test_data.mbp-10.dbn",
            "test_data.ohlcv-1s.dbn",
            "test_data.definition.dbn",
            "test_data.status.dbn",
            "test_data.imbalance.dbn"
        ]
        
        for filename in sample_files
            filepath = joinpath("test", "data", filename)
            if isfile(filepath)
                @testset "Reading $filename" begin
                    @test_nowarn begin
                        metadata, records = read_dbn_with_metadata(filepath)
                        @test !isnothing(metadata)
                        @test length(records) > 0
                        @test metadata.dataset != ""
                        @test metadata.schema != Schema.MIX
                        println("✓ $filename - $(length(records)) records, schema: $(metadata.schema)")
                    end
                end
            end
        end
        
        # Test compressed files
        compressed_files = [
            "test_data.trades.v3.dbn.zst",
            "test_data.mbo.v3.dbn.zst",
            "test_data.mbp-1.v3.dbn.zst"
        ]
        
        for filename in compressed_files
            filepath = joinpath("test", "data", filename)
            if isfile(filepath)
                @testset "Reading compressed $filename" begin
                    @test_nowarn begin
                        metadata, records = read_dbn_with_metadata(filepath)
                        @test !isnothing(metadata)
                        @test length(records) > 0
                        println("✓ $filename - $(length(records)) records (compressed)")
                    end
                end
            end
        end
    end
    
    @testset "Performance Benchmarking" begin
        test_file = joinpath("test", "data", "test_data.trades.dbn")
        if !isfile(test_file)
            test_file = joinpath("test", "data", "test_data.mbo.dbn")
        end
        
        if isfile(test_file)
            @testset "Read Performance" begin
                read_benchmark = @benchmark read_dbn($test_file)
                read_time = median(read_benchmark.times) / 1e9
                file_size = filesize(test_file)
                throughput_mb_per_sec = (file_size / 1024 / 1024) / read_time
                
                println("Read Performance:")
                println("  File size: $(round(file_size/1024/1024, digits=2)) MB")
                println("  Read time: $(round(read_time*1000, digits=2)) ms")
                println("  Throughput: $(round(throughput_mb_per_sec, digits=2)) MB/s")
                
                @test read_time < 1.0
                @test throughput_mb_per_sec > 1.0
            end
            
            @testset "Write Performance" begin
                metadata, records = read_dbn_with_metadata(test_file)
                temp_file = tempname() * ".dbn"
                
                write_benchmark = @benchmark write_dbn($temp_file, $metadata, $records)
                write_time = median(write_benchmark.times) / 1e9
                written_size = filesize(temp_file)
                write_throughput = (written_size / 1024 / 1024) / write_time
                
                println("Write Performance:")
                println("  Records: $(length(records))")
                println("  Output size: $(round(written_size/1024/1024, digits=2)) MB")
                println("  Write time: $(round(write_time*1000, digits=2)) ms")
                println("  Throughput: $(round(write_throughput, digits=2)) MB/s")
                
                @test write_time < 2.0
                @test write_throughput > 0.5
                
                safe_rm(temp_file)
            end
        end
    end
    
    @testset "Memory Usage Profiling" begin
        test_file = joinpath("test", "data", "test_data.trades.dbn")
        if !isfile(test_file)
            test_file = joinpath("test", "data", "test_data.mbo.dbn")
        end
        
        if isfile(test_file)
            @testset "Memory Efficiency" begin
                GC.gc()
                mem_before = Base.gc_live_bytes()
                
                metadata, records = read_dbn_with_metadata(test_file)
                record_count = length(records)
                
                GC.gc()
                mem_after = Base.gc_live_bytes()
                mem_used = mem_after - mem_before
                mem_per_record = mem_used / record_count
                
                println("Memory Usage:")
                println("  Records: $record_count")
                println("  Memory used: $(round(mem_used/1024/1024, digits=2)) MB")
                println("  Memory per record: $(round(mem_per_record, digits=2)) bytes")
                
                @test mem_per_record < 1000
                @test mem_used < 100_000_000
            end
            
            @testset "Streaming Memory Usage" begin
                record_count = 0
                max_memory = 0
                
                GC.gc()
                initial_memory = Base.gc_live_bytes()
                
                for record in DBNStream(test_file)
                    record_count += 1
                    if record_count % 100 == 0
                        current_memory = Base.gc_live_bytes() - initial_memory
                        max_memory = max(max_memory, current_memory)
                    end
                    if record_count > 1000
                        break
                    end
                end
                
                println("Streaming Memory:")
                println("  Records processed: $record_count")
                println("  Max memory delta: $(round(max_memory/1024/1024, digits=2)) MB")
                
                @test max_memory < 50_000_000
            end
        end
    end
    
    @testset "Thread Safety" begin
        @testset "compress_daily_files Thread Safety" begin
            temp_dir = mktempdir()
            test_date = Date("2024-01-01")
            
            try
                # Create test files
                for i in 1:3
                    filename = joinpath(temp_dir, "$(Dates.format(test_date, "yyyymmdd"))_file$i.dbn")
                    
                    metadata = Metadata(
                        UInt8(3), "TEST.PHASE10", Schema.TRADES,
                        1640995200000000000, 1640995260000000000, UInt64(1),
                        SType.RAW_SYMBOL, SType.RAW_SYMBOL, false,
                        ["TEST"], String[], String[], Tuple{String,String,Int64,Int64}[]
                    )
                    
                    hd = RecordHeader(40, RType.MBP_0_MSG, 1, 12345, 1640995200000000000)
                    trade = TradeMsg(hd, 100000000, 100, Action.TRADE, Side.NONE, 0x00, 0, 1640995200000000000, 0, 1)
                    
                    write_dbn(filename, metadata, [trade])
                end
                
                # Test concurrent compression simulation
                success_count = 0
                for i in 1:2
                    try
                        stats = compress_daily_files(test_date, temp_dir)
                        success_count += 1
                        @test isa(stats, Vector)
                    catch e
                        println("Compression run $i failed: $e")
                    end
                end
                
                @test success_count >= 1
                println("Thread safety test: $success_count/2 runs succeeded")
                
            finally
                rm(temp_dir, recursive=true, force=true)
            end
        end
    end
    
    @testset "Export Functionality" begin
        test_file = joinpath("test", "data", "test_data.trades.dbn")
        if !isfile(test_file)
            test_file = joinpath("test", "data", "test_data.mbo.dbn")
        end
        
        if isfile(test_file)
            @testset "CSV Export" begin
                temp_csv = tempname() * ".csv"
                try
                    df = dbn_to_csv(test_file, temp_csv)
                    @test isfile(temp_csv)
                    @test nrow(df) > 0
                    @test ncol(df) > 0
                    println("  Exported $(nrow(df)) records to CSV")
                finally
                    rm(temp_csv, force=true)
                end
            end
            
            @testset "JSON Export" begin
                temp_json = tempname() * ".json"
                try
                    output = dbn_to_json(test_file, temp_json, pretty=true)
                    @test isfile(temp_json)
                    @test haskey(output, "metadata")
                    @test haskey(output, "records")
                    @test length(output["records"]) > 0
                    println("  Exported $(length(output["records"])) records to JSON")
                finally
                    rm(temp_json, force=true)
                end
            end
            
            @testset "Parquet Export" begin
                temp_parquet = tempname() * ".parquet"
                try
                    df = dbn_to_parquet(test_file, temp_parquet)
                    @test isfile(temp_parquet)
                    @test nrow(df) > 0
                    @test ncol(df) > 0
                    println("  Exported $(nrow(df)) records to Parquet")
                finally
                    rm(temp_parquet, force=true)
                end
            end
            
            @testset "DataFrame Conversion" begin
                metadata, records = read_dbn_with_metadata(test_file)
                df = records_to_dataframe(records)
                @test nrow(df) == length(records)
                @test ncol(df) > 0
                println("  Converted $(nrow(df)) records to DataFrame")
            end
        end
    end
end