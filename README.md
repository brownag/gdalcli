
<!-- README.md is generated from README.Rmd. Please edit that file -->

# gdalcli: An R Frontend for the GDAL (\>=3.11) Unified CLI

[![Lifecycle:
experimental](https://img.shields.io/badge/lifecycle-experimental-orange.svg)](https://lifecycle.r-lib.org/articles/stages.html)

A modern R interface to GDAL’s unified command-line interface (GDAL
\>=3.11). Provides a **lazy evaluation framework** for building and
executing GDAL commands with composable, pipe-aware functions. Full
support for native GDAL pipelines, GDALG format persistence, and
advanced pipeline composition.

## Overview

`gdalcli` implements a frontend for GDAL’s CLI with:

- **Auto-Generated Functions**: 80+ R wrapper functions automatically
  generated from GDAL’s JSON API specification
- **Lazy Evaluation**: Build command specifications as objects
  (`gdal_job`), execute only when needed via `gdal_job_run()`
- **Pipe Composition**: Native R pipe (`|>`) support with S3 methods for
  adding options and environment variables
- **Native Pipeline Execution**: Direct execution via
  `gdal raster/vector pipeline` for efficient multi-step workflows
- **GDALG Format Support**: Save and load pipelines as JSON for
  persistence, sharing, and version control
- **Shell Script Generation**: Render pipelines as executable bash/zsh
  scripts (native or sequential modes)
- **VSI Streaming**: Support for `/vsistdin/` and `/vsistdout/` for
  file-less, memory-efficient workflows
- **Multiple Backends**: Execute with processx (default), gdalraster
  (C++ bindings), or reticulate (Python)

## Installation

``` r
# Install from GitHub (when available)
# devtools::install_github("brownag/gdalcli")
library(gdalcli)
```

## Quick Examples

### Example 1: Building and Inspecting a Job

``` r
library(gdalcli)

# Build a raster conversion job (lazy evaluation - nothing executes yet)
job <- gdal_raster_convert(
  input = "input.tif",
  output = "output.tif",
  output_format = "COG"
)

# Inspect the job object
job
#> <gdal_job>
#> Command:  gdal raster convert 
#> Arguments:
#>   input: input.tif
#>   output: output.tif
#>   --output_format: COG

# Access internal structure
# Command path
job$command_path
#> [1] "raster"  "convert"
# Arguments
str(job$arguments)
#> List of 3
#>  $ input        : chr "input.tif"
#>  $ output       : chr "output.tif"
#>  $ output_format: chr "COG"
```

### Example 2: Adding Options to Jobs

``` r
# Build a job with creation options and config options
job_with_options <- gdal_raster_convert(
  input = "input.tif",
  output = "output.tif",
  output_format = "COG"
) |>
  gdal_with_co("COMPRESS=LZW", "BLOCKXSIZE=256") |>
  gdal_with_config("GDAL_CACHEMAX=512")

job_with_options
#> <gdal_job>
#> Command:  gdal raster convert 
#> Arguments:
#>   input: input.tif
#>   output: output.tif
#>   --output_format: COG
#>   --creation-option: [COMPRESS=LZW, BLOCKXSIZE=256]
#> Config Options:
#>   GDAL_CACHEMAX=512
```

### Example 3: Rendering a Job as a Shell Command

``` r
# Render the job as a shell command (executable but not run)
cmd <- render_gdal_pipeline(job)
# Command to execute:
cmd
#> [1] "gdal raster convert input.tif output.tif --output-format COG"
```

### Example 4: Building a Multi-Step Pipeline

``` r
# Build a 3-step pipeline using native R piping
pipeline <- gdal_raster_reproject(
  input = "input.tif",
  dst_crs = "EPSG:32632"
) |>
  gdal_raster_scale(
    src_min = 0, src_max = 10000,
    dst_min = 0, dst_max = 255
  ) |>
  gdal_raster_convert(
    output = "output.tif",
    output_format = "COG"
  )

pipeline
#> <gdal_job>
#> Pipeline: 3 step(s)
#>   [1] raster reproject (input: input.tif)
#>   [2] raster scale
#>   [3] raster convert (output: output.tif)
```

### Example 5: Rendering Pipeline to Native GDAL Format

``` r
# Render as native GDAL pipeline (single command)
native_cmd <- render_gdal_pipeline(pipeline, format = "native")
# Native GDAL pipeline command:
native_cmd
#> [1] "gdal raster pipeline ! read input.tif ! reproject --dst-crs EPSG:32632 ! scale --src-min 0 --src-max 10000 --dst-min 0 --dst-max 255 ! write output.tif"
```

### Example 6: Rendering Pipeline as Shell Script

``` r
# Render as executable bash script (native mode)
native_script <- render_shell_script(pipeline, format = "native", shell = "bash")
# Bash script (native pipeline mode):
native_script
#> [1] "#!/bin/bash\n\nset -e\n\n# Native GDAL pipeline execution\ngdal raster pipeline ! read input.tif ! reproject --dst-crs EPSG:32632 ! scale --src-min 0 --src-max 10000 --dst-min 0 --dst-max 255 ! write output.tif\n"
```

### Example 7: Rendering Pipeline as Sequential Commands

``` r
# Render as separate commands (safer for hybrid workflows)
seq_script <- render_shell_script(pipeline, format = "commands", shell = "bash")
# Bash script (sequential commands mode):
seq_script
#> [1] "#!/bin/bash\n\nset -e\n\n# Job 1\ngdal raster reproject input.tif --dst-crs EPSG:32632\n\n# Job 2\ngdal raster scale --src-min 0 --src-max 10000 --dst-min 0 --dst-max 255\n\n# Job 3\ngdal raster convert output.tif --output-format COG\n"
```

### Example 8: GDALG Format - Save Pipeline

``` r
# Save pipeline to GDALG format (using custom JSON method for examples)
temp_file <- tempfile(fileext = ".gdalg.json")
gdal_save_pipeline(pipeline, temp_file, method = "json")

# Display the saved GDALG JSON structure
cat(readLines(temp_file, warn = FALSE), sep = "\n")
#> {
#>   "gdalVersion": null,
#>   "steps": [
#>     {
#>       "type": "reproject",
#>       "name": "reproject_1",
#>       "operation": "reproject",
#>       "input": "input.tif",
#>       "options": {
#>         "dst_crs": "EPSG:32632"
#>       }
#>     },
#>     {
#>       "type": "scale",
#>       "name": "scale_2",
#>       "operation": "scale",
#>       "options": {
#>         "src_min": 0.0,
#>         "src_max": 10000.0,
#>         "dst_min": 0.0,
#>         "dst_max": 255.0
#>       }
#>     },
#>     {
#>       "type": "write",
#>       "name": "write_3",
#>       "operation": "convert",
#>       "output": "output.tif"
#>     }
#>   ]
#> }

# Clean up
unlink(temp_file)
```

### Example 9: GDALG Format - Round-Trip Testing

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
#> [1] "gdal raster pipeline ! read input.tif ! reproject --dst-crs EPSG:32632 ! scale --src-min 0 --src-max 10000 --dst-min 0 --dst-max 255 ! write output.tif"

# Loaded command:
loaded_cmd
#> [1] "gdal raster pipeline ! read input.tif ! reproject --dst-crs EPSG:32632 ! scale --src-min 0 --src-max 10000 --dst-min 0 --dst-max 255 ! write output.tif"

# Commands identical:
identical(original_cmd, loaded_cmd)
#> [1] TRUE

# Clean up
unlink(temp_file)
```

### Example 10: Complex Pipeline with Configuration Options

``` r
# Build a complex pipeline with cloud storage and config options
complex_pipeline <- gdal_raster_reproject(
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
native_with_config <- render_gdal_pipeline(complex_pipeline, format = "native")
native_with_config
#> [1] "gdal raster pipeline --config AWS_REGION=us-west-2 --config AWS_REQUEST_PAYER=requester --co COMPRESS=LZW --co BLOCKXSIZE=256 ! read /vsis3/sentinel-pds/input.tif ! reproject --dst-crs EPSG:3857 ! scale --src-min 0 --src-max 10000 --dst-min 0 --dst-max 255 ! write /vsis3/my-bucket/output.tif"
```

### Example 11: Inspecting Pipeline Structure

``` r
# Build a simple pipeline to inspect
clay_file <- system.file("extdata/sample_clay_content.tif", package = "gdalcli")
reprojected_file <- tempfile(fileext = ".tif")

simple_pipeline <- gdal_raster_reproject(
  input = clay_file,
  dst_crs = "EPSG:32632"
) |>
  gdal_raster_scale(
    src_min = 0, src_max = 100,
    dst_min = 0, dst_max = 255
  ) |>
  gdal_raster_convert(output = reprojected_file)

# Inspect the pipeline object
# Pipeline object class:
class(simple_pipeline)
#> [1] "gdal_job" "list"

# Has pipeline history:
!is.null(simple_pipeline$pipeline)
#> [1] TRUE

# Access the pipeline structure
pipe_obj <- simple_pipeline$pipeline
# Number of jobs in pipeline:
length(pipe_obj$jobs)
#> [1] 3

# Job details:
for (i in seq_along(pipe_obj$jobs)) {
  job <- pipe_obj$jobs[[i]]
  # sprintf("  Job %d: %s\n", i, paste(job$command_path, collapse=" "))
  # sprintf("    Arguments: %s\n", paste(names(job$arguments), collapse=", "))
}
```

### Example 12: Detailed GDALG JSON Structure

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
#> {
#>   "gdalVersion": null,
#>   "steps": [
#>     {
#>       "type": "reproject",
#>       "name": "reproject_1",
#>       "operation": "reproject",
#>       "input": "/home/andrew/R/x86_64-pc-linux-gnu-library/4.5/gdalcli/extdata/sample_clay_content.tif",
#>       "options": {
#>         "dst_crs": "EPSG:32632"
#>       }
#>     },
#>     {
#>       "type": "scale",
#>       "name": "scale_2",
#>       "operation": "scale",
#>       "options": {
#>         "src_min": 0.0,
#>         "src_max": 100.0,
#>         "dst_min": 0.0,
#>         "dst_max": 255.0
#>       }
#>     },
#>     {
#>       "type": "write",
#>       "name": "write_3",
#>       "operation": "convert",
#>       "output": "/tmp/RtmpGQ4Ndx/filea09b55bd13b50.tif"
#>     }
#>   ]
#> }

# Parse and inspect GDALG structure
loaded <- gdal_load_pipeline(temp_gdalg)
# Loaded pipeline has X jobs:
length(loaded$jobs)
#> [1] 3

for (i in seq_along(loaded$jobs)) {
  job <- loaded$jobs[[i]]
  # sprintf("  Job %d: %s\n", i, paste(job$command_path, collapse=" "))
}

# Clean up
unlink(temp_gdalg)
```

### Example 13: Config Options Propagation

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
#> Job 1 (raster reproject): Job 2 (raster scale): Job 3 (raster convert):

# Render with config options
render_gdal_pipeline(config_pipeline, format = "native")
#> [1] "gdal raster pipeline --config GDAL_CACHEMAX=512 --config OGR_SQL_DIALECT=SQLITE ! read /home/andrew/R/x86_64-pc-linux-gnu-library/4.5/gdalcli/extdata/sample_clay_content.tif ! reproject --dst-crs EPSG:32632 ! scale --src-min 0 --src-max 100 --dst-min 0 --dst-max 255 ! write /tmp/RtmpGQ4Ndx/filea09b569c411ca.tif"
```

### Example 14: Sequential vs Native Rendering Comparison

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
#> [1] "gdal raster info /home/andrew/R/x86_64-pc-linux-gnu-library/4.5/gdalcli/extdata/sample_clay_content.tif && gdal raster reproject --dst-crs EPSG:32632 && gdal raster scale --src-min 0 --src-max 100 --dst-min 0 --dst-max 255 && gdal raster convert /tmp/RtmpGQ4Ndx/filea09b530e198c2.tif"

# Get native command rendering
native_cmd <- render_gdal_pipeline(comparison_pipeline$pipeline, format = "native")
# Native command (single GDAL pipeline):
native_cmd
#> [1] "gdal raster pipeline ! read /home/andrew/R/x86_64-pc-linux-gnu-library/4.5/gdalcli/extdata/sample_clay_content.tif ! reproject --dst-crs EPSG:32632 ! scale --src-min 0 --src-max 100 --dst-min 0 --dst-max 255 ! write /tmp/RtmpGQ4Ndx/filea09b530e198c2.tif"

# Compare as shell scripts
# Sequential Shell Script
cat(render_shell_script(comparison_pipeline, format = "commands"))
#> #!/bin/bash
#> 
#> set -e
#> 
#> # Job 1
#> gdal raster info /home/andrew/R/x86_64-pc-linux-gnu-library/4.5/gdalcli/extdata/sample_clay_content.tif
#> 
#> # Job 2
#> gdal raster reproject --dst-crs EPSG:32632
#> 
#> # Job 3
#> gdal raster scale --src-min 0 --src-max 100 --dst-min 0 --dst-max 255
#> 
#> # Job 4
#> gdal raster convert /tmp/RtmpGQ4Ndx/filea09b530e198c2.tif

# Native Shell Script
cat(render_shell_script(comparison_pipeline, format = "native"))
#> #!/bin/bash
#> 
#> set -e
#> 
#> # Native GDAL pipeline execution
#> gdal raster pipeline ! read /home/andrew/R/x86_64-pc-linux-gnu-library/4.5/gdalcli/extdata/sample_clay_content.tif ! reproject --dst-crs EPSG:32632 ! scale --src-min 0 --src-max 100 --dst-min 0 --dst-max 255 ! write /tmp/RtmpGQ4Ndx/filea09b530e198c2.tif
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

The processx backend: - Executes each GDAL command as a subprocess -
Always available if GDAL CLI is installed - Works reliably across all
platforms - No additional dependencies beyond gdalcli

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

The gdalraster backend: - Bypasses subprocess overhead with direct C++
bindings - Requires gdalraster package (\>= 2.2.0) - Auto-selected as
default if available and functional

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

Supported values for `gdalcli.prefer_backend`: - `"auto"` (default) -
Automatically selects best available backend - `"processx"` - Always use
processx - `"gdalraster"` - Always use gdalraster (if installed) -
`"reticulate"` - Always use reticulate (if configured)

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
pipeline <- gdal_raster_info(input = system.file("extdata/sample_clay_content.tif", package = "gdalcli")) |>
  gdal_raster_reproject(dst_crs = "EPSG:32632") |>
  gdal_raster_convert(output = tempfile(fileext = ".tif"))

pipeline
#> <gdal_job>
#> Pipeline: 3 step(s)
#>   [1] raster info (input: /home/andrew/R/x86_64-pc-linux-gnu-library/4.5/gdalcli/extdata/sample_clay_content.tif)
#>   [2] raster reproject
#>   [3] raster convert (output: /tmp/RtmpGQ4Ndx/filea09b5470e2d93.tif)
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

For maximum compatibility with GDAL tools across Python, C++, and CLI,
use the native GDALG format driver:

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

- **Custom JSON**: Backward compatible, works with any GDAL version,
  gdalcli-specific format
- **Native GDALG Driver**: Requires GDAL 3.11+, universal compatibility
  with other GDAL tools, full metadata support

**Method parameter:** - `method = "json"` - Uses custom JSON
serialization (backward compatible) - `method = "native"` - Uses GDAL’s
native GDALG format driver (requires GDAL 3.11+) - `method = "auto"` -
Automatically selects best method based on GDAL version

Both methods produce valid, portable GDALG files that can be loaded with
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
#> [1] "gdal raster pipeline ! read /home/andrew/R/x86_64-pc-linux-gnu-library/4.5/gdalcli/extdata/sample_clay_content.tif ! reproject --dst-crs EPSG:32632 ! scale --src-min 0 --src-max 100 --dst-min 0 --dst-max 255 ! write /tmp/RtmpGQ4Ndx/filea09b5169e1471.tif"
```

## Version Compatibility

`gdalcli` supports GDAL 3.11 and later, with additional features available
in GDAL 3.12+.

### Minimum Requirements

- **GDAL**: \>= 3.11 (CLI framework minimum)
- **R**: \>= 4.1
- **gdalraster**: \>= 2.2.0 (recommended for advanced features)

### GDAL 3.11 Features

Core GDAL CLI functionality available in GDAL 3.11+:

- **80+ Algorithm Functions**: All raster, vector, and multidimensional
  operations
- **Pipeline Execution**: Native and sequential pipeline modes
- **GDALG Format**: Read-only access to GDALG format (JSON-based
  pipeline files)
- **Configuration Options**: Full GDAL config option support
- **VSI Support**: Virtual file system integration
- **Shell Script Generation**: Export pipelines to executable bash/zsh

### GDAL 3.12 Enhancements

New algorithms and capabilities available in GDAL 3.12+:

- **GDALG Format Write Support**: Write pipelines to GDALG format for
  persistence and sharing
- **New Raster Algorithms**: blend, compare, neighbors, nodata-to-alpha,
  pansharpen, proximity, rgb-to-palette, update, zonal-stats,
  as-features
- **New Vector Algorithms**: check-coverage, check-geometry,
  clean-coverage, index, layer-algebra, make-point, partition,
  set-field-type, simplify-coverage
- **GDALG Format Driver**: Native support for GDALG as a format driver
  with additional metadata
- **Advanced Features**: Additional pipeline capabilities and algorithm
  metadata

### Checking Version Support

Use the discovery utilities to check version requirements:

``` r
# Check if GDAL meets minimum version
if (gdal_check_version("3.11")) {
  # Use gdalcli features
}

# Check for GDAL 3.12+ features
if (gdal_check_version("3.12")) {
  # Use new GDAL 3.12 algorithms
}

# List all available commands for current GDAL version
all_commands <- gdal_list_commands()
head(all_commands)

# Get help for a specific command
gdal_command_help("raster.info")
```

When regenerating the package with GDAL 3.12+ installed, all new
algorithms are automatically discovered and wrapped as R functions.

## GDAL Function Categories

The 80+ auto-generated functions are organized into logical categories:

### Raster Operations

Functions for working with raster datasets: `gdal_raster_*`

- **gdal_raster_convert** - Format conversion
- **gdal_raster_clip** - Spatial subsetting
- **gdal_raster_reproject** - Reprojection
- **gdal_raster_scale** - Value scaling
- And many more…

### Vector Operations

Functions for working with vector datasets: `gdal_vector_*`

- **gdal_vector_convert** - Format conversion
- **gdal_vector_info** - Dataset information
- **gdal_vector_reproject** - Reprojection
- And more…

### Multidimensional (MDim)

Functions for multidimensional data: `gdal_mdim_*`

- **gdal_mdim_convert** - Dimension conversion
- **gdal_mdim_info** - Dimension information

### VSI (Virtual File System)

Functions for cloud storage and remote access: `gdal_vsi_*`

- Support for S3, Azure, GCS, OSS, Swift with automatic credential
  handling

Use `gdal_gdal(drivers = TRUE)` to list all available drivers in your
GDAL installation.

## System Requirements

- **R** \>= 4.1
- **GDAL** \>= 3.11 (required for CLI)
- **Dependencies**:
  - `processx` (\>=3.8.0) - Robust subprocess management
  - `yyjsonr` (\>=0.1.0) - JSON handling
  - `rlang` (\>=1.0.0) - Error handling and programming utilities
  - `cli` (\>=3.0.0) - User-friendly terminal messages
  - `digest` (\>=0.6.0) - Cryptographic hashing

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
    - Native pipe (`|>`) support for fluent composition
2.  **Pipeline Layer** (Advanced Workflows)
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
  gdal_raster_scale(
    src_min = 0, src_max = 100,
    dst_min = 0, dst_max = 255
  ) |>
  gdal_raster_convert(output = "output.tif")

# Render as sequential commands (jobs run separately)
seq_render <- render_gdal_pipeline(pipeline$pipeline, format = "shell_chain")
# Sequential output:
seq_render
#> [1] "gdal raster info input.tif && gdal raster reproject --dst-crs EPSG:32632 && gdal raster convert output.tif"

# Render as native GDAL pipeline (single command)
native_render <- render_gdal_pipeline(pipeline$pipeline, format = "native")
# Native output:
native_render
#> [1] "gdal raster pipeline ! read input.tif ! reproject --dst-crs EPSG:32632 ! write output.tif"
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
- Edited manually for advanced workflows

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

6.  **Use external secret managers** - For production, consider:

    - HashiCorp Vault
    - AWS Secrets Manager
    - Azure Key Vault
    - Google Cloud Secret Manager
    - 1Password, Bitwarden, or other password managers with environment
      variable integration

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
