#' Extract Explicitly Set Arguments from GDAL Job
#'
#' @description
#' Retrieves the list of arguments that were explicitly set by the user
#' (versus those using system defaults) for a GDAL job.
#'
#' This function uses gdalraster's GDALAlg class `getExplicitlySetArgs()`
#' method, which is available with GDAL 3.12+ (gdalraster 2.2.0+).
#'
#' @param job A `gdal_job` object to inspect
#' @param system_only Logical. If TRUE, filters results to show only
#'   system-level arguments (e.g., "-q", "-quiet"). Default FALSE returns
#'   all explicitly set args.
#'
#' @return Named list of explicitly set arguments and their values.
#'   Returns empty list if the feature is unavailable or no explicit args
#'   were set.
#'
#' @details
#' The distinction between explicitly set and default arguments is valuable for:
#'
#' \enumerate{
#'   \item **Audit Logging**: Recording what the user actually specified
#'   \item **Configuration Introspection**: Understanding configuration state
#'   \item **Reproducibility**: Saving configuration for later replay
#'   \item **Debugging**: Identifying unintended defaults
#' }
#'
#' This capability requires GDAL 3.12+ because earlier versions of the GDAL
#' Options API do not track this distinction.
#'
#' @section Performance:
#' The function caches feature availability to avoid repeated version checks.
#' First call may be slightly slower; subsequent calls use cached result.
#'
#' @section Graceful Degradation:
#' If GDAL < 3.12 or gdalraster binding unavailable:
#'   - Returns empty character vector
#'   - Issues informational warning
#'   - Continues execution normally
#'
#' @examples
#' \dontrun{
#'   # Create a job with explicit arguments
#'   job <- new_gdal_job(
#'     command_path = c("raster", "convert"),
#'     arguments = list(
#'       input = "input.tif",
#'       output = "output.tif",
#'       output_format = "COG",
#'       creation_option = c("COMPRESS=LZW")
#'     )
#'   )
#'
#'   # Get all explicitly set arguments (returns named list)
#'   explicit_args <- gdal_job_get_explicit_args(job)
#'   # Result is a named list like:
#'   # $output_format
#'   # [1] "COG"
#'   # $creation_option
#'   # [1] "COMPRESS=LZW"
#'
#'   # Get only system-level arguments
#'   system_args <- gdal_job_get_explicit_args(job, system_only = TRUE)
#' }
#'
#' @seealso
#' [gdal_job_run_with_audit()] for using explicit args in audit logging,
#' [gdal_capabilities()] to check feature availability
#'
#' @export
gdal_job_get_explicit_args <- function(job, system_only = FALSE) {
  # Validate input
  if (!inherits(job, "gdal_job")) {
    cli::cli_abort(
      c(
        "job must be a gdal_job object",
        "i" = sprintf("Got: %s", paste(class(job), collapse = ", "))
      )
    )
  }

  # Check GDAL version requirement
  if (!gdal_check_version("3.12", op = ">=")) {
    cli::cli_inform(
      c(
        "getExplicitlySetArgs requires GDAL 3.12+",
        "i" = sprintf("Current version: %s", gdalcli:::.gdal_get_version()),
        "i" = "Feature unavailable. Returning empty vector."
      )
    )
    return(character(0))
  }

  # Check feature availability
  if (!gdalcli:::.gdal_has_feature("explicit_args")) {
    cli::cli_inform(
      c(
        "Explicit argument support not available in gdalraster",
        "i" = "Requires gdalraster >= 1.2.0 with Rcpp bindings",
        "i" = "Feature unavailable. Returning empty vector."
      )
    )
    return(character(0))
  }

  # Try to extract explicit args using gdalraster's GDALAlg class
  explicit_args <- tryCatch({
    # Check if job has underlying GDALAlg object
    if (is.null(job$alg) || !inherits(job$alg, "GDALAlg")) {
      cli::cli_warn(
        c(
          "gdal_job missing GDALAlg reference",
          "i" = "Cannot extract explicit arguments"
        )
      )
      return(list())
    }

    # Get explicit args from GDALAlg object
    # GDALAlg$getExplicitlySetArgs() returns a named list
    job$alg$getExplicitlySetArgs()
  }, error = function(e) {
    cli::cli_warn(
      c(
        "Failed to extract explicit arguments from GDAL job",
        "x" = conditionMessage(e)
      )
    )
    list()
  })

  # Apply system_only filter if requested
  # Filter to keep only system-level argument names
  if (system_only && length(explicit_args) > 0) {
    system_markers <- c(
      "quiet", "q",
      "vsicurl_use_head",
      "vsicurl_chunk_size"
    )
    explicit_args <- explicit_args[
      names(explicit_args) %in% system_markers
    ]
  }

  explicit_args
}


#' Create Audit Entry from Explicit Arguments
#'
#' Helper function to create an audit log entry capturing what arguments
#' were explicitly set during GDAL job execution.
#'
#' @param job A `gdal_job` object
#' @param status Status of execution ("pending", "success", "error")
#' @param error_msg Optional error message if status is "error"
#'
#' @return List with audit entry containing:
#'   - timestamp: When audit entry was created
#'   - job_command: The job's command path
#'   - explicit_args: Arguments explicitly set by user
#'   - status: Execution status
#'   - error: Error message (if applicable)
#'   - gdal_version: GDAL version at execution time
#'   - r_version: R version at execution time
#'
#' @keywords internal
#' @examples
#' \dontrun{
#'   job <- new_gdal_job(
#'     command_path = c("raster", "info"),
#'     arguments = list(input = "test.tif")
#'   )
#'   audit_entry <- .create_audit_entry(job, status = "success")
#' }
.create_audit_entry <- function(job, status = "pending", error_msg = NULL) {
  explicit_args <- tryCatch(
    gdal_job_get_explicit_args(job),
    error = function(e) character(0)
  )

  list(
    timestamp = Sys.time(),
    job_command = paste(job$command_path, collapse = " "),
    explicit_args = explicit_args,
    status = status,
    error = error_msg,
    gdal_version = gdalcli:::.gdal_get_version(),
    r_version = paste0(R.version$major, ".", R.version$minor)
  )
}

#' Run GDAL Job with Audit Trail
#'
#' Enhanced version of [gdal_job_run()] that captures explicit arguments
#' in an audit log for reproducibility and debugging.
#'
#' @param job A `gdal_job` object to execute
#' @param ... Additional arguments passed to [gdal_job_run()]
#' @param audit_log Logical. If TRUE, creates audit trail. Default TRUE if
#'   getOption("gdalcli.audit_logging") is TRUE.
#'
#' @return Result from [gdal_job_run()] with audit information attached
#'   as attribute "audit_trail"
#'
#' @details
#' The audit trail captures:
#' - Timestamp of execution
#' - Command and explicit arguments
#' - GDAL version used
#' - R version used
#' - Execution status and any errors
#'
#' Audit trails are stored as attributes on the result object and can be
#' accessed with `attr(result, "audit_trail")`.
#'
#' Audit logging is controlled by `options(gdalcli.audit_logging = TRUE/FALSE)`.
#' When FALSE (default), no audit trail is created even if this function is called.
#'
#' @examples
#' \dontrun{
#'   job <- new_gdal_job(
#'     command_path = c("raster", "info"),
#'     arguments = list(input = "test.tif")
#'   )
#'
#'   # Enable audit logging
#'   options(gdalcli.audit_logging = TRUE)
#'   result <- gdal_job_run_with_audit(job)
#'
#'   # Inspect audit trail
#'   audit <- attr(result, "audit_trail")
#'   cat("Explicit args used:\n")
#'   print(audit$explicit_args)
#' }
#'
#' @export
gdal_job_run_with_audit <- function(job, ..., audit_log = getOption("gdalcli.audit_logging", FALSE)) {
  # Create pre-execution audit entry
  audit_entry <- .create_audit_entry(job, status = "pending")

  # Execute job
  result <- tryCatch({
    gdal_job_run(job, ...)
  }, error = function(e) {
    # Update audit entry with error
    audit_entry$status <<- "error"
    audit_entry$error <<- conditionMessage(e)
    rethrow(e)
  })

  # Update audit entry with success
  audit_entry$status <- "success"

  # Attach audit trail if logging enabled
  if (audit_log && !is.null(result)) {
    attr(result, "audit_trail") <- audit_entry
  }

  result
}

# Re-export necessary utilities
#' @export
gdal_capabilities
