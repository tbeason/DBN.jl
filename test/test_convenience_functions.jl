using Test
using DBN
using Dates

@testset "Convenience Functions" begin

    @testset "Market Depth Readers" begin
        # Test read_trades
        trades_file = joinpath("tests", "data", "trades.10k.dbn")
        if isfile(trades_file)
            @testset "read_trades" begin
                trades = read_trades(trades_file)
                @test !isempty(trades)
                @test all(r -> isa(r, TradeMsg), trades)
            end
        end

        # Test read_mbo
        mbo_file = joinpath("tests", "data", "mbo.10k.dbn")
        if isfile(mbo_file)
            @testset "read_mbo" begin
                mbos = read_mbo(mbo_file)
                @test !isempty(mbos)
                @test all(r -> isa(r, MBOMsg), mbos)
            end
        end

        # Test read_mbp1 and read_tbbo (both use MBP1Msg)
        mbp1_file = joinpath("tests", "data", "test_data.mbp-1.dbn")
        if isfile(mbp1_file)
            @testset "read_mbp1" begin
                mbp1s = read_mbp1(mbp1_file)
                @test !isempty(mbp1s)
                @test all(r -> isa(r, MBP1Msg), mbp1s)
            end

            @testset "read_tbbo" begin
                tbbos = read_tbbo(mbp1_file)
                @test !isempty(tbbos)
                @test all(r -> isa(r, MBP1Msg), tbbos)
                # Should be identical to read_mbp1
                mbp1s = read_mbp1(mbp1_file)
                @test length(tbbos) == length(mbp1s)
            end
        end

        # Test read_mbp10
        mbp10_file = joinpath("tests", "data", "test_data.mbp-10.dbn")
        if isfile(mbp10_file)
            @testset "read_mbp10" begin
                mbp10s = read_mbp10(mbp10_file)
                @test !isempty(mbp10s)
                @test all(r -> isa(r, MBP10Msg), mbp10s)
            end
        end
    end

    @testset "OHLCV Readers" begin
        # Test generic read_ohlcv
        ohlcv_file = joinpath("tests", "data", "ohlcv.10k.dbn")
        if isfile(ohlcv_file)
            @testset "read_ohlcv" begin
                ohlcvs = read_ohlcv(ohlcv_file)
                @test !isempty(ohlcvs)
                @test all(r -> isa(r, OHLCVMsg), ohlcvs)
            end
        end

        # Test interval-specific OHLCV readers
        ohlcv_1s_file = joinpath("tests", "data", "test_data.ohlcv-1s.dbn")
        if isfile(ohlcv_1s_file)
            @testset "read_ohlcv_1s" begin
                ohlcvs = read_ohlcv_1s(ohlcv_1s_file)
                @test !isempty(ohlcvs)
                @test all(r -> isa(r, OHLCVMsg), ohlcvs)
            end

            @testset "read_ohlcv_1m" begin
                # Same file for now - in practice would have different files
                ohlcvs = read_ohlcv_1m(ohlcv_1s_file)
                @test !isempty(ohlcvs)
                @test all(r -> isa(r, OHLCVMsg), ohlcvs)
            end

            @testset "read_ohlcv_1h" begin
                ohlcvs = read_ohlcv_1h(ohlcv_1s_file)
                @test !isempty(ohlcvs)
                @test all(r -> isa(r, OHLCVMsg), ohlcvs)
            end

            @testset "read_ohlcv_1d" begin
                ohlcvs = read_ohlcv_1d(ohlcv_1s_file)
                @test !isempty(ohlcvs)
                @test all(r -> isa(r, OHLCVMsg), ohlcvs)
            end
        end
    end

    @testset "Consolidated/BBO Readers" begin
        # Note: These test files may not exist - tests will be skipped if not found

        @testset "read_cmbp1" begin
            # Would test with actual cmbp1 file if available
            @test isdefined(DBN, :read_cmbp1)
        end

        @testset "read_cbbo1s" begin
            @test isdefined(DBN, :read_cbbo1s)
        end

        @testset "read_cbbo1m" begin
            @test isdefined(DBN, :read_cbbo1m)
        end

        @testset "read_tcbbo" begin
            @test isdefined(DBN, :read_tcbbo)
        end

        @testset "read_bbo1s" begin
            @test isdefined(DBN, :read_bbo1s)
        end

        @testset "read_bbo1m" begin
            @test isdefined(DBN, :read_bbo1m)
        end
    end

    @testset "Callback Streaming Functions" begin
        trades_file = joinpath("tests", "data", "trades.10k.dbn")

        if isfile(trades_file)
            @testset "foreach_trade" begin
                count = Ref(0)
                foreach_trade(trades_file) do trade
                    count[] += 1
                    @test isa(trade, TradeMsg)
                end
                @test count[] > 0
            end
        end

        mbo_file = joinpath("tests", "data", "mbo.10k.dbn")
        if isfile(mbo_file)
            @testset "foreach_mbo" begin
                count = Ref(0)
                foreach_mbo(mbo_file) do mbo
                    count[] += 1
                    @test isa(mbo, MBOMsg)
                end
                @test count[] > 0
            end
        end

        mbp1_file = joinpath("tests", "data", "test_data.mbp-1.dbn")
        if isfile(mbp1_file)
            @testset "foreach_mbp1" begin
                count = Ref(0)
                foreach_mbp1(mbp1_file) do mbp1
                    count[] += 1
                    @test isa(mbp1, MBP1Msg)
                end
                @test count[] > 0
            end

            @testset "foreach_tbbo" begin
                count = Ref(0)
                foreach_tbbo(mbp1_file) do tbbo
                    count[] += 1
                    @test isa(tbbo, MBP1Msg)
                end
                @test count[] > 0
            end
        end

        mbp10_file = joinpath("tests", "data", "test_data.mbp-10.dbn")
        if isfile(mbp10_file)
            @testset "foreach_mbp10" begin
                count = Ref(0)
                foreach_mbp10(mbp10_file) do mbp10
                    count[] += 1
                    @test isa(mbp10, MBP10Msg)
                end
                @test count[] > 0
            end
        end

        ohlcv_file = joinpath("tests", "data", "test_data.ohlcv-1s.dbn")
        if isfile(ohlcv_file)
            @testset "foreach_ohlcv" begin
                count = Ref(0)
                foreach_ohlcv(ohlcv_file) do ohlcv
                    count[] += 1
                    @test isa(ohlcv, OHLCVMsg)
                end
                @test count[] > 0
            end

            @testset "foreach_ohlcv_1s" begin
                count = Ref(0)
                foreach_ohlcv_1s(ohlcv_file) do ohlcv
                    count[] += 1
                    @test isa(ohlcv, OHLCVMsg)
                end
                @test count[] > 0
            end

            @testset "foreach_ohlcv_1m" begin
                count = Ref(0)
                foreach_ohlcv_1m(ohlcv_file) do ohlcv
                    count[] += 1
                    @test isa(ohlcv, OHLCVMsg)
                end
                @test count[] > 0
            end

            @testset "foreach_ohlcv_1h" begin
                count = Ref(0)
                foreach_ohlcv_1h(ohlcv_file) do ohlcv
                    count[] += 1
                    @test isa(ohlcv, OHLCVMsg)
                end
                @test count[] > 0
            end

            @testset "foreach_ohlcv_1d" begin
                count = Ref(0)
                foreach_ohlcv_1d(ohlcv_file) do ohlcv
                    count[] += 1
                    @test isa(ohlcv, OHLCVMsg)
                end
                @test count[] > 0
            end
        end
    end

    @testset "Function Existence" begin
        # Ensure all documented convenience functions exist
        @test isdefined(DBN, :foreach_cmbp1)
        @test isdefined(DBN, :foreach_cbbo1s)
        @test isdefined(DBN, :foreach_cbbo1m)
        @test isdefined(DBN, :foreach_tcbbo)
        @test isdefined(DBN, :foreach_bbo1s)
        @test isdefined(DBN, :foreach_bbo1m)
    end
end
