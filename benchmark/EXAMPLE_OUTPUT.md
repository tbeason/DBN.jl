# Example Benchmark Output

This document shows example output from the DBN.jl benchmark suite.

## Throughput Benchmark Example

```
████████████████████████████████████████████████████████████████████
█                                                                  █
█  DBN.jl THROUGHPUT BENCHMARK SUITE                              █
█                                                                  █
████████████████████████████████████████████████████████████████████

Benchmark runs per test: 5
Data directory: benchmark/data

Started at: 2024-01-15 10:30:45

Found 12 test files


▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼
Testing: trades.1m.dbn.zst
▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼

[1/3] Benchmarking full read (read_dbn)...

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


[2/3] Benchmarking streaming read (DBNStream)...

======================================================================
STREAMING THROUGHPUT - trades.1m.dbn.zst
======================================================================
File:                   trades.1m.dbn.zst
Records:                1,000,000
Mean Time:              0.2812 ± 0.0089 seconds
File Size:              38.50 MB

----------------------------------------------------------------------
Throughput:
  3,556,224.90 records/second
  3,556.22 thousand records/second
  3.5562 million records/second

Bandwidth:              136.89 MB/s
======================================================================


[3/3] Benchmarking write (write_dbn)...

======================================================================
WRITE THROUGHPUT - trades.1m.dbn.zst
======================================================================
Records:                1,000,000
Mean Time:              0.3250 ± 0.0156 seconds
File Size:              38.50 MB

----------------------------------------------------------------------
Throughput:
  3,076,923.08 records/second
  3,076.92 thousand records/second
  3.0769 million records/second

Bandwidth:              118.46 MB/s
======================================================================


████████████████████████████████████████████████████████████████████
█                                                                  █
█  BENCHMARK SUMMARY                                              █
█                                                                  █
████████████████████████████████████████████████████████████████████


READ THROUGHPUT:
──────────────────────────────────────────────────────────────────────
File                              Records       Time (s)     Mrec/s
──────────────────────────────────────────────────────────────────────
trades.1k.dbn                       1,000        0.001       1.1235
trades.1k.dbn.zst                   1,000        0.001       0.9876
trades.10k.dbn                     10,000        0.003       3.4521
trades.10k.dbn.zst                 10,000        0.004       2.8912
trades.100k.dbn                   100,000        0.028       3.5714
trades.100k.dbn.zst               100,000        0.032       3.1250
trades.1m.dbn                   1,000,000        0.236       4.2373
trades.1m.dbn.zst               1,000,000        0.245       4.0816
trades.10m.dbn                 10,000,000        2.341       4.2719
trades.10m.dbn.zst             10,000,000        2.512       3.9809


STREAM THROUGHPUT:
──────────────────────────────────────────────────────────────────────
File                              Records       Time (s)     Mrec/s
──────────────────────────────────────────────────────────────────────
trades.1k.dbn                       1,000        0.001       0.9523
trades.10k.dbn                     10,000        0.004       2.5641
trades.100k.dbn                   100,000        0.032       3.1250
trades.1m.dbn                   1,000,000        0.281       3.5562


WRITE THROUGHPUT:
──────────────────────────────────────────────────────────────────────
File                              Records       Time (s)     Mrec/s
──────────────────────────────────────────────────────────────────────
trades.1k.dbn                       1,000        0.001       0.8928
trades.10k.dbn                     10,000        0.005       2.0000
trades.100k.dbn                   100,000        0.041       2.4390
trades.1m.dbn                   1,000,000        0.325       3.0769

████████████████████████████████████████████████████████████████████


Completed at: 2024-01-15 10:45:23
```

## BenchmarkTools Suite Example

```
======================================================================
DBN.jl BenchmarkTools Suite
======================================================================

Creating benchmark suite...
Suite created with 5 groups
  - read: 4 benchmarks
  - stream: 2 benchmarks
  - write: 3 benchmarks
  - convert: 2 benchmarks
  - utils: 4 benchmarks

Running benchmarks (this may take several minutes)...
Started at: 2024-01-15 10:50:00


======================================================================
BENCHMARK RESULTS
======================================================================

read:
──────────────────────────────────────────────────────────────────────
  small_uncompressed         0.89 ms    39.23 KB      45 allocs
  small_compressed           1.12 ms    39.45 KB      52 allocs
  medium_uncompressed       28.45 ms     3.81 MB     450 allocs
  medium_compressed         34.23 ms     3.82 MB     465 allocs

stream:
──────────────────────────────────────────────────────────────────────
  small                      1.05 ms    12.34 KB      23 allocs
  medium                    32.10 ms     1.23 MB     234 allocs

write:
──────────────────────────────────────────────────────────────────────
  small_uncompressed         1.23 ms    40.50 KB      67 allocs
  small_compressed           2.45 ms    45.20 KB      89 allocs
  medium_uncompressed       38.90 ms     3.95 MB     678 allocs

convert:
──────────────────────────────────────────────────────────────────────
  to_json                   15.67 ms    89.45 KB     234 allocs
  to_csv                    12.34 ms    78.23 KB     189 allocs

utils:
──────────────────────────────────────────────────────────────────────
  float_to_price            12.34 ns     0.00 KB       0 allocs
  price_to_float            10.23 ns     0.00 KB       0 allocs
  datetime_to_ts            45.67 ns     0.00 KB       0 allocs
  ts_to_datetime            52.34 ns     0.00 KB       0 allocs

======================================================================

Results saved to:
  - benchmark/results_20240115_105000.csv
  - benchmark/results_20240115_105000.json

Completed at: 2024-01-15 11:05:23
```

## CSV Results Example

The benchmark suite generates CSV files with detailed results:

```csv
group,benchmark,min_time_ns,median_time_ns,mean_time_ns,max_time_ns,memory_bytes,allocs,gc_time_ns,min_time_ms,median_time_ms,memory_mb
read,small_uncompressed,890000,895000,892500,900000,40192,45,0,0.890,0.895,0.039
read,small_compressed,1120000,1125000,1122500,1130000,40396,52,0,1.120,1.125,0.039
read,medium_uncompressed,28450000,28500000,28475000,28600000,3997696,450,0,28.450,28.500,3.813
read,medium_compressed,34230000,34250000,34240000,34300000,4005888,465,0,34.230,34.250,3.821
stream,small,1050000,1055000,1052500,1060000,12636,23,0,1.050,1.055,0.012
stream,medium,32100000,32150000,32125000,32200000,1290240,234,0,32.100,32.150,1.231
write,small_uncompressed,1230000,1235000,1232500,1240000,41472,67,0,1.230,1.235,0.040
write,small_compressed,2450000,2455000,2452500,2460000,46284,89,0,2.450,2.455,0.044
write,medium_uncompressed,38900000,38950000,38925000,39000000,4143104,678,0,38.900,38.950,3.952
convert,to_json,15670000,15700000,15685000,15720000,91596,234,0,15.670,15.700,0.087
convert,to_csv,12340000,12360000,12350000,12380000,80107,189,0,12.340,12.360,0.076
utils,float_to_price,12,12,12,13,0,0,0,0.000,0.000,0.000
utils,price_to_float,10,10,10,11,0,0,0,0.000,0.000,0.000
utils,datetime_to_ts,45,46,45,47,0,0,0,0.000,0.000,0.000
utils,ts_to_datetime,52,53,52,54,0,0,0,0.000,0.000,0.000
```

## Performance Comparison

You can compare these results with the official Rust implementation:

### Rust (dbn crate)
```bash
$ time dbn dump trades.1m.dbn.zst --output /dev/null
Processed 1,000,000 records

real    0m0.198s
user    0m0.185s
sys     0m0.012s
```
**Throughput:** ~5.05 million records/second

### Julia (DBN.jl)
```julia
julia> @time read_dbn("trades.1m.dbn.zst")
  0.245000 seconds (450 allocations: 3.82 MiB)
1000000-element Vector{TradeMsg}
```
**Throughput:** ~4.08 million records/second

**Performance Ratio:** Julia achieves ~81% of Rust performance, which is excellent for a high-level language!

## Interpreting Results

### Throughput Metrics
- **> 5 Mrec/s**: Excellent (limited by memory bandwidth)
- **3-5 Mrec/s**: Good (typical for compressed data)
- **1-3 Mrec/s**: Fair (acceptable for complex operations)
- **< 1 Mrec/s**: Poor (may indicate performance issues)

### Memory Usage
- Small files (1K-10K records): < 1 MB
- Medium files (100K records): ~4 MB
- Large files (1M records): ~40 MB
- Very large files (10M records): ~400 MB

### Allocations
- Low allocation count (< 100): Efficient
- Medium allocation count (100-1000): Acceptable
- High allocation count (> 1000): May cause GC pressure

### Compression Overhead
- Zstd typically reduces throughput by 20-30%
- File size reduction: 50-70% for market data
- Worth it for: storage, network transfer
- Skip for: in-memory processing, low-latency applications
