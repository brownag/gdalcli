#' GDALG Pipeline Format Support
#'
#' @description
#' Functions for converting between R gdal_pipeline objects and GDAL's abstract
#' pipeline format (GDALG). GDALG files are JSON-based pipeline definitions
#' that can be saved, loaded, and chained together.
#'
#' The GDALG format enables:
#' - Pipeline persistence (save/load to disk)
#' - Pipeline sharing and version control
#' - Complex workflow composition
#' - Integration with GDAL command-line tools
#'
#' @keywords internal

# ============================================================================
# GDALG JSON Structure and Conversion
# ============================================================================

#' Convert gdal_job to GDALG Step Definition
#'
#' @description
#' Internal function that converts a single gdal_job to a GDALG step definition.
#'
#' @param job A gdal_job object
#' @param step_number Integer index of the step in the pipeline
#'
#' @return A list representing a GDALG step definition
#'
#' @keywords internal
#' @noRd
.job_to_gdalg_step <- function(job, step_number) {
  # Determine step type from command_path
  cmd_path <- job$command_path
  if (length(cmd_path) > 0 && cmd_path[1] == "gdal") {
    cmd_path <- cmd_path[-1]
  }

  if (length(cmd_path) < 2) {
    rlang::abort(sprintf("Invalid job command path"))
  }

  operation <- cmd_path[2]  # e.g., "reproject", "convert"

  # Determine step type based on operation
  step_type <- switch(operation,
    "info" = "read",
    "convert" = "write",
    "create" = "write",
    "tile" = "write",
    operation  # Use operation as step type by default
  )

  # Build step object
  step <- list(
    type = step_type,
    name = sprintf("%s_%d", step_type, step_number),
    operation = operation
  )

  # Add positional arguments (input/output)
  if (!is.null(job$arguments$input)) {
    step$input <- job$arguments$input
  }
  if (!is.null(job$arguments$output)) {
    step$output <- job$arguments$output
  }

  # Add options (non-positional arguments)
  options <- list()
  skip_args <- c("input", "output", "pipeline", "input_format",
                  "output_format", "creation_option", "layer_creation_option")

  for (arg_name in names(job$arguments)) {
    if (!arg_name %in% skip_args) {
      arg_val <- job$arguments[[arg_name]]
      if (!is.null(arg_val)) {
        options[[arg_name]] <- arg_val
      }
    }
  }

  if (length(options) > 0) {
    step$options <- options
  }

  step
}

#' Convert gdal_pipeline to GDALG JSON
#'
#' @description
#' Internal function that converts a gdal_pipeline object to a GDALG JSON
#' list structure (before serialization).
#'
#' @param pipeline A gdal_pipeline object
#'
#' @return A list representing the complete GDALG structure
#'
#' @keywords internal
#' @noRd
.pipeline_to_gdalg <- function(pipeline) {
  if (!inherits(pipeline, "gdal_pipeline")) {
    rlang::abort("Expected gdal_pipeline object")
  }

  # Convert each job to a GDALG step
  steps <- list()
  for (i in seq_along(pipeline$jobs)) {
    job <- pipeline$jobs[[i]]
    step <- .job_to_gdalg_step(job, i)
    steps[[i]] <- step
  }

  # Build GDALG structure
  gdalg <- list(
    gdalVersion = NA_character_,  # Could be filled in if GDAL version is available
    steps = steps
  )

  # Add optional metadata if pipeline has name/description
  if (!is.null(pipeline$name)) {
    gdalg$name <- pipeline$name
  }
  if (!is.null(pipeline$description)) {
    gdalg$description <- pipeline$description
  }

  gdalg
}

#' Convert GDALG JSON to gdal_pipeline
#'
#' @description
#' Internal function that converts a GDALG JSON structure to a gdal_pipeline object.
#'
#' @param gdalg A list representing a GDALG structure (from yyjsonr::read_json_file)
#'
#' @return A gdal_pipeline object
#'
#' @keywords internal
#' @noRd
.gdalg_to_pipeline <- function(gdalg) {
  if (!is.list(gdalg)) {
    rlang::abort("GDALG must be a list")
  }

  if (is.null(gdalg$steps)) {
    rlang::abort("GDALG must contain a 'steps' array")
  }

  # yyjsonr preserves array structure as list
  # Handle both list (standard) and data.frame (edge case from other sources)
  steps_list <- if (is.data.frame(gdalg$steps)) {
    lapply(seq_len(nrow(gdalg$steps)), function(i) {
      as.list(gdalg$steps[i, ])
    })
  } else if (is.list(gdalg$steps)) {
    gdalg$steps
  } else {
    rlang::abort("steps must be an array")
  }

  # Convert each GDALG step to a gdal_job
  jobs <- list()
  for (i in seq_along(steps_list)) {
    step <- steps_list[[i]]
    job <- .gdalg_step_to_job(step, i)
    jobs[[i]] <- job
  }

  # Create pipeline
  pipeline <- new_gdal_pipeline(
    jobs = jobs,
    name = gdalg$name,
    description = gdalg$description
  )

  pipeline
}

#' Convert GDALG Step to gdal_job
#'
#' @description
#' Internal function that converts a single GDALG step to a gdal_job object.
#'
#' @param step A list representing a GDALG step
#' @param step_number Integer index of the step
#'
#' @return A gdal_job object
#'
#' @keywords internal
#' @noRd
.gdalg_step_to_job <- function(step, step_number) {
  # Determine command path from step type and operation
  step_type <- step$type %||% "unknown"
  operation <- step$operation %||% step_type

  # Most operations are raster-based unless explicitly marked as vector
  # This is a heuristic - ideally the GDALG would specify the type
  cmd_type <- if (grepl("vector|convert|rasterize", operation)) "vector" else "raster"

  command_path <- c(cmd_type, operation)

  # Build arguments from step - only include arguments that were actually set
  arguments <- list()

  # Add positional arguments (only if present in step)
  if (!is.null(step$input) && !is.na(step$input)) {
    arguments$input <- step$input
  }
  if (!is.null(step$output) && !is.na(step$output)) {
    arguments$output <- step$output
  }

  # Add optional arguments from options
  # Only include options that have non-NA values
  if (!is.null(step$options) && is.list(step$options)) {
    for (opt_name in names(step$options)) {
      opt_val <- step$options[[opt_name]]
      # Skip NA values - these are placeholders from JSON parsing
      if (!is.null(opt_val) && !is.na(opt_val)) {
        arguments[[opt_name]] <- opt_val
      }
    }
  }

  # Create job
  job <- new_gdal_job(
    command_path = command_path,
    arguments = arguments
  )

  job
}

# ============================================================================
# Public Functions: Save and Load Pipelines
# ============================================================================

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

#' Build Pipeline String for GDALG Export (Native)
#'
#' @description
#' Internal function that builds a pipeline command string for GDAL's native
#' GDALG format driver. The pipeline string excludes the final write step,
#' which will be added by the export function with --output-format GDALG.
#'
#' @param pipeline A gdal_pipeline object
#'
#' @return Character string representing the pipeline (without final write)
#'
#' @keywords internal
#' @noRd
.build_pipeline_for_gdalg_export <- function(pipeline) {
  if (length(pipeline$jobs) == 0) {
    cli::cli_abort("Cannot export empty pipeline")
  }

  # Use existing .build_pipeline_from_jobs but exclude final write step if present
  jobs_to_render <- pipeline$jobs

  # Check if last job is a write operation (convert, create, tile)
  last_job <- jobs_to_render[[length(jobs_to_render)]]
  cmd_path <- last_job$command_path
  if (length(cmd_path) > 0 && cmd_path[1] == "gdal") {
    cmd_path <- cmd_path[-1]
  }

  last_operation <- if (length(cmd_path) >= 2) cmd_path[2] else ""

  # If last operation is write-like, exclude it
  # The export function will add its own write step with --output-format GDALG
  if (last_operation %in% c("convert", "create", "tile")) {
    jobs_to_render <- jobs_to_render[-length(jobs_to_render)]
  }

  # Pipeline must have at least one operation after removing write steps
  if (length(jobs_to_render) == 0) {
    cli::cli_abort("Pipeline must have at least one operation (cannot be write-only)")
  }

  # Build pipeline string from remaining jobs
  .build_pipeline_from_jobs(jobs_to_render)
}

#' Save GDAL Pipeline Using Native GDALG Format Driver
#'
#' @description
#' Saves a gdal_pipeline using GDAL's native GDALG format. This method produces
#' GDALG JSON that is compatible with GDAL's native pipeline format, ensuring
#' maximum compatibility with other GDAL tools and future versions.
#'
#' @param pipeline A gdal_pipeline or gdal_job object with pipeline
#' @param path Character string specifying output path (typically .gdalg.json)
#' @param overwrite Logical. If TRUE, overwrites existing file
#' @param verbose Logical. If TRUE, prints execution details
#'
#' @return Invisibly returns the path where pipeline was saved
#'
#' @details
#' This function requires GDAL 3.11 or later with the GDALG format driver.
#' It produces GDALG JSON format that can be loaded by GDAL's native tools.
#'
#' The native GDALG format provides:
#' - Compatibility with GDAL Python/C++ APIs
#' - Full GDAL version metadata
#' - Recognition by other GDAL tools
#'
#' @examples
#' \dontrun{
#' pipeline <- gdal_raster_reproject(input = "in.tif", dst_crs = "EPSG:32632") |>
#'   gdal_raster_convert(output = "out.tif")
#'
#' if (gdal_has_gdalg_driver()) {
#'   gdal_save_pipeline_native(pipeline, "workflow.gdalg.json")
#' }
#' }
#'
#' @export
gdal_save_pipeline_native <- function(pipeline,
                                       path,
                                       overwrite = FALSE,
                                       verbose = FALSE) {
  # Version check
  if (!gdal_check_version("3.11", op = ">=")) {
    cli::cli_abort(
      c(
        "Native GDALG format requires GDAL 3.11 or later",
        "i" = "Current GDAL version does not support GDALG format driver",
        "i" = "Use gdal_save_pipeline() for custom JSON format (works with any GDAL version)"
      )
    )
  }

  # Verify GDALG driver availability
  if (!.check_gdalg_driver()) {
    cli::cli_abort(
      c(
        "GDALG format driver not found in current GDAL installation",
        "i" = "Run 'gdal raster convert --formats' to verify available formats",
        "i" = "Use gdal_save_pipeline() as fallback"
      )
    )
  }

  # Handle gdal_job with pipeline history
  if (inherits(pipeline, "gdal_job")) {
    if (is.null(pipeline$pipeline)) {
      cli::cli_abort("gdal_job does not have a pipeline history")
    }
    pipeline <- pipeline$pipeline
  }

  if (!inherits(pipeline, "gdal_pipeline")) {
    cli::cli_abort("pipeline must be a gdal_pipeline or gdal_job with pipeline")
  }

  # Check file existence
  if (file.exists(path) && !overwrite) {
    cli::cli_abort(
      c(
        "Output file already exists: {path}",
        "i" = "Set overwrite = TRUE to replace"
      )
    )
  }

  # For native GDALG, we use GDAL-compatible JSON serialization
  # (GDALG driver doesn't support writing, so we use JSON format)
  gdalg <- .pipeline_to_gdalg(pipeline)

  # Serialize to JSON using yyjsonr with auto_unbox to avoid wrapping scalars in arrays
  opts <- yyjsonr::opts_write_json(pretty = TRUE, auto_unbox = TRUE)
  yyjsonr::write_json_file(gdalg, path, opts = opts)

  if (!file.exists(path)) {
    cli::cli_abort("Failed to write GDALG file")
  }

  if (verbose) {
    cli::cli_alert_success("Native GDALG file created: {path}")
  }

  invisible(path)
}

#' Save GDAL Pipeline to GDALG Format
#'
#' @description
#' Saves a gdal_pipeline object to a GDALG JSON file. GDALG is GDAL's abstract
#' pipeline format, which can be saved to disk and loaded later for execution.
#'
#' @param pipeline A gdal_pipeline or gdal_job object with pipeline
#' @param path Character string specifying the path to save to (typically .gdalg.json)
#' @param pretty Logical. If TRUE (default), formats JSON with indentation for readability
#' @param method Character string: "auto" (default), "native", or "json"
#'   - "auto": Uses native GDALG driver if GDAL 3.11+ with driver available, else custom JSON
#'   - "native": Forces native GDALG driver (requires GDAL 3.11+)
#'   - "json": Forces custom JSON serialization
#' @param overwrite Logical. If TRUE, overwrites existing file (used with method="native")
#' @param verbose Logical. If TRUE, prints diagnostic information
#'
#' @return Invisibly returns the path where the pipeline was saved
#'
#' @details
#' This function supports two serialization methods:
#'
#' **Method: "json" (Custom JSON)**
#' - Works with any GDAL version
#' - Fast serialization (direct write)
#' - gdalcli-specific format
#'
#' **Method: "native" (GDALG Format)**
#' - Requires GDAL 3.11+ with GDALG driver
#' - Uses GDAL-compatible JSON serialization
#' - Universal GDAL compatibility
#' - Full GDAL metadata
#'
#' **Method: "auto" (Recommended)**
#' - Automatically selects the best method for your system
#' - Uses native if available, falls back to JSON
#'
#' The saved GDALG file can be:
#' - Executed with GDAL command-line tools
#' - Loaded back into R with gdal_load_pipeline()
#' - Shared with colleagues or version controlled
#' - Used in other GDAL-compatible tools
#'
#' @examples
#' \dontrun{
#' pipeline <- gdal_raster_reproject(input = "in.tif", dst_crs = "EPSG:32632") |>
#'   gdal_raster_convert(output = "out.tif")
#'
#' # Save to file (auto-detects best method)
#' gdal_save_pipeline(pipeline, "workflow.gdalg.json")
#'
#' # Force native GDALG driver
#' gdal_save_pipeline(pipeline, "workflow_native.gdalg.json", method = "native")
#'
#' # Force custom JSON
#' gdal_save_pipeline(pipeline, "workflow_json.gdalg.json", method = "json")
#'
#' # Load and execute later
#' loaded <- gdal_load_pipeline("workflow.gdalg.json")
#' gdal_job_run(loaded)
#' }
#'
#' @export
gdal_save_pipeline <- function(pipeline,
                                path,
                                pretty = TRUE,
                                method = c("auto", "native", "json"),
                                overwrite = FALSE,
                                verbose = FALSE) {
  method <- match.arg(method)

  # Auto-detect best method
  if (method == "auto") {
    if (gdal_has_gdalg_driver()) {
      method <- "native"
      if (verbose) {
        cli::cli_alert_info("Using native GDALG format driver")
      }
    } else {
      method <- "json"
      if (verbose) {
        cli::cli_alert_info("Using custom JSON serialization")
      }
    }
  }

  # Dispatch to appropriate method
  if (method == "native") {
    return(gdal_save_pipeline_native(
      pipeline = pipeline,
      path = path,
      overwrite = overwrite,
      verbose = verbose
    ))
  }

  # Method: "json" - Original custom JSON implementation
  # Handle gdal_job with pipeline history
  if (inherits(pipeline, "gdal_job")) {
    if (is.null(pipeline$pipeline)) {
      rlang::abort("gdal_job does not have a pipeline history")
    }
    pipeline <- pipeline$pipeline
  }

  if (!inherits(pipeline, "gdal_pipeline")) {
    rlang::abort("pipeline must be a gdal_pipeline or gdal_job with pipeline")
  }

  # Convert pipeline to GDALG format
  gdalg <- .pipeline_to_gdalg(pipeline)

  # Serialize to JSON using yyjsonr with auto_unbox to avoid wrapping scalars in arrays
  opts <- yyjsonr::opts_write_json(pretty = pretty, auto_unbox = TRUE)
  yyjsonr::write_json_file(gdalg, path, opts = opts)

  if (!file.exists(path)) {
    rlang::abort(sprintf("Failed to write pipeline to %s", path))
  }

  invisible(path)
}

#' Load GDAL Pipeline from GDALG Format
#'
#' @description
#' Loads a gdal_pipeline from a GDALG JSON file. GDALG files can be created by
#' gdal_save_pipeline(), GDAL command-line tools, or manually.
#'
#' @param path Character string specifying the path to the GDALG file
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
#' pipeline <- gdal_load_pipeline("workflow.gdalg.json")
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
  # Check file exists
  if (!file.exists(path)) {
    rlang::abort(sprintf("File not found: %s", path))
  }

  # Parse JSON using yyjsonr with options to preserve array structure
  tryCatch({
    opts <- yyjsonr::opts_read_json(arr_of_objs_to_df = FALSE)
    gdalg <- yyjsonr::read_json_file(path, opts = opts)
  }, .error = function(e) {
    rlang::abort(c(
      sprintf("Failed to parse GDALG file: %s", path),
      "x" = conditionMessage(e)
    ))
  })

  # Convert GDALG to pipeline
  tryCatch({
    pipeline <- .gdalg_to_pipeline(gdalg)
  }, .error = function(e) {
    rlang::abort(c(
      "Failed to convert GDALG to pipeline",
      "x" = conditionMessage(e)
    ))
  })

  pipeline
}
