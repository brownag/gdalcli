# ===================================================================
# RFC 104 Step Name Mappings
#
# This file manages the loading and caching of RFC 104 step name mappings.
# Mappings are auto-generated during build time from GDAL API endpoints,
# allowing operations to be classified as "read", "write", or transformation steps.
#
# Mappings can be overridden by users via inst/extdata/step_mappings_overrides.json
# ===================================================================

# Package environment for storing step mappings
.gdalcli_env <- new.env(parent = emptyenv())

#' Get RFC 104 Step Name for a Command
#'
#' Returns the RFC 104 step name for a given GDAL operation.
#' Maps operations like "convert" to "write", "info" to "read", etc.
#'
#' @param module Character. Module name ("raster", "vector", "mdim", etc.)
#' @param operation Character. Operation name ("convert", "reproject", etc.)
#'
#' @return Character. RFC 104 step name. If not found, returns the operation name.
#'
#' @details
#' Step mappings are generated from the GDAL API during package build and can
#' be customized via inst/extdata/step_mappings_overrides.json.
#'
#' Common step names include:
#' - "read": Operations that load data (e.g., info)
#' - "write": Operations that save data (e.g., convert)
#' - Operation-specific names: "reproject", "clip", "calc", etc.
#'
#' @keywords internal
#' @noRd
.get_step_mapping <- function(module, operation) {
  # Get mappings from environment (loaded in .onLoad), fallback to defaults
  mappings <- .gdalcli_env$step_mappings %||% .get_default_step_mappings()

  # Return mapping or default to operation name (if module or operation not found)
  mappings[[module]][[operation]] %||% operation
}

#' Load Step Mappings from Generated JSON
#'
#' Internal function called during package load to initialize step mappings
#' from the auto-generated inst/GDAL_STEP_MAPPINGS.json file, with optional
#' user overrides from inst/extdata/step_mappings_overrides.json.
#'
#' @keywords internal
#' @noRd
.load_step_mappings <- function() {
  mappings_file <- system.file("GDAL_STEP_MAPPINGS.json", package = "gdalcli")

  # Load generated step mappings
  if (!file.exists(mappings_file)) {
    # If mappings file doesn't exist, use fallback defaults
    .gdalcli_env$step_mappings <- .get_default_step_mappings()
    warning(
      "GDAL step mappings file not found at: ", mappings_file, "\n",
      "Using fallback defaults. Run 'make regen' to regenerate mappings."
    )
    return(invisible(NULL))
  }

  mappings <- tryCatch(
    {
      yyjsonr::read_json_file(mappings_file)
    },
    error = function(e) {
      warning(
        "Failed to load GDAL step mappings from: ", mappings_file, "\n",
        "Error: ", conditionMessage(e), "\n",
        "Using fallback defaults."
      )
      .get_default_step_mappings()
    }
  )

  # Load and merge user overrides if present
  overrides_file <- system.file("extdata/step_mappings_overrides.json",
                                package = "gdalcli")

  if (file.exists(overrides_file)) {
    overrides <- tryCatch(
      {
        yyjsonr::read_json_file(overrides_file)
      },
      error = function(e) {
        warning(
          "Failed to load step mapping overrides from: ", overrides_file, "\n",
          "Error: ", conditionMessage(e)
        )
        NULL
      }
    )

    # Merge overrides into loaded mappings
    if (!is.null(overrides)) {
      mappings <- modifyList(mappings, overrides)
    }
  }

  # Store in environment
  .gdalcli_env$step_mappings <- mappings
  invisible(NULL)
}

#' Get Default (Fallback) Step Mappings
#'
#' Provides hardcoded fallback step mappings used when auto-generated
#' mappings are unavailable. This ensures basic functionality even if
#' GDAL_STEP_MAPPINGS.json is missing.
#'
#' Only includes non-identity mappings (where operation != step_name).
#' Identity mappings are handled by .get_step_mapping() fallback logic that
#' returns the operation name when no mapping is found.
#'
#' @return List of step mappings by module
#'
#' @keywords internal
#' @noRd
.get_default_step_mappings <- function() {
  list(
    raster = c(
      # Write operations (I/O)
      convert = "write",
      create = "write",
      tile = "write",
      # Renamed operations (special case mappings)
      # Include both underscore and dash variants for compatibility
      fill_nodata = "fillnodata",
      "fill-nodata" = "fillnodata",
      clean_collar = "cleancol",
      "clean-collar" = "cleancol",
      # Read operations (info)
      info = "read"
    ),
    vector = c(
      # Write operations (I/O)
      convert = "write",
      # Read operations (info)
      info = "read"
    )
  )
}
