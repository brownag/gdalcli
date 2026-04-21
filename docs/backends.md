# Execution and Serialization

## Execution Backends

**Component**: [R/core-gdal_run.R](../R/core-gdal_run.R)  
**Last Updated**: 2026-01-31

Three backends: `processx` (subprocess), `gdalraster` (C++ bindings), `reticulate` (Python).

### Backend Comparison

| Feature | processx | gdalraster | reticulate |
|---------|----------|------------|------------|
| **Requires** | GDAL CLI | gdalraster ≥2.2.0 | Python + GDAL |
| **Default** | ✅ Fallback | ✅ Preferred | ❌ Explicit |
| **Streaming** | ✅ Full | ⚠️ Limited | ⚠️ Limited |
| **Native Pipeline** | ✅ Yes | ✅ Yes | ❌ No |
| **Overhead** | Higher (subprocess) | Lower (in-process) | Medium |

### Backend Selection

**Automatic**: `gdal_job_run(job)` selects best available  
**Explicit**: `gdal_job_run(job, backend = "processx")`  
**Global**: `options(gdalcli.backend = "gdalraster")`

### processx Backend

Flow:
1. Serialize job via `.serialize_gdal_job()`
2. Merge environment variables
3. Configure stdin/stdout for streaming
4. Execute via `processx::run()`
5. Handle output based on `stream_out_format`

**Streaming Support**:
- `NULL` - Invisibly returns `TRUE`
- `"text"` - Return stdout as character
- `"raw"` - Return stdout as raw vector
- `"json"` - Parse stdout as JSON
- `"stdout"` - Print to console in real-time

### gdalraster Backend

- In-process execution via C++ bindings
- Faster for batch operations
- Limited streaming support
- Requires gdalraster ≥ 2.2.0

### reticulate Backend

- Integration with Python workflows
- Requires `osgeo.gdal` in Python
- Use when Python GDAL available but CLI not

### Pipeline Execution

**Sequential Mode** (default): Each job runs separately, intermediate files on disk/virtual  
**Native Mode**: Single GDAL pipeline command with `!` separators (more efficient)

### Job Serialization

`.serialize_gdal_job()` converts `gdal_job` to CLI argument vector:

```r
job <- gdal_raster_reproject(input = "in.tif", dst_crs = "EPSG:4326")
args <- .serialize_gdal_job(job)
# → c("raster", "reproject", "--dst-crs", "EPSG:4326", "in.tif")
```

**Order**: Command path → Options → Positional inputs → Outputs

### Environment Variables

`.merge_env_vars()` combines from multiple sources with priority:
1. Job's `env_vars`
2. Legacy auth variables (`AWS_*`, `GS_*`, `AZURE_*`)
3. Explicit `env` parameter

**Security**: Credentials passed via subprocess environment, never as CLI arguments.

### Input/Output Streaming

**Input** (`stream_in`): R object for `/vsistdin/`  
**Output** (`stream_out_format`): Text, raw, JSON, or stdout

```r
gdal_raster_info("input.tif") |>
  gdal_job_run(stream_out_format = "json")
```

### Error Handling

All backends surface GDAL errors with clean messages.

### Verbose Mode

```r
gdal_job_run(job, verbose = TRUE)
# ℹ Executing: gdal raster reproject --dst-crs EPSG:4326 input.tif output.tif
```

### Audit Trail

```r
result <- gdal_job_run(job, audit = TRUE)
attr(result, "audit_trail")  # Timestamp, duration, command, status
```

---

## Pipeline Serialization

**Component**: [R/gdalg-transpiler.R](../R/gdalg-transpiler.R), [R/core-gdalg-io.R](../R/core-gdalg-io.R), [R/core-gdalcli-io.R](../R/core-gdalcli-io.R)  
**Last Updated**: 2026-01-31

Two formats: Hybrid `.gdalcli.json` (R state + GDAL compatible), Pure `.gdalg.json` (RFC 104).

### Format Comparison

| Aspect | Hybrid | Pure GDALG |
|--------|--------|------------|
| **Extension** | `.gdalcli.json` | `.gdalg.json` |
| **R Round-Trip** | ✅ Lossless | ❌ Best-effort |
| **GDAL Compatible** | ✅ | ✅ |
| **Metadata** | ✅ | ❌ |
| **arg_mapping** | ✅ | ❌ |
| **config_options** | ✅ | ❌ |
| **env_vars** | ❌ (security) | ❌ |

### Hybrid Format (`.gdalcli.json`)

```json
{
  "gdalg": {
    "type": "gdal_streamed_alg",
    "command_line": "gdal raster pipeline ! read in.tif ! reproject ... ! write out.tif",
    "relative_paths_relative_to_this_file": true
  },
  "metadata": {
    "format_version": "1.0",
    "gdalcli_version": "0.4.0",
    "gdal_version_required": "3.11",
    "pipeline_name": "My Pipeline",
    "created_at": "2026-01-31T12:00:00Z",
    "created_by_r_version": "R version 4.5.2"
  },
  "r_job_specs": [{"command_path": [...], "arguments": {...}, ...}]
}
```

### Pure GDALG Format (`.gdalg.json`)

```json
{
  "type": "gdal_streamed_alg",
  "command_line": "gdal raster pipeline ! read in.tif ! reproject ... ! write out.tif",
  "relative_paths_relative_to_this_file": true
}
```

### S3 Classes

`gdalg` - Pure RFC 104 spec  
`gdalcli_spec` - Hybrid format with metadata + R job specs

### Transpiler

**Forward** (R → GDALG):
- `pipeline_to_rfc104_command()` → command string
- `pipeline_to_gdalg_spec()` → pure GDALG JSON
- `pipeline_to_gdalcli_spec()` → hybrid JSON

**Reverse** (GDALG → R):
- `parse_rfc104_command_string()` → step tokens
- `rfc104_step_to_job()` → gdal_job objects
- `gdalg_to_pipeline()` → gdal_pipeline

### Public API

```r
gdal_save_pipeline(pipeline, path, 
                   format = c("hybrid", "gdalg"),
                   name = NULL, description = NULL)

gdal_load_pipeline(path)  # Auto-detects format
```

### Round-Trip Fidelity

**Lossless** (Hybrid): All job fields preserved  
**Best-effort** (Pure GDALG): Types may differ, metadata lost

### Known Limitations

- Argument types coerced to strings when parsing GDALG
- Complex quoted arguments not fully handled
- Credentials never serialized (security)
- Config options lost in pure GDALG format

---

## Configuration

| Option | Default | Purpose |
|--------|---------|---------|
| `gdalcli.backend` | `"auto"` | Default backend |
| `gdalcli.stream_out_format` | `NULL` | Default output format |
| `gdalcli.verbose` | `FALSE` | Print commands |

---

## Testing

### Availability Checks

```r
skip_if_not(.check_gdalraster_version("2.2.0", quietly = TRUE))
```

### Backend Parity

Verify all backends produce same results for same job.

### Unit Tests

Test serialization without GDAL:
```r
job <- gdal_raster_convert(input = "in.tif", output = "out.tif")
args <- .serialize_gdal_job(job)
expect_equal(args[1:2], c("raster", "convert"))
```

---

## Dependencies

### Required
- `processx` - Subprocess management

### Optional
- `gdalraster` ≥ 2.2.0 - C++ bindings
- `reticulate` - Python integration
- `yyjsonr` - Fast JSON (for JSON output format)

### Files to Modify

| Change Type | Files |
|-------------|-------|
| New backend | `core-gdal_run.R` |
| New output format | `gdal_job_run.gdal_job()`, all backend impls |
| Serialization logic | `.serialize_gdal_job()`, transpiler |
| New file format | `gdalg-transpiler.R`, `core-gdalcli-io.R` |
