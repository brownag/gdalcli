#' Package Load Hook for Dynamic GDAL API
#'
#' @description
#' This file contains the `.onLoad` hook that initializes the dynamic GDAL API
#' when the gdalcli package is loaded. It handles:
#' - Dependency validation (gdalraster availability)
#' - GDAL version checking (>= 3.11)
#' - Version-aware caching for fast subsequent loads
#' - Namespace assignment of the `gdal` object
#'
#' @keywords internal

.onLoad <- function(libname, pkgname) {
  # Check if gdalraster is available
  if (!requireNamespace("gdalraster", quietly = TRUE)) {
    packageStartupMessage(
      "Note: gdalraster package not found. Dynamic GDAL API will not be available.",
      "\n  Install with: install.packages('gdalraster')",
      "\n  Or use the static API instead."
    )
    return(invisible(NULL))
  }

  # Check GDAL version
  tryCatch(
    {
      gdal_version_info <- gdalraster::gdal_version()

      # Extract version string safely
      if (is.list(gdal_version_info) && "version" %in% names(gdal_version_info)) {
        version_string <- gdal_version_info[["version"]]
      } else if (is.character(gdal_version_info) && length(gdal_version_info) > 0) {
        version_string <- gdal_version_info[1]
      } else {
        packageStartupMessage(
          "Warning: Could not determine GDAL version.",
          "\n  The static API is still available."
        )
        return(invisible(NULL))
      }

      # Parse version (e.g., "GDAL 3.11.1 Eganville..." -> "3.11.1")
      # Extract just the numeric version part
      version_match <- regexpr("\\d+\\.\\d+(\\.\\d+)?", version_string)
      if (version_match > 0) {
        version_numeric <- regmatches(version_string, version_match)
        version_parts <- as.numeric(strsplit(version_numeric, "\\.")[[1]])
      } else {
        packageStartupMessage(
          "Warning: Could not parse GDAL version: ", version_string,
          "\n  The static API is still available."
        )
        return(invisible(NULL))
      }

      # Check if parsing succeeded and we have at least major.minor
      if (is.na(version_parts[1]) || is.na(version_parts[2])) {
        packageStartupMessage(
          "Warning: Could not parse GDAL version: ", version_string,
          "\n  The static API is still available."
        )
        return(invisible(NULL))
      }

      # Check minimum requirement: 3.11
      if (version_parts[1] < 3 || (version_parts[1] == 3 && version_parts[2] < 11)) {
        packageStartupMessage(
          "Warning: GDAL version ", version_string, " detected.",
          "\n  Dynamic GDAL API requires GDAL >= 3.11",
          "\n  Update GDAL or use the static API instead."
        )
        return(invisible(NULL))
      }

      # Build or load the dynamic API
      gdal_api <- GdalApi$new()

      # Assign to package namespace
      assign("gdal", gdal_api, envir = asNamespace(pkgname))
    },
    error = function(e) {
      packageStartupMessage(
        "Error initializing dynamic GDAL API:",
        "\n  ", conditionMessage(e),
        "\n  The static API is still available."
      )
    }
  )

  invisible(NULL)
}
