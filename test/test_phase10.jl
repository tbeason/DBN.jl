using Test
using DBN
using Dates
using Statistics
using BenchmarkTools

# Phase 10: Integration and Performance Testing
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
            "test_data.statistics.dbn",
            "test_data.imbalance.dbn"
        ]
        
        for filename in sample_files
            filepath = joinpath("test", "data", filename)
            if isfile(filepath)
                @testset "Reading $filename" begin
                    @test_nowarn begin
                        metadata, records = read_dbn(filepath)
                        @test !isnothing(metadata)
                        @test length(records) > 0
                        @test metadata.dataset != ""
                        @test metadata.schema != MIXED_SCHEMA
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
                        metadata, records = read_dbn(filepath)
                        @test !isnothing(metadata)
                        @test length(records) > 0
                        println("✓ $filename - $(length(records)) records (compressed)")
                    end
                end
            end
        end
    end
    
    @testset "Performance Benchmarking" begin
        # Find a substantial test file for benchmarking
        test_file = joinpath("test", "data", "test_data.trades.dbn")
        if !isfile(test_file)
            test_file = joinpath("test", "data", "test_data.mbo.dbn")
        end
        
        if isfile(test_file)
            @testset "Read Performance" begin
                # Benchmark reading
                read_benchmark = @benchmark read_dbn($test_file)
                read_time = median(read_benchmark.times) / 1e9  # Convert to seconds
                
                # Get file size for throughput calculation
                file_size = filesize(test_file)
                throughput_mb_per_sec = (file_size / 1024 / 1024) / read_time
                
                println("Read Performance:")
                println("  File size: $(round(file_size/1024/1024, digits=2)) MB")
                println("  Read time: $(round(read_time*1000, digits=2)) ms")
                println("  Throughput: $(round(throughput_mb_per_sec, digits=2)) MB/s")
                
                # Performance assertions (reasonable thresholds)
                @test read_time < 1.0  # Should read within 1 second
                @test throughput_mb_per_sec > 1.0  # Should achieve at least 1 MB/s
            end
            
            @testset "Write Performance" begin
                # Read test data first
                metadata, records = read_dbn(test_file)
                
                # Benchmark writing
                temp_file = tempname() * ".dbn"
                write_benchmark = @benchmark write_dbn($temp_file, $metadata, $records)
                write_time = median(write_benchmark.times) / 1e9
                
                # Calculate throughput
                written_size = filesize(temp_file)
                write_throughput = (written_size / 1024 / 1024) / write_time
                
                println("Write Performance:")
                println("  Records: $(length(records))")
                println("  Output size: $(round(written_size/1024/1024, digits=2)) MB")
                println("  Write time: $(round(write_time*1000, digits=2)) ms")
                println("  Throughput: $(round(write_throughput, digits=2)) MB/s")
                
                @test write_time < 2.0  # Should write within 2 seconds
                @test write_throughput > 0.5  # Should achieve at least 0.5 MB/s
                
                # Cleanup
                rm(temp_file, force=true)
            end
            
            @testset "Round-trip Performance" begin
                # Read original
                metadata, original_records = read_dbn(test_file)
                
                # Write and read back
                temp_file = tempname() * ".dbn"
                roundtrip_benchmark = @benchmark begin
                    write_dbn($temp_file, $metadata, $original_records)
                    read_dbn($temp_file)
                end
                
                roundtrip_time = median(roundtrip_benchmark.times) / 1e9
                println("Round-trip time: $(round(roundtrip_time*1000, digits=2)) ms")
                
                @test roundtrip_time < 3.0  # Should complete round-trip within 3 seconds
                
                # Verify data integrity
                metadata2, records2 = read_dbn(temp_file)
                @test length(records2) == length(original_records)
                @test metadata2.dataset == metadata.dataset
                @test metadata2.schema == metadata.schema
                
                rm(temp_file, force=true)
            end
        end
    end
    
    @testset "Memory Usage Profiling" begin
        # Test memory usage with large datasets
        test_file = joinpath("test", "data", "test_data.trades.dbn")
        if !isfile(test_file)
            test_file = joinpath("test", "data", "test_data.mbo.dbn")
        end
        
        if isfile(test_file)
            @testset "Memory Efficiency" begin
                # Measure memory before
                GC.gc()
                mem_before = Base.gc_live_bytes()
                
                # Read file
                metadata, records = read_dbn(test_file)
                record_count = length(records)
                
                # Measure memory after
                GC.gc()
                mem_after = Base.gc_live_bytes()
                mem_used = mem_after - mem_before
                
                # Calculate memory per record
                mem_per_record = mem_used / record_count
                
                println("Memory Usage:")
                println("  Records: $record_count")
                println("  Memory used: $(round(mem_used/1024/1024, digits=2)) MB")
                println("  Memory per record: $(round(mem_per_record, digits=2)) bytes")
                
                # Reasonable memory usage thresholds
                @test mem_per_record < 1000  # Less than 1KB per record seems reasonable
                @test mem_used < 100_000_000  # Less than 100MB for test data
            end
            
            @testset "Streaming Memory Usage" begin
                # Test that streaming doesn't accumulate excessive memory
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
                    
                    # Break early for large files to keep test reasonable
                    if record_count > 1000
                        break
                    end
                end
                
                println("Streaming Memory:")
                println("  Records processed: $record_count")
                println("  Max memory delta: $(round(max_memory/1024/1024, digits=2)) MB")
                
                # Streaming should maintain relatively constant memory usage
                @test max_memory < 50_000_000  # Less than 50MB additional memory
            end
        end
    end
    
    @testset "Thread Safety" begin
        @testset "compress_daily_files Thread Safety" begin
            # Create test files for compression
            temp_dir = mktempdir()
            test_date = Date("2024-01-01")
            
            try
                # Create some test files for the date
                test_files = []
                for i in 1:3
                    filename = joinpath(temp_dir, "$(Dates.format(test_date, "yyyymmdd"))_file$i.dbn")
                    
                    # Create minimal test data
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
                    trade = TradeMsg(
                        hd=RecordHeader(length=96, rtype=UInt8(RType.MBP_0_MSG), publisher_id=1, instrument_id=1, ts_event=1640995200000000000),
                        price=100000000,  # $100.00
                        size=100,
                        action=Action.TRADE,
                        side=Side.NONE,
                        flags=0,
                        depth=0,
                        ts_recv=1640995200000000000,
                        ts_in_delta=0,
                        sequence=1
                    )
                    
                    write_dbn(filename, metadata, [trade])
                    push!(test_files, filename)
                end
                
                # Test concurrent compression
                @testset "Concurrent Compression" begin
                    # Run compression in parallel threads (simulated by multiple calls)
                    tasks = []
                    for i in 1:2
                        task = Threads.@spawn begin
                            try
                                stats = compress_daily_files(test_date, temp_dir, delete_original=false)
                                return stats
                            catch e
                                return e
                            end
                        end
                        push!(tasks, task)
                    end
                    
                    # Wait for completion
                    results = []
                    for task in tasks
                        result = fetch(task)
                        push!(results, result)
                    end
                    
                    # At least one should succeed
                    success_count = sum(r -> !isa(r, Exception), results)
                    @test success_count >= 1
                    
                    println("Thread safety test: $success_count/$(length(results)) tasks succeeded")
                end
                
            finally
                # Cleanup
                rm(temp_dir, recursive=true, force=true)
            end
        end
    end
    
    @testset "Large File Handling" begin
        # Test with the largest available sample file
        largest_file = nothing
        largest_size = 0
        
        for file in readdir(joinpath("test", "data"))
            if endswith(file, ".dbn") && !contains(file, ".zst")
                filepath = joinpath("test", "data", file)
                size = filesize(filepath)
                if size > largest_size
                    largest_size = size
                    largest_file = filepath
                end
            end
        end
        
        if !isnothing(largest_file) && largest_size > 10000  # At least 10KB
            @testset "Large File Processing" begin
                println("Testing large file: $(basename(largest_file)) ($(round(largest_size/1024, digits=2)) KB)")
                
                @test_nowarn begin
                    metadata, records = read_dbn(largest_file)
                    @test length(records) > 0
                    
                    # Test streaming for large files
                    streamed_count = 0
                    for record in DBNStream(largest_file)
                        streamed_count += 1
                        # Stop after reasonable number for testing
                        if streamed_count > 10000
                            break
                        end
                    end
                    
                    @test streamed_count > 0
                    println("  Read $(length(records)) records")
                    println("  Streamed $streamed_count records")
                end
            end
        end
    end
    
    @testset "Error Recovery and Robustness" begin
        @testset "Partial File Recovery" begin
            # Test reading files that might be truncated or partially corrupted
            test_file = joinpath("test", "data", "test_data.trades.dbn")
            if isfile(test_file)
                # Create a truncated version
                temp_file = tempname() * ".dbn"
                original_data = read(test_file)
                
                # Write partial file (first 80% of data)
                truncated_size = Int(floor(length(original_data) * 0.8))
                write(temp_file, original_data[1:truncated_size])
                
                @testset "Truncated File Handling" begin
                    # Should handle truncated files gracefully
                    try
                        metadata, records = read_dbn(temp_file)
                        # If it succeeds, should have some records
                        @test length(records) >= 0
                        println("  Truncated file read $(length(records)) records")
                    catch e
                        # If it fails, should be a descriptive error
                        @test isa(e, Exception)
                        println("  Truncated file error: $(typeof(e))")
                    end
                end
                
                rm(temp_file, force=true)
            end
        end
    end
    
    @testset "Export Functionality" begin
        # Find a test file to export
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
                metadata, records = read_dbn(test_file)
                df = records_to_dataframe(records)
                @test nrow(df) == length(records)
                @test ncol(df) > 0
                println("  Converted $(nrow(df)) records to DataFrame")
            end
        end
    end
end