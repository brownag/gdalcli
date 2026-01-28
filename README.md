
<!-- README.md is generated from README.Rmd. Please edit that file -->

# gdalcli: An R Frontend for the GDAL (\>=3.11) Unified CLI

[![Lifecycle:
experimental](https://img.shields.io/badge/lifecycle-experimental-orange.svg)](https://lifecycle.r-lib.org/articles/stages.html)

An R interface to GDAL’s unified command-line interface (GDAL \>=3.11).
Provides a lazy evaluation framework for building and executing GDAL
commands with composable, pipe-aware functions. Supports native GDAL
pipelines, gdalcli pipeline format persistence, and pipeline
composition.

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

``` r
# Check your system GDAL installation
system2("gdalinfo", "--version")
```

#### Installation from Release Branch

Install the version compatible with your GDAL installation:

``` r
# For GDAL 3.12.x
remotes::install_github("brownag/gdalcli", ref = "release/gdal-3.12")

# For GDAL 3.11.x
remotes::install_github("brownag/gdalcli", ref = "release/gdal-3.11")
```

**Docker**: Pre-built images available at
`ghcr.io/brownag/gdalcli:gdal-X.Y.Z-latest`

### Requirements

- **R** \>= 4.1
- **GDAL** \>= 3.11 (CLI must be available in system PATH for processx
  backend)
- **gdalraster** (optional; enables gdalraster backend)
- **reticulate** (optional; enables reticulate backend)

## Examples

### Basic Usage

``` r
library(gdalcli)

# Create a job (lazy evaluation - nothing executes yet)
job <- gdal_raster_convert(
  input = system.file("extdata/sample_clay_content.tif", package = "gdalcli"),
  output = tempfile(fileext = ".tif"),
  output_format = "COG"
)

# Execute the job
gdal_job_run(job)
#> 0...10...20...30...40...50...60...70...80...90...100 - done.
```

### Adding Options

``` r
job <- gdal_raster_convert(
  input = system.file("extdata/sample_clay_content.tif", package = "gdalcli"),
  output = tempfile(fileext = ".tif"),
  output_format = "COG"
) |>
  gdal_with_co("COMPRESS=LZW", "PREDICTOR=2") |>
  gdal_with_config("GDAL_CACHEMAX=512")

gdal_job_run(job)
```

### Multi-Step Pipelines

``` r
pipeline <- gdal_raster_reproject(
  input = system.file("extdata/sample_clay_content.tif", package = "gdalcli"),
  dst_crs = "EPSG:32632"
) |>
  gdal_raster_scale(src_min = 0, src_max = 100, dst_min = 0, dst_max = 255) |>
  gdal_raster_convert(output = tempfile(fileext = ".tif"), output_format = "COG")

gdal_job_run(pipeline)
#> 0...10...20...30...40...50...60...70...80...90...100 - done.
#> 0...10...20...30...40...50...60...70...80...90...100 - done.
```

### Pipeline Persistence

``` r
# Save pipeline to gdalcli pipeline format
workflow_file <- tempfile(fileext = ".gdalcli.json")
gdal_save_pipeline(pipeline, workflow_file)

# Load pipeline for later use
loaded <- gdal_load_pipeline(workflow_file)
```

### Cloud Storage

``` r
# Set AWS credentials (from environment variables)
auth <- gdal_auth_s3()

job <- gdal_raster_convert(
  input = "/vsis3/my-bucket/input.tif",
  output = "/vsis3/my-bucket/output.tif",
  output_format = "COG"
) |>
  gdal_with_env(auth)

gdal_job_run(job)
```

### Raster Information

``` r
# Get detailed information about a raster file
info_job <- gdal_raster_info(
  input = system.file("extdata/sample_clay_content.tif", package = "gdalcli")
)
gdal_job_run(info_job)
```

### Vector Operations

``` r
# Convert vector format
vector_job <- gdal_vector_convert(
  input = system.file("extdata/sample_mapunit_polygons.gpkg", package = "gdalcli"),
  output = tempfile(fileext = ".geojson"),
  output_format = "GeoJSON"
)
gdal_job_run(vector_job, backend = "processx")
```

### Raster Processing Pipeline

``` r
# Simple processing pipeline: reproject and convert
processing_pipeline <- gdal_raster_reproject(
  input = system.file("extdata/sample_clay_content.tif", package = "gdalcli"),
  dst_crs = "EPSG:32632"
) |>
  gdal_raster_convert(output = tempfile(fileext = ".tif"))

gdal_job_run(processing_pipeline, backend = "processx")
```

## Backends

`gdalcli` supports multiple execution backends:

- **processx** (default): Executes GDAL CLI commands as subprocesses
- **gdalraster** (optional): Uses C++ GDAL bindings via gdalraster
  package
- **reticulate** (optional): Uses Python GDAL bindings via reticulate

Set your preferred backend globally:

``` r
# Using gdalcli_options()
gdalcli_options(backend = "gdalraster")

# Or using base R options() directly
options(gdalcli.backend = "gdalraster")  # or "processx", "reticulate"
```

## Package Options

Manage package behavior with `gdalcli_options()`:

``` r
# View current options
gdalcli_options()

# Set options
gdalcli_options(
  backend = "auto",              # "auto", "gdalraster", or "processx"
  verbose = TRUE,                # Enable verbose output
  stream_out_format = "text",    # NULL, "text", or "binary"
  audit_logging = FALSE          # Enable audit logging
)

# Set individual options
gdalcli_options(verbose = TRUE)
gdalcli_options(backend = "processx")
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

gdal_job_run(pipeline, backend = "processx")
```

### gdalcli Pipeline Format: Save and Load Pipelines

Persist pipelines as JSON for sharing and version control:

``` r
# Save pipeline to gdalcli pipeline format
workflow_file <- tempfile(fileext = ".gdalcli.json")
gdal_save_pipeline(pipeline, workflow_file)

# Load pipeline for later use
loaded <- gdal_load_pipeline(workflow_file)
```

### Shell Script Generation

Generate executable shell scripts from pipelines:

``` r
# Generate bash script
script <- render_shell_script(pipeline, format = "native", shell = "bash")
cat(script)
#> #!/bin/bash
#> 
#> set -e
#> 
#> # Native GDAL pipeline execution
#> gdal raster pipeline ! read /home/andrew/R/x86_64-pc-linux-gnu-library/4.5/gdalcli/extdata/sample_clay_content.tif ! reproject --dst-crs EPSG:32632 --output /vsimem/gdalcli_a076b690b9b3e.tif ! scale --src-min 0 --src-max 100 --dst-min 0 --dst-max 255 ! write /tmp/RtmpPRKY4D/filea076b4b8c7be7.tif --input /vsimem/gdalcli_a076b17cb9337.tif
```

## Architecture

`gdalcli` uses a three-layer architecture:

1.  **Frontend Layer**: Auto-generated R functions with composable
    modifiers
2.  **Pipeline Layer**: Automatic pipeline building and gdalcli pipeline
    format serialization  
3.  **Engine Layer**: Command execution with multiple backend options

## Contributing

We welcome contributions! Please see [CONTRIBUTING.md](CONTRIBUTING.md)
for guidelines.

## License

MIT License - see LICENSE file for details
