using Documenter
using DBN

makedocs(
    sitename = "DBN.jl",
    format = Documenter.HTML(
        prettyurls = get(ENV, "CI", nothing) == "true",
        canonical = "https://tbeason.github.io/DBN.jl",
        assets = String[],
    ),
    modules = [DBN],
    pages = [
        "Home" => "index.md",
        "Installation" => "installation.md",
        "Quick Start" => "quickstart.md",
        "User Guide" => [
            "Reading Data" => "guide/reading.md",
            "Writing Data" => "guide/writing.md",
            "Streaming" => "guide/streaming.md",
            "Format Conversion" => "guide/conversion.md",
        ],
        "API Reference" => [
            "Reading" => "api/reading.md",
            "Writing" => "api/writing.md",
            "Streaming" => "api/streaming.md",
            "Types" => "api/types.md",
            "Enums" => "api/enums.md",
            "Conversion" => "api/conversion.md",
            "Utilities" => "api/utilities.md",
        ],
        "Performance" => "performance.md",
        "Troubleshooting" => "troubleshooting.md",
    ],
    checkdocs = :none,  # Don't require docs for internal functions/constants
)

deploydocs(
    repo = "github.com/tbeason/DBN.jl.git",
    devbranch = "main",
    push_preview = true,
)
