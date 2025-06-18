using Test
using DBN
using Dates

println("Testing Phase 9 loading...")

@testset "Phase 9: Edge Cases - Simple Test" begin
    @testset "Empty file test" begin
        empty_file = tempname() * ".dbn"
        try
            touch(empty_file)
            @test_throws Exception read_dbn(empty_file)
        finally
            rm(empty_file, force=true)
        end
    end
end

println("Phase 9 simple test complete")