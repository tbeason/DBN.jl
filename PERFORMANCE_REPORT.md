# DBN.jl Performance Benchmarks

## mbo.1m.dbn (1,000,000 records, 53.41 MB)

| Implementation | Throughput |
|----------------|------------|
| Julia `read_mbo()` (optimized) | 17.07 M/s |
| Python `databento` | 10.86 M/s |
| Julia `DBNStream()` | 3.17 M/s |
| Julia `read_dbn()` | 3.00 M/s |
| Julia `write_dbn()` | 2.38 M/s |
| Rust `dbn` CLI | 2.29 M/s |

## trades.1m.dbn (1,000,000 records, 45.78 MB)

| Implementation | Throughput |
|----------------|------------|
| Julia `read_trades()` (optimized) | 17.88 M/s |
| Python `databento` | 11.87 M/s |
| Julia `DBNStream()` | 3.14 M/s |
| Julia `read_dbn()` | 3.10 M/s |
| Rust `dbn` CLI | 2.67 M/s |
| Julia `write_dbn()` | 2.20 M/s |

## trades.10m.dbn (10,000,000 records, 457.76 MB)

| Implementation | Throughput |
|----------------|------------|
| Julia `read_trades()` (optimized) | 19.30 M/s |
| Python `databento` | 11.25 M/s |
| Julia `DBNStream()` | 9.36 M/s |
| Julia `read_dbn()` | 5.55 M/s |
| Rust `dbn` CLI | 2.76 M/s |

## trades.100k.dbn (100,000 records, 4.58 MB)

| Implementation | Throughput |
|----------------|------------|
| Julia `read_trades()` (optimized) | 15.06 M/s |
| Python `databento` | 10.05 M/s |
| Julia `write_dbn()` | 2.75 M/s |
| Rust `dbn` CLI | 1.97 M/s |
| Julia `DBNStream()` | 0.44 M/s |
| Julia `read_dbn()` | 0.43 M/s |

---

**Test environment**: Windows 11, Julia 1.12.1, Python databento 0.x, Rust dbn 1.75+

**Reproduce**: `julia --project=. benchmark/compare_all_comprehensive.jl`
