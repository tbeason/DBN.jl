#!/usr/bin/env julia
# Add the missing type-stable helper functions to decode.jl

println("Adding missing helper functions to decode.jl...")

# Read current refactored file
lines = readlines("src/decode.jl")

# Find insertion point (after read_record_dispatch ends, before read_imbalance_msg)
insert_line = findfirst(l -> occursin("# Remaining type-stable reader functions", l), lines)
if insert_line === nothing
    error("Could not find insertion point")
end

println("Inserting at line $insert_line")

# Read the backup to extract original implementations
backup_lines = readlines("src/decode.jl.backup_before_refactor")

# Helper functions to add (extracted from original mega-function)
new_functions = String[]

# Add header comment
push!(new_functions, "# Type-stable reader functions for each record type - eliminates boxing/unboxing")
push!(new_functions, "")

# 1. MBO Message
push!(new_functions, "@inline function read_mbo_msg(decoder::DBNDecoder, hd::RecordHeader)")
push!(new_functions, "    ts_recv = read(decoder.io, Int64)")
push!(new_functions, "    order_id = read(decoder.io, UInt64)")
push!(new_functions, "    size = read(decoder.io, UInt32)")
push!(new_functions, "    flags = read(decoder.io, UInt8)")
push!(new_functions, "    channel_id = read(decoder.io, UInt8)")
push!(new_functions, "    action = safe_action(read(decoder.io, UInt8))")
push!(new_functions, "    side = safe_side(read(decoder.io, UInt8))")
push!(new_functions, "    price = read(decoder.io, Int64)")
push!(new_functions, "    ts_in_delta = read(decoder.io, Int32)")
push!(new_functions, "    sequence = read(decoder.io, UInt32)")
push!(new_functions, "    return MBOMsg(hd, order_id, price, size, flags, channel_id, action, side, ts_recv, ts_in_delta, sequence)")
push!(new_functions, "end")
push!(new_functions, "")

# 2. Trade Message (MBP_0)
push!(new_functions, "@inline function read_trade_msg(decoder::DBNDecoder, hd::RecordHeader)")
push!(new_functions, "    price = read(decoder.io, Int64)")
push!(new_functions, "    size = read(decoder.io, UInt32)")
push!(new_functions, "    action = safe_action(read(decoder.io, UInt8))")
push!(new_functions, "    side = safe_side(read(decoder.io, UInt8))")
push!(new_functions, "    flags = read(decoder.io, UInt8)")
push!(new_functions, "    depth = read(decoder.io, UInt8)")
push!(new_functions, "    ts_recv = read(decoder.io, Int64)")
push!(new_functions, "    ts_in_delta = read(decoder.io, Int32)")
push!(new_functions, "    sequence = read(decoder.io, UInt32)")
push!(new_functions, "    return TradeMsg(hd, price, size, action, side, flags, depth, ts_recv, ts_in_delta, sequence)")
push!(new_functions, "end")
push!(new_functions, "")

# 3. MBP1 Message
push!(new_functions, "@inline function read_mbp1_msg(decoder::DBNDecoder, hd::RecordHeader)")
push!(new_functions, "    price = read(decoder.io, Int64)")
push!(new_functions, "    size = read(decoder.io, UInt32)")
push!(new_functions, "    action = safe_action(read(decoder.io, UInt8))")
push!(new_functions, "    side = safe_side(read(decoder.io, UInt8))")
push!(new_functions, "    flags = read(decoder.io, UInt8)")
push!(new_functions, "    depth = read(decoder.io, UInt8)")
push!(new_functions, "    ts_recv = read(decoder.io, Int64)")
push!(new_functions, "    ts_in_delta = read(decoder.io, Int32)")
push!(new_functions, "    sequence = read(decoder.io, UInt32)")
push!(new_functions, "    bid_px = read(decoder.io, Int64)")
push!(new_functions, "    ask_px = read(decoder.io, Int64)")
push!(new_functions, "    bid_sz = read(decoder.io, UInt32)")
push!(new_functions, "    ask_sz = read(decoder.io, UInt32)")
push!(new_functions, "    bid_ct = read(decoder.io, UInt32)")
push!(new_functions, "    ask_ct = read(decoder.io, UInt32)")
push!(new_functions, "    levels = BidAskPair(bid_px, ask_px, bid_sz, ask_sz, bid_ct, ask_ct)")
push!(new_functions, "    return MBP1Msg(hd, price, size, action, side, flags, depth, ts_recv, ts_in_delta, sequence, levels)")
push!(new_functions, "end")
push!(new_functions, "")

# 4. MBP10 Message
push!(new_functions, "@inline function read_mbp10_msg(decoder::DBNDecoder, hd::RecordHeader)")
push!(new_functions, "    price = read(decoder.io, Int64)")
push!(new_functions, "    size = read(decoder.io, UInt32)")
push!(new_functions, "    action = safe_action(read(decoder.io, UInt8))")
push!(new_functions, "    side = safe_side(read(decoder.io, UInt8))")
push!(new_functions, "    flags = read(decoder.io, UInt8)")
push!(new_functions, "    depth = read(decoder.io, UInt8)")
push!(new_functions, "    ts_recv = read(decoder.io, Int64)")
push!(new_functions, "    ts_in_delta = read(decoder.io, Int32)")
push!(new_functions, "    sequence = read(decoder.io, UInt32)")
push!(new_functions, "    levels = ntuple(10) do _")
push!(new_functions, "        bid_px = read(decoder.io, Int64)")
push!(new_functions, "        ask_px = read(decoder.io, Int64)")
push!(new_functions, "        bid_sz = read(decoder.io, UInt32)")
push!(new_functions, "        ask_sz = read(decoder.io, UInt32)")
push!(new_functions, "        bid_ct = read(decoder.io, UInt32)")
push!(new_functions, "        ask_ct = read(decoder.io, UInt32)")
push!(new_functions, "        BidAskPair(bid_px, ask_px, bid_sz, ask_sz, bid_ct, ask_ct)")
push!(new_functions, "    end")
push!(new_functions, "    return MBP10Msg(hd, price, size, action, side, flags, depth, ts_recv, ts_in_delta, sequence, levels)")
push!(new_functions, "end")
push!(new_functions, "")

# 5. OHLCV Message
push!(new_functions, "@inline function read_ohlcv_msg(decoder::DBNDecoder, hd::RecordHeader)")
push!(new_functions, "    open = read(decoder.io, Int64)")
push!(new_functions, "    high = read(decoder.io, Int64)")
push!(new_functions, "    low = read(decoder.io, Int64)")
push!(new_functions, "    close = read(decoder.io, Int64)")
push!(new_functions, "    volume = read(decoder.io, UInt64)")
push!(new_functions, "    return OHLCVMsg(hd, open, high, low, close, volume)")
push!(new_functions, "end")
push!(new_functions, "")

# 6. Status Message
push!(new_functions, "@inline function read_status_msg(decoder::DBNDecoder, hd::RecordHeader)")
push!(new_functions, "    ts_recv = read(decoder.io, UInt64)")
push!(new_functions, "    action = read(decoder.io, UInt16)")
push!(new_functions, "    reason = read(decoder.io, UInt16)")
push!(new_functions, "    trading_event = read(decoder.io, UInt16)")
push!(new_functions, "    is_trading = read(decoder.io, UInt8)")
push!(new_functions, "    is_quoting = read(decoder.io, UInt8)")
push!(new_functions, "    is_short_sell_restricted = read(decoder.io, UInt8)")
push!(new_functions, "    _ = read(decoder.io, 7)")
push!(new_functions, "    return StatusMsg(hd, ts_recv, action, reason, trading_event, is_trading, is_quoting, is_short_sell_restricted)")
push!(new_functions, "end")
push!(new_functions, "")

# 7. InstrumentDef dispatcher
push!(new_functions, "@inline function read_instrument_def_msg(decoder::DBNDecoder, hd::RecordHeader)")
push!(new_functions, "    start_pos = position(decoder.io)")
push!(new_functions, "    record_size_bytes = hd.length * LENGTH_MULTIPLIER")
push!(new_functions, "    body_size = record_size_bytes - 16")
push!(new_functions, "    if body_size == 384")
push!(new_functions, "        return read_instrument_def_v2(decoder, hd)")
push!(new_functions, "    else")
push!(new_functions, "        return read_instrument_def_v3(decoder, hd)")
push!(new_functions, "    end")
push!(new_functions, "end")
push!(new_functions, "")

# Note: The full v2 and v3 implementations are too long to include inline here
# They should already be in the backup file. Let's extract them.
println("Extracting InstrumentDef v2 and v3 implementations...")

# Find the InstrumentDef v2 block (lines with body_size == 384)
v2_start = findfirst(l -> occursin("if body_size == 384", l), backup_lines)
v2_end = findnext(l -> occursin("else", l) && occursin("DBN V3", backup_lines[findnext(x->x==l, backup_lines, 1)+1]), backup_lines, v2_start)

if v2_start !== nothing && v2_end !== nothing
    println("Extracting V2: lines $v2_start to $(v2_end-1)")
    # Convert the v2 block into a function
    push!(new_functions, "@inline function read_instrument_def_v2(decoder::DBNDecoder, hd::RecordHeader)")
    # Extract v2 body (skip the if statement, take everything until else)
    for i in (v2_start+2):(v2_end-2)
        line = backup_lines[i]
        # Adjust indentation
        push!(new_functions, replace(line, r"^            " => "    "))
    end
    push!(new_functions, "end")
    push!(new_functions, "")
end

# Extract V3
v3_start = v2_end
v3_end = findnext(l -> occursin("return InstrumentDefMsg", l), backup_lines, v3_start+10)
if v3_end !== nothing
    v3_end = findnext(l -> strip(l) == ")", backup_lines, v3_end)
end

if v3_start !== nothing && v3_end !== nothing
    println("Extracting V3: lines $v3_start to $v3_end")
    push!(new_functions, "@inline function read_instrument_def_v3(decoder::DBNDecoder, hd::RecordHeader)")
    for i in (v3_start+2):(v3_end)
        line = backup_lines[i]
        # Adjust indentation
        push!(new_functions, replace(line, r"^            " => "    "))
    end
    push!(new_functions, "end")
    push!(new_functions, "")
end

# Now insert the new functions into the file
new_lines = vcat(
    lines[1:insert_line-1],
    new_functions,
    lines[insert_line:end]
)

# Write the updated file
open("src/decode.jl", "w") do f
    for line in new_lines
        println(f, line)
    end
end

println("✓ Added $(length(new_functions)) lines of helper functions")
println("New file: $(length(new_lines)) lines (was $(length(lines)))")
