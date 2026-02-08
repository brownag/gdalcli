#' GDALCLI Hybrid Format I/O Operations
#'
#' @description
#' Functions for saving and loading pipelines in gdalcli's hybrid format.
#' The hybrid format combines RFC 104 GDALG compatibility with R-specific
#' metadata and full job specifications for lossless round-trip serialization.
#'
#' @details
#' The hybrid format enables:
#' - **Lossless R round-trip**: Full job state preserved
#' - **GDAL compatibility**: Extract gdalg component for external tools
#' - **Rich metadata**: Store pipeline name, description, custom tags
#' - **Auditable**: Includes version info, timestamps, creation context
#'
#' @keywords internal

#' Detect Pipeline Format Type
#'
#' @description
#' Auto-detect the format of a loaded pipeline specification.
#'
#' @param spec A list loaded from JSON
#'
#' @return Character string: "hybrid", "pure_gdalg", "legacy", or "unknown"
#'
#' @keywords internal
#' @noRd
.gdalcli_detect_format <- function(spec) {
  # Check for hybrid format (gdalcli v0.5.0+)
  if (!is.null(spec$gdalg) && !is.null(spec$r_job_specs)) {
    return("hybrid")
  }

  # Check for pure GDALG (at root level)
  if (!is.null(spec$type) && spec$type == "gdal_streamed_alg") {
    return("pure_gdalg")
  }

  # Check for nested gdalg (hybrid without r_job_specs)
  if (!is.null(spec$gdalg) && !is.null(spec$gdalg$type)) {
    return("hybrid")
  }

  # Check for legacy format (pre-v0.5.0)
  if (!is.null(spec$steps)) {
    return("legacy")
  }

  "unknown"
}


#' Save GDAL Pipeline to Hybrid Format
#'
#' @description
#' Save a gdal_pipeline to a gdalcli hybrid format JSON file (.gdalcli.json).
#' The hybrid format combines RFC 104 GDALG with R-specific metadata and
#' job specifications for lossless round-trip serialization.
#'
#' @param pipeline A gdal_pipeline or gdal_job object
#' @param path Character. Path to save to (typically .gdalcli.json)
#' @param name Character. Optional pipeline name
#' @param description Character. Optional pipeline description
#' @param custom_tags List. Optional user-defined metadata
#' @param pretty Logical. If TRUE (default), format JSON for readability
#' @param overwrite Logical. If TRUE, overwrite existing file
#' @param verbose Logical. If TRUE, print status messages
#'
#' @return Invisibly returns the path
#'
#' @details
#' The resulting JSON file contains three components:
#' - `gdalg`: Pure RFC 104 GDALG specification for GDAL tool compatibility
#' - `metadata`: Pipeline metadata (name, version, timestamps, custom tags)
#' - `r_job_specs`: Full R job state for lossless reconstruction
#'
#' @keywords internal
#' @noRd
.gdal_save_pipeline_hybrid <- function(pipeline,
                                       path,
                                       name = NULL,
                                       description = NULL,
                                       custom_tags = list(),
                                       pretty = TRUE,
                                       overwrite = FALSE,
                                       verbose = FALSE) {
  # Handle gdal_job with pipeline history
  if (inherits(pipeline, "gdal_job")) {
    if (is.null(pipeline$pipeline)) {
      stop("gdal_job does not have a pipeline history", call. = FALSE)
    }
    pipeline <- pipeline$pipeline
  }

  if (!inherits(pipeline, "gdal_pipeline")) {
    stop("Expected gdal_pipeline or gdal_job with pipeline", call. = FALSE)
  }

  # Check file existence
  if (file.exists(path) && !overwrite) {
    stop("File already exists: ", path,
         " (set overwrite = TRUE to overwrite)", call. = FALSE)
  }

  # Convert pipeline to hybrid gdalcli spec
  spec <- as_gdalcli_spec(pipeline,
                          name = name,
                          description = description,
                          custom_tags = custom_tags)

  # Convert to list for JSON serialization
  spec_list <- gdalcli_spec_to_list(spec)

  # Serialize to JSON
  json_str <- tryCatch({
    yyjsonr::write_json_str(spec_list, pretty = pretty)
  }, error = function(e) {
    stop("Failed to serialize pipeline to JSON: ", conditionMessage(e),
         call. = FALSE)
  })

  # Write to file
  tryCatch({
    writeLines(json_str, path)
  }, error = function(e) {
    stop("Failed to write pipeline file: ", path, "\n",
         "  Error: ", conditionMessage(e), call. = FALSE)
  })

  if (verbose) {
    message("Saved gdalcli pipeline to ", path)
  }

  invisible(path)
}


#' Load GDAL Pipeline from File
#'
#' @description
#' Load a gdal_pipeline from a file. Supports hybrid format (.gdalcli.json)
#' and pure GDALG format (.gdalg.json). Automatically detects the format.
#'
#' @param path Character. Path to pipeline file
#'
#' @return A gdal_pipeline object
#'
#' @details
#' Format detection:
#' - **Hybrid format**: Prefers lossless `r_job_specs` for exact reconstruction
#' - **Pure GDALG**: Falls back to RFC 104 command parsing (lossy)
#' - **Legacy format**: Not supported, gives clear error message
#'
#' @keywords internal
#' @noRd
.gdal_load_pipeline_auto <- function(path) {
  # Check file exists
  if (!file.exists(path)) {
    stop("File not found: ", path, call. = FALSE)
  }

  # Read and parse JSON
  spec <- tryCatch({
    json_text <- readLines(path, warn = FALSE)
    yyjsonr::read_json_str(paste(json_text, collapse = ""))
  }, error = function(e) {
    stop("Failed to parse pipeline JSON file: ", path, "\n",
         "  Error: ", conditionMessage(e), call. = FALSE)
  })

  if (!is.list(spec)) {
    stop("Pipeline JSON must be an object/list", call. = FALSE)
  }

  # Detect format and load
  format <- .gdalcli_detect_format(spec)

  if (format == "hybrid") {
    # Load hybrid format - create gdalcli_spec and convert to pipeline
    tryCatch({
      # Convert loaded list back to pipeline via transpiler
      .gdalcli_spec_to_pipeline(spec)
    }, error = function(e) {
      stop("Failed to reconstruct pipeline from spec: ",
           conditionMessage(e), call. = FALSE)
    })
  } else if (format == "pure_gdalg") {
    # Load pure GDALG format
    tryCatch({
      .gdalcli_spec_to_pipeline(spec)
    }, error = function(e) {
      stop("Failed to reconstruct pipeline from GDALG: ",
           conditionMessage(e), call. = FALSE)
    })
  } else if (format == "legacy") {
    # Legacy format not supported
    stop(
      "File appears to be in legacy .gdalcli.json format (pre-v0.5.0)",
      "\nThis format is no longer supported.",
      "\nPlease regenerate your pipeline files using gdalcli v0.5.0+",
      call. = FALSE
    )
  } else {
    stop(
      "Cannot determine format of ", path,
      "\nExpected hybrid format (gdalg + metadata + r_job_specs) ",
      "or pure GDALG format",
      call. = FALSE
    )
  }
}
