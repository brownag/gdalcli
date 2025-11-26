<!-- README.md is generated from README.Rmd. Please edit that file -->

# gdalcli: A Generative R Frontend for the GDAL (≥3.11) Unified CLI

[![Lifecycle:
experimental](https://img.shields.io/badge/lifecycle-experimental-orange.svg)](https://lifecycle.r-lib.org/articles/stages.html)

A modern R interface to GDAL’s unified command-line interface (GDAL
&gt;=3.11). Provides a **lazy evaluation framework** for building and
executing GDAL commands with composable, pipe-aware functions. Full
support for native GDAL pipelines, GDALG format persistence, and
advanced pipeline composition.

## Overview

`gdalcli` implements a frontend for GDAL’s unified CLI with:

-   **Auto-Generated Functions**: 80+ R wrapper functions automatically
    generated from GDAL’s JSON API specification
-   **Lazy Evaluation**: Build command specifications as objects
    (`gdal_job`), execute only when needed via `gdal_job_run()`
-   **Pipe Composition**: Native R pipe (`|>`) support with S3 methods
    for adding options and environment variables
-   **Native Pipeline Execution**: Direct execution via
    `gdal raster/vector pipeline` for efficient multi-step workflows
-   **GDALG Format Support**: Save and load pipelines as JSON for
    persistence, sharing, and version control
-   **Shell Script Generation**: Render pipelines as executable bash/zsh
    scripts (native or sequential modes)
-   **VSI Streaming**: Support for `/vsistdin/` and `/vsistdout/` for
    file-less, memory-efficient workflows
-   **Multiple Backends**: Use processx, gdalraster, or reticulate
    (Python) for backend processing

## Installation

    # Install from GitHub (when available)
    # devtools::install_github("brownag/gdalcli")
    library(gdalcli)

## Quick Examples

### Example 1: Building and Inspecting a Job

    library(gdalcli)

    # Build a raster conversion job (lazy evaluation - nothing executes yet)
    job <- gdal_raster_convert(
      input = "input.tif",
      output = "output.tif",
      output_format = "COG"
    )

    # Inspect the job object
    print(job)
    #> <gdal_job>
    #> Command:  gdal raster convert 
    #> Arguments:
    #>   input: input.tif
    #>   output: output.tif
    #>   --output_format: COG

    # Access internal structure
    cat("Command path:", paste(job$command_path, collapse=" "), "\n")
    #> Command path: raster convert
    cat("Arguments:\n")
    #> Arguments:
    str(job$arguments)
    #> List of 3
    #>  $ input        : chr "input.tif"
    #>  $ output       : chr "output.tif"
    #>  $ output_format: chr "COG"

### Example 2: Adding Options to Jobs

    # Build a job with creation options and config options
    job_with_options <- gdal_raster_convert(
      input = "input.tif",
      output = "output.tif",
      output_format = "COG"
    ) |>
      gdal_with_co("COMPRESS=LZW", "BLOCKXSIZE=256") |>
      gdal_with_config("GDAL_CACHEMAX=512")

    print(job_with_options)
    #> <gdal_job>
    #> Command:  gdal raster convert 
    #> Arguments:
    #>   input: input.tif
    #>   output: output.tif
    #>   --output_format: COG
    #>   --creation-option: [COMPRESS=LZW, BLOCKXSIZE=256]
    #> Config Options:
    #>   GDAL_CACHEMAX=512

### Example 3: Rendering a Job as a Shell Command

    # Render the job as a shell command (executable but not run)
    cmd <- render_gdal_pipeline(job)
    cat("Command to execute:\n")
    #> Command to execute:
    cat(cmd, "\n")
    #> gdal raster convert input.tif output.tif --output-format COG

### Example 4: Building a Multi-Step Pipeline

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

    print(pipeline)
    #> <gdal_job>
    #> Command:  gdal raster reproject 
    #> Arguments:
    #>   input: input.tif
    #>   --dst_crs: EPSG:32632
    #> Pipeline History: 3 prior jobs

### Example 5: Rendering Pipeline to Native GDAL Format

    # Render as native GDAL pipeline (single efficient command)
    native_cmd <- render_gdal_pipeline(pipeline, format = "native")
    cat("Native GDAL pipeline command:\n")
    #> Native GDAL pipeline command:
    cat(native_cmd, "\n")
    #> gdal raster pipeline ! reproject --dst-crs EPSG:32632 ! scale --src-min 0 --src-max 10000 --dst-min 0 --dst-max 255 ! write output.tif

### Example 6: Rendering Pipeline as Shell Script

    # Render as executable bash script (native mode)
    native_script <- render_shell_script(pipeline, format = "native", shell = "bash")
    cat("Bash script (native pipeline mode):\n")
    #> Bash script (native pipeline mode):
    cat(native_script, "\n")
    #> #!/bin/bash
    #> 
    #> set -e
    #> 
    #> # Native GDAL pipeline execution
    #> gdal raster pipeline ! reproject --dst-crs EPSG:32632 ! scale --src-min 0 --src-max 10000 --dst-min 0 --dst-max 255 ! write output.tif
    #> 

### Example 7: Rendering Pipeline as Sequential Commands

    # Render as separate commands (safer for hybrid workflows)
    seq_script <- render_shell_script(pipeline, format = "commands", shell = "bash")
    cat("Bash script (sequential commands mode):\n")
    #> Bash script (sequential commands mode):
    cat(seq_script, "\n")
    #> #!/bin/bash
    #> 
    #> set -e
    #> 
    #> # Job 1
    #> gdal raster reproject input.tif --dst-crs EPSG:32632
    #> 
    #> # Job 2
    #> gdal raster scale --src-min 0 --src-max 10000 --dst-min 0 --dst-max 255
    #> 
    #> # Job 3
    #> gdal raster convert output.tif --output-format COG
    #> 

### Example 8: GDALG Format - Save Pipeline

    # Save pipeline to GDALG format (using custom JSON method for examples)
    temp_file <- tempfile(fileext = ".gdalg.json")
    gdal_save_pipeline(pipeline, temp_file, method = "json")

    # Display the saved GDALG JSON structure
    cat("Saved GDALG file:\n")
    #> Saved GDALG file:
    cat(readLines(temp_file), sep = "\n")
    #> Warning in readLines(temp_file): incomplete final line found on
    #> '/tmp/RtmpyUfIfJ/file9aad071d4ccf1.gdalg.json'
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

### Example 9: GDALG Format - Round-Trip Testing

    # Demonstrate perfect round-trip fidelity
    original_cmd <- render_gdal_pipeline(pipeline, format = "native")

    # Save to GDALG and load back
    temp_file <- tempfile(fileext = ".gdalg.json")
    gdal_save_pipeline(pipeline, temp_file, method = "json")
    loaded_pipeline <- gdal_load_pipeline(temp_file)

    # Render the loaded pipeline
    loaded_cmd <- render_gdal_pipeline(loaded_pipeline, format = "native")

    # Verify they're identical
    cat("Original command:\n")
    #> Original command:
    cat(original_cmd, "\n\n")
    #> gdal raster pipeline ! reproject --dst-crs EPSG:32632 ! scale --src-min 0 --src-max 10000 --dst-min 0 --dst-max 255 ! write output.tif

    cat("Loaded command:\n")
    #> Loaded command:
    cat(loaded_cmd, "\n\n")
    #> gdal raster pipeline ! reproject --dst-crs EPSG:32632 ! scale --src-min 0 --src-max 10000 --dst-min 0 --dst-max 255 ! write output.tif

    cat("Commands identical:", identical(original_cmd, loaded_cmd), "\n")
    #> Commands identical: TRUE

    # Clean up
    unlink(temp_file)

### Example 10: Complex Pipeline with Configuration Options

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
    native_with_config <- render_gdal_pipeline(complex_pipeline$pipeline, format = "native")
    cat("Native pipeline with config options:\n")
    #> Native pipeline with config options:
    cat(native_with_config, "\n")
    #> gdal raster pipeline ! reproject --dst-crs EPSG:3857 ! scale --src-min 0 --src-max 10000 --dst-min 0 --dst-max 255 ! write /vsis3/my-bucket/output.tif

### Example 11: Inspecting Pipeline Structure

    # Build a simple pipeline to inspect
    simple_pipeline <- gdal_raster_info(input = "input.tif") |>
      gdal_raster_reproject(dst_crs = "EPSG:32632") |>
      gdal_raster_convert(output = "output.tif")

    # Inspect the pipeline object
    cat("Pipeline object class:", class(simple_pipeline), "\n")
    #> Pipeline object class: gdal_job list
    cat("Has pipeline history:", !is.null(simple_pipeline$pipeline), "\n")
    #> Has pipeline history: TRUE

    # Access the pipeline structure
    pipe_obj <- simple_pipeline$pipeline
    cat("Number of jobs in pipeline:", length(pipe_obj$jobs), "\n")
    #> Number of jobs in pipeline: 3
    cat("\nJob details:\n")
    #> 
    #> Job details:
    for (i in seq_along(pipe_obj$jobs)) {
      job <- pipe_obj$jobs[[i]]
      cat(sprintf("  Job %d: %s\n", i, paste(job$command_path, collapse=" ")))
      cat(sprintf("    Arguments: %s\n",
                  paste(names(job$arguments), collapse=", ")))
    }
    #>   Job 1: raster info
    #>     Arguments: input
    #>   Job 2: raster reproject
    #>     Arguments: dst_crs
    #>   Job 3: raster convert
    #>     Arguments: output

### Example 12: Detailed GDALG JSON Structure

    # Build a pipeline with multiple steps
    pipeline_for_gdalg <- gdal_raster_reproject(
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
      ) |>
      gdal_with_co("COMPRESS=LZW", "BLOCKXSIZE=512")

    # Save to GDALG format (using custom JSON method for examples)
    temp_gdalg <- tempfile(fileext = ".gdalg.json")
    gdal_save_pipeline(pipeline_for_gdalg, temp_gdalg, method = "json")

    # Display the full JSON
    cat("Full GDALG JSON file:\n")
    #> Full GDALG JSON file:
    cat(readLines(temp_gdalg), sep = "\n")
    #> Warning in readLines(temp_gdalg): incomplete final line found on
    #> '/tmp/RtmpyUfIfJ/file9aad069589a01.gdalg.json'
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

    # Parse and inspect GDALG structure
    loaded <- gdal_load_pipeline(temp_gdalg)
    cat("\n\nGDALG JSON parsed back to R:\n")
    #> 
    #> 
    #> GDALG JSON parsed back to R:
    cat("Loaded pipeline has", length(loaded$jobs), "jobs\n")
    #> Loaded pipeline has 3 jobs
    for (i in seq_along(loaded$jobs)) {
      job <- loaded$jobs[[i]]
      cat(sprintf("  Job %d: %s\n", i, paste(job$command_path, collapse=" ")))
    }
    #>   Job 1: raster reproject
    #>   Job 2: raster scale
    #>   Job 3: vector convert

    # Clean up
    unlink(temp_gdalg)

### Example 13: Config Options Propagation

    # Build a pipeline with config options at different points
    config_pipeline <- gdal_raster_reproject(
      input = "input.tif",
      dst_crs = "EPSG:32632"
    ) |>
      gdal_with_config("GDAL_CACHEMAX=512") |>
      gdal_raster_scale(
        src_min = 0, src_max = 100,
        dst_min = 0, dst_max = 255
      ) |>
      gdal_raster_convert(output = "output.tif") |>
      gdal_with_config("OGR_SQL_DIALECT=SQLITE")

    # Inspect config options
    pipe_obj <- config_pipeline$pipeline
    cat("Config options by job:\n")
    #> Config options by job:
    for (i in seq_along(pipe_obj$jobs)) {
      job <- pipe_obj$jobs[[i]]
      cat(sprintf("Job %d (%s): ", i, paste(job$command_path, collapse=" ")))
      if (length(job$config_options) > 0) {
        for (config_name in names(job$config_options)) {
          cat(sprintf("%s=%s ", config_name, job$config_options[[config_name]]))
        }
        cat("\n")
      } else {
        cat("(none)\n")
      }
    }
    #> Job 1 (raster reproject): GDAL_CACHEMAX=512 
    #> Job 2 (raster scale): (none)
    #> Job 3 (raster convert): (none)

    # Render with config options
    cmd_with_config <- render_gdal_pipeline(config_pipeline$pipeline, format = "native")
    cat("\nRendered native command with config options:\n")
    #> 
    #> Rendered native command with config options:
    cat(cmd_with_config, "\n")
    #> gdal raster pipeline ! reproject --dst-crs EPSG:32632 ! scale --src-min 0 --src-max 100 --dst-min 0 --dst-max 255 ! write output.tif

### Example 14: Sequential vs Native Rendering Comparison

    # Create a pipeline
    comparison_pipeline <- gdal_raster_info(input = "input.tif") |>
      gdal_raster_reproject(dst_crs = "EPSG:32632") |>
      gdal_raster_scale(src_min = 0, src_max = 100, dst_min = 0, dst_max = 255) |>
      gdal_raster_convert(output = "output.tif")

    # Get sequential command rendering
    seq_cmd <- render_gdal_pipeline(comparison_pipeline$pipeline, format = "shell_chain")
    cat("Sequential command (separate GDAL commands chained with &&):\n")
    #> Sequential command (separate GDAL commands chained with &&):
    cat(seq_cmd, "\n\n")
    #> gdal raster info input.tif && gdal raster reproject --dst-crs EPSG:32632 && gdal raster scale --src-min 0 --src-max 100 --dst-min 0 --dst-max 255 && gdal raster convert output.tif

    # Get native command rendering
    native_cmd <- render_gdal_pipeline(comparison_pipeline$pipeline, format = "native")
    cat("Native command (single GDAL pipeline):\n")
    #> Native command (single GDAL pipeline):
    cat(native_cmd, "\n\n")
    #> gdal raster pipeline ! read input.tif ! reproject --dst-crs EPSG:32632 ! scale --src-min 0 --src-max 100 --dst-min 0 --dst-max 255 ! write output.tif

    # Compare as shell scripts
    cat("=== Sequential Shell Script ===\n")
    #> === Sequential Shell Script ===
    cat(render_shell_script(comparison_pipeline, format = "commands"), "\n\n")
    #> #!/bin/bash
    #> 
    #> set -e
    #> 
    #> # Job 1
    #> gdal raster info input.tif
    #> 
    #> # Job 2
    #> gdal raster reproject --dst-crs EPSG:32632
    #> 
    #> # Job 3
    #> gdal raster scale --src-min 0 --src-max 100 --dst-min 0 --dst-max 255
    #> 
    #> # Job 4
    #> gdal raster convert output.tif
    #> 

    cat("=== Native Shell Script ===\n")
    #> === Native Shell Script ===
    cat(render_shell_script(comparison_pipeline, format = "native"), "\n")
    #> #!/bin/bash
    #> 
    #> set -e
    #> 
    #> # Native GDAL pipeline execution
    #> gdal raster pipeline ! read input.tif ! reproject --dst-crs EPSG:32632 ! scale --src-min 0 --src-max 100 --dst-min 0 --dst-max 255 ! write output.tif
    #> 

## Pipeline Features

### Native GDAL Pipeline Execution

Execute multi-step workflows as a single native GDAL pipeline for
maximum efficiency:

    # The native pipeline format runs all steps in a single command
    # avoiding intermediate disk I/O for large datasets
    pipeline <- gdal_raster_info(input = "input.tif") |>
      gdal_raster_reproject(dst_crs = "EPSG:32632") |>
      gdal_raster_convert(output = "output.tif")

    # This pipeline would execute as a native GDAL command when passed to gdal_job_run()
    # gdal_job_run(pipeline) executes it using the default (sequential) or native mode

Native mode runs the entire pipeline in a single GDAL command, avoiding
intermediate disk I/O for large datasets.

### GDALG Format: Save and Load Pipelines

Persist pipelines as JSON files for sharing and version control:

    # Save pipeline to GDALG format
    pipeline <- gdal_raster_reproject(input = "in.tif", dst_crs = "EPSG:32632") |>
      gdal_raster_scale(src_min = 0, src_max = 100, dst_min = 0, dst_max = 255, output = "out.tif")

    gdal_save_pipeline(pipeline, "workflow.gdalg.json")

    # Load and execute later
    loaded <- gdal_load_pipeline("workflow.gdalg.json")
    gdal_job_run(loaded)

GDALG provides perfect round-trip fidelity—all pipeline structure and
arguments are preserved.

### Shell Script Generation

Generate executable shell scripts from pipelines:

    # Render as native GDAL pipeline script
    script <- render_shell_script(pipeline, format = "native", shell = "bash")
    writeLines(script, "process.sh")

    # Or as separate sequential commands
    script_seq <- render_shell_script(pipeline, format = "commands", shell = "bash")

### GDALG Format: Native Format Driver Support (GDAL 3.11+)

For maximum compatibility with GDAL tools across Python, C++, and CLI,
use the native GDALG format driver:

    # Check if native GDALG driver is available
    if (gdal_has_gdalg_driver()) {
      # Save using GDAL's native GDALG format driver
      # This ensures compatibility with other GDAL tools
      gdal_save_pipeline(pipeline, "workflow.gdalg.json", method = "native")

      # Or explicitly use the native function
      gdal_save_pipeline_native(pipeline, "workflow.gdalg.json")
    }

    # Auto-detection: automatically uses native driver if available, else custom JSON
    gdal_save_pipeline(pipeline, "workflow.gdalg.json", method = "auto")

**Comparison of serialization methods:**

<table>
<thead>
<tr class="header">
<th>Feature</th>
<th>Custom JSON</th>
<th>Native GDALG Driver</th>
</tr>
</thead>
<tbody>
<tr class="odd">
<td>GDAL Version</td>
<td>Any</td>
<td>3.11+</td>
</tr>
<tr class="even">
<td>Speed</td>
<td>Fast</td>
<td>Moderate</td>
</tr>
<tr class="odd">
<td>Compatibility</td>
<td>gdalcli-specific</td>
<td>Universal GDAL tools</td>
</tr>
<tr class="even">
<td>Metadata</td>
<td>Basic</td>
<td>Full GDAL metadata</td>
</tr>
<tr class="odd">
<td>Use Case</td>
<td>Development, testing</td>
<td>Production, cross-tool workflows</td>
</tr>
</tbody>
</table>

**Method parameter:** - `method = "json"` - Uses custom JSON
serialization (fast, backward compatible) - `method = "native"` - Uses
GDAL’s native GDALG format driver (requires GDAL 3.11+) -
`method = "auto"` - Automatically selects best method based on GDAL
version

Both methods produce valid, portable GDALG files that can be loaded with
`gdal_load_pipeline()`.

### Configuration Options in Pipelines

Add GDAL configuration options to pipeline steps:

    pipeline_with_config <- gdal_raster_reproject(
      input = "in.tif",
      dst_crs = "EPSG:32632"
    ) |>
      gdal_with_config("OGR_SQL_DIALECT=SQLITE") |>
      gdal_raster_scale(
        src_min = 0, src_max = 100,
        dst_min = 0, dst_max = 255,
        output = "out.tif"
      )

    # Config options are included in native pipeline rendering
    render_gdal_pipeline(pipeline_with_config$pipeline, format = "native")
    #> [1] "gdal raster pipeline ! reproject --dst-crs EPSG:32632 ! scale --src-min 0 --src-max 100 --dst-min 0 --dst-max 255"

## Version Compatibility

`gdalcli` supports GDAL 3.11 and later, with enhanced features available
in GDAL 3.12+.

### Minimum Requirements

-   **GDAL**: ≥ 3.11.3 (Unified CLI framework minimum)
-   **R**: ≥ 4.0.0
-   **gdalraster**: ≥ 2.2.0 (recommended for advanced features)

### GDAL 3.11 Features

Core GDAL unified CLI functionality available in GDAL 3.11+:

-   **80+ Algorithm Functions**: All raster, vector, and
    multidimensional operations
-   **Pipeline Execution**: Native and sequential pipeline modes
-   **GDALG Format**: Save/load pipelines as JSON
-   **Configuration Options**: Full GDAL config option support
-   **VSI Support**: Virtual file system integration
-   **Shell Script Generation**: Export pipelines to executable bash/zsh

### GDAL 3.12 Enhancements

New algorithms and capabilities available in GDAL 3.12+:

-   **New Raster Algorithms**: blend, compare, neighbors,
    nodata-to-alpha, pansharpen, proximity, rgb-to-palette, update,
    zonal-stats, as-features
-   **New Vector Algorithms**: check-coverage, check-geometry,
    clean-coverage, index, layer-algebra, make-point, partition,
    set-field-type, simplify-coverage
-   **GDALG Format Driver**: Native support for GDALG as a format driver
-   **Advanced Features**: Enhanced pipeline capabilities and algorithm
    metadata

### Checking Version Support

Use the discovery utilities to check version requirements:

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

When regenerating the package with GDAL 3.12+ installed, all new
algorithms are automatically discovered and wrapped as R functions.

## GDAL Function Categories

The 80+ auto-generated functions are organized into logical categories:

### Raster Operations

Functions for working with raster datasets: `gdal_raster_*`

-   **gdal\_raster\_convert** - Format conversion
-   **gdal\_raster\_clip** - Spatial subsetting
-   **gdal\_raster\_reproject** - Reprojection
-   **gdal\_raster\_scale** - Value scaling
-   And many more…

### Vector Operations

Functions for working with vector datasets: `gdal_vector_*`

-   **gdal\_vector\_convert** - Format conversion
-   **gdal\_vector\_info** - Dataset information
-   **gdal\_vector\_reproject** - Reprojection
-   And more…

### Multidimensional (MDim)

Functions for multidimensional data: `gdal_mdim_*`

-   **gdal\_mdim\_convert** - Dimension conversion
-   **gdal\_mdim\_info** - Dimension information

### VSI (Virtual File System)

Functions for cloud storage and remote access: `gdal_vsi_*`

-   Support for S3, Azure, GCS, OSS, Swift with automatic credential
    handling

Use `gdal_gdal(drivers = TRUE)` to list all available drivers in your
GDAL installation.

## System Requirements

-   **R** &gt;= 4.1
-   **GDAL** &gt;= 3.11 (required for unified CLI)
-   **Dependencies**:
    -   `processx` (&gt;=3.8.0) - Robust subprocess management
    -   `yyjsonr` (&gt;=0.1.0) - Fast, memory-efficient JSON handling
    -   `rlang` (&gt;=1.0.0) - Error handling and programming utilities
    -   `cli` (&gt;=3.0.0) - User-friendly terminal messages
    -   `digest` (&gt;=0.6.0) - Cryptographic hashing

## Documentation

-   **Getting Started**: `?gdal_vector_convert` - Example auto-generated
    function
-   **Authentication**: `?gdal_auth_s3`, `?gdal_auth_azure`, etc. - Set
    up credentials
-   **Lazy Evaluation**: `?gdal_job` - Understand the job specification
    system
-   **Execution**: `?gdal_job_run` - Run GDAL commands
-   **Composition**: `?gdal_with_co`, `?gdal_with_env` - Modify jobs
    with modifiers

## Architecture & Design

### Three-Layer Architecture

`gdalcli` separates concerns into three layers:

1.  **Frontend Layer** (User-facing R API)
    -   Auto-generated functions like `gdal_vector_convert()`,
        `gdal_raster_reproject()`, etc.
    -   Composable modifiers: `gdal_with_co()`, `gdal_with_env()`,
        `gdal_with_config()`, etc.
    -   S3 methods for extensibility
    -   Lazy `gdal_job` specification objects
    -   Native pipe (`|>`) support for fluent composition
2.  **Pipeline Layer** (Advanced Workflows)
    -   Automatic pipeline building through chained piping
    -   Native GDAL pipeline execution (`gdal raster/vector pipeline`)
    -   GDALG format serialization with `gdal_save_pipeline()` and
        `gdal_load_pipeline()`
    -   Shell script rendering for persistence and sharing
    -   Configuration option aggregation and propagation
    -   Sequential vs. native execution modes
3.  **Engine Layer** (Command Execution)
    -   `gdal_job_run()` executes individual jobs or entire pipelines
    -   Uses processx for robust subprocess management
    -   Handles environment variable injection
    -   Supports input/output streaming (`/vsistdin/`, `/vsistdout/`)
    -   Multiple backend options (processx, gdalraster, reticulate)

### Lazy Evaluation

Commands are built as specifications (`gdal_job` objects) and only
executed when passed to `gdal_job_run()`:

    # This doesn't execute anything - just builds a specification
    job <- gdal_vector_convert(
      input = "data.shp",
      output = "data.gpkg"
    )

    # Inspect the job before running
    print(job)
    #> <gdal_job>
    #> Command:  gdal vector convert 
    #> Arguments:
    #>   input: data.shp
    #>   output: data.gpkg

    # Render to see the command that would be executed
    render_gdal_pipeline(job)
    #> [1] "gdal vector convert data.shp data.gpkg"

### S3-Based Composition

All modifiers are S3 generics that accept and return `gdal_job` objects,
enabling composable workflows:

    # Each step returns a modified gdal_job
    pipeline <- gdal_raster_convert(input = "in.tif", output = "out.tif") |>
      gdal_with_co("COMPRESS=DEFLATE") |>
      gdal_with_config("GDAL_CACHEMAX=512")

    # Inspect at any point
    print(pipeline)
    #> <gdal_job>
    #> Command:  gdal raster convert 
    #> Arguments:
    #>   input: in.tif
    #>   output: out.tif
    #>   --creation-option: COMPRESS=DEFLATE
    #> Config Options:
    #>   GDAL_CACHEMAX=512

### Pipeline Composition and Execution Modes

Pipelines are automatically created when chaining GDAL operations with
the native R pipe:

    # Build a multi-step pipeline by chaining operations
    pipeline <- gdal_raster_info(input = "input.tif") |>
      gdal_raster_reproject(dst_crs = "EPSG:32632") |>
      gdal_raster_convert(output = "output.tif")

    # Render as sequential commands (jobs run separately)
    seq_render <- render_gdal_pipeline(pipeline$pipeline, format = "shell_chain")
    cat("Sequential:", seq_render, "\n\n")
    #> Sequential: gdal raster info input.tif && gdal raster reproject --dst-crs EPSG:32632 && gdal raster convert output.tif

    # Render as native GDAL pipeline (single efficient command)
    native_render <- render_gdal_pipeline(pipeline$pipeline, format = "native")
    cat("Native:", native_render, "\n")
    #> Native: gdal raster pipeline ! read input.tif ! reproject --dst-crs EPSG:32632 ! write output.tif

**Sequential Execution** (default):

-   Each job runs as a separate GDAL command
-   Safer for hybrid workflows mixing pipeline and non-pipeline
    operations
-   Intermediate results written to disk

**Native Execution**:

-   Entire pipeline runs as single `gdal raster/vector pipeline` command
-   More efficient for large datasets (avoids intermediate I/O)
-   Direct data flow between pipeline steps

### GDALG Format: Pipeline Persistence

Pipelines can be saved and loaded for persistence and sharing:

    # Save pipeline as GDALG (JSON format)
    gdal_save_pipeline(pipeline, "workflow.gdalg.json")

    # Load pipeline later
    loaded <- gdal_load_pipeline("workflow.gdalg.json")

    # Pipelines maintain perfect round-trip fidelity
    # All structure, arguments, and metadata are preserved

GDALG files can be:

-   Version controlled in git repositories
-   Shared with team members
-   Executed by other GDAL-compatible tools
-   Edited manually for advanced workflows

## Security Considerations

1.  **Credentials in .Renviron, not in code** - Never pass secrets as
    function arguments. Use `.Renviron` or external secret managers:

        # ~/.Renviron or project .Renviron
        AWS_ACCESS_KEY_ID=your_access_key
        AWS_SECRET_ACCESS_KEY=your_secret

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

    -   HashiCorp Vault
    -   AWS Secrets Manager
    -   Azure Key Vault
    -   Google Cloud Secret Manager
    -   1Password, Bitwarden, or other password managers with
        environment variable integration

## Contributing

Contributions are welcome! Here's how to get started:

### Setup

```bash
git clone https://github.com/brownag/gdalcli.git
cd gdalcli
Rscript -e "devtools::install_deps(dependencies = TRUE)"
```

### Code Conventions

**Internal functions** (not exported):
- Prefix with dot: `.error()`, `.validate_path_component()`
- Use `@noRd` roxygen tag

**Exported functions**:
- Include `@export` in roxygen comments
- All functions require roxygen documentation

**S3 Methods**:
- Use generic.class naming: `print.gdal_job`, `gdal_with_co.default`
- Auto-registered via roxygen

### Development Workflow

```bash
make dev        # Quick build (regenerate, docs, check-man)
make test       # Run tests
make docs       # Build documentation
make check      # Full R CMD check
```

### Testing

Add tests to `tests/testthat/` using testthat:

```r
test_that("descriptive test name", {
  result <- my_function(input)
  expect_equal(result, expected_value)
})
```

### Git Workflow

1. Create a branch: `git checkout -b feature/description`
2. Make changes and test locally
3. Commit with conventional commit format:
   ```
   type: brief description

   Optional longer explanation if needed.
   ```
4. Push and open a PR

**Commit types**: `feat`, `fix`, `docs`, `test`, `refactor`, `chore`, `ci`, `build`
- Keep commits focused on a single concern
- Keep subject line brief (50 chars preferred)

### Before Opening a PR

- Run `make dev` and `make test`
- Run `make check-man` and fix any documentation errors
- Keep PRs focused on a single concern
- Use draft PR for work in progress
- Rebase changes onto main branch rather than merge main into branch
- Squash commits to combine related changes

### Questions?

Open an [issue](https://github.com/brownag/gdalcli/issues/) on GitHub.

## License

MIT License - see LICENSE file for details

## References

-   **GDAL Unified CLI (≥3.11)**: <https://gdal.org/programs/index.html>
-   **GDAL Pipeline Documentation**:
    <https://gdal.org/programs/gdalinfo.html> (see
    `gdal raster pipeline`, `gdal vector pipeline`)
-   **GDAL JSON Usage API**:
    <https://gdal.org/development/rfc/rfc_index.html> (RFC 90)
-   **GDAL Virtual File Systems**:
    <https://gdal.org/user/virtual_file_systems.html>
-   **GDAL Configuration Options**:
    <https://gdal.org/user/configoptions.html>
-   **Lazy Evaluation in R**: Inspired by dbplyr, rlang, and tidyverse
    design patterns
-   **S3 Object System**: <https://adv-r.hadley.nz/s3.html>
-   **processx Package**: <https://processx.r-lib.org/>
-   **yyjsonr Package**:
    <https://cran.r-project.org/web/packages/yyjsonr/index.html>

## Acknowledgments

This package is built on GDAL’s unified CLI (≥3.11) and the GDAL
development team’s work.
