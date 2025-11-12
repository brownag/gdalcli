# gdalcli: A Generative R Frontend for the GDAL (≥3.11) Unified CLI

[![Lifecycle: experimental](https://img.shields.io/badge/lifecycle-experimental-orange.svg)](https://lifecycle.r-lib.org/articles/stages.html)

A modern R interface to GDAL's unified command-line interface (GDAL ≥3.11). Provides a **lazy evaluation framework** for building and executing GDAL commands with composable, pipe-aware functions.

## Overview

`gdalcli` implements a generative frontend for GDAL ≥3.11's unified CLI with:

- **Auto-Generated Functions**: 80+ R wrapper functions automatically generated from GDAL's JSON API specification
- **Lazy Evaluation**: Build command specifications as objects (`gdal_job`), execute only when needed via `gdal_run()`
- **Pipe Composition**: Native R pipe (`|>`) support with S3 methods for adding options and environment variables
- **Secure Authentication**: Environment-variable-only credential management (no hardcoded secrets)
- **VSI Streaming**: Support for `/vsistdin/` and `/vsistdout/` for file-less, memory-efficient workflows
- **Process Isolation**: Credentials passed directly to subprocess, avoiding global state pollution

## Quick Start

### Installation

```r
# Install from GitHub (when available)
# devtools::install_github("your-org/gdalcli")
library(gdalcli)
```

### Basic Setup: Configure Credentials via .Renviron

Add to your `~/.Renviron`:

```env
AWS_ACCESS_KEY_ID=your_access_key_id
AWS_SECRET_ACCESS_KEY=your_secret_access_key
```

Then restart R or run `readRenviron("~/.Renviron")`.

### Example 1: Vector Format Conversion

```r
library(gdalcli)

# Credentials are read from environment automatically
auth <- gdal_auth_s3()

# Build and execute command with lazy evaluation
gdal_vector_convert(
  input = "s3://my-bucket/data.shp",
  output = "converted.gpkg",
  output_format = "GPKG"
) |>
  gdal_with_env(auth) |>  # Add credentials via environment
  gdal_run()              # Execute when ready
```

### Example 2: Raster Clipping with Options

```r
library(gdalcli)

# Add AWS credentials
auth <- gdal_auth_s3()

# Clip a raster with creation options
gdal_raster_clip(
  input = "s3://sentinel-pds/tiles/32/U/QD/2020/12/1/0/TCI_10m.tif",
  output = "clipped.tif",
  projwin = c(640000, 6000000, 641000, 5999000)
) |>
  gdal_with_co("COMPRESS=DEFLATE", "BLOCKXSIZE=256") |>  # Creation options
  gdal_with_env(auth) |>                                   # Environment variables
  gdal_run()
```

## Features

- **80+ Auto-Generated Functions**: Complete coverage of GDAL's unified CLI including raster, vector, multidimensional (MDim), VSI, and driver-specific operations.

- **Lazy Evaluation Framework**: Build command specifications as `gdal_job` objects that are only executed when passed to `gdal_run()`, enabling introspection and composition.

- **Composable Modifiers**: S3 methods for adding options:
  - `gdal_with_co()` - Creation options (e.g., `COMPRESS=DEFLATE`)
  - `gdal_with_lco()` - Layer creation options
  - `gdal_with_oo()` - Open options
  - `gdal_with_config()` - GDAL configuration options
  - `gdal_with_env()` - Environment variables (credentials)

- **Secure Credential Management**: Environment-variable-only authentication with support for AWS S3, Azure, GCS, OSS, and OpenStack Swift. No hardcoded secrets in function arguments.

- **Native Pipe Support**: Full compatibility with R's native pipe (`|>`):

  ```r
  gdal_vector_convert(...) |>
    gdal_with_co(...) |>
    gdal_with_env(...) |>
    gdal_run()
  ```

- **VSI Streaming**: Support for `/vsistdin/` and `/vsistdout/` for memory-efficient, streaming workflows without intermediate files.

## GDAL Function Categories

The 80+ auto-generated functions are organized into logical categories:

### Raster Operations

Functions for working with raster datasets: `gdal_raster_*`

- **gdal_raster_convert** - Format conversion
- **gdal_raster_clip** - Spatial subsetting
- **gdal_raster_resample** - Resampling/reprojection
- **gdal_raster_contour** - Contour generation
- **gdal_raster_aspect** - Aspect calculation
- And many more...

### Vector Operations

Functions for working with vector datasets: `gdal_vector_*`

- **gdal_vector_convert** - Format conversion
- **gdal_vector_info** - Dataset information
- **gdal_vector_translate** - Complex transformations
- And more...

### Multidimensional (MDim)

Functions for multidimensional data: `gdal_mdim_*`

- **gdal_mdim_convert** - Dimension conversion
- **gdal_mdim_info** - Dimension information

### VSI (Virtual File System)

Functions for cloud storage and remote access: `gdal_vsi_*`

- Support for S3, Azure, GCS, OSS, Swift with automatic credential handling

### Driver-Specific Operations

Functions for specific format drivers: `gdal_driver_*`

- GeoPackage repacking, GTI creation, PDF operations, and more

Use `gdal_gdal(drivers = TRUE)` to list all available drivers in your GDAL installation.

## System Requirements

- **R** ≥ 3.6
- **GDAL** ≥ 3.11 (required for unified CLI)
- **Dependencies**: `processx` (≥3.8.0), `jsonlite` (≥1.8.0), `rlang`, `cli`

## Documentation

- **Getting Started**: `?gdal_vector_convert` - Example auto-generated function
- **Authentication**: `?gdal_auth_s3`, `?gdal_auth_azure`, etc. - Set up credentials
- **Lazy Evaluation**: `?gdal_job` - Understand the job specification system
- **Execution**: `?gdal_run` - Run GDAL commands
- **Composition**: `?gdal_with_co`, `?gdal_with_env` - Modify jobs with modifiers

## More Examples

### Example 1: Public S3 Data (No Credentials)

```r
library(gdalcli)

# Access public Sentinel-2 data without authentication
gdal_raster_info(
  input = "/vsis3/sentinel-pds/tiles/10/S/DG/2015/12/7/0/B01.jp2"
) |>
  gdal_auth_s3(no_sign_request = TRUE) |>
  gdal_run()
```

### Example 2: Private Azure Storage with SAS Token

```r
library(gdalcli)

# Set Azure SAS credentials in .Renviron:
# AZURE_STORAGE_ACCOUNT=myaccount
# AZURE_STORAGE_SAS_TOKEN=st=2023-01-01&se=2024-12-31...

auth <- gdal_auth_azure()

gdal_vector_info(
  input = "/vsiaz/geospatial/boundary.shp"
) |>
  gdal_with_env(auth) |>
  gdal_run()
```

### Example 3: Lazy Job Building with Introspection

```r
library(gdalcli)

# Build a job specification without executing
job <- gdal_raster_clip(
  input = "input.tif",
  output = "output.tif",
  projwin = c(0, 100, 100, 0)
) |>
  gdal_with_co("COMPRESS=DEFLATE", "BLOCKXSIZE=256") |>
  gdal_with_config("GDAL_CACHEMAX" = "512")

# Inspect the job before execution
print(job)

# Execute when ready
gdal_run(job)
```

### Example 4: Cloud-to-Cloud Format Conversion

```r
library(gdalcli)

# Set GCS credentials via environment
# GOOGLE_APPLICATION_CREDENTIALS=/path/to/credentials.json

auth <- gdal_auth_gcs()

gdal_raster_convert(
  input = "/vsigs/my-bucket/data.tif",
  output = "/vsis3/my-s3-bucket/data.gpkg",
  output_format = "GPKG"
) |>
  gdal_with_env(auth) |>
  gdal_run()
```

## Architecture & Design

### Two-Layer Model

`gdalcli` separates concerns into two layers:

1. **Frontend Layer** (User-facing R API)
   - Auto-generated functions like `gdal_vector_convert()`
   - Composable modifiers: `gdal_with_co()`, `gdal_with_env()`, etc.
   - S3 methods for extensibility
   - Lazy `gdal_job` specification objects

2. **Engine Layer** (Command Execution)
   - `gdal_run()` executes `gdal_job` objects
   - Uses processx for robust subprocess management
   - Handles environment variable injection
   - Supports input/output streaming

### Lazy Evaluation

Commands are built as specifications (`gdal_job` objects) and only executed when passed to `gdal_run()`:

```r
# This doesn't execute anything - just builds a specification
job <- gdal_vector_convert(
  input = "data.shp",
  output = "data.gpkg"
)

# Inspect the job before running
print(job)

# Execute only when ready
gdal_run(job)
```

### S3-Based Composition

All modifiers are S3 generics that accept and return `gdal_job` objects, enabling composable workflows:

```r
# Each step returns a modified gdal_job
gdal_raster_convert(...) |>
  gdal_with_co("COMPRESS=DEFLATE") |>  # Add creation option
  gdal_with_config("GDAL_CACHEMAX" = "512") |>  # Add config
  gdal_with_env(auth) |>                       # Add credentials
  gdal_run()                                   # Execute
```

### Environment-Based Credentials

Credentials are read from environment variables, never passed as function arguments:

```r
# Good ✓ - Credentials in .Renviron, not in code
# ~/.Renviron
# AWS_ACCESS_KEY_ID=your_key
# AWS_SECRET_ACCESS_KEY=your_secret

auth <- gdal_auth_s3()  # Reads from environment
job <- gdal_vector_convert(...) |>
  gdal_with_env(auth) |>
  gdal_run()

# Bad ❌ - Never pass credentials as arguments!
# This pattern is NOT supported and would expose secrets in code history
```

## Security Considerations

1. **Credentials in .Renviron, not in code** - Never pass secrets as function arguments. Use `.Renviron` or external secret managers:

   ```env
   # ~/.Renviron or project .Renviron
   AWS_ACCESS_KEY_ID=your_access_key
   AWS_SECRET_ACCESS_KEY=your_secret
   ```

2. **Environment-variable-only design** - Auth helpers read from environment, never from function arguments. This prevents accidental commits of credentials.

3. **Don't save R sessions** - Avoid saving `.RData` files or R session history containing credentials.

4. **Use temporary/rotatable credentials** - When possible, use temporary credentials (AWS STS, Azure Managed Identity, GCS service accounts) instead of long-lived secrets.

5. **Rotate credentials regularly** - Follow your organization's credential rotation policies.

6. **Use external secret managers** - For production, consider:
   - HashiCorp Vault
   - AWS Secrets Manager
   - Azure Key Vault
   - Google Cloud Secret Manager
   - 1Password, Bitwarden, or other password managers with environment variable integration

## Performance Tips

- **Lazy evaluation for exploration** - Build `gdal_job` objects to inspect what would execute without running:

  ```r
  job <- gdal_raster_clip(...)
  print(job)  # See the command that would run
  ```

- **Batch operations efficiently** - Build multiple jobs and execute them in sequence or parallel (with process isolation):

  ```r
  for (file in files) {
    gdal_raster_convert(input = file, ...) |>
      gdal_run()
  }
  ```

- **Set cloud region** - When working with cloud storage, set the appropriate region to avoid extra requests:

  ```r
  job |> gdal_with_config("AWS_REGION" = "us-west-2") |> gdal_run()
  ```

- **Use streaming for memory efficiency** - For large files or streaming pipelines, use `/vsistdin/` and `/vsistdout/` to avoid intermediate files.

## Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/my-feature`)
3. Commit your changes (`git commit -am 'Add my feature'`)
4. Push to the branch (`git push origin feature/my-feature`)
5. Open a Pull Request

## License

MIT License - see LICENSE file for details

## References

- **GDAL Unified CLI (≥3.11)**: [https://gdal.org/programs/index.html](https://gdal.org/programs/index.html)
- **GDAL JSON Usage API**: [https://gdal.org/development/rfc/rfc90.html](https://gdal.org/development/rfc/rfc90.html)
- **GDAL Virtual File Systems**: [https://gdal.org/user/virtual_file_systems.html](https://gdal.org/user/virtual_file_systems.html)
- **GDAL Configuration Options**: [https://gdal.org/user/configoptions.html](https://gdal.org/user/configoptions.html)
- **Lazy Evaluation in R**: Inspired by dbplyr, rlang, and tidyverse design patterns
- **S3 Object System**: [https://adv-r.hadley.nz/s3.html](https://adv-r.hadley.nz/s3.html)
- **processx Package**: [https://processx.r-lib.org/](https://processx.r-lib.org/)

## Acknowledgments

This package is built on top of GDAL's powerful unified CLI (≥3.11) and the excellent
work of the GDAL development team. The lazy evaluation framework is inspired by modern
R design patterns from dbplyr and the tidyverse ecosystem. Special thanks to the
processx maintainers for robust subprocess management utilities.
