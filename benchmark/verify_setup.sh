#!/bin/bash
# Verify benchmark suite setup

echo "=================================================="
echo "  DBN.jl Benchmark Suite Verification"
echo "=================================================="
echo

# Check if files exist
echo "Checking benchmark files..."
files=(
    "benchmark/generate_test_data.jl"
    "benchmark/throughput.jl"
    "benchmark/benchmarks.jl"
    "benchmark/run_benchmarks.jl"
    "benchmark/README.md"
)

all_exist=true
for file in "${files[@]}"; do
    if [ -f "$file" ]; then
        echo "  ✓ $file"
    else
        echo "  ✗ $file (missing)"
        all_exist=false
    fi
done

echo

# Check Julia installation
if command -v julia &> /dev/null; then
    echo "✓ Julia found: $(julia --version)"
    echo

    # Check if DBN can be loaded
    echo "Testing DBN package load..."
    julia --project=. -e 'using DBN; println("✓ DBN.jl loaded successfully")' 2>&1

    if [ $? -eq 0 ]; then
        echo
        echo "=================================================="
        echo "  Setup verification PASSED"
        echo "=================================================="
        echo
        echo "You can now run benchmarks with:"
        echo "  julia benchmark/run_benchmarks.jl --generate-data --quick"
        echo
    else
        echo
        echo "⚠ DBN.jl could not be loaded. Run:"
        echo "  julia --project=. -e 'using Pkg; Pkg.instantiate()'"
        echo
    fi
else
    echo "⚠ Julia not found. Please install Julia 1.12 or later."
    echo
    if [ "$all_exist" = true ]; then
        echo "Benchmark files are present and ready to use once Julia is installed."
    fi
fi

echo
