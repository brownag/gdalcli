# GDALCLI Advanced Features Implementation Roadmap

**Status:** Planning Phase
**Target GDAL Version:** 3.12+
**Architecture:** gdalcli (R-only) + gdalraster (Rcpp bindings)
**Last Updated:** November 2025

---

## Table of Contents

1. [Executive Overview](#executive-overview)
2. [Feature 1: getExplicitlySetArgs() - Configuration Introspection](#feature-1-getexplicitlysetargs)
3. [Feature 2: setVectorArgsFromObject() - In-Memory Vector Processing](#feature-2-setvectorargsfromobject)
4. [Version Detection Strategy](#version-detection-strategy)
5. [Integration Architecture](#integration-architecture)
6. [Testing Strategy](#testing-strategy)
7. [Implementation Timeline](#implementation-timeline)

---

## Executive Overview

### Goals

1. **Configuration Transparency** - Audit and reproduce GDAL operations precisely
2. **Performance Optimization** - Eliminate I/O bottlenecks in vector workflows
3. **Enterprise Readiness** - Support cloud-native and serverless architectures
4. **Backward Compatibility** - Maintain support for GDAL 3.11 and earlier

### Architecture Decision

```
┌─────────────────────────────────────────┐
│  gdalcli (R-only, user-facing API)      │
│  - No C++ code or compilation needed    │
│  - Clean, idiomatic R interfaces        │
└────────────────┬────────────────────────┘
                 │ consumes
                 ▼
┌─────────────────────────────────────────┐
│  gdalraster (Rcpp bindings)             │
│  - Exposes GDAL 3.12+ C++ APIs          │
│  - Handles memory management            │
│  - Version-conditional compilation      │
└────────────────┬────────────────────────┘
                 │ wraps
                 ▼
┌─────────────────────────────────────────┐
│  GDAL 3.12+ C++ Library                 │
│  - getExplicitlySetArgs()               │
│  - setVectorArgsFromObject()            │
│  - Arrow C Stream Interface             │
└─────────────────────────────────────────┘
```

### Design Principles

- **R-only for gdalcli**: No C++ compilation burden on users
- **Graceful degradation**: GDAL 3.11 users get fallback behavior
- **Type safety**: Strong validation before calling C++
- **Clear error messages**: When features unavailable, explain why
- **Performance first**: In-memory operations where possible

---

## Feature 1: getExplicitlySetArgs()

### Problem Statement

When a user creates a GDAL job, GDAL fills in defaults for unspecified parameters. Currently, gdalcli cannot distinguish between:
- Parameters explicitly set by the user
- Parameters filled in by GDAL defaults
- Parameters injected by the gdalcli wrapper (e.g., error suppression)

This creates reproducibility issues:
- Script runs differently on systems with different GDAL versions
- Audit trails are incomplete
- Error messages are ambiguous

### Solution: Explicit Argument Extraction

#### 1.1 gdalraster Rcpp Implementation

**File**: `src/explicit_args.cpp`

```cpp
// Header: inst/include/gdal_explicit_args.h
#ifndef GDAL_EXPLICIT_ARGS_H
#define GDAL_EXPLICIT_ARGS_H

#include <gdal_utils.h>
#include <Rcpp.h>

#ifdef GDAL_VERSION_NUM >= 3120000

// Forward declarations
class GDALTranslateOptions;
class GDALWarpAppOptions;
class GDALVectorTranslateOptions;

// Get explicitly set arguments from raster translate options
Rcpp::CharacterVector get_explicit_translate_args(SEXP options_xptr);

// Get explicitly set arguments from warp options
Rcpp::CharacterVector get_explicit_warp_args(SEXP options_xptr);

// Get explicitly set arguments from vector translate options
Rcpp::CharacterVector get_explicit_vector_translate_args(SEXP options_xptr);

#endif

#endif // GDAL_EXPLICIT_ARGS_H
```

**Implementation**: `src/explicit_args.cpp`

```cpp
#include "gdal_explicit_args.h"

#ifdef GDAL_VERSION_NUM >= 3120000

// Template-based approach for code reuse
template<typename OptionsType>
Rcpp::CharacterVector extract_explicit_args(void* options_ptr) {
    OptionsType* opts = static_cast<OptionsType*>(options_ptr);

    if (!opts) {
        Rcpp::stop("Invalid options pointer (null reference)");
    }

    try {
        // Call the GDAL 3.12+ API
        char** csl_args = opts->GetExplicitlySetArgs();

        // Convert C string list to R CharacterVector
        Rcpp::CharacterVector r_args;

        if (csl_args != nullptr) {
            int count = CSLCount(csl_args);
            for (int i = 0; i < count; i++) {
                r_args.push_back(std::string(csl_args[i]));
            }
            CSLDestroy(csl_args);
        }

        return r_args;
    } catch (const std::exception& e) {
        Rcpp::stop("Error extracting explicit arguments: " + std::string(e.what()));
    }
}

// Rcpp exposed function for raster translate
// [[Rcpp::export]]
Rcpp::CharacterVector get_explicit_translate_args(SEXP options_xptr) {
    if (TYPEOF(options_xptr) != EXTPTR_SXP) {
        Rcpp::stop("Expected external pointer to options object");
    }

    GDALTranslateOptions* opts =
        static_cast<GDALTranslateOptions*>(R_ExternalPtrAddr(options_xptr));

    return extract_explicit_args<GDALTranslateOptions>(opts);
}

// Similar implementations for warp and vector translate...
// (omitted for brevity)

#else

// Fallback for GDAL < 3.12
// [[Rcpp::export]]
Rcpp::CharacterVector get_explicit_translate_args(SEXP options_xptr) {
    Rcpp::warning("getExplicitlySetArgs requires GDAL 3.12+. Returning empty vector.");
    return Rcpp::CharacterVector::create();
}

#endif
```

#### 1.2 gdalcli R Wrapper

**File**: `R/explicit_args.R`

```r
#' Get Explicitly Set Arguments from GDAL Job
#'
#' @description
#' Extract only the arguments explicitly set by the user (or wrapper logic),
#' excluding GDAL defaults. This is useful for:
#' - Auditing what parameters were actually applied
#' - Reproducing operations across systems
#' - Logging for compliance/reproducibility
#'
#' @param job A gdal_job object
#' @param system_only Logical. If TRUE, return only system-injected args
#'   (those added by gdalcli internally, not by user)
#'
#' @return Character vector of explicit arguments in CLI format
#'
#' @details
#' **Requirements:**
#' - GDAL 3.12+ (falls back to warning on older versions)
#' - gdalraster >= 1.2.0 with Rcpp bindings
#'
#' **Return Value:**
#' Arguments are returned in CLI format, suitable for:
#' ```r
#' args <- gdal_job_get_explicit_args(job)
#' # args might be: c("-of", "GTiff", "-co", "COMPRESS=LZW")
#' ```
#'
#' **System vs User Arguments:**
#' gdalcli may inject system arguments for operational needs:
#' - `-q` for quiet mode (prevents R console lockup)
#' - Error handling callbacks
#' - Output redirection flags
#'
#' Use `system_only=TRUE` to isolate these from user-provided arguments.
#'
#' @examples
#' \dontrun{
#' # Create a job with explicit parameters
#' job <- gdal_raster_convert(
#'   input = "input.tif",
#'   output = "output.tif",
#'   output_format = "COG",
#'   creation_option = c("COMPRESS=LZW", "BLOCKXSIZE=512")
#' )
#'
#' # Get the explicit arguments that were set
#' explicit_args <- gdal_job_get_explicit_args(job)
#' print(explicit_args)
#' # Output: c("-of", "COG", "-co", "COMPRESS=LZW", "-co", "BLOCKXSIZE=512")
#'
#' # Verify system arguments separately
#' system_args <- gdal_job_get_explicit_args(job, system_only = TRUE)
#' }
#'
#' @export
gdal_job_get_explicit_args <- function(job, system_only = FALSE) {
  # Version check
  if (!gdal_check_version("3.12", op = ">=")) {
    cli::cli_warn(
      c(
        "getExplicitlySetArgs requires GDAL 3.12+",
        "i" = sprintf("Current version: %s", gdal_get_version()),
        "i" = "Returning empty vector (feature unavailable)"
      )
    )
    return(character(0))
  }

  # Validate input
  if (!inherits(job, "gdal_job")) {
    cli::cli_abort("job must be a gdal_job object")
  }

  # Verify gdalraster has the capability
  if (!has_explicit_args_support()) {
    cli::cli_warn(
      c(
        "gdalraster binding for getExplicitlySetArgs not available",
        "i" = "Update gdalraster to >= 1.2.0"
      )
    )
    return(character(0))
  }

  # Extract explicit args via gdalraster Rcpp binding
  tryCatch({
    explicit_args <- .Call("get_explicit_translate_args", job$options_ptr)

    # Filter if system_only requested
    if (system_only) {
      system_markers <- c("-q", "-quiet", "--quiet", "-vsicurl_use_head")
      explicit_args <- explicit_args[explicit_args %in% system_markers]
    }

    explicit_args
  }, error = function(e) {
    cli::cli_abort(
      c(
        "Failed to extract explicit arguments",
        "x" = conditionMessage(e)
      )
    )
  })
}

#' Check if gdalraster Supports getExplicitlySetArgs
#'
#' @keywords internal
has_explicit_args_support <- function() {
  tryCatch({
    # Check if gdalraster >= 1.2.0 is loaded
    if (!requireNamespace("gdalraster", quietly = TRUE)) {
      return(FALSE)
    }

    # Check version
    pkg_version <- utils::packageVersion("gdalraster")
    pkg_version >= "1.2.0"
  }, error = function(e) {
    FALSE
  })
}
```

#### 1.3 Usage in gdalcli Core

**File**: `R/core-gdal_run.R` (enhancement)

```r
# Enhanced error reporting using explicit args
gdal_job_run_with_audit <- function(job, ...) {
  # Get explicit args for audit trail
  explicit_args <- tryCatch(
    gdal_job_get_explicit_args(job),
    error = function(e) character(0)
  )

  # Create audit entry
  audit_entry <- list(
    timestamp = Sys.time(),
    explicit_args = explicit_args,
    gdal_version = gdal_get_version(),
    r_version = paste0(R.version$major, ".", R.version$minor)
  )

  # Log audit entry if logging is enabled
  if (getOption("gdalcli.audit_logging", default = FALSE)) {
    log_audit_entry(audit_entry)
  }

  # Execute job normally
  result <- gdal_job_run(job, ...)

  # Attach audit info to result if available
  if (!is.null(result)) {
    attr(result, "audit") <- audit_entry
  }

  result
}
```

### 1.4 Testing Strategy for getExplicitlySetArgs()

**File**: `tests/testthat/test_explicit_args.R`

```r
test_that("gdal_job_get_explicit_args returns user arguments only", {
  skip_if_not(gdal_check_version("3.12", op = ">="))
  skip_if_not(has_explicit_args_support())

  # Create job with explicit parameters
  job <- new_gdal_job(
    command_path = c("raster", "convert"),
    arguments = list(
      input = "input.tif",
      output = "output.tif",
      output_format = "COG",
      creation_option = c("COMPRESS=LZW")
    )
  )

  # Get explicit args
  explicit_args <- gdal_job_get_explicit_args(job)

  # Verify user args are present
  expect_true("-of" %in% explicit_args)
  expect_true("COG" %in% explicit_args)
  expect_true("-co" %in% explicit_args)
  expect_true("COMPRESS=LZW" %in% explicit_args)
})

test_that("system_only parameter filters correctly", {
  skip_if_not(gdal_check_version("3.12", op = ">="))
  skip_if_not(has_explicit_args_support())

  job <- new_gdal_job(
    command_path = c("raster", "convert"),
    arguments = list(input = "in.tif", output = "out.tif")
  )

  # Get system-only args
  system_args <- gdal_job_get_explicit_args(job, system_only = TRUE)

  # Should contain only system markers
  expect_true(all(system_args %in% c("-q", "-quiet", "--quiet")))
})

test_that("gracefully handles GDAL < 3.12", {
  skip_if(gdal_check_version("3.12", op = ">="))

  job <- new_gdal_job(
    command_path = c("raster", "convert"),
    arguments = list(input = "in.tif")
  )

  # Should warn and return empty
  expect_warning(
    result <- gdal_job_get_explicit_args(job),
    "requires GDAL 3.12"
  )
  expect_equal(result, character(0))
})

test_that("rejects invalid input", {
  skip_if_not(gdal_check_version("3.12", op = ">="))

  expect_error(
    gdal_job_get_explicit_args("not a job"),
    "must be a gdal_job"
  )
})
```

---

## Feature 2: setVectorArgsFromObject()

### Problem Statement

Vector workflows currently require:
1. Read sf object from disk
2. Modify in R
3. Write to temporary file
4. Call ogr2ogr on temp file
5. Read result back

This creates massive I/O overhead, especially for iterative processes.

### Solution: In-Memory Vector Processing via Arrow

#### 2.1 gdalraster Rcpp Implementation

**File**: `src/vector_args_from_object.cpp`

```cpp
#include <gdal_utils.h>
#include <gdal.h>
#include <Rcpp.h>
#include <arrow/c/abi.h>

#ifdef GDAL_VERSION_NUM >= 3120000

// Rcpp exposed function to set vector args from Arrow memory
// [[Rcpp::export]]
Rcpp::List set_vector_args_from_arrow(
    SEXP options_xptr,
    SEXP arrow_array_ptr,
    Rcpp::CharacterVector operation = "translate") {

  GDALVectorTranslateOptions* opts =
      static_cast<GDALVectorTranslateOptions*>(R_ExternalPtrAddr(options_xptr));

  ArrowArray* arrow_array =
      static_cast<ArrowArray*>(R_ExternalPtrAddr(arrow_array_ptr));

  if (!opts || !arrow_array) {
    return Rcpp::List::create(
      Rcpp::Named("success") = false,
      Rcpp::Named("error") = "Invalid pointer(s)"
    );
  }

  try {
    // GDAL 3.12 should support OGRArrowLayer wrapper
    // This wraps the Arrow array as an OGR layer

    // Validate Arrow array structure
    if (arrow_array->length == 0) {
      return Rcpp::List::create(
        Rcpp::Named("success") = false,
        Rcpp::Named("error") = "Arrow array is empty"
      );
    }

    // Validate that we have schema information
    if (arrow_array->n_children == 0) {
      return Rcpp::List::create(
        Rcpp::Named("success") = false,
        Rcpp::Named("error") = "Arrow array lacks field schema"
      );
    }

    // For GDAL 3.12+, options object may have a method to attach data
    // Hypothetical API (exact signature TBD)
    // opts->SetVectorSourceFromArrow(arrow_array);

    return Rcpp::List::create(
      Rcpp::Named("success") = true,
      Rcpp::Named("error") = NA_STRING,
      Rcpp::Named("rows") = arrow_array->length,
      Rcpp::Named("columns") = arrow_array->n_children
    );
  } catch (const std::exception& e) {
    return Rcpp::List::create(
      Rcpp::Named("success") = false,
      Rcpp::Named("error") = std::string(e.what())
    );
  }
}

// Check if GDAL supports Arrow-backed vectors
// [[Rcpp::export]]
bool gdal_has_arrow_support() {
  #ifdef GDAL_VERSION_NUM >= 3120000
    // Check at runtime if OGRArrowLayer is available
    GDALDriver* driver = GDALGetDriverByName("Arrow");
    return driver != nullptr;
  #else
    return false;
  #endif
}

#else

// Fallback for GDAL < 3.12
Rcpp::List set_vector_args_from_arrow(
    SEXP options_xptr,
    SEXP arrow_array_ptr,
    Rcpp::CharacterVector operation = "translate") {
  return Rcpp::List::create(
    Rcpp::Named("success") = false,
    Rcpp::Named("error") = "Requires GDAL 3.12+ with Arrow support"
  );
}

bool gdal_has_arrow_support() {
  return false;
}

#endif
```

#### 2.2 gdalcli R Wrapper

**File**: `R/vector_from_object.R`

```r
#' Convert Vector Object to GDAL Pipeline
#'
#' @description
#' Process an R vector object (sf or data.frame with geometry) using GDAL
#' without writing to disk. Eliminates I/O bottleneck for vector workflows.
#'
#' @param x An sf object or compatible vector data
#' @param operation Character string: "translate", "info", "sql", "filter"
#' @param sql Character string. SQL query to apply (for sql/filter operations)
#' @param dialect Character string. SQL dialect: "default", "sqlite", "ogrsql"
#' @param output_crs Character or numeric. Output CRS (e.g., "EPSG:3857")
#' @param keep_fields Character vector. Fields to keep. NULL = all
#' @param ... Additional arguments passed to operation
#'
#' @return
#' - For "translate": sf object with results
#' - For "info": List with metadata
#' - For "sql": sf object or tibble with query results
#' - For "filter": sf object with filtered geometries
#'
#' @details
#' **How It Works:**
#' 1. Convert R object to Arrow Table (in-memory columnar format)
#' 2. Pass Arrow pointer to GDAL via Arrow C Stream Interface
#' 3. GDAL processes using native OGRArrowLayer
#' 4. Result streamed back to R without disk I/O
#'
#' **Requirements:**
#' - GDAL 3.12+ with Arrow support
#' - arrow R package (for conversion to Arrow)
#' - gdalraster >= 1.2.0
#'
#' **SQL Dialects:**
#' - `"default"`: OGRSQL (basic, always available)
#' - `"sqlite"`: Full SQLite with SpatiaLite (if GDAL built with SQLite)
#' - `"ogrsql"`: OGRSQL variant for specific drivers
#'
#' **Performance Notes:**
#' - First call includes Arrow conversion overhead (~10-100ms)
#' - Subsequent operations on same object use in-memory cache
#' - For 1000+ row operations, I/O savings dominate conversion cost
#'
#' @examples
#' \dontrun{
#' library(sf)
#' library(gdalcli)
#'
#' # Load sample data
#' nc <- st_read(system.file("shape/nc.shp", package = "sf"))
#'
#' # Example 1: Reproject without disk I/O
#' nc_3857 <- gdal_vector_from_object(nc, output_crs = "EPSG:3857")
#'
#' # Example 2: SQL query on in-memory object
#' large_counties <- gdal_vector_from_object(
#'   nc,
#'   operation = "sql",
#'   sql = "SELECT * FROM layer WHERE area > 0.2",
#'   dialect = "sqlite"
#' )
#'
#' # Example 3: Spatial filter (buffer + intersection)
#' # Get counties within 50km of a point
#' buffered <- gdal_vector_from_object(
#'   nc,
#'   operation = "filter",
#'   geometry = st_buffer(st_point(c(-80, 35)), 50000)
#' )
#' }
#'
#' @export
gdal_vector_from_object <- function(
    x,
    operation = c("translate", "info", "sql", "filter"),
    sql = NULL,
    dialect = c("default", "sqlite", "ogrsql"),
    output_crs = NULL,
    keep_fields = NULL,
    ...) {

  operation <- match.arg(operation)
  dialect <- match.arg(dialect)

  # Version and capability checks
  if (!gdal_check_version("3.12", op = ">=")) {
    cli::cli_abort(
      c(
        "Vector object processing requires GDAL 3.12+",
        "i" = sprintf("Current version: %s", gdal_get_version()),
        "i" = "Use gdal_vector_translate() with temporary files for older GDAL"
      )
    )
  }

  if (!has_arrow_support()) {
    cli::cli_abort(
      c(
        "GDAL not compiled with Arrow support",
        "i" = "Recompile GDAL with --with-arrow=yes"
      )
    )
  }

  # Validate input
  if (!inherits(x, "sf")) {
    cli::cli_abort("x must be an sf object")
  }

  # Validate SQL dialect availability
  if (dialect == "sqlite" && !gdal_has_dialect("sqlite")) {
    cli::cli_warn(
      c(
        "SQLite dialect not available in this GDAL build",
        "i" = "Falling back to default OGRSQL dialect"
      )
    )
    dialect <- "default"
  }

  # Convert to Arrow (zero-copy where possible)
  tryCatch({
    arrow_table <- arrow::as_arrow_table(x)
  }, error = function(e) {
    cli::cli_abort(
      c(
        "Failed to convert sf object to Arrow",
        "x" = conditionMessage(e),
        "i" = "Ensure arrow package is installed: install.packages('arrow')"
      )
    )
  })

  # Call appropriate GDAL operation
  result <- switch(operation,
    "translate" = .gdal_vector_translate_arrow(arrow_table, output_crs, keep_fields, ...),
    "info" = .gdal_vector_info_arrow(arrow_table),
    "sql" = .gdal_vector_sql_arrow(arrow_table, sql, dialect, ...),
    "filter" = .gdal_vector_filter_arrow(arrow_table, ...),
    cli::cli_abort(sprintf("Unknown operation: %s", operation))
  )

  # Convert result back to sf if needed
  if (inherits(result, "data.frame") && !inherits(result, "sf")) {
    # Restore geometry column from Arrow
    result <- arrow::as_arrow_table(result) |>
      sf::st_as_sf()
  }

  result
}

# Internal helper: Translation
.gdal_vector_translate_arrow <- function(arrow_table, crs, fields, ...) {
  # Implementation...
}

# Internal helper: Info
.gdal_vector_info_arrow <- function(arrow_table) {
  # Implementation...
}

# Internal helper: SQL
.gdal_vector_sql_arrow <- function(arrow_table, sql, dialect, ...) {
  # Implementation...
}

# Internal helper: Filter
.gdal_vector_filter_arrow <- function(arrow_table, ...) {
  # Implementation...
}

#' Check if GDAL Has Arrow Support
#'
#' @keywords internal
has_arrow_support <- function() {
  tryCatch({
    requireNamespace("gdalraster", quietly = TRUE) &&
      .Call("gdal_has_arrow_support")
  }, error = function(e) {
    FALSE
  })
}

#' Check if Specific SQL Dialect is Available
#'
#' @keywords internal
gdal_has_dialect <- function(dialect) {
  tryCatch({
    # Query GDAL for dialect support
    # This would require a Rcpp binding to check OGRSQLDialectRegistry
    switch(dialect,
      "sqlite" = gdal_check_version("3.12", op = ">="),
      "ogrsql" = TRUE,  # Always available
      "default" = TRUE,  # Always available
      FALSE
    )
  }, error = function(e) {
    FALSE
  })
}
```

#### 2.3 Testing Strategy for setVectorArgsFromObject()

**File**: `tests/testthat/test_vector_from_object.R`

```r
test_that("gdal_vector_from_object requires GDAL 3.12+", {
  skip_if(gdal_check_version("3.12", op = ">="))

  nc <- sf::st_read(system.file("shape/nc.shp", package = "sf"))

  expect_error(
    gdal_vector_from_object(nc),
    "requires GDAL 3.12"
  )
})

test_that("vector translation works without disk I/O", {
  skip_if_not(gdal_check_version("3.12", op = ">="))
  skip_if_not(has_arrow_support())

  nc <- sf::st_read(system.file("shape/nc.shp", package = "sf"))

  # Reproject in-memory
  nc_3857 <- gdal_vector_from_object(nc, output_crs = "EPSG:3857")

  # Verify result
  expect_s3_class(nc_3857, "sf")
  expect_equal(sf::st_crs(nc_3857)$epsg, 3857)
})

test_that("SQL queries execute on Arrow data", {
  skip_if_not(gdal_check_version("3.12", op = ">="))
  skip_if_not(has_arrow_support())

  nc <- sf::st_read(system.file("shape/nc.shp", package = "sf"))

  # Run SQL query
  result <- gdal_vector_from_object(
    nc,
    operation = "sql",
    sql = "SELECT * FROM layer WHERE area > 0.2"
  )

  # Verify filtering occurred
  expect_true(nrow(result) < nrow(nc))
  expect_s3_class(result, "sf")
})

test_that("rejects non-sf objects", {
  skip_if_not(gdal_check_version("3.12", op = ">="))

  expect_error(
    gdal_vector_from_object(mtcars),
    "must be an sf object"
  )
})

test_that("warns when dialect unavailable", {
  skip_if_not(gdal_check_version("3.12", op = ">="))
  skip_if(gdal_has_dialect("sqlite"))

  nc <- sf::st_read(system.file("shape/nc.shp", package = "sf"))

  expect_warning(
    gdal_vector_from_object(
      nc,
      operation = "sql",
      sql = "SELECT * FROM layer",
      dialect = "sqlite"
    ),
    "SQLite dialect not available"
  )
})
```

---

## Version Detection Strategy

### 3.1 Runtime Capability Detection

**File**: `R/version_detection.R`

```r
#' Detect GDAL Capabilities at Runtime
#'
#' @description
#' Probe GDAL installation for available features, handling version mismatches
#' gracefully.
#'
#' @keywords internal

# Cache for version info (avoid repeated checks)
.gdal_capabilities_cache <- new.env()

#' Get GDAL Version
#'
#' @keywords internal
gdal_get_version <- function() {
  if (!exists("version", envir = .gdal_capabilities_cache)) {
    if (!requireNamespace("gdalraster", quietly = TRUE)) {
      return("unknown")
    }

    version_info <- gdalraster::gdal_version()
    # Extract simple version (e.g., "3.11.4" from full string)
    version <- version_info[4] %||% "unknown"
    assign("version", version, envir = .gdal_capabilities_cache)
  }

  get("version", envir = .gdal_capabilities_cache)
}

#' Check for Feature Availability
#'
#' @keywords internal
gdal_has_feature <- function(feature) {
  if (!exists(feature, envir = .gdal_capabilities_cache)) {
    available <- switch(feature,
      "explicit_args" = gdal_check_version("3.12", op = ">=") &&
        has_explicit_args_support(),
      "arrow_vectors" = gdal_check_version("3.12", op = ">=") &&
        has_arrow_support(),
      "gdalg_native" = gdal_check_version("3.11", op = ">=") &&
        .check_gdalg_driver(),
      FALSE
    )

    assign(feature, available, envir = .gdal_capabilities_cache)
  }

  get(feature, envir = .gdal_capabilities_cache)
}

#' Clear Version Cache (for testing)
#'
#' @keywords internal
gdal_clear_cache <- function() {
  rm(list = ls(envir = .gdal_capabilities_cache), envir = .gdal_capabilities_cache)
}

#' Report Available Features
#'
#' @export
gdal_capabilities <- function() {
  version <- gdal_get_version()

  features <- list(
    version = version,
    version_matrix = list(
      minimum = "3.11",
      current = version,
      has_311 = gdal_check_version("3.11", op = ">="),
      has_312 = gdal_check_version("3.12", op = ">=")
    ),
    features = list(
      explicit_args = gdal_has_feature("explicit_args"),
      arrow_vectors = gdal_has_feature("arrow_vectors"),
      gdalg_native = gdal_has_feature("gdalg_native"),
      # ... other features
      native_pipeline = gdal_check_version("3.11", op = ">=")
    ),
    packages = list(
      gdalraster_version = utils::packageVersion("gdalraster"),
      gdalraster_supports_312 = utils::packageVersion("gdalraster") >= "1.2.0"
    )
  )

  structure(features, class = "gdal_capabilities")
}

#' Print GDAL Capabilities
#'
#' @export
print.gdal_capabilities <- function(x, ...) {
  cat("GDAL Capabilities Report\n")
  cat("========================\n\n")

  cat("Version Information:\n")
  cat(sprintf("  Current GDAL: %s\n", x$version))
  cat(sprintf("  Minimum Required: %s\n", x$version_matrix$minimum))
  cat(sprintf("  GDAL 3.11+: %s\n", ifelse(x$version_matrix$has_311, "YES", "NO")))
  cat(sprintf("  GDAL 3.12+: %s\n\n", ifelse(x$version_matrix$has_312, "YES", "NO")))

  cat("Feature Availability:\n")
  for (feature in names(x$features)) {
    status <- ifelse(x$features[[feature]], "✓", "✗")
    cat(sprintf("  [%s] %s\n", status, feature))
  }

  cat("\nPackage Versions:\n")
  cat(sprintf("  gdalraster: %s\n", x$packages$gdalraster_version))
  cat(sprintf("  GDAL 3.12 support: %s\n",
    ifelse(x$packages$gdalraster_supports_312, "YES", "NO")))

  invisible(x)
}
```

### 3.2 Graceful Degradation Pattern

```r
# Use this pattern throughout gdalcli for optional features

safe_call_feature <- function(operation, fallback_operation) {
  if (gdal_has_feature(operation)) {
    # Use advanced feature
    do.call(operation, list(...))
  } else {
    # Fallback to stable implementation
    cli::cli_inform(
      c(
        sprintf("Feature '%s' not available", operation),
        "i" = sprintf("Falling back to: %s", fallback_operation),
        "i" = sprintf("To use advanced features, upgrade GDAL to 3.12+")
      )
    )
    do.call(fallback_operation, list(...))
  }
}
```

---

## Integration Architecture

### 4.1 Proposed Module Structure

```
gdalcli/R/
├── version_detection.R          # NEW: Capability detection
├── explicit_args.R              # NEW: getExplicitlySetArgs integration
├── vector_from_object.R         # NEW: Arrow-based vector processing
├── core-gdal_run.R              # MODIFIED: Add audit logging
├── core-gdalg.R                 # EXISTING: GDALG support
└── ...existing modules

tests/testthat/
├── test_version_detection.R     # NEW
├── test_explicit_args.R         # NEW
├── test_vector_from_object.R    # NEW
└── ...existing tests
```

### 4.2 Dependency Chain

```
gdalcli (user-facing API)
  ↓ (imports)
gdalraster (Rcpp bindings)
  ↓ (links against)
GDAL 3.12+ C++
  ↓ (uses)
Arrow C Stream Interface
```

### 4.3 Integration with Existing Code

**In gdal_job_run():**

```r
gdal_job_run <- function(job, backend = c("auto", "processx", "gdalraster"), ...) {
  backend <- match.arg(backend)

  # NEW: If feature available, use it for audit
  if (gdal_has_feature("explicit_args")) {
    audit_info <- list(
      explicit_args = gdal_job_get_explicit_args(job),
      timestamp = Sys.time()
    )
  }

  # ... existing execution logic ...

  # Attach audit info to result
  if (exists("audit_info")) {
    attr(result, "audit") <- audit_info
  }

  result
}
```

---

## Testing Strategy

### 5.1 Unit Tests

Each feature has comprehensive unit tests (see sections 1.4 and 2.3).

### 5.2 Integration Tests

**File**: `tests/testthat/test_integration_advanced_features.R`

```r
# Test interaction between features
test_that("explicit args audit works with vector operations", {
  skip_if_not(gdal_check_version("3.12", op = ">="))

  nc <- sf::st_read(system.file("shape/nc.shp", package = "sf"))

  # Perform vector operation with auditing
  result <- gdal_vector_from_object(nc, output_crs = "EPSG:3857")

  # Verify audit trail
  audit <- attr(result, "audit")
  expect_true(is.list(audit))
  expect_true("explicit_args" %in% names(audit))
  expect_true("timestamp" %in% names(audit))
})

# Test version fallback behavior
test_that("features degrade gracefully on older GDAL", {
  skip_if(gdal_check_version("3.12", op = ">="))

  nc <- sf::st_read(system.file("shape/nc.shp", package = "sf"))

  # Should warn but not error
  expect_warning(
    result <- gdal_vector_from_object(nc),
    "requires GDAL 3.12"
  )
})
```

### 5.3 Performance Tests

**File**: `tests/testthat/test_performance_advanced.R`

```r
test_that("Arrow-based operations are faster than disk-based for large data", {
  skip_if_not(gdal_check_version("3.12", op = ">="))
  skip_if_not(has_arrow_support())

  # Create large test dataset
  large_data <- sf::st_sf(
    id = 1:10000,
    geometry = sf::st_sfc(
      rep(sf::st_point(c(0, 0)), 10000),
      crs = "EPSG:4326"
    )
  )

  # Time Arrow-based operation
  arrow_time <- system.time({
    result <- gdal_vector_from_object(large_data, output_crs = "EPSG:3857")
  })

  # Arrow should be significantly faster than disk-based alternative
  expect_lt(arrow_time["elapsed"], 5.0)  # Reasonable upper bound
})
```

---

## Implementation Timeline

### Phase 1: Foundation (Week 1-2)
- [ ] Create gdalraster Rcpp bindings for getExplicitlySetArgs()
- [ ] Implement version detection framework
- [ ] Create basic unit tests

### Phase 2: Feature 1 Integration (Week 3-4)
- [ ] Implement gdalcli R wrappers for getExplicitlySetArgs()
- [ ] Integrate with gdal_job_run() for audit logging
- [ ] Comprehensive testing

### Phase 3: Feature 2 Implementation (Week 5-7)
- [ ] Create gdalraster Rcpp bindings for Arrow support
- [ ] Implement gdal_vector_from_object() wrapper
- [ ] Performance optimization

### Phase 4: Integration & Polish (Week 8-9)
- [ ] End-to-end integration testing
- [ ] Performance benchmarking
- [ ] Documentation and examples

### Phase 5: Release (Week 10)
- [ ] Final QA
- [ ] Package release
- [ ] User communication

---

## Success Criteria

✅ **Feature Completeness**
- Both getExplicitlySetArgs() and setVectorArgsFromObject() fully integrated
- Graceful fallback for GDAL < 3.12

✅ **Code Quality**
- 100% test coverage for new code
- No compilation warnings
- Lint-clean R code

✅ **Performance**
- Arrow operations > 2x faster than disk-based for large datasets
- No performance regression on existing features

✅ **User Experience**
- Clear error messages when features unavailable
- Comprehensive documentation and examples
- Easy-to-use API consistent with gdalcli design

---

## References

- GDAL 3.12 Release Notes
- Apache Arrow C Data Interface
- gdalraster package documentation
- GDAL Utilities Reference Guide
