using Test
using DBN
using Dates

@testset "Phase 9: Metadata Test" begin
    @testset "Simple metadata test" begin
        test_file = tempname() * ".dbn"
        try
            metadata = Metadata(
                UInt8(3),                    # version
                "TEST",                      # dataset
                Schema.TRADES,               # schema
                1000000000,                  # start_ts
                2000000000,                  # end_ts
                UInt64(0),                   # limit
                SType.RAW_SYMBOL,            # stype_in
                SType.INSTRUMENT_ID,         # stype_out
                false,                       # ts_out
                String[],                    # symbols
                String[],                    # partial
                String[],                    # not_found
                Tuple{String,String,Int64,Int64}[]  # mappings
            )
            
            # Should be able to create encoder
            open(test_file, "w") do f
                encoder = DBNEncoder(f, metadata)
                write_header(encoder)
                finalize_encoder(encoder)
            end
            
            # Should be able to read
            records = read_dbn(test_file)
            @test isempty(records)
        finally
            rm(test_file, force=true)
        end
    end
end