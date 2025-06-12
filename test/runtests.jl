using DBN
using Test

@testset "DBN.jl Tests" begin
    include("test_phase1.jl")
    include("test_phase2.jl")
    include("test_phase3.jl")
    include("test_phase4.jl")
    include("test_phase5.jl")
end