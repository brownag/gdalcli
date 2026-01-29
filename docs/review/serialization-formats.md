# Serialization Formats Review

**Component**: Pipeline serialization and format conversion  
**Location**: [R/gdalg-transpiler.R](../../R/gdalg-transpiler.R), [R/core-gdalg-io.R](../../R/core-gdalg-io.R), [R/core-gdalcli-io.R](../../R/core-gdalcli-io.R), [R/core-gdalg-spec.R](../../R/core-gdalg-spec.R), [R/core-gdalcli-spec.R](../../R/core-gdalcli-spec.R)  
**Last Updated**: 2026-01-31

---

## Executive Summary

gdalcli supports two serialization formats:

1. **Hybrid Format** (`.gdalcli.json`): Full R state preservation + GDAL compatibility
2. **Pure GDALG** (`.gdalg.json`): RFC 104 compliant, GDAL tool compatible

The transpiler module converts between R objects and RFC 104 command strings, enabling both lossless R round-trips and GDAL interoperability.

---

## Format Comparison

| Aspect | Hybrid Format | Pure GDALG |
|--------|--------------|------------|
| **Extension** | `.gdalcli.json` | `.gdalg.json` |
| **R Round-Trip** | ✅ Lossless | ❌ Best-effort |
| **GDAL Compatible** | ✅ (extract gdalg) | ✅ Native |
| **Preserves Metadata** | ✅ Name, description, tags | ❌ None |
| **Preserves arg_mapping** | ✅ Full | ❌ Lost |
| **Preserves config_options** | ✅ Full | ❌ Lost |
| **Preserves env_vars** | ✅ Full | ❌ Never serialized |
| **File Size** | Medium | Small |

---

## Format Structures

### Hybrid Format (`.gdalcli.json`)

```json
{
  "gdalg": {
    "type": "gdal_streamed_alg",
    "command_line": "gdal raster pipeline ! read in.tif ! reproject --dst-crs EPSG:4326 ! write out.tif",
    "relative_paths_relative_to_this_file": true
  },
  "metadata": {
    "format_version": "1.0",
    "gdalcli_version": "0.4.0",
    "gdal_version_required": "3.11",
    "pipeline_name": "My Pipeline",
    "pipeline_description": "Description",
    "created_at": "2026-01-31T12:00:00Z",
    "created_by_r_version": "R version 4.5.2",
    "custom_tags": {}
  },
  "r_job_specs": [
    {
      "command_path": ["gdal", "raster", "reproject"],
      "arguments": {"input": "in.tif", "dst_crs": "EPSG:4326"},
      "arg_mapping": {"dst_crs": {"min_count": 1, "max_count": 1}},
      "config_options": {},
      "env_vars": {},
      "stream_in": null,
      "stream_out_format": null
    },
    ...
  ]
}
```

### Pure GDALG Format (`.gdalg.json`)

```json
{
  "type": "gdal_streamed_alg",
  "command_line": "gdal raster pipeline ! read in.tif ! reproject --dst-crs EPSG:4326 ! write out.tif",
  "relative_paths_relative_to_this_file": true
}
```

---

## S3 Classes

### `gdalg` Class

Represents a pure RFC 104 GDALG specification:

```r
structure(
  list(
    type = "gdal_streamed_alg",
    command_line = "gdal raster pipeline ! ...",
    relative_paths_relative_to_this_file = TRUE
  ),
  class = c("gdalg", "list")
)
```

**Key Functions**:
- `as_gdalg()` - Convert to gdalg object
- `validate_gdalg()` - Validate structure
- `gdalg_to_list()` - Convert to list for JSON

### `gdalcli_spec` Class

Represents the hybrid format specification:

```r
structure(
  list(
    gdalg = <gdalg object>,
    metadata = list(...),
    r_job_specs = list(...)
  ),
  class = c("gdalcli_spec", "list")
)
```

**Key Functions**:
- `as_gdalcli_spec()` - Convert pipeline to spec
- `validate_gdalcli_spec()` - Validate structure
- `gdalcli_spec_to_list()` - Convert to list for JSON
- `extract_gdalg()` - Extract pure GDALG component

---

## Transpiler Module

### Forward Direction (R → GDALG)

Located in [gdalg-transpiler.R](../../R/gdalg-transpiler.R):

| Function | Purpose |
|----------|---------|
| `.quote_argument()` | Shell-safe quoting with `'...'` |
| `.format_rfc104_argument()` | Convert R value to CLI format |
| `.job_to_rfc104_step()` | Single job → pipeline step string |
| `.pipeline_to_rfc104_command()` | Full pipeline → command string |
| `.pipeline_to_gdalg_spec()` | Generate pure GDALG JSON spec |
| `.pipeline_to_gdalcli_spec()` | Generate hybrid spec with metadata |

**Flow**:
```
gdal_pipeline → .pipeline_to_rfc104_command() → command_line string
             → .pipeline_to_gdalg_spec() → {type, command_line, ...}
             → .pipeline_to_gdalcli_spec() → {gdalg, metadata, r_job_specs}
```

### Reverse Direction (GDALG → R)

| Function | Purpose |
|----------|---------|
| `.parse_rfc104_command_string()` | Tokenize command string by `!` |
| `.rfc104_step_to_job()` | Reconstruct `gdal_job` from tokens |
| `.gdalg_to_pipeline()` | Reconstruct `gdal_pipeline` from command_line |
| `.gdalcli_spec_to_pipeline()` | Load hybrid spec with lossless round-trip |

**Flow**:
```
command_line → .parse_rfc104_command_string() → step tokens
            → .rfc104_step_to_job() → gdal_job objects
            → .gdalg_to_pipeline() → gdal_pipeline
```

---

## Key Mappings (Hardcoded)

### Positional Argument Names

```r
positional_arg_names <- c("input", "output", "src_dataset", "dest_dataset", "dataset")
```

### CLI Flag Mappings

```r
flag_mapping <- c(
  "resolution" = "--resolution",
  "size" = "--ts",
  "extent" = "--te"
)
```

### Step Name Mappings (RFC 104)

Used when determining if a step is `read` or `write`:

```r
# In .rfc104_step_to_job():
if (step_name == "read") {
  arguments[["input"]] <- token
} else if (step_name == "write") {
  arguments[["output"]] <- token
}
```

---

## I/O Operations

### Writing Files

| Function | Format | Location |
|----------|--------|----------|
| `gdalg_write()` | Pure GDALG | `core-gdalg-io.R` |
| `.gdal_save_pipeline_hybrid()` | Hybrid | `core-gdalcli-io.R` |

**GDALG Writing Strategy**:
1. If GDAL 3.12+: Try native `! write -f GDALG` (`.gdalg_write_via_gdal()`)
2. Fallback: Pure R JSON serialization (`.gdalg_write_via_r()`)

### Reading Files

| Function | Format | Location |
|----------|--------|----------|
| `gdalg_read()` | Pure GDALG | `core-gdalg-io.R` |
| `.gdal_load_pipeline_auto()` | Auto-detect | `core-gdalcli-io.R` |

**Format Detection** (`.gdalcli_detect_format()`):
```r
if (!is.null(spec$gdalg) && !is.null(spec$r_job_specs)) return("hybrid")
if (!is.null(spec$type) && spec$type == "gdal_streamed_alg") return("pure_gdalg")
if (!is.null(spec$steps)) return("legacy")
return("unknown")
```

---

## Public API

### Saving Pipelines

```r
# High-level API (in core-gdalg.R)
gdal_save_pipeline(pipeline, path, 
                   format = c("hybrid", "gdalg"),
                   name = NULL,
                   description = NULL,
                   custom_tags = list())
```

### Loading Pipelines

```r
# High-level API (in core-gdalg.R)
gdal_load_pipeline(path)  # Auto-detects format
```

---

## Round-Trip Fidelity

### Lossless (Hybrid Format)

When loading a hybrid format file:
1. `r_job_specs` array is preferred
2. Each job reconstructed with full state:
   - `command_path` ✓
   - `arguments` ✓
   - `arg_mapping` ✓
   - `config_options` ✓
   - `env_vars` ✓ (but never written to GDALG component)
   - `stream_in/stream_out_format` ✓

### Best-Effort (Pure GDALG)

When loading a pure GDALG file:
1. `command_line` is parsed via transpiler
2. Jobs reconstructed heuristically:
   - `command_path` ✓ (from step name)
   - `arguments` ⚠️ (flags parsed, but types may differ)
   - `arg_mapping` ❌ (empty)
   - `config_options` ❌ (empty)
   - `env_vars` ❌ (empty)

---

## Known Limitations

### 1. Argument Type Coercion

When parsing GDALG command_line:
- All values parsed as strings
- No numeric/logical type inference
- Composite arguments (comma-separated) split correctly

### 2. Quoted Argument Parsing

Simple shell-style tokenization:
```r
tokens <- gregexpr("'[^']*'|[^\\s]+", step_str)[[1]]
```

**Limitation**: Does not handle:
- Nested quotes
- Escaped quotes within strings
- Complex SQL or URI arguments

### 3. Environment Variables

`env_vars` are **never** serialized to GDALG files (security):
- Credentials should never be committed
- Must be re-provided at load time

### 4. Config Options in Pure GDALG

`config_options` are not part of RFC 104 command_line:
- Lost when saving as pure GDALG
- Preserved only in hybrid format's `r_job_specs`

---

## Version Handling

### Format Version

```r
metadata$format_version = "1.0"
```

Currently no migration logic needed. Future versions should:
1. Check format_version on load
2. Apply migration if older format
3. Warn if newer format (possible incompatibility)

### GDAL Version Requirements

```r
metadata$gdal_version_required = "3.11"
```

Indicates minimum GDAL version needed to execute the pipeline.

---

## Testing Considerations

### Serialization Round-Trip Tests

```r
test_that("hybrid format preserves all job fields", {
  original <- gdal_raster_reproject(...) |> gdal_raster_convert(...)
  
  path <- tempfile(fileext = ".gdalcli.json")
  gdal_save_pipeline(original, path, format = "hybrid")
  loaded <- gdal_load_pipeline(path)
  
  expect_equal(loaded$jobs[[1]]$arg_mapping, original$pipeline$jobs[[1]]$arg_mapping)
})
```

### Format Detection Tests

```r
test_that("format detection works for all formats", {
  expect_equal(.gdalcli_detect_format(hybrid_spec), "hybrid")
  expect_equal(.gdalcli_detect_format(pure_gdalg_spec), "pure_gdalg")
  expect_equal(.gdalcli_detect_format(legacy_spec), "legacy")
})
```

### Command String Tests

```r
test_that("RFC 104 command string is valid", {
  cmd <- .pipeline_to_rfc104_command(pipeline)
  expect_true(grepl("^gdal (raster|vector) pipeline ! ", cmd))
})
```

---

## Dependencies

### Internal

- `core-gdal_job.R` - Job class definition
- `core-gdal_pipeline.R` - Pipeline class definition

### External

- `jsonlite` - JSON parsing/serialization
- `processx` - For GDAL-native GDALG writing (optional)

---

## Files to Modify When Changing This Component

| Change Type | Files to Update |
|-------------|-----------------|
| New file format | `gdalg-transpiler.R`, `core-gdalcli-io.R` |
| New metadata field | `core-gdalcli-spec.R`, `gdalg-transpiler.R` |
| New argument type | `gdalg-transpiler.R` (`.format_rfc104_argument()`) |
| Format version bump | `gdalg-transpiler.R` (`.pipeline_to_gdalcli_spec()`) |
| New step mapping | `gdalg-transpiler.R` (`.rfc104_step_to_job()`) |
