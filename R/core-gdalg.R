#' GDALCLI Pipeline Format Support
#'
#' @description
#' Functions for saving and loading R gdal_pipeline objects in gdalcli's
#' hybrid format. The hybrid format combines RFC 104 GDALG compatibility
#' with R-specific metadata and full job specifications.
#'
#' The gdalcli pipeline format enables:
#' - Pipeline persistence (save/load to disk)
#' - Pipeline sharing and version control
#' - Complex workflow composition
#' - Integration with GDAL command-line tools
#' - Lossless R round-trip serialization
#'
#' @keywords internal

#' Check GDALG Format Driver Availability
#'
#' @description
#' Checks if the GDALG format driver is available in the current GDAL installation.
#' This is required for using `gdal_save_pipeline_native()`.
#'
#' @return Logical TRUE if GDALG driver is available, FALSE otherwise
#'
#' @details
#' The GDALG format driver is available in GDAL 3.11+. This function checks
#' the list of available formats by running `gdal raster convert --formats`.
#'
#' @keywords internal
#' @noRd
.check_gdalg_driver <- function() {
  tryCatch({
    result <- processx::run(
      "gdal",
      c("raster", "convert", "--formats"),
      error_on_status = FALSE
    )

    if (result$status != 0) {
      return(FALSE)
    }

    # Check if GDALG is in the format list
    grepl("GDALG", result$stdout, ignore.case = TRUE)
  }, error = function(e) {
    FALSE
  })
}

#' Check if GDALG Native Serialization is Supported
#'
#' @description
#' Returns TRUE if the current GDAL installation supports native GDALG format
#' driver serialization. This requires GDAL 3.11+ with the GDALG driver.
#'
#' @return Logical indicating if native GDALG support is available
#'
#' @examples
#' \dontrun{
#'   if (gdal_has_gdalg_driver()) {
#'     message("Native GDALG support is available")
#'   }
#' }
#'
#' @export
gdal_has_gdalg_driver <- function() {
  # Check GDAL version (3.11+)
  if (!gdal_check_version("3.11", op = ">=")) {
    return(FALSE)
  }

  # Check driver availability
  .check_gdalg_driver()
}

#' Save GDAL Pipeline Using Native GDALG Format Driver
#'
#' @description
#' Saves a gdal_pipeline using the native GDALG format. This method produces
#' pure GDALG JSON that is compatible with GDAL's GDALG driver (read-only in GDAL 3.11+).
#'
#' @param pipeline A gdal_pipeline or gdal_job object with pipeline
#' @param path Character string specifying output path (typically .gdalg.json)
#' @param overwrite Logical. If TRUE, overwrites existing file
#' @param verbose Logical. If TRUE, prints diagnostic information
#'
#' @return Invisibly returns the path where pipeline was saved
#'
#' @details
#' This function:
#' 1. Converts the R pipeline to a gdalg S3 object with RFC 104 command string
#' 2. Serializes the GDALG specification to JSON format
#' 3. Writes the JSON to the specified file
#'
#' **GDALG Format:**
#' The GDALG driver in GDAL 3.11+ is read-only. It can load GDALG JSON files
#' but cannot write them directly. GDALG JSON is generated using R's yyjsonr
#' library. The format is well-documented (RFC 104) and stable.
#'
#' **Output Compatibility:**
#' Generated GDALG files are:
#' - RFC 104 compliant
#' - Loadable by GDAL 3.11+ GDALG driver
#' - Readable by gdalg_read()
#' - Compatible with other GDALG-aware tools
#'
#' @examples
#' \dontrun{
#' pipeline <- gdal_raster_reproject(input = "in.tif",
#'                                   dst_crs = "EPSG:32632") |>
#'   gdal_raster_scale(src_min = 0, src_max = 100)
#'
#' if (gdal_has_gdalg_driver()) {
#'   # Save as native GDALG format
#'   gdal_save_pipeline_native(pipeline, "workflow.gdalg.json")
#' }
#' }
#'
#' @export
gdal_save_pipeline_native <- function(pipeline,
                                      path,
                                      overwrite = FALSE,
                                      verbose = FALSE) {
  # Delegate to implementation in core-gdalg-native.R
  tryCatch({
    .gdal_save_pipeline_native_impl(
      pipeline,
      path,
      overwrite = overwrite,
      verbose = verbose
    )
  }, error = function(e) {
    cli::cli_abort(c(
      "Failed to save native GDALG pipeline",
      "x" = conditionMessage(e)
    ))
  })
}

#' Save GDAL Pipeline to gdalcli Pipeline Format
#'
#' @description
#' Saves a gdal_pipeline object to a gdalcli pipeline JSON file. The gdalcli pipeline
#' format is a JSON-based pipeline definition that can be saved to disk and loaded later
#' for execution.
#'
#' @param pipeline A gdal_pipeline or gdal_job object with pipeline
#' @param path Character string specifying the path to save to (typically .gdalcli.json)
#' @param name Character string. Optional name for the pipeline
#' @param description Character string. Optional description of the pipeline
#' @param custom_tags List. Optional user-defined metadata to include
#' @param pretty Logical. If TRUE (default), formats JSON with indentation for readability
#' @param overwrite Logical. If TRUE, overwrites existing file
#' @param verbose Logical. If TRUE, prints diagnostic information
#'
#' @return Invisibly returns the path where the pipeline was saved
#'
#' @details
#' This function saves the pipeline in gdalcli's hybrid JSON format, which combines:
#' - A pure GDALG specification (RFC 104) for GDAL compatibility
#' - R-specific metadata/tags for gdalcli features
#' - Full job specifications for lossless round-tripping
#'
#' The saved gdalcli pipeline file can be:
#' - Executed with gdal_job_run()
#' - Loaded back into R with gdal_load_pipeline()
#' - Shared with colleagues or version controlled
#' - Used in other gdalcli-compatible tools
#'
#' **Note on File Formats:**
#' This function produces `.gdalcli.json` (hybrid) files. For pure GDALG (RFC 104)
#' output suitable for `gdal raster pipeline`, use [gdal_save_pipeline_native()]
#' or [gdalg_write()], which typically use the `.gdalg.json` extension.
#'
#' @examples
#' \dontrun{
#' pipeline <- gdal_raster_reproject(input = "in.tif", dst_crs = "EPSG:32632") |>
#'   gdal_raster_convert(output = "out.tif")
#'
#' # Save to gdalcli format (.gdalcli.json)
#' gdal_save_pipeline(pipeline, "workflow.gdalcli.json")
#'
#' # Load and execute later
#' loaded <- gdal_load_pipeline("workflow.gdalcli.json")
#' gdal_job_run(loaded)
#' }
#'
#' @export
gdal_save_pipeline <- function(pipeline,
                                path,
                                name = NULL,
                                description = NULL,
                                custom_tags = list(),
                                pretty = TRUE,
                                overwrite = FALSE,
                                verbose = FALSE) {
  # Delegate to modular I/O function
  .gdal_save_pipeline_hybrid(
    pipeline,
    path,
    name = name,
    description = description,
    custom_tags = custom_tags,
    pretty = pretty,
    overwrite = overwrite,
    verbose = verbose
  )
}

#' Load GDAL Pipeline from gdalcli Pipeline Format
#'
#' @description
#' Loads a gdal_pipeline from a gdalcli pipeline JSON file. gdalcli pipeline files
#' can be created by gdal_save_pipeline() and contain pipeline definitions that
#' can be executed.
#'
#' @param path Character string specifying the path to the gdalcli pipeline file
#'
#' @return A gdal_pipeline object that can be executed or further modified
#'
#' @details
#' Loaded pipelines can be:
#' - Executed with gdal_job_run()
#' - Modified by piping new jobs
#' - Rendered to different formats (native, shell script, etc.)
#' - Saved again with gdal_save_pipeline()
#'
#' @examples
#' \dontrun{
#' # Load a previously saved pipeline
#' pipeline <- gdal_load_pipeline("workflow.gdalcli.json")
#'
#' # Execute it
#' gdal_job_run(pipeline)
#'
#' # Or extend it with additional operations
#' extended <- pipeline |>
#'   gdal_raster_scale(src_min = 0, src_max = 100)
#' }
#'
#' @export
gdal_load_pipeline <- function(path) {
  # Delegate to modular I/O function with auto-detection
  .gdal_load_pipeline_auto(path)
}
