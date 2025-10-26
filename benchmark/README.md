# DBN.jl Benchmark Suite

Comprehensive performance benchmarking tools for DBN.jl, measuring throughput (records/second), latency, memory usage, and bandwidth.

## Quick Start

```bash
# Generate test data and run all benchmarks
julia benchmark/run_benchmarks.jl --generate-data

# Quick benchmark with small datasets
julia benchmark/run_benchmarks.jl --generate-data --quick

# Run only throughput benchmarks (faster)
julia benchmark/run_benchmarks.jl --throughput-only

# Run only detailed BenchmarkTools suite
julia benchmark/run_benchmarks.jl --suite-only
```

## Components

### 1. Data Generator (`generate_test_data.jl`)

Generates realistic test data files of various sizes for benchmarking.

**Sizes:**
- `1k` - 1,000 records (~40 KB)
- `10k` - 10,000 records (~400 KB)
- `100k` - 100,000 records (~4 MB)
- `1m` - 1,000,000 records (~40 MB)
- `10m` - 10,000,000 records (~400 MB)

**Message Types:**
- `trades` - Trade execution messages
- `mbo` - Market-by-order messages
- `ohlcv` - OHLCV bar data

**Formats:**
- Uncompressed (`.dbn`)
- Zstd compressed (`.dbn.zst`)

**Usage:**
```bash
# Generate all test files
julia benchmark/generate_test_data.jl

# Generate to custom directory
julia -e 'include("benchmark/generate_test_data.jl"); generate_test_files("my_data/")'
```

### 2. Throughput Benchmarks (`throughput.jl`)

Measures real-world throughput in records/second and MB/s bandwidth.

**Metrics:**
- Records per second
- Million records per second
- Read/write bandwidth (MB/s)
- Mean time and standard deviation
- File sizes

**Usage:**
```bash
# Run on default data directory
julia benchmark/throughput.jl

# Custom data directory
julia benchmark/throughput.jl benchmark/data

# Custom number of runs
julia benchmark/throughput.jl benchmark/data 10
```

**Example Output:**
```
======================================================================
READ THROUGHPUT - trades.1m.dbn.zst
======================================================================
File:                   trades.1m.dbn.zst
Records:                1,000,000
Mean Time:              0.2450 ± 0.0123 seconds
File Size:              38.50 MB

----------------------------------------------------------------------
Throughput:
  4,081,632.65 records/second
  4,081.63 thousand records/second
  4.0816 million records/second

Bandwidth:              157.14 MB/s
======================================================================
```

### 3. BenchmarkTools Suite (`benchmarks.jl`)

Detailed statistical benchmarks using BenchmarkTools.jl for precise timing and memory profiling.

**Benchmark Groups:**
- `read` - File reading operations
- `stream` - Streaming operations
- `write` - File writing operations
- `convert` - Format conversion
- `utils` - Price and timestamp utilities

**Usage:**
```bash
# Run full suite
julia benchmark/benchmarks.jl

# Run programmatically
julia -e 'include("benchmark/benchmarks.jl"); run_benchmark_suite()'
```

**Compare Results:**
```julia
using BenchmarkTools
include("benchmark/benchmarks.jl")

# Compare two benchmark runs
compare_benchmarks("benchmark/results_20240101_120000.json",
                  "benchmark/results_20240101_130000.json")
```

### 4. Main Runner (`run_benchmarks.jl`)

Orchestrates the complete benchmark suite with options for different scenarios.

**Options:**
- `--generate-data` - Generate test data before benchmarking
- `--throughput-only` - Run only throughput benchmarks (faster)
- `--suite-only` - Run only BenchmarkTools suite
- `--quick` - Quick benchmark with small datasets only
- `--data-dir DIR` - Use custom data directory
- `--runs N` - Number of runs for throughput benchmarks (default: 5)

## Benchmark Results

Results are automatically saved to:

1. **CSV Files** (`benchmark/results_*.csv`)
   - Timestamped results for analysis
   - Easy to import into spreadsheets or Python/R
   - Columns: group, benchmark, time, memory, allocations

2. **JSON Files** (`benchmark/results_*.json`)
   - Full BenchmarkTools results
   - Can be loaded for comparison with `BenchmarkTools.load()`

## Performance Targets

Based on modern hardware (SSD, 16GB RAM):

| Operation | Target Throughput | Notes |
|-----------|------------------|-------|
| Read uncompressed | > 5M records/sec | Limited by memory bandwidth |
| Read compressed | > 2M records/sec | Limited by decompression |
| Write uncompressed | > 4M records/sec | Limited by disk I/O |
| Write compressed | > 1M records/sec | Limited by compression |
| Streaming | > 3M records/sec | Lower memory overhead |

## Example Workflow

### 1. Initial Benchmarking

```bash
# Generate data and run complete suite
julia benchmark/run_benchmarks.jl --generate-data
```

### 2. Quick Regression Testing

```bash
# Quick check after code changes
julia benchmark/run_benchmarks.jl --quick --throughput-only
```

### 3. Detailed Performance Analysis

```bash
# Run detailed suite and analyze
julia benchmark/run_benchmarks.jl --suite-only
```

### 4. Custom Analysis

```julia
using DBN
include("benchmark/throughput.jl")

# Benchmark specific file
result = benchmark_read_throughput("my_file.dbn.zst", runs=10)
println("Throughput: $(result.throughput_mrecs_per_sec) Mrec/s")

# Custom benchmark
file = "my_data.dbn"
@time records = read_dbn(file)
println("Read $(length(records)) records")
```

## Comparing Performance

### Against Other Implementations

To compare with the official Rust implementation:

```bash
# Benchmark Rust version
time dbn dump test_data.dbn --output /dev/null

# Benchmark Julia version
julia -e 'using DBN; @time read_dbn("test_data.dbn")'
```

### Across Versions

```julia
# Run benchmarks before changes
julia benchmark/run_benchmarks.jl
# Note the timestamp of results file

# Make code changes
# ...

# Run benchmarks after changes
julia benchmark/run_benchmarks.jl

# Compare
using BenchmarkTools
include("benchmark/benchmarks.jl")
compare_benchmarks("benchmark/results_BEFORE.json",
                  "benchmark/results_AFTER.json")
```

## CI Integration

To track performance over time, add to your CI pipeline:

```yaml
# .github/workflows/benchmarks.yml
name: Benchmarks

on: [push, pull_request]

jobs:
  benchmark:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      - uses: julia-actions/setup-julia@v1
      - name: Run benchmarks
        run: julia benchmark/run_benchmarks.jl --generate-data --quick
      - uses: actions/upload-artifact@v2
        with:
          name: benchmark-results
          path: benchmark/results_*.csv
```

## Profiling

For detailed profiling of hot spots:

```julia
using Profile, ProfileView
using DBN

# Profile reading
file = "benchmark/data/trades.1m.dbn"
@profile for i in 1:100
    read_dbn(file)
end

# View results
ProfileView.view()

# Or generate flamegraph
using FlameGraphs
g = flamegraph()
```

## Memory Profiling

```julia
using DBN

# Track allocations
file = "benchmark/data/trades.1m.dbn"
@time read_dbn(file)  # Warm up

# Detailed allocation tracking
@allocated read_dbn(file)

# Use --track-allocation=user when starting Julia for line-by-line profiling
```

## Tips for Accurate Benchmarking

1. **Warm up the JIT compiler** - Run operations at least once before benchmarking
2. **Clear caches** - Run `GC.gc()` between benchmarks
3. **Use realistic data** - Benchmark with production-sized datasets
4. **Multiple runs** - Average over multiple runs (default: 5)
5. **Minimize background processes** - Close unnecessary applications
6. **Consistent environment** - Use same hardware/OS for comparisons

## Troubleshooting

### "No test data found"

Run with `--generate-data`:
```bash
julia benchmark/run_benchmarks.jl --generate-data
```

### Out of Memory

Use smaller datasets or streaming operations:
```bash
julia benchmark/run_benchmarks.jl --quick
```

### Slow Benchmarks

Use throughput-only mode for faster results:
```bash
julia benchmark/run_benchmarks.jl --throughput-only
```

## Contributing

When adding new features to DBN.jl:

1. Add relevant benchmarks to `benchmarks.jl`
2. Run `julia benchmark/run_benchmarks.jl --quick` to verify no regressions
3. Include performance results in PR description if significant changes

## References

- [BenchmarkTools.jl Documentation](https://github.com/JuliaCI/BenchmarkTools.jl)
- [Julia Performance Tips](https://docs.julialang.org/en/v1/manual/performance-tips/)
- [DBN Format Specification](https://databento.com/docs/standards-and-conventions/databento-binary-encoding)
