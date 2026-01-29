# ===================================================================
# GDALCLI Configuration Options
# ===================================================================

#' Retrieve All Current GDALCLI Options
#'
#' Internal helper to get all current gdalcli option values.
#'
#' @return List of all current gdalcli option values
#' @keywords internal
#' @noRd
.get_all_gdalcli_options <- function() {
  list(
    checkpoint = getOption("gdalcli.checkpoint", FALSE),
    checkpoint_dir = getOption("gdalcli.checkpoint_dir", NULL),
    backend = getOption("gdalcli.backend", "auto"),
    verbose = getOption("gdalcli.verbose", FALSE),
    audit_logging = getOption("gdalcli.audit_logging", FALSE),
    stream_out_format = getOption("gdalcli.stream_out_format", NULL)
  )
}

#' Configure GDALCLI Global Options
#'
#' Provides a convenient interface for setting gdalcli configuration options.
#' Options control behavior of pipeline execution, checkpointing, and output.
#'
#' @param checkpoint Logical. Enable/disable automatic checkpointing for pipelines.
#'   When TRUE, pipelines automatically save intermediate results to enable resumption
#'   from failures. Default: FALSE (disabled).
#' @param checkpoint_dir Character. Directory for saving checkpoint files.
#'   Defaults to current working directory if checkpointing enabled and this is NULL.
#'   Example: `"~/gdalcli_checkpoints"`. Ignored if checkpoint = FALSE.
#' @param backend Character. Default execution backend: "processx" (subprocess),
#'   "gdalraster" (C++ bindings), "reticulate" (Python), or "auto" (auto-select).
#'   Default: "auto".
#' @param verbose Logical. Print execution details by default. Default: FALSE.
#' @param audit_logging Logical. Log all job executions. Default: FALSE.
#' @param stream_out_format Character. Default output streaming format:
#'   NULL (no streaming), "text", "raw", "json", or "stdout". Default: NULL.
#'
#' @return Invisibly returns a list of current gdalcli options (before modification).
#'
#' @details
#' # Checkpoint Configuration
#'
#' Checkpoints are **disabled by default** for backward compatibility. Enable them
#' explicitly when you need fault tolerance for long-running pipelines:
#'
#' ```r
#' # Enable checkpoints globally, use current working directory
#' gdalcli_options(checkpoint = TRUE)
#'
#' # Enable checkpoints with custom directory
#' gdalcli_options(
#'   checkpoint = TRUE,
#'   checkpoint_dir = "~/gdalcli_checkpoints"
#' )
#'
#' # Disable checkpoints
#' gdalcli_options(checkpoint = FALSE)
#' ```
#'
#' # Execution Behavior
#'
#' When checkpoints are enabled globally:
#' - Pipelines automatically save intermediate outputs after each step
#' - If interrupted, call the same pipeline with `resume = TRUE` to continue
#' - Checkpoint directory defaults to current working directory
#' - On successful completion, checkpoints are cleaned up automatically
#'
#' # Other Options
#'
#' ```r
#' # Set default execution backend
#' gdalcli_options(backend = "gdalraster")
#'
#' # Enable verbose output and audit logging
#' gdalcli_options(verbose = TRUE, audit_logging = TRUE)
#'
#' # Set default output streaming
#' gdalcli_options(stream_out_format = "json")
#' ```
#'
#' @examples
#' \dontrun{
#' # Check current options
#' gdalcli_options()
#'
#' # Enable checkpoints in custom directory
#' gdalcli_options(
#'   checkpoint = TRUE,
#'   checkpoint_dir = "~/checkpoints/gdalcli"
#' )
#'
#' # Now pipelines will automatically checkpoint
#' pipeline <- gdal_raster_reproject(
#'   input = "large.tif",
#'   dst_crs = "EPSG:4326"
#' ) |>
#'   gdal_raster_convert(output = "output.tif")
#' gdal_job_run(pipeline)  # Automatically checkpoints!
#'
#' # If interrupted, resume with:
#' gdal_job_run(pipeline, resume = TRUE)
#' }
#'
#' @export
gdalcli_options <- function(checkpoint = NULL,
                            checkpoint_dir = NULL,
                            backend = NULL,
                            verbose = NULL,
                            audit_logging = NULL,
                            stream_out_format = NULL) {
  # Store current options for return value
  current_opts <- .get_all_gdalcli_options()

  # Set checkpoint option (opt-in, default is FALSE)
  if (!is.null(checkpoint)) {
    if (!is.logical(checkpoint)) {
      cli::cli_abort("checkpoint must be logical (TRUE/FALSE)")
    }
    options("gdalcli.checkpoint" = checkpoint)
  }

  # Set checkpoint_dir (only meaningful if checkpoint is enabled)
  if (!is.null(checkpoint_dir)) {
    if (!is.character(checkpoint_dir)) {
      cli::cli_abort("checkpoint_dir must be a character string (directory path)")
    }
    options("gdalcli.checkpoint_dir" = checkpoint_dir)
  }

  # If enabling checkpoints without specifying dir, default to current working directory
  if (!is.null(checkpoint) && checkpoint && is.null(checkpoint_dir)) {
    options("gdalcli.checkpoint_dir" = getwd())
  }

  # Set backend option
  if (!is.null(backend)) {
    valid_backends <- c("auto", "processx", "gdalraster", "reticulate")
    if (!backend %in% valid_backends) {
      cli::cli_abort(
        "backend must be one of: {paste(valid_backends, collapse = ', ')}"
      )
    }
    options("gdalcli.backend" = backend)
  }

  # Set verbose option
  if (!is.null(verbose)) {
    if (!is.logical(verbose)) {
      cli::cli_abort("verbose must be logical (TRUE/FALSE)")
    }
    options("gdalcli.verbose" = verbose)
  }

  # Set audit_logging option
  if (!is.null(audit_logging)) {
    if (!is.logical(audit_logging)) {
      cli::cli_abort("audit_logging must be logical (TRUE/FALSE)")
    }
    options("gdalcli.audit_logging" = audit_logging)
  }

  # Set stream_out_format option
  if (!is.null(stream_out_format)) {
    valid_formats <- c(NULL, "text", "raw", "json", "stdout")
    if (!stream_out_format %in% valid_formats) {
      cli::cli_abort(
        "stream_out_format must be one of: NULL, 'text', 'raw', 'json', 'stdout'"
      )
    }
    options("gdalcli.stream_out_format" = stream_out_format)
  }

  # Return current options invisibly
  invisible(current_opts)
}
