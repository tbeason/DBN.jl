using Test
using DBN
using Dates

@testset "DBN.jl Tests" begin
    include("test_phase1.jl")
    include("test_phase2.jl")
    include("test_phase3.jl")
    include("test_phase4.jl")
    include("test_phase5.jl")
    include("test_phase6.jl")
    include("test_phase7.jl")
    include("test_phase8.jl")
    include("test_phase9_working.jl")  # Edge cases and error handling
    include("test_phase10_complete.jl")  # Integration and performance testing
end