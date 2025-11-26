#' Advanced Features Framework
#'
#' @description
#' Internal infrastructure for managing GDAL 3.12+ advanced features including
#' capability detection, version checking, and performance-optimized caching.
#'
#' This module provides:
#' - Feature capability detection with runtime checks
#' - Environment-based capability caching to avoid repeated version checks
#' - Version-conditional feature availability reporting
#'
#' @keywords internal
#' @name advanced_features_framework

# Environment for caching feature capabilities
.gdal_features_cache <- new.env(parent = emptyenv())

#' Get Current GDAL Version String
#'
#' Retrieves the installed GDAL version string using gdalraster if available.
#'
#' @return Character string with GDAL version (e.g., "3.12.1") or "unknown"
#'
#' @keywords internal
#' @examples
#' \dontrun{
#'   .gdal_get_version()
#' }
#' @noRd
.gdal_get_version <- function() {
  if (exists("__gdal_version__", envir = .gdal_features_cache)) {
    return(get("__gdal_version__", envir = .gdal_features_cache))
  }

  version <- tryCatch({
    if (requireNamespace("gdalraster", quietly = TRUE)) {
      version_info <- gdalraster::gdal_version()
      # gdal_version() returns [1] = description, [2] = numeric version,
      # [3] = date, [4] = simple version (e.g., "3.12.1")
      if (is.character(version_info) && length(version_info) >= 4) {
        version_info[4]
      } else if (is.character(version_info) && length(version_info) > 0) {
        matches <- regmatches(
          version_info[1],
          regexpr("[0-9]+\\.[0-9]+\\.[0-9]+", version_info[1])
        )
        if (length(matches) > 0) trimws(matches[1]) else "unknown"
      } else {
        "unknown"
      }
    } else {
      "unknown"
    }
  }, error = function(e) "unknown")

  assign("__gdal_version__", version, envir = .gdal_features_cache)
  version
}

#' Check if Feature is Available
#'
#' Checks if a specific GDAL advanced feature is available in the current
#' environment, with caching to avoid repeated runtime checks.
#'
#' @param feature Character name of feature to check. Valid values:
#'   - "explicit_args": getExplicitlySetArgs() support (GDAL 3.12+)
#'   - "arrow_vectors": setVectorArgsFromObject() with Arrow (GDAL 3.12+)
#'   - "gdalg_native": Native GDALG format driver (GDAL 3.11+)
#'
#' @return Logical TRUE if feature is available, FALSE otherwise
#'
#' @keywords internal
#' @examples
#' \dontrun{
#'   .gdal_has_feature("explicit_args")
#'   .gdal_has_feature("arrow_vectors")
#' }
#' @noRd
.gdal_has_feature <- function(feature = c("explicit_args", "arrow_vectors", "gdalg_native")) {
  feature <- match.arg(feature)

  # Check cache first
  if (exists(feature, envir = .gdal_features_cache)) {
    return(get(feature, envir = .gdal_features_cache))
  }

  # Determine availability based on feature type
  available <- switch(feature,
    "explicit_args" = .check_explicit_args_available(),
    "arrow_vectors" = .check_arrow_vectors_available(),
    "gdalg_native" = .check_gdalg_native_available(),
    FALSE
  )

  # Cache result
  assign(feature, available, envir = .gdal_features_cache)
  available
}

#' Check Explicit Args Capability
#'
#' Internal check: GDAL 3.12+ with gdalraster Rcpp binding support
#'
#' @keywords internal
#' @noRd
.check_explicit_args_available <- function() {
  # Requires GDAL 3.12+
  if (!gdal_check_version("3.12", op = ">=")) {
    return(FALSE)
  }

  # Requires gdalraster package with binding support
  if (!requireNamespace("gdalraster", quietly = TRUE)) {
    return(FALSE)
  }

  # Check if gdalraster version supports explicit args (1.2.0+)
  pkg_version <- tryCatch(
    utils::packageVersion("gdalraster"),
    error = function(e) "0.0.0"
  )

  as.numeric_version(pkg_version) >= as.numeric_version("1.2.0")
}

#' Check Arrow Vectors Capability
#'
#' Internal check: GDAL 3.12+ with Arrow support
#'
#' @keywords internal
#' @noRd
.check_arrow_vectors_available <- function() {
  # Requires GDAL 3.12+
  if (!gdal_check_version("3.12", op = ">=")) {
    return(FALSE)
  }

  # Check if GDAL was compiled with Arrow support
  .check_gdal_has_arrow_driver()
}

#' Check GDAL Arrow Driver
#'
#' Checks if GDAL has Arrow driver compiled in
#'
#' @keywords internal
#' @noRd
.check_gdal_has_arrow_driver <- function() {
  tryCatch({
    if (requireNamespace("gdalraster", quietly = TRUE)) {
      # Try to check if Arrow driver is available
      # This would need Rcpp binding support in gdalraster
      # For now, we check if arrow package is available as a proxy
      requireNamespace("arrow", quietly = TRUE)
    } else {
      FALSE
    }
  }, error = function(e) FALSE)
}

#' Check GDALG Native Format Driver
#'
#' Internal check: GDAL 3.11+ with GDALG driver support
#'
#' @keywords internal
#' @noRd
.check_gdalg_native_available <- function() {
  # Requires GDAL 3.11+
  if (!gdal_check_version("3.11", op = ">=")) {
    return(FALSE)
  }

  # Check if GDALG driver is available
  # This is checked elsewhere in the codebase (core-gdalg.R)
  gdal_has_gdalg_driver()
}

#' Get Detailed Capabilities Report
#'
#' Returns a structured report of GDAL capabilities and advanced features
#' available in the current environment.
#'
#' @return A list with class "gdal_capabilities" containing:
#'   \itemize{
#'     \item `version`: Current GDAL version string
#'     \item `version_matrix`: List of version compatibility info
#'     \item `features`: List of available advanced features
#'     \item `packages`: List of dependent package versions
#'   }
#'
#' @details
#' The returned list has a custom print method that formats the information
#' in a human-readable way.
#'
#' @keywords internal
#' @export
gdal_capabilities <- function() {
  version <- .gdal_get_version()

  capabilities <- list(
    version = version,
    version_matrix = list(
      minimum_required = "3.11",
      current = version,
      is_3_11 = gdal_check_version("3.11", op = ">="),
      is_3_12 = gdal_check_version("3.12", op = ">="),
      is_3_13 = gdal_check_version("3.13", op = ">=")
    ),
    features = list(
      explicit_args = .gdal_has_feature("explicit_args"),
      arrow_vectors = .gdal_has_feature("arrow_vectors"),
      gdalg_native = .gdal_has_feature("gdalg_native")
    ),
    packages = list(
      gdalraster = tryCatch(
        as.character(utils::packageVersion("gdalraster")),
        error = function(e) "not installed"
      ),
      arrow = tryCatch(
        as.character(utils::packageVersion("arrow")),
        error = function(e) "not installed"
      )
    )
  )

  structure(capabilities, class = c("gdal_capabilities", "list"))
}

#' Print GDAL Capabilities
#'
#' Pretty-prints GDAL capabilities report
#'
#' @param x Object of class "gdal_capabilities"
#' @param ... Additional arguments (unused)
#'
#' @keywords internal
#' @export
#' @noRd
print.gdal_capabilities <- function(x, ...) {
  cat("GDAL Advanced Features Report\n")
  cat("==============================\n\n")

  cat("Version Information:\n")
  cat(sprintf("  Current GDAL:     %s\n", x$version))
  cat(sprintf("  Minimum Required: %s\n", x$version_matrix$minimum_required))
  cat("\n")

  cat("Feature Availability:\n")
  features_info <- sprintf(
    "  %-20s %s\n",
    names(x$features),
    ifelse(unlist(x$features), "✓ Available", "✗ Unavailable")
  )
  cat(paste(features_info, collapse = ""))
  cat("\n")

  cat("Dependent Packages:\n")
  for (pkg in names(x$packages)) {
    cat(sprintf("  %-20s %s\n", pkg, x$packages[[pkg]]))
  }

  invisible(x)
}

#' Clear Feature Cache
#'
#' Clears the cached feature availability information. Useful for testing
#' or after environment changes.
#'
#' @keywords internal
#' @noRd
.clear_feature_cache <- function() {
  rm(list = ls(envir = .gdal_features_cache, all.names = TRUE),
     envir = .gdal_features_cache)
  invisible(NULL)
}

#' Get Cached Feature Status
#'
#' Returns current cached feature status for debugging
#'
#' @return List of cached feature entries
#'
#' @keywords internal
#' @noRd
.get_feature_cache <- function() {
  as.list(.gdal_features_cache)
}
