#' GDALCLI Hybrid Specification S3 Class
#'
#' @description
#' Encapsulates the complete hybrid pipeline specification used by gdalcli.
#' A gdalcli_spec combines GDALG with R-specific metadata and full job specs.
#'
#' @details
#' The hybrid format has three components:
#'
#' 1. **gdalg**: Pure GDALG (RFC 104) specification
#' 2. **metadata**: Provenance and pipeline information
#' 3. **r_job_specs**: Full R job state for exact reconstruction
#'
#' The hybrid format preserves both the portable GDALG specification and
#' the R-specific job details needed for exact pipeline reconstruction.
#'
#' @param gdalg A gdalg object or list representing the pure GDALG spec
#' @param metadata Named list of metadata fields
#' @param r_job_specs List of job specifications preserving R state
#'
#' @return A `gdalcli_spec` S3 object
#'
#' @export
new_gdalcli_spec <- function(gdalg,
                             metadata = list(),
                             r_job_specs = list()) {
  # Ensure gdalg is a gdalg object
  if (!inherits(gdalg, "gdalg")) {
    gdalg <- as_gdalg(gdalg)
  }

  structure(
    list(
      gdalg = validate_gdalg(gdalg),
      metadata = metadata,
      r_job_specs = r_job_specs
    ),
    class = c("gdalcli_spec", "list")
  )
}


#' Validate GDALCLI Specification
#'
#' @description
#' Checks that an object is a valid gdalcli_spec.
#' Validates that the gdalg component is valid, metadata is a list,
#' and r_job_specs is a list.
#'
#' @param spec Object to validate
#'
#' @return The spec object invisibly if valid
#'
#' @export
validate_gdalcli_spec <- function(spec) {
  if (!inherits(spec, "gdalcli_spec")) {
    stop("Object must be of class 'gdalcli_spec'", call. = FALSE)
  }

  # Validate gdalg component
  if (!inherits(spec$gdalg, "gdalg")) {
    stop("gdalcli_spec$gdalg must be a gdalg object", call. = FALSE)
  }

  # Validate metadata
  if (!is.list(spec$metadata)) {
    stop("gdalcli_spec$metadata must be a list", call. = FALSE)
  }

  # Validate r_job_specs
  if (!is.list(spec$r_job_specs)) {
    stop("gdalcli_spec$r_job_specs must be a list", call. = FALSE)
  }

  invisible(spec)
}


#' Print GDALCLI Specification
#'
#' @param x A gdalcli_spec object
#' @param ... Additional arguments (unused)
#'
#' @keywords internal
#' @noRd
#' @exportS3Method print gdalcli_spec
print.gdalcli_spec <- function(x, ...) {
  cat("<GDALCLI Hybrid Specification>\n")

  # Print GDALG component summary
  cat("\nGDALG Component:\n")
  cat("  Type:        ", x$gdalg$type, "\n")

  cmd_display <- if (nchar(x$gdalg$command_line) > 60) {
    paste0(strtrim(x$gdalg$command_line, 57), "...")
  } else {
    x$gdalg$command_line
  }
  cat("  Command:     ", cmd_display, "\n")

  # Print metadata summary
  cat("\nMetadata:\n")
  cat("  Pipeline:    ", x$metadata$pipeline_name %||% "(unnamed)", "\n")
  cat("  Version:     ", x$metadata$gdalcli_version %||% "(unknown)", "\n")
  cat("  Created:     ", x$metadata$created_at %||% "(unknown)", "\n")

  custom_tags_count <- length(x$metadata$custom_tags %||% list())
  cat("  Custom tags: ", custom_tags_count, "field(s)\n")

  # Print job specs summary
  job_count <- length(x$r_job_specs)
  cat("\nR Job Specifications:\n")
  cat("  Jobs:        ", job_count, "\n")

  invisible(x)
}


#' Coerce to GDALCLI Specification
#'
#' @description
#' Generic function to convert objects to gdalcli_spec class.
#'
#' @param x Object to coerce
#' @param ... Additional arguments
#'
#' @return A gdalcli_spec object
#'
#' @export
as_gdalcli_spec <- function(x, ...) {
  UseMethod("as_gdalcli_spec")
}


#' Coerce gdal_pipeline to GDALCLI Specification
#'
#' @description
#' Convert a gdal_pipeline to a complete hybrid gdalcli_spec by:
#' 1. Generating the pure GDALG component
#' 2. Building metadata with name, description, and custom tags
#' 3. Extracting full R job specs for lossless reconstruction
#'
#' @param x A gdal_pipeline object
#' @param name Character. Optional pipeline name
#' @param description Character. Optional pipeline description
#' @param custom_tags List. Optional user-defined metadata
#' @param ... Additional arguments (unused)
#'
#' @return A gdalcli_spec object
#'
#' @keywords internal
#' @noRd
#' @exportS3Method as_gdalcli_spec gdal_pipeline
as_gdalcli_spec.gdal_pipeline <- function(x,
                                          name = NULL,
                                          description = NULL,
                                          custom_tags = list(),
                                          ...) {
  if (!inherits(x, "gdal_pipeline")) {
    stop("Expected a gdal_pipeline object", call. = FALSE)
  }

  # Delegate to transpiler function which creates the hybrid spec
  spec_list <- .pipeline_to_gdalcli_spec(x, name = name, description = description, custom_tags = custom_tags)

  # Wrap in S3 class by converting gdalg to S3 object first
  gdalg <- as_gdalg(spec_list$gdalg)

  new_gdalcli_spec(gdalg, spec_list$metadata, spec_list$r_job_specs)
}


#' Convert GDALCLI Specification to List (for JSON serialization)
#'
#' @description
#' Convert a gdalcli_spec S3 object to a plain list suitable for
#' JSON serialization.
#'
#' @param spec A gdalcli_spec object
#'
#' @return A list representing the complete specification
#'
#' @keywords internal
#' @noRd
gdalcli_spec_to_list <- function(spec) {
  validate_gdalcli_spec(spec)

  list(
    gdalg = gdalg_to_list(spec$gdalg),
    metadata = spec$metadata,
    r_job_specs = spec$r_job_specs
  )
}
