#' Check GDAL Version Compatibility
#'
#' @description
#' Verifies that the runtime GDAL version matches (or is compatible with)
#' the GDAL version used to build the gdalcli package.
#'
#' This function is useful when using version-pinned release branches, where
#' specific GDAL versions are pre-computed for optimal compatibility.
#'
#' @return
#' A list with elements:
#' \itemize{
#'   \item `package_gdal_version`: GDAL version the package was built for
#'   \item `runtime_gdal_version`: Currently installed GDAL version
#'   \item `compatible`: Logical indicating if versions match
#'   \item `message`: Human-readable status message
#' }
#'
#' @details
#' Compatibility is determined by comparing major.minor version numbers.
#' For example, GDAL 3.11.0 and 3.11.5 are compatible, but 3.11.x and
#' 3.12.x are not.
#'
#' @seealso [gdal_job_run()], [gdalraster::gdal_version()]
#'
#' @examples
#' \dontrun{
#'   result <- gdal_version_check()
#'   cat(result$message, "\n")
#'
#'   if (!result$compatible) {
#'     warning("Consider switching to a different release branch")
#'   }
#' }
#'
#' @export
gdal_version_check <- function() {
  # Read package metadata
  pkg_info_path <- system.file("GDAL_VERSION_INFO.json", package = "gdalcli")

  pkg_info <- if (file.exists(pkg_info_path)) {
    tryCatch(
      jsonlite::fromJSON(pkg_info_path),
      error = function(e) list(gdal_version = "unknown")
    )
  } else {
    list(gdal_version = "unknown")
  }

  # Get runtime GDAL version
  runtime_info <- tryCatch(
    {
      if (requireNamespace("gdalraster", quietly = TRUE)) {
        gdalraster::gdal_version()
      } else {
        list(version = "unknown")
      }
    },
    error = function(e) list(version = "unknown")
  )

  # Extract version strings
  pkg_version_string <- pkg_info$gdal_version %||% "unknown"
  runtime_version_string <- if (is.list(runtime_info)) {
    runtime_info[["version"]] %||% "unknown"
  } else {
    as.character(runtime_info[1]) %||% "unknown"
  }

  # Extract major.minor versions
  pkg_major_minor <- .extract_major_minor(pkg_version_string)
  runtime_major_minor <- .extract_major_minor(runtime_version_string)

  # Determine compatibility
  compatible <- if (pkg_major_minor == "unknown" ||
                      runtime_major_minor == "unknown") {
    NA  # Can't determine
  } else {
    pkg_major_minor == runtime_major_minor
  }

  # Build message
  message <- if (is.na(compatible)) {
    "Unable to determine GDAL compatibility"
  } else if (compatible) {
    sprintf(
      "\u2713 Package built for GDAL %s, runtime GDAL %s - compatible",
      pkg_major_minor, runtime_major_minor
    )
  } else {
    sprintf(
      "\u26a0 Package built for GDAL %s, but runtime GDAL %s detected - may have compatibility issues",
      pkg_major_minor, runtime_major_minor
    )
  }

  list(
    package_gdal_version = pkg_version_string,
    runtime_gdal_version = runtime_version_string,
    package_major_minor = pkg_major_minor,
    runtime_major_minor = runtime_major_minor,
    compatible = compatible,
    message = message,
    branch = pkg_info$branch %||% "unknown",
    notes = pkg_info$notes %||% ""
  )
}

#' Extract Major.Minor Version
#'
#' Internal helper to extract major.minor version from version strings.
#'
#' @param version_string Character version string (e.g., "GDAL 3.11.1 Eganville...")
#'
#' @return Character in format "X.Y" or "unknown" if parsing fails
#'
#' @keywords internal
#' @noRd
.extract_major_minor <- function(version_string) {
  if (!nzchar(version_string) || version_string == "unknown") {
    return("unknown")
  }

  # Match pattern: digits.digits (with optional more digits after)
  version_match <- regexpr("\\d+\\.\\d+", version_string)

  if (version_match > 0) {
    regmatches(version_string, version_match)
  } else {
    "unknown"
  }
}

