#!/usr/bin/env julia

"""
Example demonstrating bidirectional format conversion in DBN.jl

This example shows how to:
1. Create sample trade data
2. Export to JSON, CSV, and Parquet
3. Import back from each format to DBN
4. Verify round-trip compatibility
"""

using DBN
using Dates

function main()
    println("🔄 DBN.jl Bidirectional Format Conversion Example")
    println("=" ^ 60)
    
    # Create sample trade data
    println("\n📊 Creating sample trade data...")
    
    metadata = Metadata(
        UInt8(3),                    # DBN version
        "XNAS",                      # dataset
        Schema.TRADES,               # schema
        datetime_to_ts(DateTime(2024, 1, 1, 9, 30)),   # start_ts
        datetime_to_ts(DateTime(2024, 1, 1, 16, 0)),   # end_ts
        UInt64(3),                   # limit
        SType.RAW_SYMBOL,            # stype_in
        SType.RAW_SYMBOL,            # stype_out
        false,                       # ts_out
        String[],                    # symbols
        String[],                    # partial
        String[],                    # not_found
        Tuple{String, String, Int64, Int64}[]  # mappings
    )
    
    # Create sample trades
    trades = [
        TradeMsg(
            RecordHeader(
                UInt8(sizeof(TradeMsg) ÷ DBN.LENGTH_MULTIPLIER),
                RType.MBP_0_MSG,
                UInt16(1),           # publisher_id
                UInt32(12345),       # instrument_id
                datetime_to_ts(DateTime(2024, 1, 1, 9, 30, 0))
            ),
            float_to_price(100.50),  # price
            UInt32(100),             # size
            Action.TRADE,
            Side.BID,
            UInt8(0),                # flags
            UInt8(0),                # depth
            datetime_to_ts(DateTime(2024, 1, 1, 9, 30, 0)),  # ts_recv
            Int32(0),                # ts_in_delta
            UInt32(1)                # sequence
        ),
        TradeMsg(
            RecordHeader(
                UInt8(sizeof(TradeMsg) ÷ DBN.LENGTH_MULTIPLIER),
                RType.MBP_0_MSG,
                UInt16(1),
                UInt32(12345),
                datetime_to_ts(DateTime(2024, 1, 1, 9, 30, 30))
            ),
            float_to_price(100.75),
            UInt32(200),
            Action.TRADE,
            Side.ASK,
            UInt8(0),
            UInt8(0),
            datetime_to_ts(DateTime(2024, 1, 1, 9, 30, 30)),
            Int32(0),
            UInt32(2)
        ),
        TradeMsg(
            RecordHeader(
                UInt8(sizeof(TradeMsg) ÷ DBN.LENGTH_MULTIPLIER),
                RType.MBP_0_MSG,
                UInt16(1),
                UInt32(12345),
                datetime_to_ts(DateTime(2024, 1, 1, 9, 31, 0))
            ),
            float_to_price(101.00),
            UInt32(150),
            Action.TRADE,
            Side.BID,
            UInt8(0),
            UInt8(0),
            datetime_to_ts(DateTime(2024, 1, 1, 9, 31, 0)),
            Int32(0),
            UInt32(3)
        )
    ]
    
    println("   Created $(length(trades)) sample trade records")
    
    # Write original DBN file
    original_file = "sample_trades.dbn"
    write_dbn(original_file, metadata, trades)
    println("   Wrote original DBN file: $original_file")
    
    # Test round-trip conversions
    formats = [
        ("JSON", "sample_trades.json", dbn_to_json, json_to_dbn),
        ("CSV", "sample_trades.csv", dbn_to_csv, csv_to_dbn),
        ("Parquet", "sample_trades.parquet", dbn_to_parquet, parquet_to_dbn)
    ]
    
    println("\n🔄 Testing round-trip conversions...")
    
    for (format_name, intermediate_file, export_func, import_func) in formats
        println("\n   Testing $format_name format:")
        
        # Export to format
        print("      Exporting to $format_name... ")
        try
            export_func(original_file, intermediate_file)
            println("✅")
        catch e
            println("❌ Export failed: $e")
            continue
        end
        
        # Import back to DBN
        roundtrip_file = "roundtrip_$format_name.dbn"
        print("      Importing back to DBN... ")
        try
            if format_name in ["CSV", "Parquet"]
                # These formats need schema specification
                import_func(intermediate_file, roundtrip_file, schema=Schema.TRADES, dataset="XNAS")
            else
                import_func(intermediate_file, roundtrip_file)
            end
            println("✅")
        catch e
            println("❌ Import failed: $e")
            continue
        end
        
        # Verify data integrity
        print("      Verifying data integrity... ")
        try
            original_metadata, original_records = read_dbn_with_metadata(original_file)
            roundtrip_metadata, roundtrip_records = read_dbn_with_metadata(roundtrip_file)
            
            if length(original_records) == length(roundtrip_records)
                println("✅ ($(length(original_records)) records)")
            else
                println("❌ Record count mismatch: $(length(original_records)) vs $(length(roundtrip_records))")
            end
        catch e
            println("❌ Verification failed: $e")
        end
        
        # Clean up intermediate files
        rm(intermediate_file, force=true)
        rm(roundtrip_file, force=true)
    end
    
    # Clean up original file
    rm(original_file, force=true)
    
    println("\n🎉 Round-trip conversion testing complete!")
    println("\nDBN.jl now supports bidirectional conversion between:")
    println("   • DBN ↔ JSON (including JSONL)")
    println("   • DBN ↔ CSV")  
    println("   • DBN ↔ Parquet")
    println("\nThis enables seamless integration with data analysis workflows!")
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end