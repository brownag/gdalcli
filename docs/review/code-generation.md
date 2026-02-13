# Code Generation System Review

**Component**: Auto-generated GDAL wrapper functions  
**Location**: [build/generate_gdal_api.R](../../build/generate_gdal_api.R), [build/validate_generated_api.R](../../build/validate_generated_api.R), [build/setup_gdal_repo.R](../../build/setup_gdal_repo.R)  
**Last Updated**: 2026-01-31

---

## Executive Summary

gdalcli auto-generates approximately 90 R wrapper functions from GDAL's JSON API specification. The generation system crawls GDAL's command tree via `gdal --json-usage`, parses the output, enriches documentation from RST source files, and produces complete R function files with roxygen documentation.

---

## Generation Flow

```
┌─────────────────────────────────────────────────────────────────┐
│  1. GDAL API Crawling                                           │
│     gdal --json-usage raster                                    │
│     gdal --json-usage vector                                    │
│     ... (recursive discovery)                                   │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│  2. JSON Parsing                                                │
│     - Handle Infinity values → "__R_INF__" sentinel             │
│     - Extract command paths, arguments, descriptions            │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│  3. Documentation Enrichment                                    │
│     - Fetch examples from local GDAL repo RST files             │
│     - Parse CLI examples, transpile to R code                   │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│  4. Function Generation                                         │
│     - Generate R function signature                             │
│     - Generate roxygen documentation                            │
│     - Generate function body with pipeline support              │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│  5. Output & Validation                                         │
│     - Write to R/gdal_*.R files                                 │
│     - Save GDAL_VERSION_INFO.json                               │
│     - Run validate_generated_api.R                              │
└─────────────────────────────────────────────────────────────────┘
```

---

## Key Functions

### API Crawling

| Function | Purpose |
|----------|---------|
| `crawl_gdal_api()` | Recursively crawl GDAL API via `gdal --json-usage` |
| `.get_gdal_version()` | Get current GDAL version |
| `.parse_gdal_version()` | Parse version string into components |
| `.write_gdal_version_info()` | Write `inst/GDAL_VERSION_INFO.json` |

### JSON Handling

| Function | Purpose |
|----------|---------|
| `.convert_infinity_strings()` | Replace `"__R_INF__"` with `Inf` |
| (yyjsonr::read_json_str) | Parse JSON with native types |

### Documentation Enrichment

| Function | Purpose |
|----------|---------|
| `fetch_enriched_docs()` | Fetch and cache documentation |
| `fetch_examples_from_rst()` | Extract examples from GDAL RST files |
| `.extract_examples_from_rst()` | Parse RST code-block directives |
| `construct_doc_url()` | Build version-aware documentation URLs |
| `create_doc_cache()` | Cache documentation lookups |

### Function Generation

| Function | Purpose |
|----------|---------|
| `generate_function()` | Generate complete R function with roxygen |
| `generate_r_arguments()` | Map GDAL args to R function signature |
| `generate_roxygen_doc()` | Build roxygen documentation block |
| `generate_function_body()` | Create function body with pipeline logic |
| `generate_family_tag()` | Create `@family` tag for pkgdown grouping |

### Example Transpilation

| Function | Purpose |
|----------|---------|
| `convert_cli_to_r_example()` | Transpile CLI example to R code |
| `parse_cli_command()` | Parse CLI command into components |

---

## Argument Handling

### Required vs Optional

Determined by GDAL JSON `required` field (NOT `min_count`):

```r
# From JSON:
# {"name": "input", "required": true, ...}
# {"name": "dst_crs", "required": false, ...}

# Generated R signature:
gdal_raster_reproject <- function(input, dst_crs = NULL, ...)
```

### Default Values

- **Required args**: No default (positional)
- **Optional args**: `NULL` default
- **Flags**: `FALSE` default for boolean options

### Composite vs Repeatable

Detected from `min_count`/`max_count`:

```r
# Composite (fixed count): --bbox 1,2,3,4
# {"name": "bbox", "min_count": 4, "max_count": 4}
# → bbox = c(xmin, ymin, xmax, ymax)

# Repeatable (variable count): --co COMPRESS=LZW --co TILED=YES
# {"name": "creation-option", "min_count": 0, "max_count": "Infinity"}
# → creation_option = c("COMPRESS=LZW", "TILED=YES")
```

**Agent Note**: The `arg_mapping` in generated jobs stores this metadata for correct serialization.

---

## First-Arg Piping Detection

All generated functions include piping detection logic:

```r
gdal_raster_convert <- function(input = NULL, output = NULL, ...) {
  # Check if input is a piped gdal_job
  if (!is.null(input) && inherits(input, "gdal_job")) {
    # Pipeline extension mode: input is previous job's output
    return(extend_gdal_pipeline(input, 
      command_path = c("gdal", "raster", "convert"),
      arguments = list(output = output, ...)
    ))
  }
  
  # Normal mode: create new job
  new_gdal_job(
    command_path = c("gdal", "raster", "convert"),
    arguments = list(input = input, output = output, ...),
    arg_mapping = arg_mapping
  )
}
```

**Design Decision**: The first positional argument (`input` for most commands) can accept either:
1. A file path (string) → Creates new standalone job
2. A `gdal_job` → Extends pipeline from that job

---

## RST Example Extraction

### Source Files

Examples are extracted from local GDAL RST documentation:

```
build/gdal_repo/doc/source/programs/gdal_raster_info.rst
```

### Parsing Logic (in `.extract_examples_from_rst()`)

1. Find `Examples` section heading
2. Locate `.. code-block:: bash` or `.. code-block:: console` directives
3. Extract code content respecting indentation
4. Remove shell prompts (`$`)
5. Also handle `.. command-output::` directives

### Example Transpilation

CLI examples are converted to R code:

```bash
# RST example:
gdal raster reproject --dst-crs=EPSG:4326 input.tif output.tif

# Generated R code:
job <- gdal_raster_reproject(
    input = "input.tif",
    output = "output.tif",
    dst_crs = "EPSG:4326"
)
```

**Transpilation Logic** (in `convert_cli_to_r_example()`):
- Parse CLI into command parts, positional args, options
- Map CLI flag names to R parameter names (`--dst-crs` → `dst_crs`)
- Quote string values, detect numeric values
- Handle composite args (comma-separated → `c(...)`)
- Handle repeatable args (multiple flags → `c(...)`)

---

## Version-Aware Generation

### Version Metadata

```json
// inst/GDAL_VERSION_INFO.json
{
  "generated_at": "2026-01-26 21:12:18",
  "gdal_version": "3.11.4",
  "gdal_version_parsed": {"full": "3.11.4", "major": 3, "minor": 11, "patch": 4},
  "r_version": "4.5.2"
}
```

### Version in Generated Files

File headers include version info:

```r
# gdal_raster_info.R (Generated for GDAL 3.11.4)
# Generation date: 2026-01-26
```

### Version-Aware URLs

Documentation URLs use version-specific paths:

```r
# @seealso https://gdal.org/en/3.11.4/programs/gdal_raster_info.html
```

---

## Validation

### validate_generated_api.R Checks

| Check | Description | Severity |
|-------|-------------|----------|
| Version metadata | Header contains GDAL version | Required |
| `\dontrun{}` wrapping | Examples wrapped in `\dontrun{}` | Required |
| No Phase comments | No debug "Phase X:" comments | Required |
| Version-aware URLs | URLs use `/en/{version}/` | Informational |

---

## Output Files

### Generated R Files

```
R/gdal_raster_info.R
R/gdal_raster_convert.R
R/gdal_raster_reproject.R
R/gdal_vector_convert.R
...
```

**Naming Convention**:
- `gdal_raster_*` - Raster operations
- `gdal_vector_*` - Vector operations
- `gdal_mdim_*` - Multidimensional data
- `gdal_vsi_*` - Virtual file system operations
- `gdal_driver_*` - Driver-specific operations

### Metadata File

```
inst/GDAL_VERSION_INFO.json
```

---

## Running Generation

```bash
# Full generation
make api

# Or directly:
Rscript build/generate_gdal_api.R
```

### Prerequisites

1. GDAL 3.11+ installed and on PATH
2. R packages: `processx`, `yyjsonr`, `glue`
3. Local GDAL repo (for RST examples): `build/gdal_repo/`

### Setup GDAL Repo

```bash
# Run setup script (clones/updates GDAL repo)
Rscript build/setup_gdal_repo.R
```

---

## Common Issues

### 1. Missing Examples

**Symptom**: Generated function has no examples in `\dontrun{}`.

**Causes**:
- RST file doesn't exist for command
- RST file has no `Examples` section
- Code block parsing failed

**Fix**: Check RST file manually, or add examples to function post-generation.

### 2. Infinity Handling

**Issue**: GDAL JSON uses `Infinity` for unbounded max_count.

**Solution**: Pre-process JSON with sed/awk to replace `Infinity` with `"__R_INF__"`:

```bash
gdal --json-usage raster | sed 's/Infinity/"__R_INF__"/g'
```

Then convert back in R: `.convert_infinity_strings()`.

### 3. Argument Type Mismatches

**Issue**: Generated function expects different type than GDAL.

**Cause**: GDAL JSON doesn't always specify types precisely.

**Fix**: Review `arg_mapping` and add manual type handling in function body.

---

## Extension Points

### Adding New Command Categories

1. Update `crawl_gdal_api()` to include new category
2. Update `generate_family_tag()` for pkgdown grouping
3. Update naming patterns if needed

### Custom Argument Handling

For special arguments that need custom handling:

1. Add to post-generation fixes in generation script
2. Or create manual override file that patches generated code

### Example Enhancement

To improve example quality:

1. Add examples to GDAL RST files (upstream contribution)
2. Or add post-generation example injection
3. Or maintain manual examples in separate files

---

## Dependencies

### R Packages

- `processx` - Run GDAL CLI commands
- `yyjsonr` - Fast JSON parsing (YYJSON bindings)
- `glue` - String interpolation
- `digest` - Cache key generation

### External

- GDAL 3.11+ CLI (`gdal` command)
- Git (for GDAL repo cloning)

---

## Files to Modify When Changing This Component

| Change Type | Files to Update |
|-------------|-----------------|
| New argument type | `generate_r_arguments()` in generate_gdal_api.R |
| New example source | `fetch_examples_from_rst()` or add new fetcher |
| New validation check | `validate_generated_api.R` |
| Version handling | `.parse_gdal_version()`, `.write_gdal_version_info()` |
| Pipeline support | `generate_function_body()` |
| Documentation URL | `construct_doc_url()` |
