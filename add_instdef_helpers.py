#!/usr/bin/env python3
"""Add the missing InstrumentDef v2/v3 helper functions"""

# Read the current file
with open("src/decode.jl", "r", encoding="utf-8") as f:
    lines = f.readlines()

print(f"Current file: {len(lines)} lines")

# Find the insertion point (after read_instrument_def_msg, line 808)
insert_at = 808  # 0-indexed

# Extract v2 and v3 code from the backup
with open("src/decode.jl.backup_before_refactor", "r", encoding="utf-8") as f:
    backup_lines = f.readlines()

# Find v2 block in backup (starts at line 514, ends before 605)
v2_start = 513  # Line 514 in 1-indexed
v2_end = 604    # Line 605

# Find v3 block in backup (starts at line 608, ends at 728)
v3_start = 607  # Line 608
v3_end = 728    # Line 729

# Build v2 function
v2_func = ["@inline function read_instrument_def_v2(decoder::DBNDecoder, hd::RecordHeader)\n"]
v2_func.append("    # ===== DBN V2 InstrumentDefMsg =====\n")
v2_func.append("    # CRITICAL: In v2, encode_order attributes are COMPLETELY IGNORED!\n")
v2_func.append("    # Read ALL fields in exact Rust struct declaration order\n")

# Add v2 body (remove 12 spaces of indentation, add 4)
for i in range(v2_start, v2_end):
    line = backup_lines[i]
    if line.strip():  # Skip empty lines at start/end
        # Remove 12 spaces of indentation, add 4
        if line.startswith("            "):
            line = "    " + line[12:]
        v2_func.append(line)

v2_func.append("end\n")
v2_func.append("\n")

# Build v3 function
v3_func = ["@inline function read_instrument_def_v3(decoder::DBNDecoder, hd::RecordHeader)\n"]
v3_func.append("    # ===== DBN V3 InstrumentDefMsg =====\n")

# Add v3 body
for i in range(v3_start, v3_end):
    line = backup_lines[i]
    if line.strip():
        # Remove 12 spaces of indentation, add 4
        if line.startswith("            "):
            line = "    " + line[12:]
        v3_func.append(line)

v3_func.append("end\n")
v3_func.append("\n")

print(f"v2 function: {len(v2_func)} lines")
print(f"v3 function: {len(v3_func)} lines")

# Insert into file
new_lines = (
    lines[:insert_at] +
    v2_func +
    v3_func +
    lines[insert_at:]
)

# Write back
with open("src/decode.jl", "w", encoding="utf-8", newline='\n') as f:
    f.writelines(new_lines)

print(f"New file: {len(new_lines)} lines (was {len(lines)})")
print("Added v2 and v3 helper functions successfully!")
