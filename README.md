
<!-- README.md is generated from README.Rmd. Please edit that file -->

# gdalcli: An R Frontend for the GDAL (\>=3.11) Unified CLI

[![Lifecycle:
experimental](https://img.shields.io/badge/lifecycle-experimental-orange.svg)](https://lifecycle.r-lib.org/articles/stages.html)

An R interface to GDAL’s unified command-line interface (GDAL \>=3.11).
Provides a lazy evaluation framework for building and executing GDAL
commands with composable, pipe-aware functions. Supports native GDAL
pipelines, GDALG format persistence, and pipeline composition.

## Overview

`gdalcli` implements a frontend for GDAL’s CLI with:

- **Auto-Generated Functions**: 80+ R wrapper functions automatically
  generated from GDAL’s JSON API specification
- **Lazy Evaluation**: Build command specifications as objects
  (`gdal_job`), execute only when needed via `gdal_job_run()`
- **Pipe Composition**: Native R pipe (`|>`) support with S3 methods for
  adding options and environment variables
- **Native Pipeline Execution**: Direct execution via
  `gdal raster/vector pipeline` for multi-step workflows
- **GDALG Format Support**: Save and load pipelines as JSON for
  persistence, sharing, and version control
- **Shell Script Generation**: Render pipelines as executable bash/zsh
  scripts (native or sequential modes)
- **VSI Streaming**: Support for `/vsistdin/` and `/vsistdout/` for
  file-less workflows
- **Multiple Backends**: Execute with processx (default), gdalraster
  (C++ bindings), or reticulate (Python)

## Installation

### Version-Specific Releases

`gdalcli` is released as version-specific builds tied to particular GDAL
releases. Using a package version matching your GDAL version is
recommended. Newer package versions introduce features that require
newer GDAL versions. Existing functionality should generally remain
compatible with older GDAL installations, though this cannot be
guaranteed until the GDAL CLI is stabilized.

**See [GitHub Releases](https://github.com/brownag/gdalcli/releases) for
the latest version-specific builds.**

Each release is tagged with both the package version and the GDAL
version it targets:

- `v0.2.1-3.11.0` - Compatible with GDAL 3.11.0
- `v0.2.1-3.12.0` - Compatible with GDAL 3.12.0
- etc.

#### Finding Your GDAL Version

Check which GDAL version you have installed:

``` r
# Using gdalraster (if installed)
if (requireNamespace("gdalraster", quietly = TRUE)) {
  gdalraster::gdal_version()
}

# Or check your system GDAL installation
system2("gdalinfo", "--version")

# Or use the GDAL command directly
system2("gdal", "info --version")
```

#### Installation from Release Branch

Install the version compatible with your GDAL installation:

``` r
# For GDAL 3.12.x
remotes::install_github("brownag/gdalcli", ref = "release/gdal-3.12")

# For GDAL 3.11.x
remotes::install_github("brownag/gdalcli", ref = "release/gdal-3.11")

# For a specific tagged release
remotes::install_github("brownag/gdalcli", ref = "v0.2.1-3.12.0")
```

#### GDAL Installation Sources

Choose your GDAL installation method based on your platform:

**Linux (Ubuntu/Debian)**:

``` bash
# From ubuntugis PPA - use unstable for GDAL >= 3.11 (currently 3.11.4)
sudo add-apt-repository ppa:ubuntugis/ubuntugis-unstable
sudo apt update
sudo apt install gdal-bin libgdal-dev

# Verify installation
gdalinfo --version
```

**macOS**:

``` bash
# Using Homebrew
brew install gdal

# Verify installation
gdalinfo --version
```

**Windows**:

``` r
# Option 1: Install gdalraster package (provides GDAL C++ bindings)
if (!requireNamespace("gdalraster", quietly = TRUE)) {
  install.packages("gdalraster")
}

# Use gdalraster backend for execution (does not require system GDAL)
job <- gdal_raster_info(input = "your_file.tif")
gdal_job_run(job, backend = "gdalraster")

# Option 2: Install GDAL via Rtools or OSGeo4W for CLI access
# Then use processx backend (default) 
```

**Docker**:

``` bash
# Pre-built images with gdalcli for specific GDAL versions
docker pull ghcr.io/brownag/gdalcli:gdal-3.12.0-latest
docker run -it ghcr.io/brownag/gdalcli:gdal-3.12.0-latest R
```

Inside the container:

``` r
library(gdalcli)

#  GDAL and gdalcli already installed
job <- gdal_raster_info(input = "your_file.tif")
gdal_job_run(job)
```

### Development Installation

To install the current development version that is used as the feedstock
for release branches and images:

``` r
remotes::install_github("brownag/gdalcli", ref = "main")
```

### Requirements

- **R** \>= 4.1
- **GDAL** \>= 3.11 (CLI must be available in system PATH for processx
  backend)
- **gdalraster** (optional; enables gdalraster backend)
- **reticulate** (optional; enables reticulate backend)

## Quick Examples

### Basic Usage

Build and execute a GDAL command:

``` r
library(gdalcli)

# Create a job (lazy evaluation - nothing executes yet)
job <- gdal_raster_convert(
  input = "input.tif",
  output = "output.tif",
  output_format = "COG"
)

# Execute the job
gdal_job_run(job)
```

### Adding Options

Use modifiers to add creation options and configuration:

``` r
job <- gdal_raster_convert(
  input = "input.tif",
  output = "output.tif",
  output_format = "COG"
) |>
  gdal_with_co("COMPRESS=LZW", "BLOCKXSIZE=256") |>
  gdal_with_config("GDAL_CACHEMAX=512")

gdal_job_run(job)
```

### Multi-Step Pipelines

Chain operations with the native R pipe:

``` r
pipeline <- gdal_raster_reproject(
  input = "input.tif",
  dst_crs = "EPSG:32632"
) |>
  gdal_raster_scale(src_min = 0, src_max = 10000, dst_min = 0, dst_max = 255) |>
  gdal_raster_convert(output = "output.tif", output_format = "COG")

gdal_job_run(pipeline)
```

### Pipeline Persistence

Save and load pipelines as JSON:

``` r
# Save pipeline to GDALG format
gdal_save_pipeline(pipeline, "workflow.gdalg.json")

# Load and execute later
loaded <- gdal_load_pipeline("workflow.gdalg.json")
gdal_job_run(loaded)
```

### Shell Script Generation

Export pipelines as executable scripts:

``` r
# Generate bash script
script <- render_shell_script(pipeline, format = "native", shell = "bash")
cat(script)
```

### Cloud Storage

Work with remote datasets using virtual file systems:

``` r
# Set AWS credentials from environment variables
auth <- gdal_auth_s3()

job <- gdal_raster_convert(
  input = "/vsis3/my-bucket/input.tif",
  output = "/vsis3/my-bucket/output.tif",
  output_format = "COG"
) |>
  gdal_with_env(auth)

gdal_job_run(job)
```

## Backend Setup

``` r
# Save pipeline to GDALG format (using custom JSON method for examples)
temp_file <- tempfile(fileext = ".gdalg.json")
gdal_save_pipeline(pipeline, temp_file, method = "json")

# Display the saved GDALG JSON structure
cat(readLines(temp_file, warn = FALSE), sep = "\n")

# Clean up
unlink(temp_file)
```

### GDALG Format - Round-Trip Testing

``` r
# Demonstrate round-trip fidelity
original_cmd <- render_gdal_pipeline(pipeline, format = "native")

# Save to GDALG and load back
temp_file <- tempfile(fileext = ".gdalg.json")
gdal_save_pipeline(pipeline, temp_file, method = "json")
loaded_pipeline <- gdal_load_pipeline(temp_file)

# Render the loaded pipeline
loaded_cmd <- render_gdal_pipeline(loaded_pipeline, format = "native")

# Verify they're identical
# Original command:
original_cmd

# Loaded command:
loaded_cmd

# Commands identical:
identical(original_cmd, loaded_cmd)

# Clean up
unlink(temp_file)
```

### Pipeline with Configuration Options

``` r
# Build a pipeline with cloud storage and config options
pipeline <- gdal_raster_reproject(
  input = "/vsis3/sentinel-pds/input.tif",
  dst_crs = "EPSG:3857"
) |>
  gdal_raster_scale(src_min = 0, src_max = 10000, dst_min = 0, dst_max = 255) |>
  gdal_raster_convert(
    output = "/vsis3/my-bucket/output.tif",
    output_format = "COG"
  ) |>
  gdal_with_co("COMPRESS=LZW", "BLOCKXSIZE=256") |>
  gdal_with_config("AWS_REGION=us-west-2", "AWS_REQUEST_PAYER=requester")

# Render with config options included
native_with_config <- render_gdal_pipeline(pipeline, format = "native")
native_with_config
```

### Inspecting Pipeline Structure

``` r
# Build a simple pipeline to inspect
clay_file <- system.file("extdata/sample_clay_content.tif", package = "gdalcli")
reprojected_file <- tempfile(fileext = ".tif")

simple_pipeline <- gdal_raster_reproject(
  input = clay_file,
  dst_crs = "EPSG:32632"
) |>
  gdal_raster_convert(output = reprojected_file)

# Inspect the pipeline object
# Pipeline object class:
class(simple_pipeline)

# Has pipeline history:
!is.null(simple_pipeline$pipeline)

# Access the pipeline structure
pipe_obj <- simple_pipeline$pipeline
# Number of jobs in pipeline:
length(pipe_obj$jobs)

# Job details:
for (i in seq_along(pipe_obj$jobs)) {
  job <- pipe_obj$jobs[[i]]
  # sprintf("  Job %d: %s\n", i, paste(job$command_path, collapse=" "))
  # sprintf("    Arguments: %s\n", paste(names(job$arguments), collapse=", "))
}
```

### Detailed GDALG JSON Structure

``` r
# Build a pipeline with multiple steps
clay_file <- system.file("extdata/sample_clay_content.tif", package = "gdalcli")
processed_file <- tempfile(fileext = ".tif")

pipeline_for_gdalg <- gdal_raster_reproject(
  input = clay_file,
  dst_crs = "EPSG:32632"
) |>
  gdal_raster_scale(
    src_min = 0, src_max = 100,
    dst_min = 0, dst_max = 255
  ) |>
  gdal_raster_convert(
    output = processed_file,
    output_format = "COG"
  ) |>
  gdal_with_co("COMPRESS=LZW", "BLOCKXSIZE=512")

# Save to GDALG format (using custom JSON method for examples)
temp_gdalg <- tempfile(fileext = ".gdalg.json")
gdal_save_pipeline(pipeline_for_gdalg, temp_gdalg, method = "json")

# Display the full JSON
cat(readLines(temp_gdalg, warn = FALSE), sep = "\n")

# Parse and inspect GDALG structure
loaded <- gdal_load_pipeline(temp_gdalg)
# Loaded pipeline has X jobs:
length(loaded$jobs)

for (i in seq_along(loaded$jobs)) {
  job <- loaded$jobs[[i]]
  # sprintf("  Job %d: %s\n", i, paste(job$command_path, collapse=" "))
}

# Clean up
unlink(temp_gdalg)
```

### Config Options Propagation

``` r
# Build a pipeline with config options at different points
clay_file <- system.file("extdata/sample_clay_content.tif", package = "gdalcli")
processed_file <- tempfile(fileext = ".tif")

config_pipeline <- gdal_raster_reproject(
  input = clay_file,
  dst_crs = "EPSG:32632"
) |>
  gdal_with_config("GDAL_CACHEMAX=512") |>
  gdal_raster_scale(
    src_min = 0, src_max = 100,
    dst_min = 0, dst_max = 255
  ) |>
  gdal_raster_convert(output = processed_file) |>
  gdal_with_config("OGR_SQL_DIALECT=SQLITE")

# Inspect config options
pipe_obj <- config_pipeline$pipeline
# Config options by job:
for (i in seq_along(pipe_obj$jobs)) {
  job <- pipe_obj$jobs[[i]]
  cat(sprintf("Job %d (%s): ", i, paste(job$command_path, collapse=" ")))
  if (length(job$config_options) > 0) {
    for (config_name in names(job$config_options)) {
      cat(sprintf("%s=%s ", config_name, job$config_options[[config_name]]))
    }
  }
}

# Render with config options
render_gdal_pipeline(config_pipeline, format = "native")
```

### Sequential vs Native Rendering Comparison

``` r
# Create a pipeline
clay_file <- system.file("extdata/sample_clay_content.tif", package = "gdalcli")
processed_file <- tempfile(fileext = ".tif")

comparison_pipeline <- gdal_raster_reproject(
  input = clay_file,
  dst_crs = "EPSG:32632"
) |>
  gdal_raster_scale(src_min = 0, src_max = 100, dst_min = 0, dst_max = 255) |>
  gdal_raster_convert(output = processed_file)

# Get sequential command rendering
seq_cmd <- render_gdal_pipeline(comparison_pipeline$pipeline, format = "shell_chain")
# Sequential command (separate GDAL commands chained with &&):
seq_cmd

# Get native command rendering
native_cmd <- render_gdal_pipeline(comparison_pipeline$pipeline, format = "native")
# Native command (single GDAL pipeline):
native_cmd

# Compare as shell scripts
# Sequential Shell Script
cat(render_shell_script(comparison_pipeline, format = "commands"))

# Native Shell Script
cat(render_shell_script(comparison_pipeline, format = "native"))
```

## Backend Setup

`gdalcli` supports three execution backends, each with different
performance characteristics and requirements.

### processx Backend (Default)

The processx backend is the default and requires only that GDAL \>=3.11
is installed:

``` r
# This uses processx backend automatically (no setup needed)
job <- gdal_raster_info(input = "inst/extdata/sample_clay_content.tif")
gdal_job_run(job)
```

The processx backend:

- Executes each GDAL command as a subprocess
- Always available if GDAL CLI is installed
- Works across all platforms
- No additional dependencies beyond gdalcli

### gdalraster Backend (Optional)

The gdalraster backend uses C++ GDAL bindings through the
[gdalraster](https://CRAN.R-project.org/package/gdalraster) package:

``` r
# Install gdalraster if not already installed
if (!requireNamespace("gdalraster", quietly = TRUE)) {
  install.packages("gdalraster")
}

# Use gdalraster backend for execution
job <- gdal_raster_info(input = system.file("extdata/sample_clay_content.tif", package = "gdalcli"))
gdal_job_run(job, backend = "gdalraster")
```

The gdalraster backend:

- Uses C++ GDAL bindings through the gdalraster package
- Requires gdalraster package (\>= 2.2.0)
- Auto-selected as default if available and functional

### reticulate Backend (Optional)

The reticulate backend uses Python’s GDAL bindings via
[reticulate](https://rstudio.github.io/reticulate/) for seamless
Python/R integration:

#### Setup

1.  Create a Python virtual environment with GDAL:

``` r
# Install reticulate if needed
if (!requireNamespace("reticulate", quietly = TRUE)) {
  install.packages("reticulate")
}

# Create a virtual environment for Python packages
reticulate::virtualenv_create("venv")

# Activate and install osgeo + GDAL
reticulate::virtualenv_install("venv", "gdal==3.11.4")

# Verify installation
reticulate::use_virtualenv("venv")
reticulate::py_run_string("from osgeo import gdal; print(gdal.VersionInfo())")
```

2.  Verify reticulate can find the virtualenv:

``` r
# Use the virtualenv
reticulate::use_virtualenv("venv")
```

3.  Test with gdalcli:

``` r
library(gdalcli)

# Use the virtualenv (assumes "venv" exists in project directory)
reticulate::use_virtualenv("venv")

# Only evaluate if osgeo.gdal is available in the active reticulate environment
if (reticulate::py_module_available("osgeo.gdal")) {
  # Execute a simple operation
  job <- gdal_raster_info(input = "inst/extdata/sample_clay_content.tif")
  result <- gdal_job_run(job, backend = "reticulate")
}
```

#### Note on Conda Environments

While conda environments can be used as an alternative to virtual
environments, the venv approach is recommended for this package. The
reticulate integration assumes a local `venv` directory in the project.

### Backend Selection

You can specify which backend to use for each operation:

``` r
library(gdalcli)

job <- gdal_raster_info(input = system.file("extdata/sample_clay_content.tif", package = "gdalcli"))

# Explicit backend selection (processx)
gdal_job_run(job, backend = "processx")

# Explicit backend selection (gdalraster, if installed)
gdal_job_run(job, backend = "gdalraster")

# Explicit backend selection (reticulate, if configured)
if (reticulate::py_module_available("osgeo.gdal")) {
  gdal_job_run(job, backend = "reticulate")
}
```

### Setting a Default Backend

You can set a preferred backend globally without passing `backend` to
every call:

``` r
# Set gdalraster as your default backend
options(gdalcli.prefer_backend = "gdalraster")

# Now all gdal_job_run() calls use gdalraster by default
job <- gdal_raster_info(input = system.file("extdata/sample_clay_content.tif", package = "gdalcli"))
gdal_job_run(job)  # Uses gdalraster

# You can still override with explicit backend parameter
gdal_job_run(job, backend = "processx")  # Uses processx for this call
```

Supported values for `gdalcli.prefer_backend`:

- `"auto"` (default) - Automatically selects best available backend

- `"processx"` - Always use processx

- `"gdalraster"` - Always use gdalraster (if installed)

- `"reticulate"` - Always use reticulate (if installed and configured)

## Usage Examples by Backend

### Example: Raster Information Query

Query a raster file to get metadata:

``` r
library(gdalcli)

# Build the job
job <- gdal_raster_info(input = system.file("extdata/sample_clay_content.tif", package = "gdalcli"))

# Execute with processx (default)
gdal_job_run(job)

# Or with gdalraster (if installed)
gdal_job_run(job, backend = "gdalraster")

# Or with reticulate (must set up venv)
reticulate::use_virtualenv("venv")
if (reticulate::py_module_available("osgeo.gdal")) {
  gdal_job_run(job, backend = "reticulate")
}
```

### Example: Raster Reprojection with Options

Reproject a raster to a different coordinate system with creation
options:

``` r
library(gdalcli)

job <- gdal_raster_reproject(
  input = system.file("extdata/sample_clay_content.tif", package = "gdalcli"),
  output = tempfile(fileext = ".tif"),
  dst_crs = "EPSG:3857"
) |>
  gdal_with_co("COMPRESS=DEFLATE", "BLOCKXSIZE=256") |>
  gdal_with_config("GDAL_CACHEMAX=1024")

# Execute with your preferred backend
gdal_job_run(job)
```

### Example: Vector Format Conversion

Convert a vector dataset between formats:

``` r
library(gdalcli)

job <- gdal_vector_convert(
  input = system.file("extdata/sample_mapunit_polygons.gpkg", package = "gdalcli"),
  output = tempfile(fileext = ".geojson"),
  output_format = "GeoJSON"
)

# Execute
gdal_job_run(job)
```

### Example: Multi-Step Pipeline

Chain multiple operations:

``` r
library(gdalcli)

pipeline <- gdal_raster_reproject(
  input = system.file("extdata/sample_clay_content.tif", package = "gdalcli"),
  dst_crs = "EPSG:3857"
) |>
  gdal_raster_scale(
    src_min = 0, src_max = 100,
    dst_min = 0, dst_max = 255
  ) |>
  gdal_raster_convert(
    output = tempfile(fileext = ".tif"),
    output_format = "COG"
  ) |>
  gdal_with_co("COMPRESS=LZW")

# Execute the entire pipeline
gdal_job_run(pipeline)
```

### Example: Cloud-Based Processing

Work with remote datasets using virtual file systems:

``` r
library(gdalcli)

# Set AWS credentials (from environment variables or .Renviron)
auth <- gdal_auth_s3()

job <- gdal_raster_convert(
  input = "/vsis3/bucket/sample_clay_content.tif",
  output = "/vsis3/bucket/sample_clay_processed.tif",
  output_format = "COG"
) |>
  gdal_with_env(auth) |>
  gdal_with_co("COMPRESS=DEFLATE")

# Execute with cloud storage
gdal_job_run(job)
```

## Pipeline Features

### Native GDAL Pipeline Execution

Execute multi-step workflows as a single GDAL pipeline:

``` r
pipeline <- gdal_raster_reproject(
  input = system.file("extdata/sample_clay_content.tif", package = "gdalcli"),
  dst_crs = "EPSG:32632"
) |>
  gdal_raster_convert(output = tempfile(fileext = ".tif"))

pipeline
```

### GDALG Format: Save and Load Pipelines

Persist pipelines as JSON for sharing and version control:

``` r
# Save pipeline to GDALG format
workflow_file <- tempfile(fileext = ".gdalg.json")
gdal_save_pipeline(pipeline, workflow_file)

# Load and execute later
loaded <- gdal_load_pipeline(workflow_file)
gdal_job_run(loaded)
```

GDALG provides round-trip fidelity - all pipeline structure and
arguments are preserved.

### Shell Script Generation

Generate executable shell scripts from pipelines:

``` r
# Render as native GDAL pipeline script
script <- render_shell_script(pipeline, format = "native", shell = "bash")
cat(script)

# Or as separate sequential commands
script_seq <- render_shell_script(pipeline, format = "commands", shell = "bash")
cat(script_seq)
```

### GDALG Format: Native Format Driver Support (GDAL 3.11+)

For compatibility with GDAL tools across Python, C++, and CLI, use the
native GDALG format driver:

``` r
# Check if native GDALG driver is available
workflow_file <- tempfile(fileext = ".gdalg.json")

if (gdal_has_gdalg_driver()) {
  # Save using GDAL's native GDALG format driver
  # This ensures compatibility with other GDAL tools
  gdal_save_pipeline(pipeline, workflow_file, method = "native")

  # Or explicitly use the native function
  gdal_save_pipeline_native(pipeline, workflow_file)
}

# Auto-detection: automatically uses native driver if available, else custom JSON
gdal_save_pipeline(pipeline, workflow_file, method = "auto")
```

**Comparison of serialization methods:**

- **Custom JSON**: Works with any GDAL version, gdalcli-specific format
- **Native GDALG Driver**: Requires GDAL 3.11+, compatible with other
  GDAL tools, includes metadata

**Method parameter:** - `method = "json"` - Uses custom JSON
serialization (works with any GDAL version) - `method = "native"` - Uses
GDAL’s native GDALG format driver (requires GDAL 3.11+) -
`method = "auto"` - Automatically selects method based on GDAL version

Both methods produce valid GDALG files that can be loaded with
`gdal_load_pipeline()`.

### Configuration Options in Pipelines

Add GDAL configuration options to pipeline steps:

``` r
pipeline_with_config <- gdal_raster_reproject(
  input = system.file("extdata/sample_clay_content.tif", package = "gdalcli"),
  dst_crs = "EPSG:32632"
) |>
  gdal_with_config("OGR_SQL_DIALECT=SQLITE") |>
  gdal_raster_scale(
    src_min = 0, src_max = 100,
    dst_min = 0, dst_max = 255,
    output = tempfile(fileext = ".tif")
  )

# Config options are included in native pipeline rendering
render_gdal_pipeline(pipeline_with_config$pipeline, format = "native")
```

## Documentation

- **Getting Started**: `?gdal_vector_convert` - Example auto-generated
  function
- **Authentication**: `?gdal_auth_s3`, `?gdal_auth_azure`, etc. - Set up
  credentials
- **Lazy Evaluation**: `?gdal_job` - Understand the job specification
  system
- **Execution**: `?gdal_job_run` - Run GDAL commands
- **Composition**: `?gdal_with_co`, `?gdal_with_env` - Modify jobs with
  modifiers

## Architecture & Design

### Three-Layer Architecture

`gdalcli` separates concerns into three layers:

1.  **Frontend Layer** (User-facing R API)
    - Auto-generated functions like `gdal_vector_convert()`,
      `gdal_raster_reproject()`, etc.
    - Composable modifiers: `gdal_with_co()`, `gdal_with_env()`,
      `gdal_with_config()`, etc.
    - S3 methods for extensibility
    - Lazy `gdal_job` specification objects
    - Native pipe (`|>`) support for composition
2.  **Pipeline Layer** (Workflows)
    - Automatic pipeline building through chained piping
    - Native GDAL pipeline execution (`gdal raster/vector pipeline`)
    - GDALG format serialization with `gdal_save_pipeline()` and
      `gdal_load_pipeline()`
    - Shell script rendering for persistence and sharing
    - Configuration option aggregation and propagation
    - Sequential vs. native execution modes
3.  **Engine Layer** (Command Execution)
    - `gdal_job_run()` executes individual jobs or entire pipelines
    - Uses processx for robust subprocess management
    - Handles environment variable injection
    - Supports input/output streaming (`/vsistdin/`, `/vsistdout/`)
    - Multiple backend options (processx, gdalraster, reticulate)

### Lazy Evaluation

Commands are built as specifications (`gdal_job` objects) and only
executed when passed to `gdal_job_run()`:

``` r
library(gdalcli)

# This doesn't execute anything - just builds a specification
job <- gdal_vector_convert(
  input = "data.shp",
  output = "data.gpkg"
)

# Inspect the job before running
job
#> <gdal_job>
#> Command:  gdal vector convert 
#> Arguments:
#>   input: data.shp
#>   output: data.gpkg

# Render to see the command that would be executed
render_gdal_pipeline(job)
#> [1] "gdal vector convert data.shp data.gpkg"
```

### S3-Based Composition

All modifiers are S3 generics that accept and return `gdal_job` objects,
enabling composable workflows:

``` r
# Each step returns a modified gdal_job
pipeline <- gdal_raster_convert(input = "in.tif", output = "out.tif") |>
  gdal_with_co("COMPRESS=DEFLATE") |>
  gdal_with_config("GDAL_CACHEMAX=512")

# Inspect at any point
pipeline
#> <gdal_job>
#> Command:  gdal raster convert 
#> Arguments:
#>   input: in.tif
#>   output: out.tif
#>   --creation-option: COMPRESS=DEFLATE
#> Config Options:
#>   GDAL_CACHEMAX=512
```

### Pipeline Composition and Execution Modes

Pipelines are automatically created when chaining GDAL operations with
the native R pipe:

``` r
# Build a multi-step pipeline by chaining operations
pipeline <- gdal_raster_reproject(
  input = "input.tif",
  dst_crs = "EPSG:32632"
) |>
  gdal_raster_convert(output = "output.tif")

# Render as sequential commands (jobs run separately)
seq_render <- render_gdal_pipeline(pipeline$pipeline, format = "shell_chain")
# Sequential output:
seq_render
#> [1] "gdal raster reproject --dst-crs EPSG:32632 input.tif /vsimem/gdalcli_1e454b1968fb65.tif && gdal raster convert /vsimem/gdalcli_1e454b1968fb65.tif output.tif"

# Render as native GDAL pipeline (single command)
native_render <- render_gdal_pipeline(pipeline$pipeline, format = "native")
# Native output:
native_render
#> [1] "gdal raster pipeline ! read input.tif ! reproject --dst-crs EPSG:32632 --output /vsimem/gdalcli_1e454b1968fb65.tif ! write output.tif --input /vsimem/gdalcli_1e454b1968fb65.tif"
```

**Sequential Execution** (default):

- Each job runs as a separate GDAL command
- Safer for hybrid workflows mixing pipeline and non-pipeline operations
- Intermediate results written to disk

**Native Execution**:

- Entire pipeline runs as single `gdal raster/vector pipeline` command
- More efficient for large datasets (avoids intermediate I/O)
- Direct data flow between pipeline steps

### GDALG Format: Pipeline Persistence

Pipelines can be saved and loaded for persistence and sharing:

``` r
# Save pipeline as GDALG (JSON format)
gdal_save_pipeline(pipeline, "workflow.gdalg.json")

# Load pipeline later
loaded <- gdal_load_pipeline("workflow.gdalg.json")

# Pipelines maintain round-trip fidelity
# All structure, arguments, and metadata are preserved
```

GDALG files can be:

- Version controlled in git repositories
- Shared with team members
- Executed by other GDAL-compatible tools
- Edited manually for complex workflows

## Security Considerations

1.  **Credentials in .Renviron, not in code** - Never pass secrets as
    function arguments. Use `.Renviron` or external secret managers:

    ``` env
    # ~/.Renviron or project .Renviron
    AWS_ACCESS_KEY_ID=your_access_key
    AWS_SECRET_ACCESS_KEY=your_secret
    ```

2.  **Environment-variable-only design** - Auth helpers read from
    environment, never from function arguments. This prevents accidental
    commits of credentials.

3.  **Don’t save R sessions** - Avoid saving `.RData` files or R session
    history containing credentials.

4.  **Use temporary/rotatable credentials** - When possible, use
    temporary credentials (AWS STS, Azure Managed Identity, GCS service
    accounts) instead of long-lived secrets.

5.  **Rotate credentials regularly** - Follow your organization’s
    credential rotation policies.

6.  **Use external secret managers**

## Contributing

We welcome contributions! Please see [CONTRIBUTING.md](CONTRIBUTING.md)
for guidelines.

## License

MIT License - see LICENSE file for details

## References

- **GDAL CLI (\>=3.11)**: <https://gdal.org/programs/index.html>
- **GDAL RFCs**: <https://gdal.org/development/rfc/>
- **GDAL Virtual File Systems**:
  <https://gdal.org/user/virtual_file_systems.html>
- **GDAL Configuration Options**:
  <https://gdal.org/user/configoptions.html>

## Acknowledgments

This package is built on GDAL’s CLI (\>=3.11) and the GDAL development
team’s work.

Also, the development of this package has been heavily influenced by
Michael Sumner (@mdsumner), Chris Toney (@ctoney), and the
[gdalraster](https://CRAN.R-project.org/package=gdalraster) package.
