#' Pure GDALG Format I/O Operations
#'
#' @description
#' Functions for reading, writing, and converting pure GDALG (RFC 104)
#' specifications. These work with the minimal GDALG format compatible
#' with GDAL tools.
#'
#' @details
#' Pure GDALG format is:
#' - **Portable**: Can be used with GDAL tools and APIs
#' - **Minimal**: Only contains RFC 104 command specification
#' - **Lossy**: Cannot preserve R-specific metadata or job attributes
#'
#' Read GDALG JSON File
#'
#' @description
#' Load a pure GDALG specification from a JSON file and return
#' it as a gdalg S3 object.
#'
#' @param path Character. Path to .gdalg.json file
#'
#' @return A gdalg object
#'
#' @export
gdalg_read <- function(path) {
  if (!file.exists(path)) {
    stop("File not found: ", path, call. = FALSE)
  }

  # Read and parse JSON
  spec <- tryCatch({
    json_text <- readLines(path, warn = FALSE)
    yyjsonr::read_json_str(paste(json_text, collapse = ""))
  }, error = function(e) {
    stop("Failed to parse GDALG JSON file: ", path, "\n",
         "  Error: ", conditionMessage(e), call. = FALSE)
  })

  # Validate and convert to gdalg S3 object
  tryCatch({
    as_gdalg(spec)
  }, error = function(e) {
    stop("Invalid GDALG specification in ", path, "\n",
         "  Error: ", conditionMessage(e), call. = FALSE)
  })
}


#' Write GDALG JSON File
#'
#' @description
#' Write a pure GDALG specification to a JSON file. Uses GDAL's native
#' GDALG writing capability (GDAL 3.12+) when available for RFC 104
#' compliance. Falls back to pure R JSON serialization for older GDAL versions.
#'
#' @param gdalg A gdalg object
#' @param path Character. Path to write to (typically .gdalg.json)
#' @param pretty Logical. If TRUE (default), format JSON for readability
#' @param overwrite Logical. If TRUE, overwrite existing file
#'
#' @return Invisibly returns the path
#'
#' @details
#' When GDAL 3.12+ is available, GDALG JSON is written using GDAL's native
#' `gdal raster pipeline ... ! write -f GDALG` command for maximum RFC 104
#' compliance and forward compatibility. For older GDAL versions (3.11 and below),
#' this function falls back to direct R JSON serialization using yyjsonr.
#'
#' @export
gdalg_write <- function(gdalg, path, pretty = TRUE, overwrite = FALSE) {
  # Validate gdalg object
  validate_gdalg(gdalg)

  # Check if file exists
  if (file.exists(path) && !overwrite) {
    stop("File already exists: ", path,
         " (set overwrite = TRUE to replace)", call. = FALSE)
  }

  # Try GDAL-native writing if available (GDAL 3.12+)
  if (gdal_check_version("3.12", op = ">=")) {
    result <- tryCatch({
      .gdalg_write_via_gdal(gdalg, path)
    }, error = function(e) {
      # Fallback to pure R on GDAL write failure
      NULL
    })

    if (!is.null(result)) {
      return(invisible(path))
    }
  }

  # Fallback: Use pure R JSON generation
  .gdalg_write_via_r(gdalg, path, pretty = pretty)

  invisible(path)
}


#' Write GDALG via GDAL (Internal)
#'
#' @description
#' Uses GDAL's native `gdal raster pipeline ... ! write -f GDALG` command
#' to generate GDALG JSON files with full RFC 104 compliance.
#'
#' @param gdalg A gdalg object
#' @param path Output file path
#'
#' @return Invisibly returns the path on success, NULL on failure
#'
#' @keywords internal
#' @noRd
.gdalg_write_via_gdal <- function(gdalg, path) {
  # Extract RFC 104 command from gdalg object
  # The command_line field contains the full pipeline
  # e.g., "gdal raster pipeline read --input input.tif ! reproject --dst-crs EPSG:4326"
  command_line <- gdalg$command_line

  # Detect pipeline type (raster or vector) from command
  is_raster <- grepl("\\bgdal\\s+raster", command_line, ignore.case = TRUE)
  is_vector <- grepl("\\bgdal\\s+vector", command_line, ignore.case = TRUE)

  if (!is_raster && !is_vector) {
    return(NULL)  # Cannot determine pipeline type
  }

  # Extract the pipeline operations (remove "gdal raster/vector pipeline " prefix)
  # This gives us the full pipeline string including ! separators
  pipeline_ops <- sub("^\\s*gdal\\s+(raster|vector)\\s+pipeline\\s+", "", command_line)

  # Determine pipeline type for command execution
  pipeline_type <- if (is_raster) "raster" else "vector"

  # Build the complete pipeline with write step appended
  # GDAL expects: raster/vector pipeline <operations> ! write [write-options]
  full_pipeline <- paste(pipeline_ops, "! write -f GDALG -o", shQuote(path))

  # Execute GDAL command via processx
  # The pipeline string must be passed as a single argument to be properly parsed
  exit_code <- tryCatch({
    result <- processx::run(
      "gdal",
      c(pipeline_type, "pipeline", full_pipeline),
      error_on_status = FALSE
    )
    result$status
  }, error = function(e) {
    1  # Return error status on exception
  })

  if (exit_code == 0 && file.exists(path)) {
    return(invisible(path))
  }

  NULL  # GDAL write failed
}


#' Write GDALG via Pure R (Internal)
#'
#' @description
#' Fallback method using R's yyjsonr library to serialize GDALG JSON.
#'
#' @param gdalg A gdalg object
#' @param path Output file path
#' @param pretty Logical. Whether to format JSON for readability
#'
#' @keywords internal
#' @noRd
.gdalg_write_via_r <- function(gdalg, path, pretty = TRUE) {
  # Convert to list for JSON serialization
  gdalg_list <- gdalg_to_list(gdalg)

  # Serialize to JSON
  json_str <- tryCatch({
    yyjsonr::write_json_str(gdalg_list, pretty = pretty)
  }, error = function(e) {
    stop("Failed to serialize GDALG to JSON: ", conditionMessage(e),
         call. = FALSE)
  })

  # Write to file
  tryCatch({
    writeLines(json_str, path)
  }, error = function(e) {
    stop("Failed to write GDALG file: ", path, "\n",
         "  Error: ", conditionMessage(e), call. = FALSE)
  })
}


#' Convert GDALG to Pipeline
#'
#' @description
#' Parse a gdalg specification and reconstruct it as a gdal_pipeline
#' object. This is a best-effort conversion - some R-specific info
#' (arg_mapping, config_options, env_vars) may be lost.
#'
#' @param gdalg A gdalg object
#'
#' @return A gdal_pipeline object
#'
#' @export
gdalg_to_pipeline <- function(gdalg) {
  if (!inherits(gdalg, "gdalg")) {
    stop("Expected a gdalg object", call. = FALSE)
  }

  # Delegate to transpiler function
  .gdalg_to_pipeline(gdalg$command_line)
}
