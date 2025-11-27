#' gdalraster Backend - C++ Execution Acceleration
#'
#' @description
#' The gdalraster backend provides fast C++ execution through Rcpp bindings,
#' eliminating subprocess overhead. This is the fastest execution path for
#' batch GDAL operations.
#'
#' gdalcli automatically selects the best available backend:
#' 1. gdalraster (if installed, gdalraster >= 2.2.0)
#' 2. processx (system GDAL subprocess, fallback)
#' 3. reticulate (Python GDAL bindings, if configured)
#'
#' @details
#' ## Why Use gdalraster?
#'
#' **Advantages:**
#' - Fast C++ execution via Rcpp bindings (no subprocess overhead)
#' - Works on Windows with binary package installation
#' - Native R integration for data structures (sf objects, matrices, etc.)
#' - In-memory vector processing with GDAL 3.12+ (gdalraster 2.3.0+)
#' - Better debugging and .error messages from C++ layer
#'
#' **When to use:**
#' - Windows systems without system GDAL installed
#' - Performance-critical applications requiring repeated GDAL operations
#' - In-memory vector processing workflows
#' - When you prefer pure R dependencies without system requirements
#'
#' ## Actual Performance (Benchmarked)
#'
#' **Test Setup:** 50 command discovery operations with gdalraster 2.2.1 + GDAL 3.11.4
#'
#' **Results:**
#' - gdalraster (Rcpp): 0.145 seconds (2.9 ms per call)
#' - processx (subprocess): 2.597 seconds (51.94 ms per call)
#' - **Speedup: 17.91x**
#'
#' **Projected savings at scale:**
#' - 100 operations: ~4.9 seconds saved
#' - 500 operations: ~24 seconds saved
#' - 1000 operations: ~49 seconds saved
#'
#' **Key finding:** Subprocess startup overhead is ~49 ms per operation.
#'
#' ## Installation
#'
#' ### Windows
#' ```r
#' install.packages("gdalraster")  # Pre-compiled binaries, no system GDAL needed
#' ```
#'
#' ### macOS
#' ```r
#' install.packages("gdalraster")
#' ```
#' If binary installation fails, install system GDAL first:
#' ```bash
#' brew install gdal
#' ```
#'
#' ### Linux
#' Install system GDAL first:
#' ```bash
#' # Ubuntu/Debian
#' sudo apt-get install gdal-bin libgdal-dev
#'
#' # Fedora/RHEL
#' sudo dnf install gdal gdal-devel
#'
#' # Arch
#' sudo pacman -S gdal
#' ```
#' Then install the R package:
#' ```r
#' install.packages("gdalraster")
#' ```
#'
#' ## Feature Availability by Version
#'
#' **gdalraster 2.2.0+** provides:
#' - Job execution via `gdal_alg()`
#' - Command discovery (list available operations)
#' - Command help (get help text)
#' - Explicit argument access (for audit logging)
#'
#' **gdalraster 2.3.0+** adds:
#' - Vector from object (in-memory) - Process R objects without temp files
#' - Advanced features - Extended functionality
#'
#' **Minimum requirements:**
#' - gdalraster >= 2.2.0 for basic execution
#' - gdalraster >= 2.3.0 for advanced vector processing
#' - GDAL >= 3.11 for unified CLI commands
#'
#' @examples
#' \dontrun{
#'   library(gdalcli)
#'
#'   # Auto-selection: gdalraster if available, otherwise processx
#'   job <- gdal_raster_info("test.tif")
#'   result <- gdal_job_run(job)
#'
#'   # Force specific backend
#'   result <- gdal_job_run(job, backend = "gdalraster")
#'
#'   # Check gdalraster version
#'   gdalcli:::.get_gdalraster_version()
#'
#'   # Check if feature is available
#'   gdalcli:::.gdal_has_feature("setVectorArgsFromObject")
#' }
#'
#' @seealso
#' [gdalcli::gdal_job_run()] for backend selection,
#' [gdalcli::backends] for all backend options,
#' [gdalcli::GDAL-features] for GDAL 3.12+ features
#'
#' @keywords internal
#' @name gdalraster-backend
NULL


#' Check gdalraster Installation and Version
#'
#' @description
#' Internal utility functions for detecting gdalraster availability and
#' verifying feature support.
#'
#' @details
#' These functions provide the internal infrastructure for backend selection
#' and feature detection:
#'
#' - `.check_gdalraster_version()` - Verify minimum version requirements
#' - `.get_gdalraster_version()` - Get installed version string
#' - `.get_gdalraster_features()` - List available features by version
#' - `.gdal_has_feature()` - Check specific feature with caching
#'
#' See `core-gdalraster-detection.R` for implementation details.
#'
#' @keywords internal
#' @name gdalraster-detection
NULL
