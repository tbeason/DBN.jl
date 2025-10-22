using Test
using DBN
using Dates

# Load test utilities (safe_rm, etc.)
include("test_utils.jl")

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
    
    # Run compatibility tests if the Rust CLI is available
    dbn_cli_path = if Sys.iswindows()
        joinpath(homedir(), "dbn-workspace", "dbn", "target", "release", "dbn.exe")
    else
        joinpath(homedir(), "dbn-workspace", "dbn", "target", "release", "dbn")
    end

    if isfile(dbn_cli_path)
        include("test_compatibility_updated.jl")  # Updated cross-implementation compatibility testing
    else
        @warn "Skipping compatibility tests - Rust dbn-cli not found at $dbn_cli_path"
    end

    # Import/export tests (optional - uncomment if needed)
    # include("test_import_simple.jl")
end