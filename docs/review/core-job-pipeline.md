# Core Job and Pipeline System Review

**Component**: `gdal_job` and `gdal_pipeline` S3 classes  
**Location**: [R/core-gdal_job.R](../../R/core-gdal_job.R), [R/core-gdal_pipeline.R](../../R/core-gdal_pipeline.R)  
**Last Updated**: 2026-01-31

---

## Executive Summary

The job/pipeline system is the central architecture of gdalcli, implementing a **lazy evaluation framework** where GDAL commands are constructed as specification objects (`gdal_job`) and only executed when explicitly run via `gdal_job_run()`. This design enables composability, auditability, and serialization of complex geospatial workflows.

---

## Core Data Structures

### `gdal_job` S3 Class

The fundamental unit of work. Structure:

```r
list(
  command_path = c("gdal", "raster", "convert"),  # Command hierarchy
  arguments = list("input" = "...", "output" = "..."),  # CLI arguments
  config_options = c("GDAL_CACHEMAX" = "512"),  # --config options
  env_vars = c("AWS_ACCESS_KEY_ID" = "..."),  # Environment for subprocess
  stream_in = NULL,  # R object for /vsistdin/
  stream_out_format = NULL,  # "text", "raw", "json", "stdout"
  pipeline = NULL,  # gdal_pipeline if chained
  arg_mapping = list()  # Argument metadata (min_count, max_count)
)
class: c("gdal_job", "list")
```

### `gdal_pipeline` S3 Class

A DAG of jobs for sequential execution. Structure:

```r
list(
  jobs = list(job1, job2, job3),  # Ordered list of gdal_job objects
  name = "My Pipeline",  # Optional name (used in serialization)
  description = "Description"  # Optional description
)
class: c("gdal_pipeline", "list")
```

---

## Key Design Patterns

### 1. Lazy Evaluation

Jobs are specifications, not executions:

```r
job <- gdal_raster_convert(input = "in.tif", output = "out.tif")  # Lazy spec
gdal_job_run(job)  # Actual execution
```

**Agent Implementation Notes**:
- Never execute jobs in `new_gdal_job()` or generated wrapper functions
- All job construction must be side-effect free
- Execution only happens in `gdal_job_run()` and its methods

### 2. First-Arg Piping Detection

Auto-generated functions detect if the first argument is a piped `gdal_job`:

```r
# Fresh call - first arg is data
gdal_raster_convert(input = "in.tif", output = "out.tif")

# Piped call - first arg is gdal_job, extends pipeline
gdal_raster_reproject(input = "in.tif", dst_crs = "EPSG:4326") |>
  gdal_raster_convert(output = "out.tif")  # "input" comes from pipe
```

**Detection Logic** (in generated functions):
```r
if (inherits(input, "gdal_job")) {
  # Extend pipeline: input is previous job's output
  extend_gdal_pipeline(input, command_path, arguments)
} else {
  # Fresh job: input is actual data path
  new_gdal_job(command_path, arguments)
}
```

### 3. Pipeline Extension Mechanics

The `extend_gdal_pipeline()` function (lines 580-670 in core-gdal_pipeline.R):

1. Creates a new job for the current operation
2. If previous job has no output, assigns virtual path (`/vsimem/...`)
3. Connects new job's input to previous job's output
4. Builds/extends the pipeline DAG

**Connection Logic**:
- Virtual paths (`/vsimem/`, `/vsistdin/`) are auto-replaced with previous output
- Explicit user paths are preserved
- Only input/output positional args participate in connection

### 4. S3 Composition via Modifiers

All `gdal_with_*` functions return modified `gdal_job` objects:

```r
job |> 
  gdal_with_co("COMPRESS=LZW") |>  # Creation options
  gdal_with_config("GDAL_CACHEMAX" = "512")  # Config options
```

**Modifier Flow**:
1. Accept `gdal_job` as first argument
2. Clone/modify specific fields (config_options, arguments, etc.)
3. Return new `gdal_job` (immutable pattern)

---

## Key Functions

### Constructors

| Function | Purpose | Exported |
|----------|---------|----------|
| `new_gdal_job()` | Low-level constructor | ✅ |
| `new_gdal_pipeline()` | Pipeline constructor | ✅ |
| `extend_gdal_pipeline()` | Add job to pipeline | ✅ |

### Accessors

| Function | Purpose | Notes |
|----------|---------|-------|
| `$.gdal_job` | Property access + fluent methods | `job$arguments`, `job$run()` |
| `[.gdal_job` | Extract job(s) from pipeline | `pipeline[1:3]` |
| `length.gdal_job` | Number of pipeline steps | Returns 1 if no pipeline |
| `c.gdal_job` | Combine jobs into pipeline | Flattens nested pipelines |

### Pipeline Operations

| Function | Purpose | Notes |
|----------|---------|-------|
| `add_job()` | Add job to pipeline | Returns new pipeline |
| `get_jobs()` | Get job list | Returns `list` of jobs |
| `set_name()` | Set pipeline name | For serialization |
| `set_description()` | Set pipeline description | For serialization |
| `render_gdal_pipeline()` | Generate CLI string | `"shell_chain"` or `"native"` |
| `render_shell_script()` | Generate shell script | `"commands"` or `"native"` |

---

## Argument Handling

### Positional vs Option Arguments

GDAL CLI structure: `gdal [command] [options] [input...] [output]`

```r
positional_arg_names <- c("input", "output", "src_dataset", "dest_dataset", "dataset")
```

Serialization order:
1. Command path (`raster convert`)
2. Option arguments (`--dst-crs EPSG:4326`)
3. Positional inputs (`input.tif`)
4. Positional outputs (`output.tif`)

### Composite vs Repeatable Arguments

Determined by `arg_mapping` metadata:

- **Composite** (fixed count): `--bbox 1,2,3,4` (comma-separated)
- **Repeatable** (variable count): `--co COMPRESS=LZW --co TILED=YES` (repeated flags)

Detection:
```r
is_composite <- arg_meta$min_count == arg_meta$max_count && arg_meta$min_count > 1
```

---

## Pipeline Execution Modes

### Sequential Mode (Default)

Each job runs as separate GDAL subprocess:

```r
gdal_job_run(pipeline, execution_mode = "sequential")
```

Flow:
1. Execute job 1, write to disk/virtual
2. Execute job 2 reading from job 1's output
3. Continue until pipeline complete
4. Clean up temporary files

### Native Mode

Single GDAL pipeline command (more efficient):

```r
gdal_job_run(pipeline, execution_mode = "native")
```

Generates: `gdal raster pipeline ! read in.tif ! reproject --dst-crs EPSG:4326 ! write out.tif`

**Native Pipeline Building** (`.build_pipeline_from_jobs()`):
- Maps gdalcli operations to RFC 104 step names (`convert` → `write`, `info` → `read`)
- Strips input/output from intermediate steps
- Adds `! read` prefix and `! write` suffix as needed

---

## Critical Mappings

### Step Name Mapping (in `.build_pipeline_from_jobs()`)

```r
step_mapping <- list(
  "raster" = c(
    "convert" = "write",
    "info" = "read",
    "reproject" = "reproject",
    "clip" = "clip",
    "calc" = "calc",
    ...
  ),
  "vector" = c(
    "convert" = "write",
    "info" = "read",
    "reproject" = "reproject",
    ...
  )
)
```

**Agent Note**: When adding new GDAL commands, update step mappings if the RFC 104 step name differs from the gdalcli operation name.

---

## Potential Improvements

### 1. Coupling to RFC 104 Step Names

**Issue**: Step mappings are hardcoded in `.build_pipeline_from_jobs()`.

**Recommendation**: Extract to configuration or generate from GDAL JSON API at build time.

### 2. Pipeline Branching

**Current State**: Linear DAG only (single output per step).

**Future**: Support DAG with multiple outputs for forked workflows.

### 3. Checkpoint/Resume

**Current State**: No intermediate state persistence.

**Future**: Consider checkpointing for long-running pipelines.

---

## Testing Considerations

### Structure Tests (No GDAL Required)

```r
test_that("pipeline creation works", {
  job <- gdal_raster_reproject(input = "in.tif", dst_crs = "EPSG:4326")
  expect_s3_class(job, "gdal_job")
  expect_equal(job$arguments$dst_crs, "EPSG:4326")
})
```

### Pipeline Connection Tests

```r
test_that("pipeline connects outputs to inputs", {
  job <- gdal_raster_reproject(...) |> gdal_raster_convert(...)
  expect_equal(job$pipeline$jobs[[2]]$arguments$input, 
               job$pipeline$jobs[[1]]$arguments$output)
})
```

### Render Verification Tests

```r
test_that("native pipeline renders correctly", {
  native_cmd <- render_gdal_pipeline(pipeline, format = "native")
  expect_true(grepl("! read", native_cmd))
  expect_true(grepl("! write", native_cmd))
})
```

---

## Dependencies

### Internal Dependencies

- `core-gdal_modifiers.R` - `gdal_with_*` functions
- `gdalg-transpiler.R` - RFC 104 command generation
- `core-gdal_run.R` - Execution backends

### External Dependencies

- `rlang` - Error handling, tidy evaluation
- `cli` - Message formatting
- `processx` - Subprocess management (for execution)

---

## Files to Modify When Changing This Component

| Change Type | Files to Update |
|-------------|-----------------|
| New job field | `core-gdal_job.R`, `gdalg-transpiler.R`, `core-gdalcli-spec.R` |
| New pipeline field | `core-gdal_pipeline.R`, `core-gdalcli-spec.R` |
| New step mapping | `core-gdal_job.R` (`.build_pipeline_from_jobs()`) |
| New modifier | `core-gdal_modifiers.R` |
| New execution mode | `core-gdal_pipeline.R`, `core-gdal_run.R` |
