# Test utility functions

"""
    safe_rm(path::String; max_attempts=5, delay=0.1)

Safely delete a file with retry logic for Windows file locking issues.

Windows may not immediately release file locks even after close(),
causing "resource busy or locked (EBUSY)" errors. This function:
1. Forces garbage collection to release file handles
2. Retries deletion with exponential backoff
3. Fails gracefully with a warning rather than throwing an error

# Arguments
- `path::String`: Path to the file to delete
- `max_attempts::Int=5`: Maximum number of deletion attempts
- `delay::Float64=0.1`: Initial delay between attempts (in seconds)
"""
function safe_rm(path::String; max_attempts=5, delay=0.1)
    if !isfile(path)
        return
    end

    # Force garbage collection to ensure file handles are released
    GC.gc()

    for attempt in 1:max_attempts
        try
            rm(path; force=true)
            return
        catch e
            if attempt == max_attempts
                @warn "Failed to delete file after $max_attempts attempts: $path" exception=e
                # Don't rethrow - we don't want cleanup failures to fail the test
                return
            end
            # Wait a bit for Windows to release the file lock
            sleep(delay)
        end
    end
end
