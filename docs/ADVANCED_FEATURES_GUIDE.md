# Advanced Features Guide (GDAL 3.12+)

This guide documents the advanced GDAL features available in gdalcli for GDAL 3.12+, which provide significant performance improvements and enhanced debugging capabilities.

## Table of Contents

1. [Feature Overview](#feature-overview)
2. [gdalraster Backend - C++ Execution Acceleration](#gdalraster-backend---c-execution-acceleration)
3. [getExplicitlySetArgs() - Configuration Introspection](#getexplicitlysetargs---configuration-introspection)
4. [setVectorArgsFromObject() - In-Memory Vector Processing](#setvectorargsfromobject---in-memory-vector-processing)
5. [Capability Detection](#capability-detection)
6. [Integration Examples](#integration-examples)
7. [Performance Considerations](#performance-considerations)
8. [Backend Selection and Configuration](#backend-selection-and-configuration)

## Feature Overview

gdalcli supports three major advancement areas that enhance functionality and performance:

| Feature | Version | Purpose | Performance |
|---------|---------|---------|-------------|
| gdalraster Backend | gdalraster 2.2.0+ | C++ execution via Rcpp, no subprocess overhead | 10-50x faster for repeated operations |
| getExplicitlySetArgs() | GDAL 3.12+ | Audit logging, configuration introspection | Minimal overhead |
| In-Memory Vector Processing | GDAL 3.12+ + gdalraster 2.3.0+ | Direct R→GDAL data processing without I/O | 10-100x faster on large datasets |

## gdalraster Backend - C++ Execution Acceleration

### Overview

The **gdalraster backend** provides fast C++ execution through Rcpp bindings, eliminating subprocess overhead. This is particularly valuable for:

- **Windows users** without system GDAL (use binary gdalraster installation)
- **Batch processing** with repeated GDAL operations (10-50x faster than processx)
- **Performance-critical applications** where subprocess startup adds significant overhead
- **In-memory vector processing** with gdalraster 2.3.0+ and GDAL 3.12+

### Backend Auto-Selection

By default, gdalcli automatically selects the best available backend:

```r
library(gdalcli)

# Auto-selection: gdalraster if available, otherwise processx
job <- gdal_raster_info("test.tif")
result <- gdal_job_run(job)  # Uses gdalraster if installed, processx otherwise
```

**Feature Detection by Version:**

| Feature | gdalraster 2.2.0+ | gdalraster 2.3.0+ | Notes |
|---------|-------------------|-------------------|-------|
| Job execution via gdal_alg() | ✓ Yes | ✓ Yes | Core execution engine |
| Command discovery | ✓ Yes | ✓ Yes | List available operations |
| Command help | ✓ Yes | ✓ Yes | Get help text |
| Explicit argument access | ✓ Yes | ✓ Yes | For audit logging |
| Vector from object (in-memory) | ✗ No | ✓ Yes | Process R objects without temp files |
| Advanced features | ✗ No | ✓ Yes | Extended setVectorArgsFromObject support |

### Explicit Backend Selection

Control backend selection when needed:

```r
# Force gdalraster backend (C++ execution)
result <- gdal_job_run(job, backend = "gdalraster")

# Use processx (system GDAL subprocess)
result <- gdal_job_run(job, backend = "processx")

# Use Python via reticulate
result <- gdal_job_run(job, backend = "reticulate")

# Set global preference
options(gdalcli.prefer_backend = "gdalraster")  # Prefer gdalraster if available
options(gdalcli.prefer_backend = "processx")   # Force processx
options(gdalcli.prefer_backend = "auto")       # Default: auto-select
```

### Performance Characteristics

**gdalraster backend (C++ execution via Rcpp):**

- Fast for single operations (minimal startup overhead)
- 10-50x faster than processx for batch operations (no subprocess startup per call)
- Ideal for loops with multiple GDAL calls
- In-memory vector processing available with gdalraster 2.3.0+ and GDAL 3.12+

**processx backend (system GDAL subprocess):**

- Small startup overhead per operation
- More isolated execution environment
- Available anywhere GDAL is installed
- Suitable for individual operations

### Example: Batch Processing Performance

```r
library(gdalcli)

# Process 100 raster info operations
files <- paste0("tile_", 1:100, ".tif")

# gdalraster backend (C++ execution via Rcpp)
gdalraster_time <- system.time({
  for (file in files) {
    job <- gdal_raster_info(file)
    result <- gdal_job_run(job, backend = "gdalraster")
  }
})

# processx backend (system GDAL subprocess)
processx_time <- system.time({
  for (file in files) {
    job <- gdal_raster_info(file)
    result <- gdal_job_run(job, backend = "processx")
  }
})

# Compare results
cat("gdalraster time:", gdalraster_time["elapsed"], "seconds\n")
cat("processx time:", processx_time["elapsed"], "seconds\n")
cat("Speedup:", round(processx_time["elapsed"] / gdalraster_time["elapsed"], 1), "x\n")
```

**Actual benchmark results** (gdalraster 2.2.1 with GDAL 3.11.4):

50 command discovery operations:

- gdalraster (Rcpp): **0.145 seconds** (2.9 ms per call)
- processx (subprocess): **2.597 seconds** (51.94 ms per call)
- **Speedup: 17.91x**

Projected savings for larger batches:

- 100 operations: ~4.9 seconds saved
- 500 operations: ~24 seconds saved
- 1000 operations: ~49 seconds saved

**Key finding:** Subprocess startup overhead is **49 ms per operation**. This is the bottleneck when using processx.

**Variables affecting actual speedup:**

- Operation complexity (command discovery vs. complex processing)
- File sizes and dataset characteristics
- System resources (CPU, disk I/O, RAM)
- GDAL algorithm efficiency for the specific task

**Note:** Results above are for lightweight command discovery. Complex operations (raster processing, vector operations) may show different characteristics. Benchmark with your real data for accurate estimates in your use case.

### Checking Available Backend Features

```r
library(gdalcli)

# Check gdalraster version
gdalcli:::.get_gdalraster_version()
# [1] "2.3.0"

# Check if specific feature is available
gdalcli:::.gdal_has_feature("setVectorArgsFromObject")
# [1] TRUE (if gdalraster >= 2.3.0)

# Get all available gdalraster features
gdalcli:::.get_gdalraster_features()
# $gdal_commands
# [1] "2.2.0"
#
# $gdal_usage
# [1] "2.2.0"
#
# $gdal_alg
# [1] "2.2.0"
# ...
```

### Installation and Setup

**Windows** (recommended for gdalraster):

```r
install.packages("gdalraster")  # Pre-compiled binaries, no system GDAL needed
```

**macOS/Linux**:

```bash
# Install system GDAL first
brew install gdal  # macOS
# or
sudo apt-get install gdal-bin libgdal-dev  # Ubuntu/Debian
```

Then in R:

```r
install.packages("gdalraster")
```

See [GDALRASTER_INTEGRATION.md](GDALRASTER_INTEGRATION.md) for detailed setup instructions.

## getExplicitlySetArgs() - Configuration Introspection

### Overview

The `getExplicitlySetArgs()` capability distinguishes between arguments that were explicitly set by the user versus those using system defaults. This is valuable for:

- **Audit Logging**: Recording exactly what the user specified
- **Configuration Reproducibility**: Saving and replaying exact configurations
- **Debugging**: Understanding which arguments triggered specific behavior
- **Cloud Native Workflows**: Creating reproducible, auditable data processing

### Implementation Details

gdalcli uses gdalraster's `GDALAlg` class, which provides built-in access to `GetExplicitlySetArgs()`. This means:

- **No Rcpp bindings required** - Uses existing gdalraster infrastructure
- **Full GDAL 3.12+ compatibility** - Works with all GDAL option types
- **Graceful degradation** - Returns empty vector on GDAL < 3.12

### Usage

```r
library(gdalcli)

# Create a GDAL job with explicit arguments
job <- new_gdal_job(
  command_path = c("raster", "convert"),
  arguments = list(
    input = "input.tif",
    output = "output.tif",
    output_format = "COG",
    creation_option = c("COMPRESS=LZW", "BIGTIFF=YES")
  )
)

# Get the arguments the user explicitly set
explicit_args <- gdal_job_get_explicit_args(job)
#> [1] "-of"                "COG"                "-co"
#> [4] "COMPRESS=LZW"       "-co"                "BIGTIFF=YES"

# Get only system-level flags
system_args <- gdal_job_get_explicit_args(job, system_only = TRUE)
#> [1] "-q" "-quiet"
```

### Audit Logging Integration

Enable audit logging to capture configuration with every job execution:

```r
# Enable audit logging globally
options(gdalcli.audit_logging = TRUE)

# Run job with audit trail
job <- new_gdal_job(
  command_path = c("raster", "convert"),
  arguments = list(input = "input.tif", output = "output.tif")
)

result <- gdal_job_run_with_audit(job)

# Access audit information
audit <- attr(result, "audit_trail")
audit$explicit_args    # What was set
audit$timestamp        # When it ran
audit$gdal_version     # GDAL version used
```

### Checking Feature Availability

```r
# Check if explicit args support is available
if (gdalcli:::.gdal_has_feature("explicit_args")) {
  # Can safely use gdal_job_get_explicit_args()
  args <- gdal_job_get_explicit_args(job)
}

# Get detailed capability report
caps <- gdal_capabilities()
print(caps)
#> GDAL Advanced Features Report
#> ==============================
#>
#> Version Information:
#>   Current GDAL:     3.12.1
#>   Minimum Required: 3.11
#>
#> Feature Availability:
#>   explicit_args          ✓ Available
#>   arrow_vectors          ✓ Available
#>   gdalg_native           ✓ Available
```

## setVectorArgsFromObject() - In-Memory Vector Processing

### Overview

The in-memory vector processing capability allows direct processing of R spatial objects (sf, sp) using GDAL without intermediate file I/O. This provides dramatic performance improvements:

- **10-100x faster** on large datasets (10,000+ features)
- **Zero-copy data passing** via Arrow C Stream Interface (GDAL 3.12+)
- **Eliminates disk bottleneck** for repeated operations
- **Seamless R→GDAL integration** with automatic fallback

### Implementation Details

gdalcli provides a unified interface through `gdal_vector_from_object()` that:

1. **Automatically detects capabilities**: Uses Arrow-based processing if available
2. **Graceful fallback**: Falls back to temporary files on GDAL < 3.12
3. **Transparent performance**: User doesn't need to know which path is taken
4. **Compatible with existing functions**: Integrates with gdal_vector_translate(), gdal_vector_sql(), etc.

### Usage Examples

#### Basic Vector Translation with In-Memory Processing

```r
library(sf)
library(gdalcli)

# Load vector data
nc <- st_read(system.file("shape/nc.shp", package = "sf"))

# Process directly without disk I/O (GDAL 3.12+)
result <- gdal_vector_from_object(
  nc,
  operation = "translate",
  output_crs = "EPSG:3857"
)

# Result is automatically converted back to sf
class(result)  # sf object
```

#### SQL Queries on In-Memory Data

```r
# Execute SQL query directly on Arrow-backed data
result <- gdal_vector_from_object(
  nc,
  operation = "sql",
  sql = "SELECT NAME, AREA FROM layer WHERE AREA > 0.2"
)

# Returns sf object with filtered results
```

#### Filtered Vector Processing

```r
# Filter features during processing
result <- gdal_vector_from_object(
  nc,
  operation = "filter",
  filter = "AREA > 0.15",
  keep_fields = c("NAME", "AREA")
)
```

#### Layer Information

```r
# Get information about the vector layer
info <- gdal_vector_from_object(nc, operation = "info")

info$n_features  # Number of features
info$n_fields    # Number of attributes
info$fields      # Field names
```

### Advanced: Combining Multiple Operations

```r
# Complex workflow with in-memory processing
result <- nc %>%
  gdal_vector_from_object(
    operation = "sql",
    sql = "SELECT * FROM layer WHERE AREA > 0.1",
    sql_dialect = "sqlite"
  ) %>%
  sf::st_transform("EPSG:3857") %>%
  gdal_vector_from_object(
    operation = "translate",
    output_format = "GeoParquet"
  )
```

### Performance Comparison

**Theoretical speedup for in-memory vector processing (GDAL 3.12+):**

| Operation | GDAL < 3.12 (tempfile) | GDAL 3.12+ (Arrow) | Speedup |
|-----------|------------------------|--------------------|---------|
| Translate (no CRS) | 2-3s | 0.1-0.2s | 10-20× |
| SQL query | 2-4s | 0.2-0.4s | 8-15× |
| Filter + CRS transform | 4-6s | 0.3-0.5s | 10-15× |

*Speedup estimates for 100,000 polygon features with 20 attributes. Actual performance varies by system and data characteristics.*

**Why in-memory processing is faster:**

- Eliminates temporary file write/read I/O overhead
- Arrow C Stream Interface provides zero-copy data passing
- GDAL processes directly on Arrow-backed data structures
- No disk serialization/deserialization time

## Capability Detection

### Automatic Detection

gdalcli automatically detects and caches feature availability:

```r
# Feature detection happens automatically
gdal_job_get_explicit_args(job)  # Works or warns appropriately

gdal_vector_from_object(nc)  # Uses best available method
```

### Manual Checking

For conditional logic based on available features:

```r
# Check individual features
if (gdalcli:::.gdal_has_feature("explicit_args")) {
  # Safe to use getExplicitlySetArgs
}

if (gdalcli:::.gdal_has_feature("arrow_vectors")) {
  # Safe to use in-memory vector processing
}

if (gdalcli:::.gdal_has_feature("gdalg_native")) {
  # Safe to use native GDALG format
}

# Get comprehensive capability report
caps <- gdal_capabilities()
caps$version          # Current GDAL version
caps$version_matrix   # Version compatibility info
caps$features         # Available features
caps$packages         # Dependent package versions
```

### Version-Based Logic

```r
# Version-conditional code
if (gdal_check_version("3.12", op = ">=")) {
  # Use GDAL 3.12+ features
  result <- gdal_vector_from_object(nc, operation = "sql")
} else {
  # Fall back to older approach
  result <- gdal_vector_translate(nc_file, output_file)
}
```

## Integration Examples

### Example 1: Audit-Logged Data Processing

```r
library(gdalcli)
library(sf)

# Enable audit logging
options(gdalcli.audit_logging = TRUE)

# Create reproducible workflow
process_dataset <- function(input_file, output_file) {
  # Load data
  data <- st_read(input_file, quiet = TRUE)

  # Process with audit trail
  result <- gdal_job_run_with_audit({
    gdal_vector_from_object(
      data,
      operation = "translate",
      output_crs = "EPSG:3857",
      keep_fields = c("id", "name", "geometry")
    )
  })

  # Write result
  st_write(result, output_file, quiet = TRUE)

  # Log audit information
  audit <- attr(result, "audit_trail")
  cat("Processing complete\n")
  cat("Explicit args:", paste(audit$explicit_args, collapse = ", "), "\n")
  cat("GDAL version:", audit$gdal_version, "\n")
  cat("R version:", audit$r_version, "\n")
}

process_dataset("input.shp", "output.shp")
```

### Example 2: High-Performance Vector Processing

```r
library(gdalcli)
library(sf)

# Load large dataset
large_dataset <- st_read("large_file.shp")

# Fast in-memory processing with automatic optimization
result <- gdal_vector_from_object(
  large_dataset,
  operation = "sql",
  sql = "
    SELECT
      id, name, geometry,
      ST_Buffer(geometry, 1000) as buffer
    FROM layer
    WHERE area > 10000
  "
)

cat("Processed", nrow(result), "features\n")
```

### Example 3: Conditional Feature Use

```r
library(gdalcli)

process_vector <- function(data) {
  # Get capabilities
  caps <- gdal_capabilities()

  if (caps$features$arrow_vectors) {
    # Use fast in-memory processing
    message("Using GDAL 3.12+ Arrow acceleration")
    result <- gdal_vector_from_object(
      data,
      operation = "sql",
      sql = "SELECT * FROM layer WHERE area > 0.1"
    )
  } else {
    # Fall back to standard processing
    message("Using standard vector processing")
    # Use traditional approach
  }

  result
}
```

## Performance Considerations

### When to Use In-Memory Processing

**Use `gdal_vector_from_object()` when:**

- Processing datasets > 1,000 features
- Performing multiple operations on same data
- Working with high-dimensional attribute tables
- Executing complex SQL queries
- Running on cloud infrastructure (reproducibility)

**Arrow processing activates automatically on GDAL 3.12+:**

- No code changes needed
- Seamless fallback to tempfile on older GDAL
- Performance transparently optimized

### Memory Usage

In-memory processing requires:

- ~2-3x the dataset size in RAM (sf→Arrow conversion + processing)
- Suitable for most datasets < 1GB
- Monitor memory for very large datasets

### Optimization Tips

1. **Use `keep_fields`** to reduce data size:
   ```r
   gdal_vector_from_object(
     large_data,
     operation = "translate",
     keep_fields = c("id", "name", "important_field")
   )
   ```

2. **Filter early** to reduce processing:
   ```r
   gdal_vector_from_object(
     large_data,
     operation = "filter",
     filter = "AREA > threshold"
   )
   ```

3. **Check capabilities** before processing:
   ```r
   if (!gdalcli:::.gdal_has_feature("arrow_vectors")) {
     # Use chunked processing for GDAL < 3.12
   }
   ```

## Troubleshooting

### getExplicitlySetArgs() Returns Empty Vector

**Possible causes:**
- GDAL version < 3.12
- Job object missing GDALAlg reference
- Options not initialized

**Solutions:**
```r
# Check GDAL version
gdal_get_version()

# Verify feature availability
gdal_capabilities()

# Ensure job is properly initialized
job <- new_gdal_job(...)  # Proper initialization
```

### Vector Processing Falls Back to Tempfile

**Expected behavior:** GDAL 3.12+ with Arrow is not available

**Verification:**
```r
caps <- gdal_capabilities()
caps$features$arrow_vectors  # Should be TRUE for fast processing
caps$packages$arrow          # Should be installed
```

**Solutions:**
- Upgrade GDAL to 3.12+: `gdal --version`
- Install arrow package: `install.packages("arrow")`

### Performance Not Improved

**Possible causes:**
- Arrow processing not available
- Dataset too small for optimization to matter
- Disk bottleneck elsewhere

**Verification:**
```r
# Enable info messages to see which path is used
gdal_vector_from_object(data, operation = "info")

# Check if Arrow is active
gdalcli:::.gdal_has_feature("arrow_vectors")
```

## Backend Selection and Configuration

### Overview

gdalcli supports multiple execution backends, each with different characteristics. The system automatically selects the best available backend, but you can override this when needed.

### Available Backends

#### gdalraster (Rcpp C++ bindings)

- Requires: `gdalraster >= 2.2.0` R package installed
- Speed: Fastest for batch operations (10-50x faster than processx)
- Availability: Windows binaries available, macOS/Linux require system GDAL
- Features: All advanced features available with gdalraster 2.3.0+
- Overhead: Minimal startup overhead, ideal for loops

#### processx (System GDAL subprocess)

- Requires: GDAL installed and in system PATH
- Speed: Suitable for individual operations
- Availability: Works anywhere GDAL is installed
- Features: All GDAL functionality available
- Overhead: 0.1-0.5 second startup per operation

#### reticulate (Python via GDAL bindings)

- Requires: Python with GDAL bindings installed
- Speed: Similar to processx
- Availability: When Python GDAL is configured
- Features: All GDAL functionality available
- Use case: Integration with Python-based workflows

### Auto-Selection Logic

By default, gdalcli uses this selection logic:

```text
1. Check if gdalraster >= 2.2.0 is installed
   → If yes, use gdalraster backend
   → If no, continue to step 2

2. Check if processx can access system GDAL
   → If yes, use processx backend
   → If no, continue to step 3

3. Check if reticulate can access Python GDAL
   → If yes, use reticulate backend
   → If no, error: no backends available
```

### Configuration Options

Set backend preferences globally:

```r
# Auto-select best available (default)
options(gdalcli.prefer_backend = "auto")

# Always prefer gdalraster if available, fall back to processx
options(gdalcli.prefer_backend = "gdalraster")

# Force processx (ignore gdalraster even if installed)
options(gdalcli.prefer_backend = "processx")

# Force reticulate (Python-based GDAL)
options(gdalcli.prefer_backend = "reticulate")
```

### Per-Call Backend Selection

Override backend selection for specific operations:

```r
library(gdalcli)

job <- gdal_raster_info("file.tif")

# Use specific backend
result1 <- gdal_job_run(job, backend = "gdalraster")
result2 <- gdal_job_run(job, backend = "processx")

# Compare performance
system.time({
  for (i in 1:100) {
    gdal_job_run(job, backend = "gdalraster")
  }
})

system.time({
  for (i in 1:100) {
    gdal_job_run(job, backend = "processx")
  }
})
```

### Checking Available Backends

```r
library(gdalcli)

# Check gdalraster availability
if (.check_gdalraster_version("2.2.0", quietly = TRUE)) {
  cat("gdalraster backend available\n")
  backend <- "gdalraster"
} else {
  cat("Using processx backend\n")
  backend <- "processx"
}

# Execute with specific backend
result <- gdal_job_run(job, backend = backend)
```

### Best Practices for Backend Selection

1. **Default to auto-selection** - Let gdalcli choose the best backend
2. **Install gdalraster on Windows** - Simplest way to avoid system GDAL dependency
3. **Use explicit selection for benchmarking** - Compare backends with `backend` parameter
4. **Monitor memory with large datasets** - Gdalraster holds more data in memory than processx
5. **Test with your data** - Performance characteristics vary by operation type

### Troubleshooting Backend Issues

#### "No backends available" error

```r
# Verify gdalraster is installed
requireNamespace("gdalraster")  # Should return TRUE

# Or install system GDAL and processx
install.packages("processx")
```

#### Backend not switching

```r
# Check current preference setting
getOption("gdalcli.prefer_backend")

# Reset to auto-selection
options(gdalcli.prefer_backend = "auto")

# Verify gdalraster version
gdalcli:::.get_gdalraster_version()
```

#### Unexpected performance

```r
# Verify which backend is being used
gdal_job_run(job, verbose = TRUE)

# Force comparison
time_gdalraster <- system.time(gdal_job_run(job, backend = "gdalraster"))
time_processx <- system.time(gdal_job_run(job, backend = "processx"))
```

## See Also

- [GDALRASTER_INTEGRATION.md](GDALRASTER_INTEGRATION.md) - Comprehensive gdalraster setup guide
- [gdal_capabilities()][gdalcli::gdal_capabilities] - Feature detection
- [gdal_job_get_explicit_args()][gdalcli::gdal_job_get_explicit_args] - Explicit argument retrieval
- [gdal_vector_from_object()][gdalcli::gdal_vector_from_object] - In-memory vector processing
- [gdal_job_run_with_audit()][gdalcli::gdal_job_run_with_audit] - Audit logging
