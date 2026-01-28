# gdalcli 0.4.1 (2026-01-28)

- Added `gdalcli_options()` function for managing package options (backend, verbose, stream_out_format, audit_logging)
  - Backend option supports "auto", "gdalraster", "processx", and "reticulate" with validation

# gdalcli 0.4.0 (2026-01-27)

- Removed gdalcli core `gdal_pipeline` function, renamed to `gdal_compose` which is now deprecated.
  - Users are encouraged to use the R pipe operator (`|>`) to compose jobs, which is now the "recommended" (more idiomatic R) approach
  - Alternately, use the generated `gdal_pipeline()`, `gdal_raster_pipeline()`, or `gdal_vector_pipeline()` instead.
- Added a new `stream_out_format = "stdout"` option to print output to stdout and robust handling existing `"text"`, `"raw"`, and `"json"` formats.
- Improved backend detection and selection logic, including support for gdalraster's native pipeline execution when available
- Refined error handling and argument extraction in `gdal_job_get_explicit_args()`
- Enhanced test setup for reticulate integration

# gdalcli 0.3.0 (2025-12-14)

- Auto-generated R wrapper functions for GDAL commands
- Lazy evaluation with composable `gdal_job` objects
- Multiple execution backends (processx, gdalraster, reticulate)
- Composable pipeline operations using native R pipe operator
- Environment-based cloud storage authentication (S3, Azure, GCS, OSS, Swift)
- VSI streaming support for memory-efficient file I/O
- Pipeline persistence in gdalcli JSON format or native GDAL pipeline format
- Helper functions for VSI URL composition (30+ cloud/archive/utility handlers)
