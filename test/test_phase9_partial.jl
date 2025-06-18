using Test
using DBN
using Dates

@testset "Phase 9: Invalid Files Test" begin
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
end