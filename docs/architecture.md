# Architecture

## Code Generation

**Component**: [build/generate_gdal_api.R](../build/generate_gdal_api.R), [build/validate_generated_api.R](../build/validate_generated_api.R)  
**Last Updated**: 2026-01-31

Auto-generates ~90 R wrapper functions from GDAL's JSON API via `gdal --json-usage`.

### Flow

1. Crawl API: `gdal --json-usage` → JSON output
2. Parse: Extract commands, arguments, handle Infinity → `"__R_INF__"`
3. Enrich: Fetch examples from GDAL RST files, transpile to R
4. Generate: Create R functions with roxygen, pipeline support
5. Output: Write `R/gdal_*.R`, save `GDAL_VERSION_INFO.json`, validate

### Arguments

- **Required**: GDAL JSON `required` field (not `min_count`)
- **Defaults**: Required=no default, Optional=`NULL`, Flags=`FALSE`
- **Composite**: Fixed count via `min_count`/`max_count` (e.g. `bbox` = 4 values)
- **Repeatable**: Variable count (e.g. `--co COMPRESS=LZW --co TILED=YES`)

---

## Job and Pipeline

**Component**: [R/core-gdal_job.R](../R/core-gdal_job.R), [R/core-gdal_pipeline.R](../R/core-gdal_pipeline.R)  
**Last Updated**: 2026-01-31

Lazy evaluation: `gdal_job` specs built by functions, executed only via `gdal_job_run()`.

### Data Structures

`gdal_job`:
```r
list(command_path, arguments, config_options, env_vars, 
     stream_in, stream_out_format, pipeline, arg_mapping)
```

`gdal_pipeline`:
```r
list(jobs, name, description)
```

### Key Patterns

- **Lazy construction**: No execution in `new_gdal_job()` or generated functions
- **First-arg piping**: Detect if first arg is `gdal_job`, extend pipeline or create new job
- **Virtual paths**: Auto-assign `/vsimem/*` for intermediate outputs
- **Immutable modifiers**: `gdal_with_*` functions return new job objects

### Key Functions

**Constructors:**
- `new_gdal_job()` - Low-level constructor
- `new_gdal_pipeline()` - Pipeline constructor
- `extend_gdal_pipeline()` - Add job to pipeline

**Accessors:**
- `$.gdal_job` - Property access + fluent methods
- `[.gdal_job` - Extract job(s) from pipeline
- `length.gdal_job()` - Number of pipeline steps
- `c.gdal_job()` - Combine jobs into pipeline

**Pipeline Operations:**
- `add_job()` - Add job to pipeline
- `get_jobs()` - Get job list
- `set_name()` - Set pipeline name
- `set_description()` - Set pipeline description
- `render_gdal_pipeline()` - Generate CLI string
- `render_shell_script()` - Generate shell script
