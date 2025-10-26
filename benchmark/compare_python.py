#!/usr/bin/env python3
"""
compare_python.py

Benchmark Python databento client performance for comparison with Julia DBN.jl.

This script measures read throughput of the Python databento package to compare against:
- Julia: DBN.jl package
- Rust: Official Databento dbn CLI

Installation:
    pip install databento

Usage:
    python benchmark/compare_python.py [--data-dir DIR] [--runs N]
"""

import sys
import os
import time
import statistics
from pathlib import Path
from typing import List, Tuple, Optional

try:
    from databento import DBNStore
except ImportError:
    print("ERROR: databento package not installed")
    print("\nTo install:")
    print("  pip install databento")
    sys.exit(1)


def benchmark_python_read(filepath: str, runs: int = 5) -> dict:
    """
    Benchmark Python dbn read performance.

    Args:
        filepath: Path to DBN file
        runs: Number of benchmark runs

    Returns:
        Dictionary with benchmark results
    """
    # Warmup - read once to get record count
    record_count = 0
    store = DBNStore.from_file(filepath)
    for _ in store:
        record_count += 1

    times = []
    for _ in range(runs):
        time.sleep(0.1)  # Small pause between runs

        start = time.perf_counter()
        count = 0
        store = DBNStore.from_file(filepath)
        for _ in store:
            count += 1
        elapsed = time.perf_counter() - start

        times.append(elapsed)
        assert count == record_count, f"Record count mismatch: {count} != {record_count}"

    mean_time = statistics.mean(times)
    std_time = statistics.stdev(times) if len(times) > 1 else 0.0
    throughput = record_count / mean_time

    return {
        'records': record_count,
        'mean_time': mean_time,
        'std_time': std_time,
        'throughput': throughput,
        'times': times
    }


def format_number(n: int) -> str:
    """Format number with comma separators."""
    return f"{n:,}"


def format_throughput(throughput: float) -> str:
    """Format throughput in M rec/s."""
    return f"{throughput / 1e6:.2f} M/s"


def run_benchmarks(data_dir: str, runs: int = 5):
    """
    Run Python dbn benchmarks on all test files.

    Args:
        data_dir: Directory containing test DBN files
        runs: Number of runs per file
    """
    print("=" * 70)
    print("  Python databento Performance Benchmark")
    print("=" * 70)
    print()
    print(f"Data directory: {data_dir}")
    print(f"Runs per test: {runs}")
    print(f"Python version: {sys.version.split()[0]}")
    print()

    # Find test files (uncompressed only for now)
    data_path = Path(data_dir)
    test_files = sorted([
        f for f in data_path.glob("*.dbn")
        if not f.name.endswith(".zst")
    ])

    if not test_files:
        print(f"ERROR: No test files found in {data_dir}")
        sys.exit(1)

    print(f"Found {len(test_files)} test files\n")

    results = []

    for filepath in test_files:
        filename = filepath.name
        filesize_mb = filepath.stat().st_size / (1024 ** 2)

        print(f"Testing: {filename} ({filesize_mb:.2f} MB)")
        print("-" * 70)

        try:
            result = benchmark_python_read(str(filepath), runs=runs)

            throughput_str = format_throughput(result['throughput'])
            print(f"  Python dbn:    {throughput_str} "
                  f"({result['mean_time']:.3f} s ± {result['std_time']:.3f} s)")
            print(f"  Records:       {format_number(result['records'])}")

            results.append({
                'file': filename,
                'records': result['records'],
                'throughput_mrec_s': result['throughput'] / 1e6,
                'mean_time': result['mean_time'],
                'std_time': result['std_time']
            })

        except Exception as e:
            print(f"  ERROR: {e}")
            import traceback
            traceback.print_exc()

        print()

    # Print summary
    print_summary(results)

    return results


def print_summary(results: List[dict]):
    """Print summary table of results."""
    if not results:
        return

    print("\n" + "=" * 70)
    print("  SUMMARY")
    print("=" * 70)
    print()

    # Header
    print(f"{'File':<30} {'Records':>12} {'Throughput':>12} {'Time (s)':>12}")
    print("-" * 70)

    # Results
    for r in results:
        print(f"{r['file']:<30} {format_number(r['records']):>12} "
              f"{r['throughput_mrec_s']:>11.2f} M/s {r['mean_time']:>11.3f}")

    print()

    # Average
    avg_throughput = statistics.mean([r['throughput_mrec_s'] for r in results])
    print(f"Average throughput: {avg_throughput:.2f} M rec/s")
    print()


def main():
    """Main entry point."""
    import argparse

    parser = argparse.ArgumentParser(
        description="Benchmark Python databento-dbn read performance"
    )
    parser.add_argument(
        '--data-dir',
        default='benchmark/data',
        help='Directory containing test DBN files (default: benchmark/data)'
    )
    parser.add_argument(
        '--runs',
        type=int,
        default=5,
        help='Number of runs per file (default: 5)'
    )

    args = parser.parse_args()

    run_benchmarks(args.data_dir, runs=args.runs)


if __name__ == '__main__':
    main()
