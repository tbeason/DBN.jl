"""
    generate_test_data.jl

Generate large DBN test files for performance benchmarking.

This script creates DBN files of various sizes with realistic market data
to enable thorough performance testing.
"""

using DBN
using Dates
using Printf

"""
    generate_trade_messages(n_records::Int;
                           start_time=DateTime(2024, 1, 1, 9, 30),
                           instrument_id=12345,
                           publisher_id=1)

Generate a vector of `n_records` synthetic trade messages with realistic price movements.

# Arguments
- `n_records`: Number of trade records to generate
- `start_time`: Starting timestamp for the first trade
- `instrument_id`: Instrument ID for the trades
- `publisher_id`: Publisher ID for the trades

# Returns
- `Vector{TradeMsg}`: Vector of synthetic trade messages
"""
function generate_trade_messages(n_records::Int;
                                start_time=DateTime(2024, 1, 1, 9, 30),
                                instrument_id=12345,
                                publisher_id=1)
    trades = TradeMsg[]
    sizehint!(trades, n_records)

    # Starting price around $100
    base_price = 100.0
    current_price = base_price

    # Convert start time to nanoseconds
    current_ts = datetime_to_ts(start_time)

    for i in 1:n_records
        # Simulate price movement (random walk with small steps)
        price_change = (rand() - 0.5) * 0.10  # +/- $0.05
        current_price = max(base_price * 0.9, min(base_price * 1.1, current_price + price_change))

        # Random size between 1 and 1000 shares
        size = UInt32(rand(1:1000))

        # Random side
        side = rand([Side.BID, Side.ASK])

        # Increment timestamp by ~100-500 microseconds
        current_ts += rand(100_000:500_000)

        trade = TradeMsg(
            RecordHeader(
                UInt8(sizeof(TradeMsg) ÷ 4),  # length in 4-byte units
                RType.MBP_0_MSG,
                UInt16(publisher_id),
                UInt32(instrument_id),
                UInt64(current_ts)
            ),
            float_to_price(current_price),
            size,
            Action.TRADE,
            side,
            UInt8(0),      # flags
            UInt8(0),      # depth
            current_ts,    # ts_recv
            Int32(0),      # ts_in_delta
            UInt32(i)      # sequence
        )

        push!(trades, trade)
    end

    return trades
end

"""
    generate_mbo_messages(n_records::Int; kwargs...)

Generate synthetic market-by-order messages.
"""
function generate_mbo_messages(n_records::Int;
                              start_time=DateTime(2024, 1, 1, 9, 30),
                              instrument_id=12345,
                              publisher_id=1)
    messages = MBOMsg[]
    sizehint!(messages, n_records)

    base_price = 100.0
    current_ts = datetime_to_ts(start_time)
    order_id_counter = UInt64(1000000)

    for i in 1:n_records
        price_offset = (rand() - 0.5) * 1.0
        price = base_price + price_offset
        size = UInt32(rand(1:1000))
        side = rand([Side.BID, Side.ASK])
        action = rand([Action.ADD, Action.MODIFY, Action.CANCEL, Action.TRADE])

        current_ts += rand(10_000:100_000)
        order_id_counter += 1

        msg = MBOMsg(
            RecordHeader(
                UInt8(sizeof(MBOMsg) ÷ 4),
                RType.MBO_MSG,
                UInt16(publisher_id),
                UInt32(instrument_id),
                UInt64(current_ts)
            ),
            order_id_counter,
            float_to_price(price),
            size,
            UInt8(0),      # flags
            UInt8(1),      # channel_id
            action,
            side,
            current_ts,
            Int32(0),
            UInt32(i)
        )

        push!(messages, msg)
    end

    return messages
end

"""
    generate_ohlcv_messages(n_records::Int; kwargs...)

Generate synthetic OHLCV messages.
"""
function generate_ohlcv_messages(n_records::Int;
                                start_time=DateTime(2024, 1, 1, 9, 30),
                                instrument_id=12345,
                                publisher_id=1)
    messages = OHLCVMsg[]
    sizehint!(messages, n_records)

    base_price = 100.0
    current_ts = datetime_to_ts(start_time)

    for i in 1:n_records
        # Each bar is 1 minute apart
        current_ts += 60_000_000_000  # 60 seconds in nanoseconds

        open_price = base_price + (rand() - 0.5) * 2.0
        high = open_price + rand() * 1.0
        low = open_price - rand() * 1.0
        close_price = open_price + (rand() - 0.5) * 1.5
        volume = UInt64(rand(1000:100000))

        msg = OHLCVMsg(
            RecordHeader(
                UInt8(sizeof(OHLCVMsg) ÷ 4),
                RType.OHLCV_1M_MSG,
                UInt16(publisher_id),
                UInt32(instrument_id),
                UInt64(current_ts)
            ),
            float_to_price(open_price),
            float_to_price(high),
            float_to_price(low),
            float_to_price(close_price),
            volume
        )

        push!(messages, msg)
    end

    return messages
end

"""
    create_metadata(schema::Schema.T, records, dataset="TEST")

Create metadata for a set of records.
"""
function create_metadata(schema::Schema.T, records, dataset="TEST")
    start_ts = records[1].hd.ts_event
    end_ts = records[end].hd.ts_event

    return Metadata(
        UInt8(DBN_VERSION),
        dataset,
        schema,
        start_ts,
        end_ts,
        UInt64(length(records)),
        SType.RAW_SYMBOL,
        SType.RAW_SYMBOL,
        false,
        String[],
        String[],
        String[],
        Tuple{String, String, Int64, Int64}[]
    )
end

"""
    generate_test_files(output_dir="benchmark/data")

Generate a suite of test files with various sizes and types.

Creates the following files:
- Small files (1K, 10K records) - for quick tests
- Medium files (100K, 1M records) - for realistic benchmarks
- Large files (10M records) - for stress testing
- Different message types (TRADES, MBO, OHLCV)
- Both compressed and uncompressed versions
"""
function generate_test_files(output_dir="benchmark/data")
    mkpath(output_dir)

    sizes = [
        ("1k", 1_000),
        ("10k", 10_000),
        ("100k", 100_000),
        ("1m", 1_000_000),
        ("10m", 10_000_000),
    ]

    for (size_label, n_records) in sizes
        println("\nGenerating $size_label records...")

        # TRADES
        println("  - trades.$size_label...")
        trades = generate_trade_messages(n_records)
        metadata = create_metadata(Schema.TRADES, trades, "XNAS")

        trades_file = joinpath(output_dir, "trades.$size_label.dbn")
        write_dbn(trades_file, metadata, trades)

        # Create compressed version
        trades_zst = joinpath(output_dir, "trades.$size_label.dbn.zst")
        write_dbn(trades_zst, metadata, trades)

        # MBO (skip for 10M to save time)
        if n_records <= 1_000_000
            println("  - mbo.$size_label...")
            mbo = generate_mbo_messages(n_records)
            metadata_mbo = create_metadata(Schema.MBO, mbo, "XNAS")

            mbo_file = joinpath(output_dir, "mbo.$size_label.dbn")
            write_dbn(mbo_file, metadata_mbo, mbo)

            mbo_zst = joinpath(output_dir, "mbo.$size_label.dbn.zst")
            write_dbn(mbo_zst, metadata_mbo, mbo)
        end

        # OHLCV (smaller counts since these are aggregated)
        if n_records <= 100_000
            ohlcv_count = min(n_records ÷ 100, 10_000)
            println("  - ohlcv.$size_label ($ohlcv_count bars)...")
            ohlcv = generate_ohlcv_messages(ohlcv_count)
            metadata_ohlcv = create_metadata(Schema.OHLCV_1M, ohlcv, "XNAS")

            ohlcv_file = joinpath(output_dir, "ohlcv.$size_label.dbn")
            write_dbn(ohlcv_file, metadata_ohlcv, ohlcv)

            ohlcv_zst = joinpath(output_dir, "ohlcv.$size_label.dbn.zst")
            write_dbn(ohlcv_zst, metadata_ohlcv, ohlcv)
        end
    end

    println("\n" * "="^60)
    println("Test data generation complete!")
    println("Output directory: $output_dir")
    println("="^60)

    # Print file sizes
    println("\nGenerated files:")
    for file in readdir(output_dir, join=true)
        size_mb = filesize(file) / 1024^2
        @printf "  %-40s %8.2f MB\n" basename(file) size_mb
    end
end

# Run if executed as script
if abspath(PROGRAM_FILE) == @__FILE__
    println("Generating benchmark test data...")
    generate_test_files()
end
