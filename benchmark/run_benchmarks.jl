"""
    run_benchmarks.jl

Main entry point for running all DBN.jl benchmarks.

Usage:
    julia benchmark/run_benchmarks.jl [options]

Options:
    --generate-data     Generate test data before benchmarking
    --throughput-only   Run only throughput benchmarks (faster)
    --suite-only        Run only BenchmarkTools suite (detailed)
    --quick             Quick benchmark with small datasets only
    --data-dir DIR      Use custom data directory (default: benchmark/data)
    --runs N            Number of runs for throughput benchmarks (default: 5)
"""

using Pkg

# Ensure we're in the right environment
if !haskey(Pkg.project().dependencies, "DBN")
    error("DBN package not found. Make sure you're in the DBN.jl project directory.")
end

# Activate the project
Pkg.activate(".")

# Load DBN
using DBN
using Printf
using Dates

"""
    parse_args(args)

Parse command-line arguments.
"""
function parse_args(args)
    options = Dict{Symbol, Any}(
        :generate_data => false,
        :throughput_only => false,
        :suite_only => false,
        :quick => false,
        :data_dir => "benchmark/data",
        :runs => 5
    )

    i = 1
    while i <= length(args)
        arg = args[i]

        if arg == "--generate-data"
            options[:generate_data] = true
        elseif arg == "--throughput-only"
            options[:throughput_only] = true
        elseif arg == "--suite-only"
            options[:suite_only] = true
        elseif arg == "--quick"
            options[:quick] = true
        elseif arg == "--data-dir"
            i += 1
            if i <= length(args)
                options[:data_dir] = args[i]
            else
                error("--data-dir requires a directory path")
            end
        elseif arg == "--runs"
            i += 1
            if i <= length(args)
                options[:runs] = parse(Int, args[i])
            else
                error("--runs requires a number")
            end
        elseif arg == "--help" || arg == "-h"
            print_help()
            exit(0)
        else
            @warn "Unknown argument: $arg"
        end

        i += 1
    end

    return options
end

"""
    print_help()

Print usage information.
"""
function print_help()
    println("""
    DBN.jl Benchmark Suite

    Usage:
        julia benchmark/run_benchmarks.jl [options]

    Options:
        --generate-data     Generate test data before benchmarking
        --throughput-only   Run only throughput benchmarks (faster)
        --suite-only        Run only BenchmarkTools suite (detailed)
        --quick             Quick benchmark with small datasets only
        --data-dir DIR      Use custom data directory (default: benchmark/data)
        --runs N            Number of runs for throughput benchmarks (default: 5)
        --help, -h          Show this help message

    Examples:
        # Full benchmark suite (generates data, runs all benchmarks)
        julia benchmark/run_benchmarks.jl --generate-data

        # Quick benchmark with existing data
        julia benchmark/run_benchmarks.jl --quick

        # Throughput-only benchmark
        julia benchmark/run_benchmarks.jl --throughput-only

        # Custom data directory
        julia benchmark/run_benchmarks.jl --data-dir /path/to/data
    """)
end

"""
    print_banner()

Print an attractive banner for the benchmark suite.
"""
function print_banner()
    println("\n")
    println("█"^80)
    println("█" * " "^78 * "█")
    println("█" * "        DBN.jl - Databento Binary Encoding Performance Benchmark" * " "^12 * "█")
    println("█" * " "^78 * "█")
    println("█"^80)
    println()
end

"""
    check_data_exists(data_dir)

Check if benchmark data exists.
"""
function check_data_exists(data_dir)
    if !isdir(data_dir)
        return false
    end

    test_files = filter(f -> endswith(f, ".dbn") || endswith(f, ".dbn.zst"),
                       readdir(data_dir))

    return !isempty(test_files)
end

"""
    main()

Main benchmark runner.
"""
function main()
    options = parse_args(ARGS)

    print_banner()

    println("Configuration:")
    println("  Data directory: $(options[:data_dir])")
    println("  Throughput runs: $(options[:runs])")
    println("  Quick mode: $(options[:quick])")
    println()

    # Check if data exists
    data_exists = check_data_exists(options[:data_dir])

    if !data_exists && !options[:generate_data]
        println("⚠️  No test data found in $(options[:data_dir])")
        println()
        println("You need to generate test data first. Run with:")
        println("  julia benchmark/run_benchmarks.jl --generate-data")
        println()
        println("Or generate data separately:")
        println("  julia benchmark/generate_test_data.jl")
        println()
        exit(1)
    end

    # Step 1: Generate test data if requested
    if options[:generate_data]
        println("\n" * "▶"^80)
        println("STEP 1: Generating Test Data")
        println("▶"^80)
        println()

        include("generate_test_data.jl")

        if options[:quick]
            println("Quick mode: Generating small datasets only...")
            # Generate only small files for quick benchmarking
            generate_test_files_quick(options[:data_dir])
        else
            generate_test_files(options[:data_dir])
        end

        println("\n✓ Test data generation complete!")
    end

    # Step 2: Run throughput benchmarks
    if !options[:suite_only]
        println("\n" * "▶"^80)
        println("STEP 2: Throughput Benchmarks (Records/Second)")
        println("▶"^80)
        println()

        include("throughput.jl")
        run_throughput_benchmarks(options[:data_dir], runs=options[:runs])

        println("\n✓ Throughput benchmarks complete!")
    end

    # Step 3: Run BenchmarkTools suite
    if !options[:throughput_only]
        println("\n" * "▶"^80)
        println("STEP 3: Detailed BenchmarkTools Suite")
        println("▶"^80)
        println()

        include("benchmarks.jl")
        results = run_benchmark_suite(options[:data_dir])

        println("\n✓ BenchmarkTools suite complete!")
    end

    # Final summary
    println("\n\n")
    println("█"^80)
    println("█" * " "^78 * "█")
    println("█" * "  BENCHMARK SUITE COMPLETED" * " "^50 * "█")
    println("█" * " "^78 * "█")
    println("█"^80)
    println()
    println("All benchmarks completed successfully at: $(Dates.format(now(), "yyyy-mm-dd HH:MM:SS"))")
    println()
    println("Results saved in:")
    println("  - benchmark/results_*.csv")
    println("  - benchmark/results_*.json")
    println()
end

"""
    generate_test_files_quick(output_dir)

Generate only small test files for quick benchmarking.
"""
function generate_test_files_quick(output_dir)
    mkpath(output_dir)

    sizes = [
        ("1k", 1_000),
        ("10k", 10_000),
    ]

    for (size_label, n_records) in sizes
        println("Generating $size_label records...")

        # TRADES
        trades = generate_trade_messages(n_records)
        metadata = create_metadata(Schema.TRADES, trades, "XNAS")

        trades_file = joinpath(output_dir, "trades.$size_label.dbn")
        write_dbn(trades_file, metadata, trades)

        trades_zst = joinpath(output_dir, "trades.$size_label.dbn.zst")
        write_dbn(trades_zst, metadata, trades)
    end

    println("\nQuick test data generation complete!")
end

# Run main if executed as script
if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
