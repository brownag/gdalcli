#' Execution Backends - gdalcli Backend Options and Configuration
#'
#' @description
#' gdalcli supports multiple execution backends, each with different characteristics.
#' The system automatically selects the best available backend, but you can override
#' this when needed.
#'
#' @details
#' ## Available Backends
#'
#' ### gdalraster (Rcpp C++ bindings)
#' - **Requires:** gdalraster >= 2.2.0 R package installed
#' - **Speed:** Fastest for batch operations (10-50x faster than processx)
#' - **Availability:** Windows binaries available; macOS/Linux require system GDAL
#' - **Features:** All advanced features with gdalraster 2.3.0+
#' - **Overhead:** Minimal startup overhead, ideal for loops
#' - **Best for:** Batch processing, Windows users, performance-critical applications
#'
#' ### processx (System GDAL subprocess)
#' - **Requires:** GDAL installed and in system PATH
#' - **Speed:** Suitable for individual operations
#' - **Availability:** Works anywhere GDAL is installed
#' - **Features:** All GDAL functionality available
#' - **Overhead:** 0.1-0.5 second startup per operation (~49 ms per call)
#' - **Best for:** Individual operations, isolated execution, maximum compatibility
#'
#' ### reticulate (Python via GDAL bindings)
#' - **Requires:** Python with GDAL bindings installed
#' - **Speed:** Similar to processx
#' - **Availability:** When Python GDAL is configured
#' - **Features:** All GDAL functionality available
#' - **Use case:** Integration with Python-based workflows
#'
#' ## Auto-Selection Logic
#'
#' By default, gdalcli uses this selection logic:
#'
#' ```
#' 1. Check if gdalraster >= 2.2.0 is installed
#'    → If yes, use gdalraster backend
#'    → If no, continue to step 2
#'
#' 2. Check if processx can access system GDAL
#'    → If yes, use processx backend
#'    → If no, continue to step 3
#'
#' 3. Check if reticulate can access Python GDAL
#'    → If yes, use reticulate backend
#'    → If no, error: no backends available
#' ```
#'
#' ## Backend Configuration
#'
#' ### Global Backend Preference
#'
#' Set default backend selection via options:
#'
#' ```r
#' # Auto-select best available (default)
#' options(gdalcli.prefer_backend = "auto")
#'
#' # Always prefer gdalraster if available, fall back to processx
#' options(gdalcli.prefer_backend = "gdalraster")
#'
#' # Force processx (ignore gdalraster even if installed)
#' options(gdalcli.prefer_backend = "processx")
#'
#' # Force reticulate (Python-based GDAL)
#' options(gdalcli.prefer_backend = "reticulate")
#' ```
#'
#' ### Per-Call Backend Selection
#'
#' Override backend selection for specific operations:
#'
#' ```r
#' library(gdalcli)
#'
#' job <- gdal_raster_info("file.tif")
#'
#' # Use specific backend
#' result1 <- gdal_job_run(job, backend = "gdalraster")
#' result2 <- gdal_job_run(job, backend = "processx")
#' ```
#'
#' ## Performance Comparison
#'
#' **Actual benchmark results** (gdalraster 2.2.1 with GDAL 3.11.4):
#'
#' 50 command discovery operations:
#' - gdalraster (Rcpp): **0.145 seconds** (2.9 ms per call)
#' - processx (subprocess): **2.597 seconds** (51.94 ms per call)
#' - **Speedup: 17.91x**
#'
#' Projected savings for larger batches:
#' - 100 operations: ~4.9 seconds saved
#' - 500 operations: ~24 seconds saved
#' - 1000 operations: ~49 seconds saved
#'
#' **Key finding:** Subprocess startup overhead is ~49 ms per operation.
#'
#' **Variables affecting actual speedup:**
#' - Operation complexity (command discovery vs. complex processing)
#' - File sizes and dataset characteristics
#' - System resources (CPU, disk I/O, RAM)
#' - GDAL algorithm efficiency for the specific task
#'
#' **Note:** Results above are for lightweight command discovery. Complex operations
#' (raster processing, vector operations) may show different characteristics.
#' Benchmark with your real data for accurate estimates in your use case.
#'
#' ## Checking Backend Availability
#'
#' ```r
#' library(gdalcli)
#'
#' # Check if gdalraster is available
#' if (.check_gdalraster_version("2.2.0", quietly = TRUE)) {
#'   cat("gdalraster backend available\n")
#' } else {
#'   cat("Using processx backend\n")
#' }
#'
#' # Check gdalraster version
#' gdalcli:::.get_gdalraster_version()
#' # [1] "2.3.0"
#'
#' # Check if specific feature is available
#' gdalcli:::.gdal_has_feature("setVectorArgsFromObject")
#' # [1] TRUE (if gdalraster >= 2.3.0)
#' ```
#'
#' ## Best Practices
#'
#' 1. **Default to auto-selection** - Let gdalcli choose the best backend
#' 2. **Install gdalraster on Windows** - Simplest way to avoid system GDAL dependency
#' 3. **Use explicit selection for benchmarking** - Compare backends with `backend` parameter
#' 4. **Monitor memory with large datasets** - Gdalraster holds more data in memory than processx
#' 5. **Test with your data** - Performance characteristics vary by operation type
#'
#' ## Troubleshooting
#'
#' ### "No backends available" error
#'
#' Either gdalraster and processx are not installed:
#' ```r
#' # Verify gdalraster is installed
#' requireNamespace("gdalraster")
#'
#' # Or install system GDAL and processx
#' install.packages("processx")
#' ```
#'
#' ### Backend not switching
#'
#' ```r
#' # Check current preference setting
#' getOption("gdalcli.prefer_backend")
#'
#' # Reset to auto-selection
#' options(gdalcli.prefer_backend = "auto")
#'
#' # Verify gdalraster version
#' gdalcli:::.get_gdalraster_version()
#' ```
#'
#' ### Unexpected performance
#'
#' ```r
#' # Verify which backend is being used
#' gdal_job_run(job, verbose = TRUE)
#'
#' # Force comparison
#' time_gdalraster <- system.time(gdal_job_run(job, backend = "gdalraster"))
#' time_processx <- system.time(gdal_job_run(job, backend = "processx"))
#' ```
#'
#' @seealso
#' [gdalcli::gdal_job_run()] for `backend` parameter documentation,
#' [gdalcli::gdalraster-backend] for gdalraster-specific information,
#' [gdalcli::GDAL-features] for advanced GDAL 3.12+ features
#'
#' @keywords internal
#' @name backends
NULL
