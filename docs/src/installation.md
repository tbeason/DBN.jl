# Installation

## Requirements

- Julia 1.12 or later
- Operating System: Windows, macOS, or Linux

## Installing DBN.jl

!!! note
    DBN.jl is not yet registered in the Julia General registry. Install directly from GitHub.

### From GitHub

```julia
using Pkg
Pkg.add(url="https://github.com/tbeason/DBN.jl")
```

### Development Installation

If you want to modify the package or contribute:

```julia
using Pkg
Pkg.develop(url="https://github.com/tbeason/DBN.jl")
```

This will clone the repository to `~/.julia/dev/DBN`.

## Verifying Installation

Test that DBN.jl is installed correctly:

```julia
using DBN

# Check package version
println(Pkg.TOML.parsefile(joinpath(dirname(pathof(DBN)), "..", "Project.toml"))["version"])

# Test basic functionality
# (assumes you have a DBN file to test with)
# records = read_dbn("path/to/test.dbn")
```

## Dependencies

DBN.jl has the following dependencies (automatically installed):

- **CodecZstd** - Zstd compression support
- **CSV** - CSV file conversion
- **JSON3** - JSON file conversion
- **Parquet2** - Parquet file conversion
- **DataFrames** - DataFrame conversion
- **EnumX** - Enhanced enum support
- **StructTypes** - Type serialization
- **TranscodingStreams** - Streaming compression
- **Dates** - Timestamp handling
- **Statistics** - Basic statistical functions

## Troubleshooting

### Package Not Found

If you get a "Package not found" error, make sure you're using the full GitHub URL:

```julia
Pkg.add(url="https://github.com/tbeason/DBN.jl")
```

### Dependency Conflicts

If you encounter dependency version conflicts:

```julia
# Update all packages
Pkg.update()

# Resolve package versions
Pkg.resolve()
```

### Zstd Compression Issues

If you have issues with `.zst` compressed files, verify CodecZstd is installed:

```julia
using CodecZstd
```

If this fails, reinstall the codec:

```julia
Pkg.rm("CodecZstd")
Pkg.add("CodecZstd")
```

## Next Steps

- [Quick Start Guide](quickstart.md) - Get started in 5 minutes
- [Reading Data](guide/reading.md) - Learn the different ways to read DBN files
- [API Reference](api/reading.md) - Explore the full API
