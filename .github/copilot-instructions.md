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
- **Purpose**: Build reusable GDAL base images and full runtime Docker images with gdalcli
- **Trigger**: Weekly schedule (Saturdays), main branch pushes, manual dispatch
- **Base Image Output**: `ghcr.io/brownag/gdalcli:deps-gdal-X.Y.Z-amd64`
- **Runtime Image Output**: `ghcr.io/brownag/gdalcli:gdal-X.Y.Z-latest`
- **Manual parameters**: `gdal_version`, `image_stage` (both/deps/full), `push_images`
- **When to run**: Automated weekly builds or when GDAL versions/dependencies need updates

**build-releases.yml**
- **Purpose**: Dynamic package builds and GitHub releases for specific GDAL versions
- **Trigger**: Manual dispatch with parameters
- **Output**: Release branches, GitHub releases, package binaries
- **When to run**: When creating new package releases for specific GDAL versions

### Workflow Selection Guide

| Scenario | Recommended Workflow | Notes |
|----------|---------------------|-------|
| Code changes | R-CMD-check-ubuntu.yml + R-CMD-check-docker.yml | Both run automatically on PRs |
| GDAL version updates | build-docker-images.yml | Builds both base and runtime images |
| Package releases | build-releases.yml | Manual workflow with version parameters |
| Docker issues | R-CMD-check-docker.yml | Isolated testing environment |
| Performance testing | R-CMD-check-docker.yml | Consistent environment |

### Manual Workflow Triggers

Some workflows require manual triggering via GitHub Actions:

- **build-docker-images.yml**: Set `push_images=true` and choose `image_stage` (both/deps/full) to control what's built and published
- **build-releases.yml**: Configure `gdal_version`, `package_version`, `create_release`, etc.

### Docker Image Architecture

The project uses a multi-stage Docker architecture for consistent GDAL environments:

**Base Images** (`ghcr.io/brownag/gdalcli:deps-gdal-X.Y.Z-amd64`)
- Built by: `build-docker-images.yml` with `image_stage=deps` or `image_stage=both`
- Contains: GDAL X.Y.Z, R, and all package dependencies (no gdalcli package)
- Purpose: Reusable foundation for CI and development
- When updated: When GDAL versions change or dependencies update

**Runtime Images** (`ghcr.io/brownag/gdalcli:gdal-X.Y.Z-latest`)  
- Built by: `build-docker-images.yml` with `image_stage=full` or `image_stage=both`
- Contains: Complete gdalcli package installed and tested
- Purpose: Production-ready images for users and deployment
- When updated: Weekly or when package changes significantly

**Relationship:**
- Base images provide the GDAL + R foundation
- Runtime images extend base images with the compiled gdalcli package
- CI workflows use base images for testing (faster, no package pre-install needed)
- Users can pull runtime images for ready-to-use gdalcli environments

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

### Authentication

```r
# Read from environment variables only
auth <- gdal_auth_s3()  # AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY
auth <- gdal_auth_azure()  # AZURE_STORAGE_ACCOUNT, AZURE_STORAGE_SAS_TOKEN
auth <- gdal_auth_gcs()  # GOOGLE_APPLICATION_CREDENTIALS

# Add to job
job |> gdal_with_env(auth) |> gdal_run()
```

## Testing

### Test Structure

- **Unit Tests**: `tests/testthat/test_*.R`
- **Pipeline Tests**: `tests/testthat/test_pipeline.R` - Core functionality
- **Mocking**: Use `mockery` for external dependencies
- **File System**: Avoid real file operations in tests

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