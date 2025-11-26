# gdalraster Backend Integration

## Overview

gdalcli supports multiple execution backends. The **gdalraster backend** uses R bindings to GDAL via Rcpp, providing fast C++ execution without subprocess overhead. This makes gdalraster especially valuable for Windows users who can install gdalraster binaries without needing a system GDAL installation.

## Why Use gdalraster?

**Advantages:**
- Fast execution via C++ Rcpp bindings (no subprocess overhead)
- Works on Windows with binary package installation
- Native R integration for data structures (sf objects, matrices, etc.)
- In-memory vector processing with GDAL 3.12+
- Better debugging and error messages from C++ layer

**When to use:**
- Windows systems without system GDAL installed
- Performance-critical applications requiring repeated GDAL operations
- In-memory vector processing workflows
- When you prefer pure R dependencies without system requirements

## Installation

gdalraster is optional and managed through R's package manager.

### Windows

```r
install.packages("gdalraster")
```

gdalraster provides pre-compiled binaries for Windows, requiring no system GDAL installation.

### macOS

```r
install.packages("gdalraster")
```

If binary installation fails, Homebrew can install system GDAL:
```bash
brew install gdal
```

Then retry the R package installation.

### Linux

System GDAL must be installed first:

```bash
# Ubuntu/Debian
sudo apt-get install gdal-bin libgdal-dev

# Fedora/RHEL
sudo dnf install gdal gdal-devel

# Arch
sudo pacman -S gdal
```

Then install the R package:
```r
install.packages("gdalraster")
```

## Feature Availability by Version

| Feature | gdalraster 2.2.0 | gdalraster 2.3.0 | Notes |
|---------|------------------|------------------|-------|
| Job execution via gdal_alg() | Yes | Yes | Core execution engine |
| Command discovery (gdal_commands) | Yes | Yes | List available GDAL operations |
| Command help (gdal_usage) | Yes | Yes | Get help text for commands |
| Explicit args (getExplicitlySetArgs) | Yes | Yes | Extract explicitly set arguments |
| Vector from object (in-memory) | No | Yes | Process R objects without temp files |
| Advanced features | No | Yes | setVectorArgsFromObject and more |

**Minimum requirements:**
- gdalraster >= 2.2.0 for basic execution
- gdalraster >= 2.3.0 for advanced vector processing
- GDAL >= 3.11 for unified CLI commands

## Usage Examples

### Auto Backend Selection (Default)

By default, gdalcli automatically uses gdalraster if available:

```r
library(gdalcli)

# Check what backend will be used
job <- gdal_raster_info("test.tif")
result <- gdal_job_run(job)
# If gdalraster is installed, this uses C++ execution
# Otherwise falls back to processx (system GDAL)
```

### Explicit Backend Selection

Force a specific backend:

```r
# Use gdalraster backend explicitly
result <- gdal_job_run(job, backend = "gdalraster")

# Use processx backend (system GDAL subprocess)
result <- gdal_job_run(job, backend = "processx")

# Use Python backend via reticulate
result <- gdal_job_run(job, backend = "reticulate")
```

### Configure Default Backend

Set global preference:

```r
# Prefer gdalraster if available
options(gdalcli.prefer_backend = "gdalraster")

# Force processx even if gdalraster installed
options(gdalcli.prefer_backend = "processx")

# Auto-select (default)
options(gdalcli.prefer_backend = "auto")
```

### Check Available Features

Determine what features your installed gdalraster supports:

```r
library(gdalcli)

# Check gdalraster version
gdalcli:::.get_gdalraster_version()
# [1] "2.3.0"

# Check if specific feature available
gdalcli:::.gdal_has_feature("setVectorArgsFromObject")
# [1] TRUE (if gdalraster >= 2.3.0)

# Get list of all available features
gdalcli:::.get_gdalraster_features()
```

## Performance Comparison

**gdalraster backend (C++ execution):**
- Fast for single operations (no subprocess startup)
- Ideal for loops with multiple GDAL calls
- In-memory vector processing available with GDAL 3.12+

**processx backend (system GDAL subprocess):**
- Small startup overhead per operation
- More isolated execution environment
- Available anywhere GDAL is installed

Example: Processing 100 raster operations

```r
library(gdalcli)
library(sf)
library(microbenchmark)

# gdalraster backend (automatic if installed)
gdalraster_time <- microbenchmark(
  for (i in 1:100) {
    job <- gdal_raster_info("test.tif")
    gdal_job_run(job, backend = "gdalraster")
  },
  times = 1
)

# processx backend
processx_time <- microbenchmark(
  for (i in 1:100) {
    job <- gdal_raster_info("test.tif")
    gdal_job_run(job, backend = "processx")
  },
  times = 1
)

# gdalraster typically 10-50x faster for repeated operations
```

## In-Memory Vector Processing (GDAL 3.12+)

When gdalraster 2.3.0+ is installed with GDAL 3.12+, vector operations on R objects avoid temporary files:

```r
library(sf)
library(gdalcli)

# Load vector data
nc <- st_read(system.file("shape/nc.shp", package = "sf"))

# Process without temporary files (GDAL 3.12+ with gdalraster 2.3.0+)
result <- gdal_vector_from_object(
  nc,
  operation = "sql",
  sql = "SELECT * FROM layer WHERE AREA > 0.2"
)
# Uses gdalraster in-memory processing
# Falls back to temp files if requirements not met
```

## Troubleshooting

### "gdalraster package required for this operation"

gdalraster is not installed. Install it:
```r
install.packages("gdalraster")
```

Or explicitly use processx:
```r
gdal_job_run(job, backend = "processx")
```

### Version mismatch errors

Check your installed versions:
```r
packageVersion("gdalraster")  # R package version
gdalcli::gdal_check_version()  # GDAL version
```

Upgrade gdalraster if needed:
```r
install.packages("gdalraster")  # Gets latest binary
```

### Feature not available error

Your gdalraster version doesn't support that feature. Check:
```r
gdalcli:::.get_gdalraster_features()
```

Features requiring gdalraster >= 2.3.0:
- `setVectorArgsFromObject`
- `advanced_features`

Upgrade if needed:
```r
install.packages("gdalraster")
```

### Performance not as expected

Verify you're using the right backend:
```r
# Check which backend will be used
gdal_job_run(job)  # Shows backend in verbose output

# Compare backends explicitly
microbenchmark(
  gdal_job_run(job, backend = "gdalraster"),
  gdal_job_run(job, backend = "processx")
)
```

Single operations may show small differences. Improvement is most visible in loops or batch processing.

## Best Practices

1. **Install gdalraster on Windows** - Gets GDAL without system dependencies
2. **Let auto-selection work** - Default behavior chooses the best backend
3. **Use explicit backend selection** only when testing or comparing performance
4. **Check feature availability** before using advanced features
5. **Use gdalraster for batch processing** - Most benefit from lack of subprocess startup
6. **Fall back to processx** if you encounter compatibility issues

## Related Documentation

- [ADVANCED_FEATURES_GUIDE.md](ADVANCED_FEATURES_GUIDE.md) - Advanced gdalraster features
- [VERSION_MATRIX.md](VERSION_MATRIX.md) - Complete version compatibility
- `?gdal_job_run` - Backend selection in R help
