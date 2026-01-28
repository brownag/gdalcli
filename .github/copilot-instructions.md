# Copilot Instructions for gdalcli

UNDER NO CIRCUMSTANCES SHOULD YOU EVER PUSH TO A REMOTE GIT REPOSITORY

## Package Overview

`gdalcli` is a generative R frontend for GDAL's CLI (>=3.11). It provides auto-generated R wrapper functions for GDAL commands with lazy evaluation and composable pipelines.

## Architecture

### Two-Layer Design

1. **Frontend Layer** (User-facing R API)
   - Auto-generated functions from GDAL JSON API (`build/generate_gdal_api.R`)
   - Composable modifiers: `gdal_with_co()`, `gdal_with_env()`, etc.
   - S3 methods for extensibility
   - Lazy `gdal_job` specification objects

2. **Engine Layer** (Command Execution)
   - `gdal_run()` executes `gdal_job` objects
   - Uses `processx` for subprocess management
   - Environment variable injection for credentials
   - VSI streaming support (`/vsistdin/`, `/vsistdout/`)

### Key Design Patterns

- **Lazy Evaluation**: Commands built as `gdal_job` objects, executed only via `gdal_run()`
- **S3 Composition**: All modifiers are S3 generics that return modified `gdal_job` objects
- **Environment-Based Auth**: Credentials read from environment variables, never passed as arguments
- **Process Isolation**: Each command runs in isolated subprocess with injected environment
- **Pipe Composition**: Use native R pipe (`|>`) to compose jobs into pipelines naturally

### GDAL Version Conflicts and API Evolution

**GDAL 3.12+ Native Commands:**
- GDAL 3.12.0+ introduced native `gdal pipeline` command
- This conflicts with gdalcli's original `gdal_pipeline()` convenience wrapper function
- **Resolution**: Renamed function to `gdal_compose()`, marked deprecated for 0.5.x removal
- **Rationale**: 
  - Piping with `|>` is more idiomatic R for composition
  - Explicit type specification (`gdal_raster_pipeline()` vs `gdal_vector_pipeline()`) is clearer than type auto-detection
  - Function added minimal value over direct function calls
  - Users can still pass lists directly: `gdal_raster_pipeline(jobs = list(j1, j2, j3))`

**Deprecated Functions:**
- `gdal_compose()` - Deprecated as of 0.4.x, removal planned for 0.5.x
  - Issues warning via `.Deprecated()` on use
  - Docs recommend pipe approach instead
  - Will remove unless real-world use cases emerge

## CI/CD Workflows

The project uses GitHub Actions for automated testing, building, and deployment. Workflows are organized by purpose:

### Testing Workflows

**R-CMD-check-ubuntu.yml**
- **Purpose**: Comprehensive R CMD check on native Ubuntu/GitHub runners
- **Trigger**: Push to main, pull requests
- **Environment**: Ubuntu 22.04 with GDAL 3.11+ from ubuntugis PPA
- **Coverage**: Full R CMD check including vignettes, tests, and gdalraster compatibility
- **When to use**: Standard CI for all changes

**R-CMD-check-docker.yml** 
- **Purpose**: R CMD check in isolated Docker containers
- **Trigger**: Push to main, pull requests
- **Environment**: Custom Docker images with controlled GDAL versions
- **Coverage**: Full R CMD check with pre-installed dependencies
- **When to use**: Verify Docker compatibility and controlled environments

### Build Workflows

**build-docker-images.yml**
- **Purpose**: Build GDAL Docker images (base and runtime) for specific GDAL versions
- **Flexibility**: Accepts any GDAL version via `gdal_version` input in workflow_dispatch
  - When `gdal_version` provided: builds only that specific version
  - When triggered by schedule/push: builds default matrix (3.11.4, 3.12.0)
- **Trigger**: Weekly schedule (Saturdays), main branch pushes, manual dispatch
- **When to run**: New GDAL patch versions, when dependencies need updates, or to build arbitrary versions

**build-releases.yml**
- **Purpose**: Generate gdalcli for specific GDAL version and create releases with tagged commits
- **Branching Strategy**:
  - New minor version: Creates `release/gdal-X.Y` from main
  - Patch version: Continues on existing `release/gdal-X.Y` without reset to main
- **Releases**: Creates tags like `v0.3.0-3.12.0`, `v0.3.0-3.12.1` for each patch
- **Trigger**: Manual dispatch with `gdal_version`
- **When to run**: After building Docker image for new GDAL patch or minor version

### Workflow Selection Guide

| Scenario | Recommended Workflow | Notes |
|----------|---------------------|-------|
| Code changes | R-CMD-check-ubuntu.yml + R-CMD-check-docker.yml | Both run automatically on PRs |
| New GDAL version | build-docker-images.yml → build-releases.yml | Build image first, then release |
| GDAL patch update | build-docker-images.yml → build-releases.yml | Same workflow for new patch |
| Docker issues | R-CMD-check-docker.yml | Isolated testing environment |
| Performance testing | R-CMD-check-docker.yml | Consistent environment |

### Manual Workflow Triggers

Some workflows require manual triggering via GitHub Actions:

- **build-docker-images.yml**: 
  - Optional `gdal_version`: Leave empty for default matrix, or specify any version (e.g., 3.12.1)
  - Set `push_images=true` to publish to GHCR
  - Choose `image_stage` (both/deps/full) for what to build

- **build-releases.yml**: 
  - `gdal_version`: Specific version to release (must have corresponding Docker image)
  - `create_release`: true/false to create GitHub release and tag
  - `dry_run`: true/false to test without committing

### Patch Version Release Workflow

When GDAL patch version is released (e.g., 3.12.0 -> 3.12.1):

1. Build Docker images via `build-docker-images.yml` with `gdal_version=3.12.1`
2. Run `build-releases.yml` with `gdal_version=3.12.1`
3. Workflow automatically:
   - Detects existing `release/gdal-3.12` branch
   - Checks out existing branch (preserves 3.12.0 work)
   - Generates API for 3.12.1
   - Creates new commit on `release/gdal-3.12` with generated code
   - Tags as `v0.3.0-3.12.1`

Users can then:
- Install latest patch: `remotes::install_github("brownag/gdalcli", ref = "release/gdal-3.12")`
- Install specific patch: `remotes::install_github("brownag/gdalcli", ref = "v0.3.0-3.12.0")`

### Docker Image Architecture

The project uses a multi-stage Docker architecture for consistent GDAL environments:

**Base Images** (`ghcr.io/brownag/gdalcli:deps-gdal-X.Y.Z-amd64`)
- Built by: `build-docker-images.yml` with `image_stage=deps` or `image_stage=both`
- Contains: GDAL X.Y.Z, R, and all package dependencies (no gdalcli package)
- Purpose: Reusable foundation for CI and development
- Built for: All patch versions (one per patch, e.g., 3.11.4, 3.12.0, 3.12.1)

**Runtime Images** (`ghcr.io/brownag/gdalcli:gdal-X.Y.Z-latest`)  
- Built by: `build-docker-images.yml` with `image_stage=full` or `image_stage=both`
- Contains: Complete gdalcli package installed and tested
- Purpose: Production-ready images for users and deployment
- Built for: All patch versions (one per patch, e.g., 3.11.4, 3.12.0, 3.12.1)

**Relationship:**
- Base images provide the GDAL + R foundation
- Runtime images extend base images with the compiled gdalcli package
- CI workflows use base images for testing (faster, no package pre-install needed)
- Users can pull runtime images for ready-to-use gdalcli with specific GDAL patch versions

## Development Workflow

### Building the Package

```bash
# Generate all GDAL wrapper functions from JSON API
make api

# Build package documentation
make docs

# Run tests
make test

# Full build and check
make check
```

### Auto-Generated Functions

Functions are generated from GDAL's JSON API specification in `build/generate_gdal_api.R`:

- **Source**: GDAL's `--help` JSON output
- **Output**: R functions in `R/gdal_*.R` files
- **Categories**: raster, vector, mdim, vsi, driver-specific operations

### Function Naming Convention

- `gdal_raster_*` - Raster operations
- `gdal_vector_*` - Vector operations
- `gdal_mdim_*` - Multidimensional data
- `gdal_vsi_*` - Virtual file system operations
- `gdal_driver_*` - Driver-specific operations

### Parameter Handling

- **Required vs Optional**: Determined by GDAL JSON `required` field (not `min_count`)
- **Defaults**: Optional parameters get `NULL` defaults
- **Type Conversion**: Automatic R type conversion for GDAL parameters

## Code Patterns

### Creating GDAL Jobs

```r
# Build specification (lazy)
job <- gdal_raster_clip(
  input = "input.tif",
  output = "output.tif",
  projwin = c(xmin, ymax, xmax, ymin)
)

# Execute when ready
gdal_run(job)
```

### Composable Modifiers

```r
gdal_raster_convert(...) |>
  gdal_with_co("COMPRESS=DEFLATE") |>     # Creation options
  gdal_with_config("GDAL_CACHEMAX" = "512") |>  # GDAL config
  gdal_with_env(auth) |>                  # Environment variables
  gdal_run()
```

### Pipeline Composition

**Preferred approach: Use the pipe operator**
```r
# Compose multiple operations naturally with piping
result <- gdal_raster_reproject(
  input = "input.tif",
  dst_crs = "EPSG:32632"
) |>
  gdal_raster_scale(src_min = 0, src_max = 100) |>
  gdal_raster_convert(output = "output.tif") |>
  gdal_job_run()
```

**For programmatic job lists: Use explicit pipeline functions**
```r
# When you have a list of jobs and know the type
jobs <- build_job_list(config)
pipeline <- gdal_raster_pipeline(jobs = jobs)
gdal_job_run(pipeline)
```

### Authentication

```r
# Read from environment variables only
auth <- gdal_auth_s3()  # AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY
auth <- gdal_auth_azure()  # AZURE_STORAGE_ACCOUNT, AZURE_STORAGE_SAS_TOKEN
auth <- gdal_auth_gcs()  # GOOGLE_APPLICATION_CREDENTIALS

# Add to job
job |> gdal_with_env(auth) |> gdal_run()
```

### Package Options

The package provides a comprehensive options system via `gdalcli_options()` for controlling default behaviors.

```r
# View current options
gdalcli_options()

# Set options
gdalcli_options(backend = "processx", verbose = TRUE)

# Common options:
gdalcli_options(
  backend = "auto",              # "auto" (default), "gdalraster", or "processx"
  verbose = FALSE,               # Enable verbose output
  stream_out_format = NULL,      # NULL, "text", or "binary" for streaming
  audit_logging = FALSE          # Enable audit logging of executed commands
)
```

**Backend Selection:**
- `"auto"` (default): Automatically select the best available backend
- `"gdalraster"`: Use gdalraster backend (faster, direct API calls when available)
- `"processx"`: Use processx backend (universal, subprocess-based)
- `"reticulate"`: Use reticulate backend (Python GDAL bindings)

**Verbose Output:**
- `FALSE` (default): No verbose output
- `TRUE`: Print detailed execution information during command execution

**Streaming Output Format:**
- `NULL` (default): No streaming format preference
- `"text"`: Use text format for streaming output
- `"binary"`: Use binary format for streaming output

**Audit Logging:**
- `FALSE` (default): No audit logging
- `TRUE`: Log all executed commands (requires setting up audit handler via `gdal_job_run_with_audit()`)

## Testing

### Test Structure

- **Unit Tests**: `tests/testthat/test_*.R`
- **Pipeline Tests**: `tests/testthat/test_pipeline.R` - Core functionality
- **Mocking**: Use `mockery` for external dependencies
- **File System**: Avoid real file operations in tests
- **Expected Failures**: Use "nonexistent.tif" for tests where GDAL should fail (file not found) - makes GDAL error messages consistent and clearly intentional

### Running Tests

```r
# All tests
devtools::test()

# Specific test file
devtools::test(filter = "pipeline")

# With coverage
covr::package_coverage()
```

## Documentation

### Roxygen Documentation

- **Auto-generated**: Function docs enriched from GDAL help text
- **Manual**: Core functions documented with examples
- **Build**: `make docs` generates Rd files

### README Structure

- **Quick Start**: Installation and basic usage
- **Features**: Key capabilities and design decisions
- **Examples**: Real-world usage patterns
- **Architecture**: Design principles and patterns

## Common Tasks

### Adding New GDAL Functions

1. Update `build/generate_gdal_api.R` if needed
2. Run `make api` to regenerate functions
3. Add tests in `tests/testthat/`
4. Update documentation

### Modifying Function Signatures

- Edit parameter logic in `build/generate_gdal_api.R`
- Regenerate with `make api`
- Update tests and documentation

### Adding New Modifiers

1. Create S3 generic: `gdal_with_newoption <- function(x, ...) UseMethod("gdal_with_newoption")`
2. Implement method: `gdal_with_newoption.gdal_job <- function(x, ...) { ... }`
3. Add to `NAMESPACE` with `@export`
4. Document and test

## Security Considerations

- **Never pass credentials as arguments** - Only environment variables
- **Process isolation** - Credentials injected into subprocess environment
- **No global state** - Each command runs in clean environment
- **Environment-only auth** - Prevents accidental credential commits

## Performance Patterns

- **Lazy evaluation** - Build jobs without executing
- **Streaming** - Use `/vsistdin/` and `/vsistdout/` for memory efficiency
- **Batch operations** - Build multiple jobs, execute sequentially
- **Configuration** - Set GDAL options appropriately (`GDAL_CACHEMAX`, etc.)

## Debugging

### Inspecting Jobs

```r
job <- gdal_raster_clip(...)
print(job)  # See command specification
```

### Process Debugging

```r
# Enable verbose output
job |> gdal_with_config("CPL_DEBUG" = "ON") |> gdal_run()

# See actual command
job |> gdal_with_dry_run() |> gdal_run()
```

### Common Issues

- **Parameter errors**: Check if function was regenerated after build script changes
- **Auth failures**: Verify environment variables are set correctly
- **GDAL version**: Ensure GDAL >=3.11 for CLI
- **Memory issues**: Use streaming for large files

## Dependencies

### Core Dependencies

- `rlang` - Tidyverse infrastructure
- `cli` - Command-line interface tools
- `processx` - Process management
- `jsonlite` - JSON parsing
- `gdalraster` - GDAL R bindings
- `digest` - Hashing utilities

### Development Dependencies

- `devtools` - Package development
- `testthat` - Testing framework
- `roxygen2` - Documentation generation
- `covr` - Code coverage

## File Organization

```
gdalcli/
├── R/                    # Auto-generated and manual R functions
├── build/               # Build scripts and API generation
├── tests/testthat/      # Unit tests
├── man/                 # Generated documentation
├── inst/                # Package data
├── docs/                # Additional documentation
├── DESCRIPTION          # Package metadata
├── NAMESPACE            # Exported functions
├── LICENSE.md           # License text
└── README.md           # Package overview
```

## Contributing Guidelines

1. **Fork and branch**: Create feature branches for changes
2. **Test thoroughly**: Add tests for new functionality
3. **Update docs**: Keep README and function docs current
4. **Follow patterns**: Use established design patterns
5. **Security first**: Never compromise credential handling

## References

- [GDAL Documentation](https://gdal.org/)
- [GDAL RFC 104 - CLI](https://gdal.org/development/rfc/rfc104.html)
- [processx Package](https://processx.r-lib.org/)
- [R Packages Book](https://r-pkgs.org/)