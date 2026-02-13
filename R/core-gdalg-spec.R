#' GDALG Specification S3 Class
#'
#' @description
#' Encapsulates a pure RFC 104 GDALG (GDAL Algorithm) specification.
#' A gdalg object represents a GDAL pipeline defined as a command string,
#' ready for use with GDAL tools or serialization to files.
#'
#' @details
#' GDALG is GDAL's standard format for expressing streaming pipeline operations.
#' It uses RFC 104 command string syntax with step delimiters.
#'
#' The gdalg format is:
#' - **Portable**: Can be used with any GDAL tool that supports GDALG
#' - **Minimal**: Contains only the RFC 104 command specification
#' - **Standardized**: Compatible with GDAL tools and APIs
#'
#' @param command_line Character string. RFC 104 pipeline command.
#' @param type Character string. Always "gdal_streamed_alg" for valid specs.
#' @param relative_paths Logical. If TRUE (default), paths relative to file.
#'
#' @return A `gdalg` S3 object representing the specification.
#'
#' @export
new_gdalg <- function(command_line,
                      type = "gdal_streamed_alg",
                      relative_paths = TRUE) {
  structure(
    list(
      type = type,
      command_line = command_line,
      relative_paths_relative_to_this_file = relative_paths
    ),
    class = c("gdalg", "list")
  )
}


#' Validate GDALG Specification
#'
#' @description
#' Checks that an object is a valid GDALG specification.
#' Validates required fields and ensures RFC 104 compliance.
#'
#' @param gdalg Object to validate
#'
#' @return The gdalg object invisibly if valid
#'
#' @export
validate_gdalg <- function(gdalg) {
  if (!inherits(gdalg, "gdalg")) {
    stop("Object must be of class 'gdalg'", call. = FALSE)
  }

  if (is.null(gdalg$type) || gdalg$type != "gdal_streamed_alg") {
    stop("gdalg$type must be 'gdal_streamed_alg'", call. = FALSE)
  }

  if (is.null(gdalg$command_line) || !is.character(gdalg$command_line)) {
    stop("gdalg$command_line must be a character string", call. = FALSE)
  }

  if (length(gdalg$command_line) != 1) {
    stop("gdalg$command_line must be a single character string", call. = FALSE)
  }

  invisible(gdalg)
}


#' Print GDALG Specification
#'
#' @param x A gdalg object
#' @param ... Additional arguments (unused)
#'
#' @keywords internal
#' @noRd
#' @exportS3Method print gdalg
print.gdalg <- function(x, ...) {
  cat("<GDALG RFC 104 Specification>\n")
  cat("Type:        ", x$type, "\n")

  # Truncate long command lines for display
  cmd_display <- if (nchar(x$command_line) > 70) {
    paste0(strtrim(x$command_line, 67), "...")
  } else {
    x$command_line
  }
  cat("Command:     ", cmd_display, "\n")

  cat("Relative:    ", x$relative_paths_relative_to_this_file, "\n")

  invisible(x)
}


#' Coerce to GDALG Specification
#'
#' @description
#' Generic function to convert objects to gdalg class.
#'
#' @param x Object to coerce
#' @param ... Additional arguments
#'
#' @return A gdalg object
#'
#' @export
as_gdalg <- function(x, ...) {
  UseMethod("as_gdalg")
}


#' Coerce gdal_pipeline to GDALG
#'
#' @description
#' Convert a gdal_pipeline to a pure GDALG specification by
#' transpiling it to an RFC 104 command string.
#'
#' @param x A gdal_pipeline object
#' @param ... Additional arguments (unused)
#'
#' @return A gdalg object
#' @keywords internal
#' @noRd
#' @exportS3Method as_gdalg gdal_pipeline
as_gdalg.gdal_pipeline <- function(x, ...) {
  if (!inherits(x, "gdal_pipeline")) {
    stop("Expected a gdal_pipeline object", call. = FALSE)
  }

  # Delegate to transpiler function to generate GDALG spec
  # This returns a plain list, we'll wrap it in the S3 class
  gdalg_spec <- .pipeline_to_gdalg_spec(x)

  # Wrap in gdalg S3 class
  new_gdalg(
    command_line = gdalg_spec$command_line,
    type = gdalg_spec$type,
    relative_paths = gdalg_spec$relative_paths_relative_to_this_file
  )
}


#' Coerce gdal_job to GDALG
#'
#' @description
#' Convert a gdal_job to a pure GDALG specification.
#' If the job has an embedded pipeline (from pipe composition), that pipeline
#' is converted. Otherwise, a minimal single-job pipeline is created.
#'
#' @param x A gdal_job object
#' @param ... Additional arguments (unused)
#'
#' @return A gdalg object
#' @keywords internal
#' @noRd
#' @exportS3Method as_gdalg gdal_job
as_gdalg.gdal_job <- function(x, ...) {
  if (!inherits(x, "gdal_job")) {
    stop("Expected a gdal_job object", call. = FALSE)
  }

  # If the job has an embedded pipeline, convert that
  if (!is.null(x$pipeline)) {
    return(as_gdalg(x$pipeline))
  }

  # Otherwise, create a minimal single-job pipeline and convert it
  pipeline <- new_gdal_pipeline(list(x))
  as_gdalg(pipeline)
}


#' Coerce List to GDALG
#'
#' @description
#' Convert a plain list representing a GDALG spec to a gdalg object.
#' The list must have 'type' and 'command_line' fields.
#'
#' @param x A list with GDALG structure
#' @param ... Additional arguments (unused)
#'
#' @return A gdalg object
#' @keywords internal
#' @noRd
#' @exportS3Method as_gdalg list
as_gdalg.list <- function(x, ...) {
  if (!is.list(x)) {
    stop("Input must be a list", call. = FALSE)
  }

  if (is.null(x$type) || is.null(x$command_line)) {
    stop("List must contain 'type' and 'command_line' fields", call. = FALSE)
  }

  gdalg <- new_gdalg(
    command_line = x$command_line,
    type = x$type,
    relative_paths = x$relative_paths_relative_to_this_file %||% TRUE
  )

  validate_gdalg(gdalg)
  gdalg
}


#' Convert GDALG to List (for JSON serialization)
#'
#' @description
#' Convert a gdalg S3 object back to a plain list for JSON serialization.
#'
#' @param gdalg A gdalg object
#'
#' @return A list representing the GDALG specification
#'
#' @keywords internal
#' @noRd
gdalg_to_list <- function(gdalg) {
  validate_gdalg(gdalg)

  list(
    type = gdalg$type,
    command_line = gdalg$command_line,
    relative_paths_relative_to_this_file = gdalg$relative_paths_relative_to_this_file
  )
}
