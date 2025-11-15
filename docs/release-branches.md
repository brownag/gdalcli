# Version-Pinned Release Branches

This document explains gdalcli's release strategy and how to use version-pinned release branches.

## Overview

gdalcli uses a **multi-version release strategy** to support different GDAL installations:

- **Development branch** (`main`) - Latest features, requires runtime GDAL detection
- **Release branches** (`release/gdal-3.11`, `release/gdal-3.12`, etc.) - Pre-computed for specific GDAL versions

Each release branch has:
1. ✅ **Pre-generated static API** (83+ functions) for immediate availability
2. ✅ **Enriched documentation** from official GDAL docs
3. ✅ **Version-specific metadata** for compatibility checking
4. ✅ **Pre-seeded dynamic API cache** for fast first load (< 100ms)

## Installation

### Option 1: Main Branch (Any GDAL >= 3.11)

Install from main development branch:

```r
# From GitHub
remotes::install_github("andrewbrown/gdalcli")

# Or from R-Universe (all versions)
install.packages('gdalcli', repos = 'https://andrewbrown.r-universe.dev')
```

**Pros:**
- Always get latest features
- Works with any GDAL >= 3.11

**Cons:**
- First load takes 5-10 seconds (dynamic API build)
- Requires gdalraster + system GDAL at runtime

### Option 2: Version-Pinned Release Branch (GDAL 3.11)

For users with GDAL 3.11.x installed:

```r
# From GitHub
remotes::install_github("andrewbrown/gdalcli", ref = "release/gdal-3.11")

# Or from GDAL 3.11-specific R-Universe
install.packages('gdalcli',
  repos = 'https://andrewbrown-gdal311.r-universe.dev')
```

**Pros:**
- Static API available immediately (no build delay)
- Pre-seeded cache for fast first load
- Version-specific optimization
- Works without gdalraster (static API only)

**Cons:**
- Need to use correct branch for your GDAL version
- Different installations need different branches

### Option 3: Version-Pinned Release Branch (GDAL 3.12)

For users with GDAL 3.12.x installed:

```r
# From GitHub
remotes::install_github("andrewbrown/gdalcli", ref = "release/gdal-3.12")

# Or from GDAL 3.12-specific R-Universe
install.packages('gdalcli',
  repos = 'https://andrewbrown-gdal312.r-universe.dev')
```

## Checking Your Installation

After installing, check compatibility:

```r
library(gdalcli)

# Check version compatibility
result <- gdal_version_check()
cat(result$message, "\n")

# View details
str(result)
```

Output if versions match:
```
✓ Package built for GDAL 3.11, runtime GDAL 3.11.1 - compatible
```

Output if versions mismatch:
```
⚠ Package built for GDAL 3.11, but runtime GDAL 3.12.0 detected - may have compatibility issues
```

## Version Metadata (Auto-Generated)

Each release branch includes an auto-generated `inst/GDAL_VERSION_INFO.json` file created by the GitHub Actions workflow. Example:

```json
{
  "gdal_version": "3.11.1",
  "release_date": "2024-09-04",
  "api_generation_date": "2025-11-12",
  "command_count": 83,
  "groups": ["raster", "vector", "mdim", "vsi", "driver"],
  "branch": "release/gdal-3.11",
  "package_version": "0.2.0+gdal3.11",
  "notes": "Pre-computed API for GDAL 3.11.x series"
}
```

This metadata is used by `gdal_version_check()` to validate runtime compatibility.

## Release Branch Details

### GDAL 3.11 Release

- **Branch:** `release/gdal-3.11`
- **R-Universe:** `https://andrewbrown-gdal311.r-universe.dev`
- **GitHub:** `https://github.com/andrewbrown/gdalcli/tree/release/gdal-3.11`
- **GDAL Requirement:** `>= 3.11.0, < 3.12`
- **Tested With:** GDAL 3.11.1
- **Commands:** 83+ raster, vector, mdim, VSI, and driver functions

**Installation:**
```r
install.packages('gdalcli', repos = 'https://andrewbrown-gdal312.r-universe.dev')
```

### GDAL 3.12 Release (When Available)

- **Branch:** `release/gdal-3.12`
- **R-Universe:** `https://andrewbrown-gdal312.r-universe.dev`
- **GitHub:** `https://github.com/andrewbrown/gdalcli/tree/release/gdal-3.12`
- **GDAL Requirement:** `>= 3.12.0, < 3.13`
- **Commands:** 83+ (architecture-specific commands)

**Installation:**
```r
install.packages('gdalcli', repos = 'https://andrewbrown-gdal312.r-universe.dev')
```

## Architecture

### Static API (All Release Branches)

Pre-generated functions like `gdal_raster_info()`, `gdal_vector_convert()`, etc.

**Characteristics:**
- Generated at build time from `build/generate_gdal_api.R`
- Uses `gdal --json-usage` to discover command structure
- Returns `gdal_job` objects for lazy evaluation
- Available immediately on package load
- Works with any GDAL version (within reason)

**Example:**
```r
library(gdalcli)

# Static API function (available immediately)
job <- gdal_raster_info(input = "data.tif")

# Execute
result <- gdal_run(job)
```

### Dynamic API (Main Branch + Cached)

Hierarchical R6 object structure: `gdal$raster$convert()`

**Characteristics:**
- Built at runtime by `.onLoad` hook
- Uses `gdalraster::gdal_commands()` for introspection
- Cached per GDAL version in user cache directory
- Pre-seeded in release branches for fast load
- Provides IDE autocompletion

**Example:**
```r
library(gdalcli)

# Dynamic API (built from cache or live)
job <- gdal$raster$info(input = "data.tif")

# Execute
result <- gdal_run(job)
```

## Workflow: Choosing the Right Branch

```
Do you have GDAL installed?
├─ NO → Use main branch (dynamic API builds)
│       or use static-only release branch
│
├─ YES: What version?
│   ├─ 3.11.x → Use release/gdal-3.11
│   │
│   ├─ 3.12.x → Use release/gdal-3.12
│   │
│   └─ Other → Use main branch (dynamic API detects)
│
```

## Troubleshooting

### "Package built for GDAL 3.11 but runtime GDAL 3.12 detected"

**Cause:** You installed the 3.11 release branch, but your system has GDAL 3.12.

**Solution:**
1. Check your GDAL version: `gdal --version`
2. Reinstall from correct release branch or main branch
3. Or downgrade/upgrade your GDAL installation

### "First load takes 10 seconds"

**Cause:** Using main branch which builds dynamic API at load time.

**Solution:** Switch to version-pinned release branch for your GDAL version.

### "gdalraster not found"

**Cause:** Dynamic API requires gdalraster package.

**Solution:**
```r
install.packages("gdalraster")
```

Or use static-only release branch (doesn't require gdalraster).

## Development

For developers working with multiple GDAL versions:

```bash
# Generate release branch for GDAL 3.11
Rscript -c "
# In a Docker container with GDAL 3.11
Rscript build/generate_gdal_api.R
"

# Or use GitHub Actions workflow
# (See .github/workflows/release-branch.yml)
```

## See Also

- [gdalcli README](../README.md)
- [Dynamic API Guide](../vignettes/dynamic-api.Rmd)
- [GDAL Documentation](https://gdal.org)
- [gdalraster Package](https://usdaforestservice.github.io/gdalraster/)
