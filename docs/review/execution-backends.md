# Execution Backends Review

**Component**: GDAL job execution subsystem  
**Location**: [R/core-gdal_run.R](../../R/core-gdal_run.R)  
**Last Updated**: 2026-01-31

---

## Executive Summary

gdalcli supports three execution backends for running GDAL jobs:

1. **processx** (default): Subprocess-based via `processx::run()`
2. **gdalraster**: C++ bindings via `gdalraster::gdal_alg()`
3. **reticulate**: Python osgeo.gdal via `reticulate`

Backend selection is automatic or explicit. The system enables flexibility for different environments while maintaining a consistent API.

---

## Backend Comparison

| Feature | processx | gdalraster | reticulate |
|---------|----------|------------|------------|
| **Requires** | GDAL CLI | gdalraster ≥2.2.0 | Python + GDAL |
| **Default** | ✅ Fallback | ✅ Preferred | ❌ Explicit |
| **Streaming** | ✅ Full | ⚠️ Limited | ⚠️ Limited |
| **Native Pipeline** | ✅ Yes | ✅ Yes | ❌ No |
| **Overhead** | Higher (subprocess) | Lower (in-process) | Medium |
| **Debug with GDAL_DEBUG** | ✅ Yes | ⚠️ Partial | ⚠️ Partial |
| **Audit Trail** | ✅ Yes | ✅ Yes | ✅ Yes |

---

## Backend Selection

### Automatic Selection

```r
gdal_job_run(job)  # Auto-selects best available
```

**Selection Logic**:
```r
if (getOption("gdalcli.backend") is set) {
  use that backend
} else if (gdalraster ≥ 2.2.0 is available) {
  use "gdalraster"
} else {
  use "processx"
}
```

### Explicit Selection

```r
gdal_job_run(job, backend = "processx")
gdal_job_run(job, backend = "gdalraster")
gdal_job_run(job, backend = "reticulate")
```

### Global Default

```r
options(gdalcli.backend = "gdalraster")  # Set default
options(gdalcli.backend = "auto")        # Reset to auto-selection
```

---

## Job Execution Flow

### Main Entry Point

```r
gdal_job_run(x, ..., backend = NULL)
```

**Dispatch Logic**:
1. Check if `x` is `gdal_pipeline` → delegate to `gdal_job_run.gdal_pipeline()`
2. Check if `x` has `$pipeline` → run the pipeline
3. Select backend (auto or explicit)
4. Dispatch to backend-specific implementation

### Backend Implementations

| Implementation | Function |
|----------------|----------|
| processx | `gdal_job_run.gdal_job()` |
| gdalraster | `.gdal_job_run_gdalraster()` |
| reticulate | `.gdal_job_run_reticulate()` |

---

## processx Backend

### Implementation: `gdal_job_run.gdal_job()`

**Flow**:
1. Serialize job via `.serialize_gdal_job()`
2. Merge environment variables via `.merge_env_vars()`
3. Configure stdin/stdout for streaming
4. Execute via `processx::run()`
5. Handle output based on `stream_out_format`

**Streaming Support**:

| stream_out_format | Behavior |
|-------------------|----------|
| `NULL` | Invisibly returns `TRUE` |
| `"text"` | Returns stdout as character |
| `"raw"` | Returns stdout as raw vector |
| `"json"` | Parses stdout as JSON |
| `"stdout"` | Prints to console in real-time |

**Example**:
```r
result <- gdal_raster_info("input.tif") |>
  gdal_job_run(stream_out_format = "json")
```

---

## gdalraster Backend

### Implementation: `.gdal_job_run_gdalraster()`

**Requires**: `gdalraster` package ≥ 2.2.0

**Flow**:
1. Serialize job via `.serialize_gdal_job()`
2. Set environment variables temporarily
3. Split into command/args for `gdal_alg()`
4. Create algorithm: `gdalraster::gdal_alg(cmd, args)`
5. Run: `alg$run()`
6. Get output: `alg$output()`
7. Restore environment

**Advantages**:
- In-process (no subprocess overhead)
- Direct C++ GDAL bindings
- Potentially faster for batch operations

**Limitations**:
- Streaming to/from R objects more limited
- Some advanced CLI features may not work

### Native Pipeline Support

```r
.gdal_job_run_native_pipeline_gdalraster(pipeline, ...)
```

Builds native pipeline string and executes via `gdalraster::gdal_alg()`.

---

## reticulate Backend

### Implementation: `.gdal_job_run_reticulate()`

**Requires**: 
- `reticulate` package
- Python with `osgeo.gdal` module

**Flow**:
1. Serialize job via `.serialize_gdal_job()`
2. Set environment variables
3. Convert CLI args to Python kwargs via `.convert_cli_args_to_kwargs()`
4. Import Python GDAL: `reticulate::import("osgeo.gdal")`
5. Call: `gdal_py$Run(command_path, kwargs)`
6. Get output: `alg$Output()`

**Use Cases**:
- Integration with Python geospatial workflows
- When GDAL CLI not available but Python GDAL is
- Cross-language debugging

---

## Pipeline Execution

### Sequential Mode

```r
gdal_job_run(pipeline, execution_mode = "sequential")
```

Each job runs as separate GDAL subprocess:

```
job1 → write to disk/virtual →
job2 → read from disk/virtual → write to disk/virtual →
job3 → read from disk/virtual → final output
```

**Implementation**: Loop in `gdal_job_run.gdal_pipeline()`

### Native Mode

```r
gdal_job_run(pipeline, execution_mode = "native")
```

Single GDAL pipeline command:

```bash
gdal raster pipeline ! read in.tif ! reproject --dst-crs=EPSG:4326 ! write out.tif
```

**Implementations**:
- processx: `.gdal_job_run_native_pipeline()`
- gdalraster: `.gdal_job_run_native_pipeline_gdalraster()`

**Advantages**:
- No intermediate disk I/O
- More efficient for large datasets
- GDAL optimizes data flow

---

## Job Serialization

### Main Function: `.serialize_gdal_job()`

Converts `gdal_job` to CLI argument vector:

```r
job <- gdal_raster_reproject(input = "in.tif", dst_crs = "EPSG:4326")
args <- .serialize_gdal_job(job)
# → c("raster", "reproject", "--dst-crs", "EPSG:4326", "in.tif")
```

**Serialization Order**:
1. Command path (e.g., `"raster"`, `"reproject"`)
2. Option arguments (`--flag value`)
3. Positional inputs (`input.tif`)
4. Positional outputs (`output.tif`)

**Argument Type Handling**:
- Logical `TRUE` → flag only
- Logical `FALSE` → skip
- Single value → `--flag value`
- Composite vector → `--flag val1,val2,val3`
- Repeatable vector → `--flag val1 --flag val2`

---

## Environment Variable Handling

### Main Function: `.merge_env_vars()`

Combines environment variables from multiple sources:

```r
env_final <- .merge_env_vars(job$env_vars, explicit_env, job$config_options)
```

**Source Priority** (later overrides earlier):
1. Job's `env_vars`
2. Legacy global auth variables (`AWS_*`, `GS_*`, `AZURE_*`, etc.)
3. Explicit `env` parameter

**Security Note**: Credentials are passed via subprocess environment, never as CLI arguments.

---

## Streaming Options

### Input Streaming (`stream_in`)

```r
geojson <- '{"type": "FeatureCollection", ...}'
gdal_vector_convert(input = "/vsistdin/", output = "out.gpkg") |>
  gdal_job_run(stream_in = geojson)
```

**Implementation**: Passed to `processx::run(stdin = ...)`.

### Output Streaming (`stream_out_format`)

| Format | Description |
|--------|-------------|
| `NULL` | Don't capture (default) |
| `"text"` | Return as character string |
| `"raw"` | Return as raw vector |
| `"json"` | Parse as JSON, return list |
| `"stdout"` | Print to console in real-time |

**Global Default**:
```r
options(gdalcli.stream_out_format = "text")
```

---

## Error Handling

### processx Backend

```r
processx::run(..., error_on_status = TRUE)
```

Throws error with GDAL stderr on non-zero exit.

### gdalraster Backend

```r
tryCatch({
  alg$run()
}, error = function(e) {
  # Extract GDAL error from message
  if (grepl("GDAL FAILURE", e$message)) {
    # Parse and re-throw with clean message
  }
})
```

### Error Messages

All backends surface GDAL error messages:

```
Error in gdal_job_run(job):
! GDAL command failed
✖ Failed to open file: nonexistent.tif
```

---

## Verbose Mode

```r
gdal_job_run(job, verbose = TRUE)
```

Prints executed command:

```
ℹ Executing: gdal raster reproject --dst-crs EPSG:4326 input.tif output.tif
```

**Global Default**:
```r
options(gdalcli.verbose = TRUE)
```

---

## Audit Trail

When `audit = TRUE`:

```r
result <- gdal_raster_info("input.tif") |>
  gdal_job_run(stream_out_format = "text", audit = TRUE)

attr(result, "audit_trail")
# list(
#   timestamp = <POSIXct>,
#   duration = <difftime>,
#   command = "gdal raster info input.tif",
#   backend = "gdalraster",
#   explicit_args = list(...),
#   status = "success"
# )
```

---

## Configuration Options

| Option | Default | Description |
|--------|---------|-------------|
| `gdalcli.backend` | `"auto"` | Default backend |
| `gdalcli.stream_out_format` | `NULL` | Default output format |
| `gdalcli.verbose` | `FALSE` | Print commands |

---

## Testing Considerations

### Backend Availability Check

```r
test_that("gdalraster backend works", {
  skip_if_not(.check_gdalraster_version("2.2.0", quietly = TRUE))
  # ... test with gdalraster ...
})
```

### Backend Parity Tests

```r
test_that("all backends produce same result", {
  job <- gdal_raster_info("test.tif")
  
  result_px <- gdal_job_run(job, backend = "processx", stream_out_format = "json")
  result_gr <- gdal_job_run(job, backend = "gdalraster", stream_out_format = "json")
  
  expect_equal(result_px$bands, result_gr$bands)
})
```

### Mock Execution

For unit tests without GDAL:

```r
test_that("job structure is correct", {
  job <- gdal_raster_convert(input = "in.tif", output = "out.tif")
  args <- .serialize_gdal_job(job)  # Test serialization only
  expect_equal(args[1:2], c("raster", "convert"))
})
```

---

## Dependencies

### Required

- `processx` - Subprocess management (always used as fallback)

### Optional

- `gdalraster` ≥ 2.2.0 - C++ bindings
- `reticulate` - Python integration
- `yyjsonr` - Fast JSON parsing (for `stream_out_format = "json"`)

---

## Files to Modify When Changing This Component

| Change Type | Files to Update |
|-------------|-----------------|
| New backend | `core-gdal_run.R` (add dispatcher + implementation) |
| New output format | `gdal_job_run.gdal_job()`, all backend impls |
| Env var handling | `.merge_env_vars()` |
| Serialization logic | `.serialize_gdal_job()` |
| Pipeline execution | `gdal_job_run.gdal_pipeline()`, native pipeline impls |
