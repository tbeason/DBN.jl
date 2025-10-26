#!/usr/bin/env julia
#
# Refactor read_record() to use function barriers for type stability
# This eliminates ~1.1M allocations by splitting the mega-function into type-stable helpers
#

println("Refactoring read_record() in src/decode.jl...")

# Read current file
lines = readlines("src/decode.jl")
println("Original file: $(length(lines)) lines")

# The old read_record function spans lines 382-998 (617 lines)
# We'll replace it with the new refactored version

# Part 1: Keep everything before read_record (lines 1-381)
before = lines[1:381]

# Part 2: Keep everything after read_record (lines 999-end)
after = lines[999:end]

# Part 3: New refactored read_record code
new_code = String[]

push!(new_code, """function read_record(decoder::DBNDecoder)
    if eof(decoder.io)
        return nothing
    end

    hd_result = read_record_header(decoder.io)

    # Handle unknown record types
    if hd_result isa Tuple
        _, rtype_raw, record_length = hd_result
        skip(decoder.io, record_length - 2)
        return nothing
    end

    hd = hd_result

    # Dispatch to type-stable reader functions (function barrier pattern)
    return read_record_dispatch(decoder, hd, hd.rtype)
end""")

push!(new_code, "")
push!(new_code, "# Type-stable dispatch function - eliminates type instability from mega-function")
push!(new_code, "@inline function read_record_dispatch(decoder::DBNDecoder, hd::RecordHeader, rtype::RType.T)")
push!(new_code, "    if rtype == RType.MBO_MSG")
push!(new_code, "        return read_mbo_msg(decoder, hd)")
push!(new_code, "    elseif rtype == RType.MBP_0_MSG")
push!(new_code, "        return read_trade_msg(decoder, hd)")
push!(new_code, "    elseif rtype == RType.MBP_1_MSG")
push!(new_code, "        return read_mbp1_msg(decoder, hd)")
push!(new_code, "    elseif rtype == RType.MBP_10_MSG")
push!(new_code, "        return read_mbp10_msg(decoder, hd)")
push!(new_code, "    elseif rtype in (RType.OHLCV_1S_MSG, RType.OHLCV_1M_MSG, RType.OHLCV_1H_MSG, RType.OHLCV_1D_MSG)")
push!(new_code, "        return read_ohlcv_msg(decoder, hd)")
push!(new_code, "    elseif rtype == RType.STATUS_MSG")
push!(new_code, "        return read_status_msg(decoder, hd)")
push!(new_code, "    elseif rtype == RType.INSTRUMENT_DEF_MSG")
push!(new_code, "        return read_instrument_def_msg(decoder, hd)")
push!(new_code, "    elseif rtype == RType.IMBALANCE_MSG")
push!(new_code, "        return read_imbalance_msg(decoder, hd)")
push!(new_code, "    elseif rtype == RType.STAT_MSG")
push!(new_code, "        return read_stat_msg(decoder, hd)")
push!(new_code, "    elseif rtype == RType.ERROR_MSG")
push!(new_code, "        return read_error_msg(decoder, hd)")
push!(new_code, "    elseif rtype == RType.SYMBOL_MAPPING_MSG")
push!(new_code, "        return read_symbol_mapping_msg(decoder, hd)")
push!(new_code, "    elseif rtype == RType.SYSTEM_MSG")
push!(new_code, "        return read_system_msg(decoder, hd)")
push!(new_code, "    elseif rtype == RType.CMBP_1_MSG")
push!(new_code, "        return read_cmbp1_msg(decoder, hd)")
push!(new_code, "    elseif rtype == RType.CBBO_1S_MSG")
push!(new_code, "        return read_cbbo1s_msg(decoder, hd)")
push!(new_code, "    elseif rtype == RType.CBBO_1M_MSG")
push!(new_code, "        return read_cbbo1m_msg(decoder, hd)")
push!(new_code, "    elseif rtype == RType.TCBBO_MSG")
push!(new_code, "        return read_tcbbo_msg(decoder, hd)")
push!(new_code, "    elseif rtype == RType.BBO_1S_MSG")
push!(new_code, "        return read_bbo1s_msg(decoder, hd)")
push!(new_code, "    elseif rtype == RType.BBO_1M_MSG")
push!(new_code, "        return read_bbo1m_msg(decoder, hd)")
push!(new_code, "    else")
push!(new_code, "        skip(decoder.io, hd.length - 16)")
push!(new_code, "        return nothing")
push!(new_code, "    end")
push!(new_code, "end")
push!(new_code, "")

# Now add all the type-stable helper functions
# Include the helpers from the separate file we created
helper_code = read("src/decode_refactored.jl", String)
append!(new_code, split(helper_code, '\n'))

# Combine all parts
new_lines = vcat(before, new_code, after)

println("New file: $(length(new_lines)) lines")
println("Difference: $(length(new_lines) - length(lines)) lines")

# Write the refactored file
open("src/decode.jl", "w") do f
    for line in new_lines
        println(f, line)
    end
end

println("✓ Refactoring complete!")
println("  - Old read_record: 617 lines (type-unstable mega-function)")
println("  - New read_record + helpers: ~$(length(new_code)) lines (type-stable dispatch)")
