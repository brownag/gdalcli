#' Save GDAL Pipeline Using Native GDALG Format Driver
#'
#' @description
#' Saves a gdal_pipeline using GDAL's native GDALG format. This method
#' produces GDALG JSON compatible with GDAL native tools.
#'
#' @param pipeline A gdal_pipeline or gdal_job object with pipeline
#' @param path Character. Output path (typically .gdalg.json)
#' @param overwrite Logical. If TRUE, overwrites existing file
#' @param verbose Logical. If TRUE, prints status messages
#'
#' @return Invisibly returns the path
#'
#' @details
#' This function requires GDAL 3.11 or later with GDALG driver.
#' It produces pure GDALG format suitable for use with GDAL tools.
#'
#' @keywords internal
#' @noRd
.gdal_save_pipeline_native_impl <- function(pipeline,
                                            path,
                                            overwrite = FALSE,
                                            verbose = FALSE) {
  # Version and driver checks are done in the public function
  # (gdal_save_pipeline_native in core-gdalg.R calls gdal_has_gdalg_driver)

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
         " (set overwrite = TRUE to replace)", call. = FALSE)
  }

  # Convert pipeline to gdalg S3 object
  gdalg <- as_gdalg(pipeline)

  # Write pure GDALG file
  gdalg_write(gdalg, path, pretty = TRUE, overwrite = TRUE)

  if (verbose) {
    message("Native GDALG file created: ", path)
  }

  invisible(path)
}
