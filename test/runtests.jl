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
    if isfile("/workspace/dbn/target/release/dbn")
        include("test_compatibility_updated.jl")  # Updated cross-implementation compatibility testing
    else
        @warn "Skipping compatibility tests - Rust dbn-cli not found. Build it with: cd /workspace/dbn/rust/dbn-cli && cargo build --release"
    end

    # Import/export tests (optional - uncomment if needed)
    # include("test_import_simple.jl")
end