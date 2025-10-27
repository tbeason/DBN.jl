"""
Benchmark Python databento-dbn package (Rust wrapper) for direct comparison.
"""

import databento_dbn as dbn
import time
import sys
from pathlib import Path

def benchmark_python_read(filepath, iterations=5):
    print(f"Benchmarking Python databento-dbn on: {filepath}")
    print("=" * 70)

    # Warmup
    with open(filepath, 'rb') as f:
        data = dbn.from_dbn(f)
        record_count = len(data)

    print(f"File contains {record_count:,} records")
    print(f"\nRunning {iterations} iterations...")

    times = []
    for i in range(iterations):
        time.sleep(0.1)

        start = time.perf_counter()
        with open(filepath, 'rb') as f:
            data = dbn.from_dbn(f)
        elapsed = time.perf_counter() - start

        times.append(elapsed)
        throughput = record_count / elapsed / 1e6
        print(f"  Iteration {i+1}: {elapsed:.4f} s ({throughput:.2f} M rec/s)")

    mean_time = sum(times) / len(times)
    best_time = min(times)
    mean_throughput = record_count / mean_time
    best_throughput = record_count / best_time

    print(f"\nResults:")
    print(f"  Mean: {mean_time:.4f} s ({mean_throughput/1e6:.2f} M rec/s)")
    print(f"  Best: {best_time:.4f} s ({best_throughput/1e6:.2f} M rec/s)")

    return {
        'records': record_count,
        'mean_time': mean_time,
        'best_time': best_time,
        'mean_throughput': mean_throughput,
        'best_throughput': best_throughput
    }

if __name__ == '__main__':
    if len(sys.argv) < 2:
        filepath = 'benchmark/data/trades.1m.dbn'
    else:
        filepath = sys.argv[1]

    if not Path(filepath).exists():
        print(f"ERROR: File not found: {filepath}")
        sys.exit(1)

    benchmark_python_read(filepath)
