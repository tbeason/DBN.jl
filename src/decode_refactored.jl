# Remaining type-stable reader functions (continued from main refactor)

@inline function read_imbalance_msg(decoder::DBNDecoder, hd::RecordHeader)
    ts_recv = read(decoder.io, UInt64)
    ref_price = read(decoder.io, Int64)
    auction_time = read(decoder.io, UInt64)
    cont_book_clr_price = read(decoder.io, Int64)
    auct_interest_clr_price = read(decoder.io, Int64)
    ssr_filling_price = read(decoder.io, Int64)
    ind_match_price = read(decoder.io, Int64)
    upper_collar = read(decoder.io, Int64)
    lower_collar = read(decoder.io, Int64)
    paired_qty = read(decoder.io, UInt32)
    total_imbalance_qty = read(decoder.io, UInt32)
    market_imbalance_qty = read(decoder.io, UInt32)
    unpaired_qty = read(decoder.io, UInt32)
    auction_type = read(decoder.io, UInt8)
    side = safe_side(read(decoder.io, UInt8))
    auction_status = read(decoder.io, UInt8)
    freeze_status = read(decoder.io, UInt8)
    num_extensions = read(decoder.io, UInt8)
    unpaired_side = read(decoder.io, UInt8)
    significant_imbalance = read(decoder.io, UInt8)
    _ = read(decoder.io, 1)
    return ImbalanceMsg(hd, ts_recv, ref_price, auction_time, cont_book_clr_price, auct_interest_clr_price, ssr_filling_price, ind_match_price, upper_collar, lower_collar, paired_qty, total_imbalance_qty, market_imbalance_qty, unpaired_qty, auction_type, side, auction_status, freeze_status, num_extensions, unpaired_side, significant_imbalance)
end

@inline function read_stat_msg(decoder::DBNDecoder, hd::RecordHeader)
    ts_recv = read(decoder.io, UInt64)
    ts_ref = read(decoder.io, UInt64)
    price = read(decoder.io, Int64)
    quantity_raw = read(decoder.io, UInt64)
    quantity = if quantity_raw == 0xffffffffffffffff
        typemax(Int64)
    else
        quantity_raw <= typemax(Int64) ? Int64(quantity_raw) : typemax(Int64)
    end
    sequence = read(decoder.io, UInt32)
    ts_in_delta = read(decoder.io, Int32)
    stat_type = read(decoder.io, UInt16)
    channel_id = read(decoder.io, UInt16)
    update_action = read(decoder.io, UInt8)
    stat_flags = read(decoder.io, UInt8)
    _ = read(decoder.io, 18)
    return StatMsg(hd, ts_recv, ts_ref, price, quantity, sequence, ts_in_delta, stat_type, channel_id, update_action, stat_flags)
end

@inline function read_error_msg(decoder::DBNDecoder, hd::RecordHeader)
    msg_bytes = hd.length - 16
    if msg_bytes > 0
        err_data = read(decoder.io, msg_bytes)
        null_pos = findfirst(==(0), err_data)
        if null_pos !== nothing
            err_string = String(err_data[1:null_pos-1])
        else
            err_string = String(err_data)
        end
    else
        err_string = ""
    end
    return ErrorMsg(hd, err_string)
end

@inline function read_symbol_mapping_msg(decoder::DBNDecoder, hd::RecordHeader)
    stype_in = SType.T(read(decoder.io, UInt8))
    _ = read(decoder.io, 3)
    stype_in_len = read(decoder.io, UInt16)
    stype_in_symbol = String(read(decoder.io, stype_in_len))
    stype_out = SType.T(read(decoder.io, UInt8))
    _ = read(decoder.io, 3)
    stype_out_len = read(decoder.io, UInt16)
    stype_out_symbol = String(read(decoder.io, stype_out_len))
    start_ts = read(decoder.io, Int64)
    end_ts = read(decoder.io, Int64)
    return SymbolMappingMsg(hd, stype_in, stype_in_symbol, stype_out, stype_out_symbol, start_ts, end_ts)
end

@inline function read_system_msg(decoder::DBNDecoder, hd::RecordHeader)
    remaining_bytes = hd.length - 16
    if remaining_bytes > 0
        msg_data = read(decoder.io, remaining_bytes)
        null_pos = findfirst(==(0), msg_data)
        if null_pos !== nothing
            msg_string = String(msg_data[1:null_pos-1])
            if null_pos < length(msg_data)
                code_data = msg_data[null_pos+1:end]
                code_null = findfirst(==(0), code_data)
                if code_null !== nothing
                    code_string = String(code_data[1:code_null-1])
                else
                    code_string = String(code_data)
                end
            else
                code_string = ""
            end
        else
            msg_string = String(msg_data)
            code_string = ""
        end
    else
        msg_string = ""
        code_string = ""
    end
    return SystemMsg(hd, msg_string, code_string)
end

@inline function read_cmbp1_msg(decoder::DBNDecoder, hd::RecordHeader)
    price = read(decoder.io, Int64)
    size = read(decoder.io, UInt32)
    action = safe_action(read(decoder.io, UInt8))
    side = safe_side(read(decoder.io, UInt8))
    flags = read(decoder.io, UInt8)
    depth = read(decoder.io, UInt8)
    ts_recv = read(decoder.io, Int64)
    ts_in_delta = read(decoder.io, Int32)
    sequence = read(decoder.io, UInt32)

    bid_px = read(decoder.io, Int64)
    ask_px = read(decoder.io, Int64)
    bid_sz = read(decoder.io, UInt32)
    ask_sz = read(decoder.io, UInt32)
    bid_ct = read(decoder.io, UInt32)
    ask_ct = read(decoder.io, UInt32)
    levels = BidAskPair(bid_px, ask_px, bid_sz, ask_sz, bid_ct, ask_ct)

    return CMBP1Msg(hd, price, size, action, side, flags, depth, ts_recv, ts_in_delta, sequence, levels)
end

@inline function read_cbbo1s_msg(decoder::DBNDecoder, hd::RecordHeader)
    price = read(decoder.io, Int64)
    size = read(decoder.io, UInt32)
    action = safe_action(read(decoder.io, UInt8))
    side = safe_side(read(decoder.io, UInt8))
    flags = read(decoder.io, UInt8)
    depth = read(decoder.io, UInt8)
    ts_recv = read(decoder.io, Int64)
    ts_in_delta = read(decoder.io, Int32)
    sequence = read(decoder.io, UInt32)

    bid_px = read(decoder.io, Int64)
    ask_px = read(decoder.io, Int64)
    bid_sz = read(decoder.io, UInt32)
    ask_sz = read(decoder.io, UInt32)
    bid_ct = read(decoder.io, UInt32)
    ask_ct = read(decoder.io, UInt32)
    levels = BidAskPair(bid_px, ask_px, bid_sz, ask_sz, bid_ct, ask_ct)

    return CBBO1sMsg(hd, price, size, action, side, flags, depth, ts_recv, ts_in_delta, sequence, levels)
end

@inline function read_cbbo1m_msg(decoder::DBNDecoder, hd::RecordHeader)
    price = read(decoder.io, Int64)
    size = read(decoder.io, UInt32)
    action = safe_action(read(decoder.io, UInt8))
    side = safe_side(read(decoder.io, UInt8))
    flags = read(decoder.io, UInt8)
    depth = read(decoder.io, UInt8)
    ts_recv = read(decoder.io, Int64)
    ts_in_delta = read(decoder.io, Int32)
    sequence = read(decoder.io, UInt32)

    bid_px = read(decoder.io, Int64)
    ask_px = read(decoder.io, Int64)
    bid_sz = read(decoder.io, UInt32)
    ask_sz = read(decoder.io, UInt32)
    bid_ct = read(decoder.io, UInt32)
    ask_ct = read(decoder.io, UInt32)
    levels = BidAskPair(bid_px, ask_px, bid_sz, ask_sz, bid_ct, ask_ct)

    return CBBO1mMsg(hd, price, size, action, side, flags, depth, ts_recv, ts_in_delta, sequence, levels)
end

@inline function read_tcbbo_msg(decoder::DBNDecoder, hd::RecordHeader)
    price = read(decoder.io, Int64)
    size = read(decoder.io, UInt32)
    action = safe_action(read(decoder.io, UInt8))
    side = safe_side(read(decoder.io, UInt8))
    flags = read(decoder.io, UInt8)
    depth = read(decoder.io, UInt8)
    ts_recv = read(decoder.io, Int64)
    ts_in_delta = read(decoder.io, Int32)
    sequence = read(decoder.io, UInt32)

    bid_px = read(decoder.io, Int64)
    ask_px = read(decoder.io, Int64)
    bid_sz = read(decoder.io, UInt32)
    ask_sz = read(decoder.io, UInt32)
    bid_ct = read(decoder.io, UInt32)
    ask_ct = read(decoder.io, UInt32)
    levels = BidAskPair(bid_px, ask_px, bid_sz, ask_sz, bid_ct, ask_ct)

    return TCBBOMsg(hd, price, size, action, side, flags, depth, ts_recv, ts_in_delta, sequence, levels)
end

@inline function read_bbo1s_msg(decoder::DBNDecoder, hd::RecordHeader)
    price = read(decoder.io, Int64)
    size = read(decoder.io, UInt32)
    action = safe_action(read(decoder.io, UInt8))
    side = safe_side(read(decoder.io, UInt8))
    flags = read(decoder.io, UInt8)
    depth = read(decoder.io, UInt8)
    ts_recv = read(decoder.io, Int64)
    ts_in_delta = read(decoder.io, Int32)
    sequence = read(decoder.io, UInt32)

    bid_px = read(decoder.io, Int64)
    ask_px = read(decoder.io, Int64)
    bid_sz = read(decoder.io, UInt32)
    ask_sz = read(decoder.io, UInt32)
    bid_ct = read(decoder.io, UInt32)
    ask_ct = read(decoder.io, UInt32)
    levels = BidAskPair(bid_px, ask_px, bid_sz, ask_sz, bid_ct, ask_ct)

    return BBO1sMsg(hd, price, size, action, side, flags, depth, ts_recv, ts_in_delta, sequence, levels)
end

@inline function read_bbo1m_msg(decoder::DBNDecoder, hd::RecordHeader)
    price = read(decoder.io, Int64)
    size = read(decoder.io, UInt32)
    action = safe_action(read(decoder.io, UInt8))
    side = safe_side(read(decoder.io, UInt8))
    flags = read(decoder.io, UInt8)
    depth = read(decoder.io, UInt8)
    ts_recv = read(decoder.io, Int64)
    ts_in_delta = read(decoder.io, Int32)
    sequence = read(decoder.io, UInt32)

    bid_px = read(decoder.io, Int64)
    ask_px = read(decoder.io, Int64)
    bid_sz = read(decoder.io, UInt32)
    ask_sz = read(decoder.io, UInt32)
    bid_ct = read(decoder.io, UInt32)
    ask_ct = read(decoder.io, UInt32)
    levels = BidAskPair(bid_px, ask_px, bid_sz, ask_sz, bid_ct, ask_ct)

    return BBO1mMsg(hd, price, size, action, side, flags, depth, ts_recv, ts_in_delta, sequence, levels)
end
