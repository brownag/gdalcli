#' gdalraster Package Detection and Feature Availability
#'
#' @description
#' Internal functions to detect gdalraster package, check its version, and
#' determine which features are available based on the installed version.
#'
#' These functions provide a centralized system for version-aware feature
#' detection, allowing code to gracefully handle missing gdalraster or
#' feature availability based on gdalraster version.
#'
#' @keywords internal

#' Check gdalraster Version
#'
#' @description
#' Determines if gdalraster is installed and meets a minimum version requirement.
#'
#' @param min_version Character string specifying minimum required version
#'   (e.g., "2.2.0", "2.3.0")
#' @param quietly Logical. If TRUE, suppresses warnings. If FALSE (default),
#'   returns silently.
#' @param error_on_unavailable Logical. If TRUE, raises an error when gdalraster
#'   is not available or version is too old. If FALSE (default), returns FALSE.
#'
#' @return
#' Logical: TRUE if gdalraster is available and meets minimum version,
#' FALSE otherwise (or error if error_on_unavailable = TRUE).
#'
#' @details
#' Version comparison uses semantic versioning: major.minor.patch.
#'
#' @keywords internal
.check_gdalraster_version <- function(min_version = "2.2.0",
                                      quietly = FALSE,
                                      error_on_unavailable = FALSE) {
  # Check if gdalraster is available
  if (!requireNamespace("gdalraster", quietly = TRUE)) {
    if (error_on_unavailable) {
      cli::cli_abort(
        c(
          "gdalraster package required for this operation",
          "i" = "Install with: install.packages('gdalraster')",
          "i" = "Minimum required version: {min_version}"
        )
      )
    }
    return(FALSE)
  }

  # Try to get gdalraster version
  current_version <- tryCatch({
    packageVersion("gdalraster")
  }, error = function(e) {
    if (!quietly) {
      cli::cli_warn("Could not determine gdalraster version: {e$message}")
    }
    NULL
  })

  if (is.null(current_version)) {
    return(FALSE)
  }

  # Parse versions to numeric for comparison
  parse_version <- function(v) {
    if (inherits(v, "package_version")) {
      v <- as.character(v)
    }
    v <- trimws(v)
    parts <- suppressWarnings(as.numeric(strsplit(v, "\\.")[[1]]))

    if (any(is.na(parts))) {
      return(NULL)
    }

    # Convert to numeric: major * 10000 + minor * 100 + patch
    major <- parts[1] %||% 0
    minor <- if (length(parts) > 1) parts[2] else 0
    patch <- if (length(parts) > 2) parts[3] else 0

    major * 10000 + minor * 100 + patch
  }

  current_numeric <- parse_version(current_version)
  min_numeric <- parse_version(min_version)

  if (is.null(current_numeric) || is.null(min_numeric)) {
    return(FALSE)
  }

  result <- current_numeric >= min_numeric

  if (!result && !quietly) {
    cli::cli_warn(
      c(
        "gdalraster version {as.character(current_version)} is less than required {min_version}",
        "i" = "Update with: install.packages('gdalraster')"
      )
    )
  }

  result
}


#' Get Installed gdalraster Version
#'
#' @description
#' Returns the version of the installed gdalraster package, or NULL if
#' gdalraster is not available.
#'
#' @return Character string with version (e.g., "2.2.0") or NULL if not available.
#'
#' @keywords internal
.get_gdalraster_version <- function() {
  if (!requireNamespace("gdalraster", quietly = TRUE)) {
    return(NULL)
  }

  tryCatch({
    as.character(packageVersion("gdalraster"))
  }, error = function(e) NULL)
}


#' Get Available gdalraster Features
#'
#' @description
#' Returns a list of features available in the installed gdalraster version.
#' This allows other code to conditionally enable functionality based on
#' gdalraster capabilities.
#'
#' @return
#' List with names indicating available features and values indicating
#' the minimum gdalraster version required for that feature.
#'
#' Feature list:
#' - `gdal_commands`: gdal_commands() function (2.2.0+)
#' - `gdal_usage`: gdal_usage() function (2.2.0+)
#' - `gdal_alg`: gdal_alg() function for algorithm execution (2.2.0+)
#' - `getExplicitlySetArgs`: GDALAlg$getExplicitlySetArgs() method (2.2.0+)
#' - `setVectorArgsFromObject`: gdalraster setVectorArgsFromObject() (2.3.0+)
#' - `advanced_features`: Advanced features like vector processing (2.3.0+)
#'
#' @details
#' The list includes all features available in the installed version.
#' Iterating over this list to check feature availability is more efficient
#' than repeated version checks.
#'
#' @keywords internal
.get_gdalraster_features <- function() {
  version <- .get_gdalraster_version()

  # Start with base features available in 2.2.0+
  features <- list(
    gdal_commands = "2.2.0",
    gdal_usage = "2.2.0",
    gdal_alg = "2.2.0",
    getExplicitlySetArgs = "2.2.0"
  )

  # Add features available in 2.3.0+
  if (!is.null(version) && .check_gdalraster_version("2.3.0", quietly = TRUE)) {
    features$setVectorArgsFromObject <- "2.3.0"
    features$advanced_features <- "2.3.0"
  }

  features
}


#' Check if gdalraster Feature is Available
#'
#' @description
#' Determines if a specific gdalraster feature is available in the
#' installed version. Results are cached for performance.
#'
#' @param feature_name Character string: name of the feature to check.
#'   Valid names: "gdal_commands", "gdal_usage", "gdal_alg",
#'   "getExplicitlySetArgs", "setVectorArgsFromObject", "advanced_features"
#' @param quietly Logical. If FALSE (default), warns if feature is unavailable.
#'   If TRUE, returns silently.
#'
#' @return
#' Logical: TRUE if feature is available, FALSE otherwise.
#'
#' @details
#' Feature availability is cached in package environment to avoid
#' repeated version checks. Cache is set on first call and reused.
#'
#' @keywords internal
.gdal_has_feature <- function(feature_name, quietly = FALSE) {
  # Use package-level cache to avoid repeated checks
  pkg_env <- parent.env(environment())

  cache_name <- ".gdalraster_features_cache"
  if (!exists(cache_name, where = pkg_env, inherits = FALSE)) {
    # Cache not yet created, build it
    features <- .get_gdalraster_features()
    assign(cache_name, features, envir = pkg_env)
  } else {
    # Get from cache
    features <- get(cache_name, pos = pkg_env)
  }

  # Check if feature exists
  has_feature <- feature_name %in% names(features)

  if (!has_feature && !quietly) {
    cli::cli_warn(
      c(
        "gdalraster feature '{feature_name}' not available",
        "i" = "Ensure gdalraster >= {features[[feature_name]]} is installed"
      )
    )
  }

  has_feature
}
