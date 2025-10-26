#!/usr/bin/env python3
"""
Function barrier refactoring for read_record()
Converts the 616-line type-unstable mega-function into type-stable helpers
"""

def main():
    print("Function Barrier Refactoring")
    print("=" * 70)

    # Read the original file
    with open("src/decode.jl", "r", encoding="utf-8") as f:
        lines = f.readlines()

    print(f"Original file: {len(lines)} lines")

    # read_record is at lines 382-998 (1-indexed, so 381-997 in 0-indexed)
    read_record_start = 381  # Line 382 in 1-indexed
    read_record_end = 997    # Line 998 in 1-indexed

    # Verify
    assert "function read_record(decoder::DBNDecoder)" in lines[read_record_start]
    assert lines[read_record_end].strip() == "end"

    print(f"Found read_record: lines {read_record_start+1} to {read_record_end+1}")
    print(f"Function size: {read_record_end - read_record_start + 1} lines")
    print()

    # Build the new code
    new_code = []

    # Main read_record function (compact)
    new_code.extend([
        "function read_record(decoder::DBNDecoder)\n",
        "    if eof(decoder.io)\n",
        "        return nothing\n",
        "    end\n",
        "    \n",
        "    hd_result = read_record_header(decoder.io)\n",
        "    \n",
        "    # Handle unknown record types\n",
        "    if hd_result isa Tuple\n",
        "        _, rtype_raw, record_length = hd_result\n",
        "        skip(decoder.io, record_length - 2)\n",
        "        return nothing\n",
        "    end\n",
        "    \n",
        "    hd = hd_result\n",
        "    \n",
        "    # Type-stable dispatch - function barrier eliminates type instability\n",
        "    return read_record_dispatch(decoder, hd, hd.rtype)\n",
        "end\n",
        "\n",
    ])

    # Dispatch function
    new_code.extend([
        "# Dispatch to type-stable helpers - each helper has concrete types\n",
        "@inline function read_record_dispatch(decoder::DBNDecoder, hd::RecordHeader, rtype::RType.T)\n",
        "    if rtype == RType.MBO_MSG\n",
        "        return read_mbo_msg(decoder, hd)\n",
        "    elseif rtype == RType.MBP_0_MSG\n",
        "        return read_trade_msg(decoder, hd)\n",
        "    elseif rtype == RType.MBP_1_MSG\n",
        "        return read_mbp1_msg(decoder, hd)\n",
        "    elseif rtype == RType.MBP_10_MSG\n",
        "        return read_mbp10_msg(decoder, hd)\n",
        "    elseif rtype in (RType.OHLCV_1S_MSG, RType.OHLCV_1M_MSG, RType.OHLCV_1H_MSG, RType.OHLCV_1D_MSG)\n",
        "        return read_ohlcv_msg(decoder, hd)\n",
        "    elseif rtype == RType.STATUS_MSG\n",
        "        return read_status_msg(decoder, hd)\n",
        "    elseif rtype == RType.INSTRUMENT_DEF_MSG\n",
        "        return read_instrument_def_msg(decoder, hd)\n",
        "    elseif rtype == RType.IMBALANCE_MSG\n",
        "        return read_imbalance_msg(decoder, hd)\n",
        "    elseif rtype == RType.STAT_MSG\n",
        "        return read_stat_msg(decoder, hd)\n",
        "    elseif rtype == RType.ERROR_MSG\n",
        "        return read_error_msg(decoder, hd)\n",
        "    elseif rtype == RType.SYMBOL_MAPPING_MSG\n",
        "        return read_symbol_mapping_msg(decoder, hd)\n",
        "    elseif rtype == RType.SYSTEM_MSG\n",
        "        return read_system_msg(decoder, hd)\n",
        "    elseif rtype == RType.CMBP_1_MSG\n",
        "        return read_cmbp1_msg(decoder, hd)\n",
        "    elseif rtype == RType.CBBO_1S_MSG\n",
        "        return read_cbbo1s_msg(decoder, hd)\n",
        "    elseif rtype == RType.CBBO_1M_MSG\n",
        "        return read_cbbo1m_msg(decoder, hd)\n",
        "    elseif rtype == RType.TCBBO_MSG\n",
        "        return read_tcbbo_msg(decoder, hd)\n",
        "    elseif rtype == RType.BBO_1S_MSG\n",
        "        return read_bbo1s_msg(decoder, hd)\n",
        "    elseif rtype == RType.BBO_1M_MSG\n",
        "        return read_bbo1m_msg(decoder, hd)\n",
        "    else\n",
        "        skip(decoder.io, hd.length - 16)\n",
        "        return nothing\n",
        "    end\n",
        "end\n",
        "\n",
    ])

    # Now extract and convert each handler from the original function
    old_function = lines[read_record_start:read_record_end+1]

    # Helper to convert an if/elseif block to a function
    def extract_handler(start_marker, func_name):
        # Find start
        start_idx = None
        for i, line in enumerate(old_function):
            if start_marker in line:
                start_idx = i
                break

        if start_idx is None:
            print(f"Warning: Could not find {func_name}")
            return []

        # Find the return statement (end of this handler)
        end_idx = None
        for i in range(start_idx + 1, len(old_function)):
            if "return " in old_function[i] and ("Msg(" in old_function[i] or "nothing" in old_function[i]):
                end_idx = i
                break

        if end_idx is None:
            print(f"Warning: Could not find end for {func_name}")
            return []

        # Build the function
        func_lines = [f"@inline function {func_name}(decoder::DBNDecoder, hd::RecordHeader)\n"]

        # Add the body (skip the if/elseif line, include up to and including return)
        for i in range(start_idx + 1, end_idx + 1):
            line = old_function[i]
            # Remove one level of indentation (8 spaces)
            if line.startswith("        "):
                line = "    " + line[8:]
            func_lines.append(line)

        func_lines.append("end\n\n")
        return func_lines

    # Extract all handlers
    print("Extracting handlers...")

    # Simple handlers
    handlers = [
        ("if hd.rtype == RType.MBO_MSG", "read_mbo_msg"),
        ("elseif hd.rtype == RType.MBP_0_MSG", "read_trade_msg"),
        ("elseif hd.rtype == RType.MBP_1_MSG", "read_mbp1_msg"),
        ("elseif hd.rtype == RType.MBP_10_MSG", "read_mbp10_msg"),
        ("elseif hd.rtype in [RType.OHLCV", "read_ohlcv_msg"),
        ("elseif hd.rtype == RType.STATUS_MSG", "read_status_msg"),
        ("elseif hd.rtype == RType.IMBALANCE_MSG", "read_imbalance_msg"),
        ("elseif hd.rtype == RType.STAT_MSG", "read_stat_msg"),
        ("elseif hd.rtype == RType.ERROR_MSG", "read_error_msg"),
        ("elseif hd.rtype == RType.SYMBOL_MAPPING_MSG", "read_symbol_mapping_msg"),
        ("elseif hd.rtype == RType.SYSTEM_MSG", "read_system_msg"),
        ("elseif hd.rtype == RType.CMBP_1_MSG", "read_cmbp1_msg"),
        ("elseif hd.rtype == RType.CBBO_1S_MSG", "read_cbbo1s_msg"),
        ("elseif hd.rtype == RType.CBBO_1M_MSG", "read_cbbo1m_msg"),
        ("elseif hd.rtype == RType.TCBBO_MSG", "read_tcbbo_msg"),
        ("elseif hd.rtype == RType.BBO_1S_MSG", "read_bbo1s_msg"),
        ("elseif hd.rtype == RType.BBO_1M_MSG", "read_bbo1m_msg"),
    ]

    for marker, func_name in handlers:
        print(f"  - {func_name}")
        handler_code = extract_handler(marker, func_name)
        new_code.extend(handler_code)

    # InstrumentDef is special - it's huge and has v2/v3 variants
    # Handle it separately
    print("  - read_instrument_def_msg (complex)")

    # Find the InstrumentDef block
    inst_start = None
    for i, line in enumerate(old_function):
        if "elseif hd.rtype == RType.INSTRUMENT_DEF_MSG" in line:
            inst_start = i
            break

    if inst_start:
        # Add the main dispatcher
        new_code.extend([
            "@inline function read_instrument_def_msg(decoder::DBNDecoder, hd::RecordHeader)\n",
            "    start_pos = position(decoder.io)\n",
            "    record_size_bytes = hd.length * LENGTH_MULTIPLIER\n",
            "    body_size = record_size_bytes - 16\n",
            "    if body_size == 384\n",
            "        return read_instrument_def_v2(decoder, hd)\n",
            "    else\n",
            "        return read_instrument_def_v3(decoder, hd)\n",
            "    end\n",
            "end\n",
            "\n",
        ])

        # Find v2 block (starts at "if body_size == 384", ends before "else")
        v2_start = None
        for i in range(inst_start, len(old_function)):
            if "if body_size == 384" in old_function[i]:
                v2_start = i
                break

        v2_end = None
        if v2_start:
            for i in range(v2_start + 1, len(old_function)):
                if old_function[i].strip().startswith("else") and "DBN V3" in old_function[min(i+2, len(old_function)-1)]:
                    v2_end = i
                    break

        if v2_start and v2_end:
            print("  - read_instrument_def_v2")
            new_code.append("@inline function read_instrument_def_v2(decoder::DBNDecoder, hd::RecordHeader)\n")
            # Skip comments and "if body_size" line, take body
            for i in range(v2_start + 11, v2_end - 1):  # Skip header comments
                line = old_function[i]
                if line.startswith("            "):
                    line = "    " + line[12:]
                new_code.append(line)
            new_code.append("end\n\n")

        # Find v3 block
        v3_start = v2_end
        v3_end = None
        if v3_start:
            # Find the big return statement for InstrumentDefMsg
            for i in range(v3_start, len(old_function)):
                if "return InstrumentDefMsg(" in old_function[i]:
                    # Find the closing paren
                    for j in range(i, len(old_function)):
                        if old_function[j].strip() == ")":
                            v3_end = j
                            break
                    break

        if v3_start and v3_end:
            print("  - read_instrument_def_v3")
            new_code.append("@inline function read_instrument_def_v3(decoder::DBNDecoder, hd::RecordHeader)\n")
            for i in range(v3_start + 7, v3_end + 1):  # Skip "else" and comments
                line = old_function[i]
                if line.startswith("            "):
                    line = "    " + line[12:]
                new_code.append(line)
            new_code.append("end\n\n")

    print()
    print(f"Generated {len(new_code)} lines of refactored code")

    # Assemble the final file
    final_lines = (
        lines[:read_record_start] +  # Before
        new_code +                     # New refactored code
        lines[read_record_end+1:]      # After
    )

    print(f"Final file: {len(final_lines)} lines (was {len(lines)})")
    print(f"Change: {len(final_lines) - len(lines):+d} lines")
    print()

    # Write the refactored file
    with open("src/decode.jl", "w", encoding="utf-8", newline='\n') as f:
        f.writelines(final_lines)

    print("✓ Refactoring complete!")
    print("  - Replaced 616-line mega-function")
    print("  - Created type-stable helper functions")
    print("  - All helpers marked @inline")

if __name__ == "__main__":
    main()
