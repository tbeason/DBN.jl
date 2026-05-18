# Phase 11: foreach_record_with_control — typed data path + Union-typed
# control path on the same stream. Used by the DatabentoAPI.jl typed Live
# reader to split data records from gateway control records.

using Test
using DBN

@testset "foreach_record_with_control" begin

    # Build a mixed-record file: TradeMsg interleaved with SystemMsg,
    # SymbolMappingMsg, and ErrorMsg. Mirrors what a live OPRA stream looks
    # like after subscription (mappings + heartbeats + data).
    function build_mixed_file()
        metadata = DBN.Metadata(
            DBN.DBN_VERSION, "TEST.MOCK", DBN.Schema.TRADES,
            Int64(0), nothing, nothing, nothing,
            DBN.SType.INSTRUMENT_ID, false,
            ["AAPL"], String[], String[],
            Tuple{String,String,Int64,Int64}[],
        )

        recs = DBN.DBNRecord[]
        ts0 = Int64(1_700_000_000_000_000_000)

        # SystemMsg first (looks like the live "session start" greeting).
        # Encoder writes: msg + null + code + null, padded to hd.length*4-16.
        # hd.length must cover at least (msg + null + code + null) bytes.
        sys_text = "session started"
        sys_code = "0"
        sys_body = length(sys_text) + 1 + length(sys_code) + 1
        sys_units = UInt8(((16 + sys_body + 3) ÷ 4))
        sys_hd = DBN.RecordHeader(sys_units, DBN.RType.SYSTEM_MSG,
                                  UInt16(0), UInt32(0), ts0)
        push!(recs, DBN.SystemMsg(sys_hd, sys_text, sys_code))

        # Two trades.
        for i in 1:2
            hd = DBN.RecordHeader(UInt8(0), DBN.RType.MBP_0_MSG,
                                  UInt16(1), UInt32(100 + i),
                                  ts0 + i * 1_000_000)
            push!(recs, DBN.TradeMsg(
                hd, Int64(150_000_000_000 + i * 1_000_000), UInt32(100),
                DBN.Action.TRADE, DBN.Side.ASK, UInt8(0), UInt8(1),
                ts0 + i * 1_000_000, Int32(0), UInt32(i),
            ))
        end

        # A SymbolMappingMsg — looks like a gateway-side ID/raw_symbol resolution.
        # hd.length = 44 (4-byte units) matches the v2+ layout the encoder writes
        # at DBN_VERSION = 3:
        #   header(16) + stype_in(1) + sym_in[71] + stype_out(1) + sym_out[71] +
        #   start_ts(8) + end_ts(8) = 176 bytes / 4 = 44 units.
        smap_units = UInt8(44)
        smap_hd = DBN.RecordHeader(smap_units, DBN.RType.SYMBOL_MAPPING_MSG,
                                   UInt16(1), UInt32(100), ts0 + 5_000_000)
        push!(recs, DBN.SymbolMappingMsg(
            smap_hd,
            DBN.SType.RAW_SYMBOL, "AAPL",
            DBN.SType.INSTRUMENT_ID, "100",
            ts0 + 5_000_000, ts0 + 10_000_000_000_000))

        # Three more trades.
        for i in 3:5
            hd = DBN.RecordHeader(UInt8(0), DBN.RType.MBP_0_MSG,
                                  UInt16(1), UInt32(100 + i),
                                  ts0 + i * 1_000_000)
            push!(recs, DBN.TradeMsg(
                hd, Int64(150_000_000_000 + i * 1_000_000), UInt32(100),
                DBN.Action.TRADE, DBN.Side.ASK, UInt8(0), UInt8(1),
                ts0 + i * 1_000_000, Int32(0), UInt32(i),
            ))
        end

        # An ErrorMsg.
        err_text = "test error"
        err_total = 16 + length(err_text) + 1
        err_units = UInt8(((err_total + 3) ÷ 4))
        err_hd = DBN.RecordHeader(err_units, DBN.RType.ERROR_MSG,
                                  UInt16(0), UInt32(0), ts0 + 6_000_000)
        push!(recs, DBN.ErrorMsg(err_hd, err_text))

        tmp, io = mktemp(); close(io)
        DBN.write_dbn(tmp, metadata, recs)
        return tmp
    end

    @testset "routes data vs control correctly" begin
        path = build_mixed_file()
        try
            trades = DBN.TradeMsg[]
            controls = Any[]
            DBN.foreach_record_with_control(
                rec -> push!(trades, rec),
                ctrl -> push!(controls, ctrl),
                path, DBN.TradeMsg)

            @test length(trades) == 5
            @test all(t -> t isa DBN.TradeMsg, trades)
            # Trades arrive in order: indices 1, 2, 3, 4, 5.
            @test [t.sequence for t in trades] == UInt32[1, 2, 3, 4, 5]

            @test length(controls) == 3
            @test any(c -> c isa DBN.SystemMsg, controls)
            @test any(c -> c isa DBN.SymbolMappingMsg, controls)
            @test any(c -> c isa DBN.ErrorMsg, controls)
        finally
            rm(path; force = true)
        end
    end

    @testset "unmatched data rtype does NOT throw (skipped instead)" begin
        # Build a file labelled TRADES but with an MBO record. The
        # mixed-file fallback in read_dbn is permissive; we want the same
        # here — control records that don't match T are forwarded to
        # f_control, but data records of the wrong type are SKIPPED
        # silently (so the live reader doesn't crash on a gateway-side
        # schema change).
        metadata = DBN.Metadata(
            DBN.DBN_VERSION, "TEST.MOCK", DBN.Schema.TRADES,
            Int64(0), nothing, nothing, nothing,
            DBN.SType.INSTRUMENT_ID, false,
            ["AAPL"], String[], String[],
            Tuple{String,String,Int64,Int64}[],
        )
        ts0 = Int64(1_700_000_000_000_000_000)
        recs = DBN.DBNRecord[]
        # One MBO (wrong type for TRADES schema)
        mbo_hd = DBN.RecordHeader(UInt8(14), DBN.RType.MBO_MSG,
                                  UInt16(1), UInt32(101), ts0)
        push!(recs, DBN.MBOMsg(mbo_hd, UInt64(1), Int64(10_000), UInt32(1),
                               UInt8(0), UInt8(0), DBN.Action.ADD,
                               DBN.Side.BID, ts0, Int32(0), UInt32(1)))
        # One trade (expected)
        tr_hd = DBN.RecordHeader(UInt8(0), DBN.RType.MBP_0_MSG,
                                 UInt16(1), UInt32(100), ts0 + 1_000_000)
        push!(recs, DBN.TradeMsg(tr_hd, Int64(150_000_000_000), UInt32(100),
                                 DBN.Action.TRADE, DBN.Side.ASK,
                                 UInt8(0), UInt8(1),
                                 ts0 + 1_000_000, Int32(0), UInt32(1)))

        tmp, io = mktemp(); close(io)
        try
            DBN.write_dbn(tmp, metadata, recs)
            trades = DBN.TradeMsg[]
            controls = Any[]
            # Should NOT throw.
            DBN.foreach_record_with_control(
                rec -> push!(trades, rec),
                ctrl -> push!(controls, ctrl),
                tmp, DBN.TradeMsg)
            @test length(trades) == 1   # MBO was skipped
            @test length(controls) == 0
        finally
            rm(tmp; force = true)
        end
    end

    @testset "unknown rtype is skipped without desyncing the stream" begin
        # Regression test for the skip-length bug: the unknown-rtype branch
        # must skip `length_units * 4 - 2` bytes (record_length is in
        # 4-byte units), not `length_units - 2`. The bug would leave the
        # stream cursor mid-record, corrupting every subsequent record.
        #
        # Construct a stream manually: one valid TradeMsg, then a record
        # with an unknown rtype (0xFE) and length = 8 units (= 32 bytes
        # total, 30 bytes body after the 2-byte header), then a second
        # valid TradeMsg. With the bug the post-unknown TradeMsg would be
        # read at the wrong offset and either fail or yield garbage data.
        metadata = DBN.Metadata(
            DBN.DBN_VERSION, "TEST.MOCK", DBN.Schema.TRADES,
            Int64(0), nothing, nothing, nothing,
            DBN.SType.INSTRUMENT_ID, false,
            ["AAPL"], String[], String[],
            Tuple{String,String,Int64,Int64}[],
        )
        ts0 = Int64(1_700_000_000_000_000_000)

        # Write metadata + first trade via the standard encoder, then
        # append the unknown-rtype bytes + second trade by hand.
        tmp, io = mktemp(); close(io)
        try
            # Use a temp file written via the encoder to get the metadata
            # header + first trade correctly framed.
            tr1 = DBN.TradeMsg(
                DBN.RecordHeader(UInt8(0), DBN.RType.MBP_0_MSG,
                                 UInt16(1), UInt32(100), ts0),
                Int64(100_000_000_000), UInt32(50),
                DBN.Action.TRADE, DBN.Side.ASK, UInt8(0), UInt8(1),
                ts0, Int32(0), UInt32(1))
            DBN.write_dbn(tmp, metadata, DBN.DBNRecord[tr1])

            # Append an unknown-rtype record (8 units = 32 bytes total,
            # body 30 bytes of garbage) + a second TradeMsg.
            tr2 = DBN.TradeMsg(
                DBN.RecordHeader(UInt8(0), DBN.RType.MBP_0_MSG,
                                 UInt16(1), UInt32(200), ts0 + 1),
                Int64(200_000_000_000), UInt32(75),
                DBN.Action.TRADE, DBN.Side.ASK, UInt8(0), UInt8(1),
                ts0 + 1, Int32(0), UInt32(2))

            # Encode tr2 to a temporary buffer to grab its bytes.
            tmp2, io2 = mktemp(); close(io2)
            DBN.write_dbn(tmp2, metadata, DBN.DBNRecord[tr2])
            tr2_bytes = read(tmp2)
            rm(tmp2; force = true)

            # We need just the record portion of tr2_bytes, not the metadata
            # header. The simplest approach: read tr2_bytes minus the metadata.
            # Use the encoder's metadata header to find the record start.
            md_bytes = read(tmp)   # has header + tr1 only
            # md_bytes layout: dbn header + tr1.
            # tr2_bytes layout: dbn header + tr2.
            # The dbn header length is constant for the same metadata, so
            # the record portion of tr2_bytes starts at the same offset as
            # the record portion of md_bytes (which is after the header,
            # i.e. md_bytes[end - tr1_bytes_len + 1 : end]).
            # Easier: compute header length from tr2_bytes - tr1 bytes len.
            # tr1 is a TradeMsg = 48 bytes.
            header_len = length(tr2_bytes) - 48
            tr2_record = tr2_bytes[header_len + 1 : end]

            # Unknown-rtype record: 8 units = 32 bytes total. Layout:
            # [length(1)=8] [rtype(1)=0xFE] [30 bytes body]
            unknown_record = vcat(UInt8[8, 0xFE], rand(UInt8, 30))

            # Append unknown-record + tr2-record to the file.
            open(tmp, "a") do io
                write(io, unknown_record)
                write(io, tr2_record)
            end

            trades = DBN.TradeMsg[]
            controls = Any[]
            DBN.foreach_record_with_control(
                rec -> push!(trades, rec),
                ctrl -> push!(controls, ctrl),
                tmp, DBN.TradeMsg)
            @test length(trades) == 2
            @test trades[1].sequence == UInt32(1)
            @test trades[2].sequence == UInt32(2)
            @test trades[2].price == Int64(200_000_000_000)
            @test length(controls) == 0   # unknown rtype was skipped, not routed
        finally
            rm(tmp; force = true)
        end
    end

    @testset "data-path callback near-zero allocation" begin
        # Generate a pure-data fixture and time the callback path.
        metadata = DBN.Metadata(
            DBN.DBN_VERSION, "TEST.MOCK", DBN.Schema.TRADES,
            Int64(0), nothing, nothing, nothing,
            DBN.SType.INSTRUMENT_ID, false,
            ["AAPL"], String[], String[],
            Tuple{String,String,Int64,Int64}[],
        )
        ts0 = Int64(1_700_000_000_000_000_000)
        n = 10_000
        recs = Vector{DBN.DBNRecord}(undef, n)
        for i in 1:n
            hd = DBN.RecordHeader(UInt8(0), DBN.RType.MBP_0_MSG,
                                  UInt16(1), UInt32(100 + i), ts0 + i)
            recs[i] = DBN.TradeMsg(hd, Int64(150_000_000_000 + i),
                                   UInt32(100), DBN.Action.TRADE, DBN.Side.ASK,
                                   UInt8(0), UInt8(1), ts0 + i, Int32(0), UInt32(i))
        end
        tmp, io = mktemp(); close(io)
        try
            DBN.write_dbn(tmp, metadata, recs)

            # Warmup so the callback compiles.
            count = Ref(0)
            DBN.foreach_record_with_control(
                rec -> count[] += 1,
                ctrl -> nothing,
                tmp, DBN.TradeMsg)
            @test count[] == n

            # Measure data-path allocs alone (no control records in this fixture)
            # and compare to foreach_record's allocation profile for the same
            # data — the typed-data path should be in the same ballpark.
            count[] = 0
            base_allocs = @allocated DBN.foreach_record(
                rec -> count[] += 1, tmp, DBN.TradeMsg)
            @test count[] == n

            count[] = 0
            allocs = @allocated DBN.foreach_record_with_control(
                rec -> count[] += 1,
                ctrl -> nothing,
                tmp, DBN.TradeMsg)
            @test count[] == n
            # Within 2× of foreach_record's allocation profile (the extra
            # closure-capture and dual-callback wiring adds a small fixed
            # overhead). Critically, both should be O(file open) NOT O(n_records).
            @test allocs <= 2 * base_allocs + 4096
        finally
            rm(tmp; force = true)
        end
    end
end
