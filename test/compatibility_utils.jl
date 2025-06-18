module CompatibilityUtils

using DBN
using Test
using JSON
using DataFrames
using CSV: CSV
using Dates

# Path to the Rust DBN CLI executable
const DBN_CLI_PATH = "/workspace/dbn/target/release/dbn"

"""
    run_dbn_cli(args::Vector{String})

Run the DBN CLI with the given arguments and return the output.
"""
function run_dbn_cli(args::Vector{String})
    if !isfile(DBN_CLI_PATH)
        error("DBN CLI not found at $DBN_CLI_PATH. Please build the Rust implementation first.")
    end
    
    cmd = Cmd([DBN_CLI_PATH; args])
    try
        output = read(cmd, String)
        return output
    catch e
        if isa(e, Base.IOError)
            error("Failed to run DBN CLI: $(e.msg)")
        else
            rethrow(e)
        end
    end
end

"""
    compare_binary_files(file1::String, file2::String)

Compare two files byte-for-byte.
"""
function compare_binary_files(file1::String, file2::String)
    if !isfile(file1) || !isfile(file2)
        return false
    end
    
    content1 = read(file1)
    content2 = read(file2)
    
    return content1 == content2
end

"""
    compare_json_output(julia_output::String, rust_output::String; tolerance=1e-9)

Compare JSON outputs from Julia and Rust implementations, allowing for floating-point tolerance.
"""
function compare_json_output(julia_output::String, rust_output::String; tolerance=1e-9)
    # Parse JSON lines
    julia_lines = filter(!isempty, split(julia_output, '\n'))
    rust_lines = filter(!isempty, split(rust_output, '\n'))
    
    if length(julia_lines) != length(rust_lines)
        @warn "Different number of records: Julia=$(length(julia_lines)), Rust=$(length(rust_lines))"
        return false
    end
    
    for (i, (jl_line, rs_line)) in enumerate(zip(julia_lines, rust_lines))
        jl_obj = JSON.parse(jl_line)
        rs_obj = JSON.parse(rs_line)
        
        if !compare_json_objects(jl_obj, rs_obj, tolerance)
            @warn "Mismatch at record $i"
            @warn "Julia: $jl_line"
            @warn "Rust: $rs_line"
            return false
        end
    end
    
    return true
end

"""
    compare_json_objects(obj1, obj2, tolerance)

Recursively compare two JSON objects with floating-point tolerance.
"""
function compare_json_objects(obj1, obj2, tolerance)
    if typeof(obj1) != typeof(obj2)
        return false
    end
    
    if isa(obj1, Dict)
        if keys(obj1) != keys(obj2)
            return false
        end
        for key in keys(obj1)
            if !compare_json_objects(obj1[key], obj2[key], tolerance)
                return false
            end
        end
        return true
    elseif isa(obj1, Array)
        if length(obj1) != length(obj2)
            return false
        end
        for (v1, v2) in zip(obj1, obj2)
            if !compare_json_objects(v1, v2, tolerance)
                return false
            end
        end
        return true
    elseif isa(obj1, Number) && isa(obj2, Number)
        return abs(obj1 - obj2) <= tolerance
    else
        return obj1 == obj2
    end
end

"""
    compare_csv_output(julia_output::String, rust_output::String; tolerance=1e-9)

Compare CSV outputs from Julia and Rust implementations.
"""
function compare_csv_output(julia_output::String, rust_output::String; tolerance=1e-9)
    # Read CSV data
    julia_df = CSV.read(IOBuffer(julia_output), DataFrame)
    rust_df = CSV.read(IOBuffer(rust_output), DataFrame)
    
    # Check dimensions
    if size(julia_df) != size(rust_df)
        @warn "Different dimensions: Julia=$(size(julia_df)), Rust=$(size(rust_df))"
        return false
    end
    
    # Check column names
    if names(julia_df) != names(rust_df)
        @warn "Different column names: Julia=$(names(julia_df)), Rust=$(names(rust_df))"
        return false
    end
    
    # Compare values
    for col in names(julia_df)
        julia_col = julia_df[!, col]
        rust_col = rust_df[!, col]
        
        for (i, (jv, rv)) in enumerate(zip(julia_col, rust_col))
            if isa(jv, Number) && isa(rv, Number)
                if abs(jv - rv) > tolerance
                    @warn "Mismatch in column $col, row $i: Julia=$jv, Rust=$rv"
                    return false
                end
            elseif jv != rv
                @warn "Mismatch in column $col, row $i: Julia=$jv, Rust=$rv"
                return false
            end
        end
    end
    
    return true
end

"""
    test_round_trip(test_file::String, output_dir::String)

Test round-trip compatibility: Julia reads → writes → Rust reads → validates.
"""
function test_round_trip(test_file::String, output_dir::String)
    mkpath(output_dir)
    
    # Read with Julia
    metadata, records = DBN.read_dbn_with_metadata(test_file)
    
    # Write with Julia
    julia_output = joinpath(output_dir, "julia_output.dbn")
    DBN.write_dbn(julia_output, metadata, records)
    
    # Read with Rust and convert to JSON
    rust_json = run_dbn_cli([julia_output, "--json"])
    
    # Convert Julia records to JSON for comparison
    julia_json = IOBuffer()
    for record in records
        # Convert struct to dict for JSON serialization, handling nested structs
        record_dict = struct_to_dict(record)
        JSON.print(julia_json, record_dict)
        println(julia_json)
    end
    julia_json_str = String(take!(julia_json))
    
    # Compare outputs
    return compare_json_output(julia_json_str, rust_json)
end

"""
    test_file_compatibility(test_file::String)

Test that Julia can correctly read a file and produce the same output as Rust.
"""
function test_file_compatibility(test_file::String)
    # Read with Rust and convert to JSON
    rust_json = run_dbn_cli([test_file, "--json"])
    
    # Read with Julia
    metadata, records = DBN.read_dbn_with_metadata(test_file)
    
    # Convert Julia records to JSON
    julia_json = IOBuffer()
    for record in records
        # Convert struct to dict for JSON serialization, handling nested structs
        record_dict = struct_to_dict(record)
        JSON.print(julia_json, record_dict)
        println(julia_json)
    end
    julia_json_str = String(take!(julia_json))
    
    # Compare outputs
    return compare_json_output(julia_json_str, rust_json)
end

"""
    benchmark_read_performance(test_file::String; iterations=10)

Benchmark read performance between Julia and Rust implementations.
"""
function benchmark_read_performance(test_file::String; iterations=10)
    # Julia benchmark
    julia_times = Float64[]
    for _ in 1:iterations
        t = @elapsed DBN.read_dbn(test_file)
        push!(julia_times, t)
    end
    julia_avg = mean(julia_times)
    
    # Rust benchmark (convert to JSON to force full read)
    rust_times = Float64[]
    for _ in 1:iterations
        t = @elapsed run_dbn_cli([test_file, "--json", "-o", "/dev/null"])
        push!(rust_times, t)
    end
    rust_avg = mean(rust_times)
    
    return (julia=julia_avg, rust=rust_avg, ratio=julia_avg/rust_avg)
end

"""
    get_test_files(pattern::String="*.dbn")

Get all test DBN files matching the pattern.
"""
function get_test_files(pattern::String="*.dbn")
    test_data_dir = "/workspace/dbn/tests/data"
    if !isdir(test_data_dir)
        error("Test data directory not found: $test_data_dir")
    end
    
    files = String[]
    for (root, dirs, filenames) in walkdir(test_data_dir)
        for filename in filenames
            # Convert glob pattern to regex
            pattern_regex = replace(pattern, "*" => ".*")
            if occursin(Regex(pattern_regex), filename)
                push!(files, joinpath(root, filename))
            end
        end
    end
    
    return sort(files)
end

# Helper function for mean calculation
mean(x) = sum(x) / length(x)

"""
    struct_to_dict(obj)

Convert a struct to a dictionary, handling nested structs recursively.
"""
function struct_to_dict(obj)
    if isa(obj, Union{Number, String, Bool})
        return obj
    elseif isa(obj, Array)
        return [struct_to_dict(item) for item in obj]
    elseif isdefined(Base, :hasmethod) && hasmethod(fieldnames, typeof(obj))
        # It's a struct with fields
        dict = Dict{String, Any}()
        for field in fieldnames(typeof(obj))
            dict[string(field)] = struct_to_dict(getfield(obj, field))
        end
        return dict
    else
        # For enums and other types, convert to string representation
        return string(obj)
    end
end

end # module