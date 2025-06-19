using Test
using DBN
using Dates

@testset "Basic Import Functionality" begin
    
    @testset "JSON Import Basic Test" begin
        # Create a simple JSON structure that we know should work
        json_content = """{
            "metadata": {
                "version": 3,
                "dataset": "TEST",
                "schema": "TRADES",
                "start_ts": "1704099000000000000",
                "end_ts": "1704099030000000000",
                "limit": 1,
                "stype_in": "RAW_SYMBOL",
                "stype_out": "RAW_SYMBOL",
                "ts_out": false,
                "symbols": [],
                "partial": [],
                "not_found": [],
                "mappings": []
            },
            "records": [
                {
                    "hd": {
                        "ts_event": "1704099000000000000",
                        "rtype": 0,
                        "publisher_id": 1,
                        "instrument_id": 12345
                    },
                    "price": "100500000000",
                    "size": 100,
                    "action": "T",
                    "side": "B",
                    "flags": 0,
                    "depth": 0,
                    "ts_recv": "1704099000000000000",
                    "ts_in_delta": 0,
                    "sequence": 1
                }
            ]
        }"""
        
        json_file = "test_simple.json"
        dbn_file = "test_simple.dbn"
        
        try
            # Write test JSON
            open(json_file, "w") do f
                write(f, json_content)
            end
            
            # Test conversion - this should work with structured JSON
            record_count = json_to_dbn(json_file, dbn_file)
            @test record_count == 1
            
            # Verify output file exists and has content
            @test isfile(dbn_file)
            @test filesize(dbn_file) > 0
            
        finally
            rm(json_file, force=true)
            rm(dbn_file, force=true)
        end
    end
    
    @testset "Error Handling" begin
        # Test with malformed JSON
        json_file = "malformed.json"
        dbn_file = "output.dbn"
        
        try
            open(json_file, "w") do f
                write(f, "{invalid json")
            end
            
            @test_throws Exception json_to_dbn(json_file, dbn_file)
            
        finally
            rm(json_file, force=true)
            rm(dbn_file, force=true)
        end
        
        # Test missing file
        @test_throws SystemError json_to_dbn("nonexistent.json", "output.dbn")
    end
    
    @testset "Parameter Validation" begin
        # Test CSV/Parquet missing parameters
        @test_throws ArgumentError csv_to_dbn("test.csv", "test.dbn", dataset="TEST")
        @test_throws ArgumentError csv_to_dbn("test.csv", "test.dbn", schema=Schema.TRADES)
        @test_throws ArgumentError parquet_to_dbn("test.parquet", "test.dbn", dataset="TEST")
        @test_throws ArgumentError parquet_to_dbn("test.parquet", "test.dbn", schema=Schema.TRADES)
    end
end