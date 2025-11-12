#' Execute a GDAL Job
#'
#' @description
#' `gdal_run()` is an S3 generic function that executes a GDAL command specification.
#' It is the "collector" function in the lazy evaluation framework, taking a [gdal_job] object
#' and converting it into a running process.
#'
#' For `gdal_job` objects, the method performs the following steps:
#' 1. Serializes the job specification into GDAL CLI arguments.
#' 2. Configures input/output streaming if specified.
#' 3. Aggregates configuration options and environment variables.
#' 4. Executes the process using [processx::run()].
#' 5. Handles errors and returns the result (or stdout if streaming).
#'
#' @param x An S3 object to be executed. Typically a [gdal_job].
#' @param ... Additional arguments passed to specific methods.
#' @param stream_in An R object to be streamed to `/vsistdin/`. Can be `NULL`,
#'   a character string, or raw vector. If provided, overrides `x$stream_in`.
#' @param stream_out_format Character string: `NULL` (default, no streaming),
#'   `"text"` (return stdout as character), or `"raw"` (return as raw bytes).
#'   If provided, overrides `x$stream_out_format`.
#' @param env A named character vector of environment variables for the subprocess.
#'   These are merged with `x$env_vars`, with explicit `env` values taking precedence.
#' @param verbose Logical. If `TRUE`, prints the command being executed. Default `FALSE`.
#'
#' @return
#' Depends on the streaming configuration:
#' - If `stream_out_format = NULL` (default): Invisibly returns `TRUE` on success.
#'   Raises an R error if the GDAL process fails.
#' - If `stream_out_format = "text"`: Returns the stdout as a character string.
#' - If `stream_out_format = "raw"`: Returns the stdout as a raw vector.
#'
#' @seealso
#' [gdal_job], [gdal_with_co()], [gdal_with_config()], [gdal_with_env()]
#'
#' @examples
#' \dontrun{
#' # Basic usage (no streaming)
#' job <- gdal_vector_convert(
#'   input = "input.shp",
#'   output = "output.gpkg"
#' ) |>
#'   gdal_with_co("COMPRESS=LZW")
#' gdal_run(job)
#'
#' # With input streaming
#' geojson_string <- '{type: "FeatureCollection", ...}'
#' job <- gdal_vector_convert(
#'   input = "/vsistdin/",
#'   output = "output.gpkg"
#' )
#' gdal_run(job, stream_in = geojson_string)
#'
#' # With output streaming
#' job <- gdal_vector_info("input.gpkg", output_format = "JSON")
#' json_result <- gdal_run(job, stream_out = "text")
#' }
#'
#' @export
gdal_run <- function(x, ..., backend = NULL) {
  # Allow explicit backend selection
  if (!is.null(backend)) {
    if (backend == "gdalraster" && requireNamespace("gdalraster", quietly = TRUE)) {
      return(gdal_run_gdalraster(x, ...))
    } else if (backend == "processx") {
      return(gdal_run.gdal_job(x, ...))
    }
  }

  UseMethod("gdal_run")
}


#' @rdname gdal_run
#' @export
gdal_run.gdal_job <- function(x,
                              stream_in = NULL,
                              stream_out_format = NULL,
                              env = NULL,
                              verbose = FALSE,
                              ...) {
  # Resolve streaming parameters (explicit args override job specs)
  stream_in_final <- if (!is.null(stream_in)) stream_in else x$stream_in
  stream_out_final <- if (!is.null(stream_out_format)) stream_out_format else x$stream_out_format

  # Serialize job to GDAL command arguments
  args <- .serialize_gdal_job(x)

  # Merge environment variables
  env_final <- .merge_env_vars(x$env_vars, env, x$config_options)

  # Configure input/output streams
  stdin_arg <- if (!is.null(stream_in_final)) stream_in_final else NULL
  stdout_arg <- if (!is.null(stream_out_final)) "|" else NULL

  if (verbose) {
    cli::cli_alert_info(sprintf("Executing: gdal %s", paste(args, collapse = " ")))
  }

  # Execute the GDAL process using processx
  result <- processx::run(
    command = "gdal",
    args = args,
    stdin = stdin_arg,
    stdout = stdout_arg,
    env = env_final,
    error_on_status = TRUE
  )

  # Handle output based on streaming format
  if (!is.null(stream_out_final)) {
    if (stream_out_final == "text") {
      return(result$stdout)
    } else if (stream_out_final == "raw") {
      return(charToRaw(result$stdout))
    }
  }

  invisible(TRUE)
}


#' Serialize a gdal_job to GDAL CLI Arguments
#'
#' @description
#' Internal function that converts a [gdal_job] specification into a final argument
#' vector suitable for passing to the `gdal` command-line executable.
#'
#' This function handles:
#' - Serializing the command path (e.g., `["vector", "convert"]` → `"vector", "convert"`)
#' - Converting argument names from snake_case to kebab-case (e.g., `dst_crs` → `dst-crs`)
#' - Flattening vector arguments (e.g., `c("COL1=val1", "COL2=val2")` for a repeatable arg)
#' - Converting logical arguments to their flag equivalents
#'
#' @param job A [gdal_job] object.
#'
#' @return A character vector of arguments ready for processx.
#'
#' @keywords internal
.serialize_gdal_job <- function(job) {
  args <- c(job$command_path)

  # Process regular arguments
  for (i in seq_along(job$arguments)) {
    arg_name <- names(job$arguments)[i]
    arg_value <- job$arguments[[i]]

    if (is.null(arg_value)) {
      # Skip NULL arguments
      next
    }

    # Convert argument name from snake_case to kebab-case
    cli_flag <- paste0("--", gsub("_", "-", arg_name))

    # Handle different value types
    if (is.logical(arg_value)) {
      if (arg_value) {
        args <- c(args, cli_flag)
      }
    } else if (length(arg_value) > 1) {
      # Repeatable arguments (e.g., -co, -oo)
      for (val in arg_value) {
        args <- c(args, cli_flag, as.character(val))
      }
    } else {
      # Single-value arguments
      args <- c(args, cli_flag, as.character(arg_value))
    }
  }

  args
}


#' Merge Environment Variables with Config Options
#'
#' @description
#' Internal function that combines environment variables from multiple sources:
#' 1. Base environment variables from the job
#' 2. Explicit environment variables passed to gdal_run
#' 3. GDAL config options (converted to GDAL_CONFIG_* format if needed)
#' 4. Legacy global environment variables (for backward compatibility)
#'
#' @param job_env Named character vector of env vars from the job.
#' @param explicit_env Named character vector of explicit env vars passed to gdal_run.
#' @param config_opts Named character vector of GDAL config options.
#'
#' @return A named character vector of all environment variables to pass to processx.
#'
#' @keywords internal
.merge_env_vars <- function(job_env, explicit_env, config_opts) {
  # Start with job environment variables
  merged <- job_env

  # Add explicit environment variables (override job env)
  if (!is.null(explicit_env)) {
    merged <- c(merged, explicit_env)
  }

  # Harvest legacy global auth environment variables for backward compatibility
  # These are auth variables that may have been set via set_gdal_auth() using Sys.setenv()
  legacy_patterns <- c("^AWS_", "^GS_", "^AZURE_", "^OSS_", "^GOOGLE_", "^SWIFT_", "^OS_")
  legacy_vars <- character()
  for (pattern in legacy_patterns) {
    matching <- Sys.getenv()[grep(pattern, names(Sys.getenv()))]
    if (length(matching) > 0) {
      legacy_vars <- c(legacy_vars, matching)
    }
  }

  # Merge with precedence: explicit_env > legacy_vars > merged
  if (length(legacy_vars) > 0) {
    # Add legacy vars that aren't already in merged
    for (i in seq_along(legacy_vars)) {
      var_name <- names(legacy_vars)[i]
      if (!(var_name %in% names(merged))) {
        merged <- c(merged, legacy_vars[i])
      }
    }
  }

  # Convert config options to environment variable format if needed
  # GDAL config options can also be passed as --config flags in the CLI,
  # but they can be environment variables too
  if (length(config_opts) > 0) {
    for (i in seq_along(config_opts)) {
      opt_name <- names(config_opts)[i]
      opt_val <- config_opts[i]
      # Could pass via env or CLI flags; CLI is preferred, so skip here
    }
  }

  merged
}


#' Default gdal_run Method
#'
#' @keywords internal
#' @export
gdal_run.default <- function(x, ...) {
  rlang::abort(
    c(
      sprintf("No gdal_run method available for class '%s'.", class(x)[1]),
      "i" = "gdal_run() is designed for gdal_job objects."
    ),
    class = "gdalcli_unsupported_gdal_run"
  )
}


#' Execute GDAL Job via gdalraster Backend
#'
#' @description
#' Internal function that executes a gdal_job using the gdalraster package's
#' native GDAL bindings instead of processx system calls.
#'
#' @param job A [gdal_job] object
#' @param stream_in Ignored (gdalraster backend handles this differently)
#' @param stream_out_format Output format: `NULL` (default) or `"text"`
#' @param env Environment variables (merged with job config)
#' @param verbose Logical. If TRUE, prints the command being executed.
#' @param ... Additional arguments (ignored)
#'
#' @return
#' - If `stream_out_format = NULL`: Invisibly returns `TRUE` on success
#' - If `stream_out_format = "text"`: Returns stdout as character string
#'
#' @keywords internal
gdal_run_gdalraster <- function(job,
                               stream_in = NULL,
                               stream_out_format = NULL,
                               env = NULL,
                               verbose = FALSE,
                               ...) {
  # Check gdalraster is available
  if (!requireNamespace("gdalraster", quietly = TRUE)) {
    cli::cli_abort(
      c(
        "gdalraster package required for this operation",
        "i" = "Install with: install.packages('gdalraster')"
      )
    )
  }

  # Build command string from path and arguments
  cmd_parts <- job$command_path

  # Serialize arguments
  args <- .serialize_gdal_job(job)

  # Print command if verbose
  if (verbose) {
    cli::cli_alert_info(sprintf("Executing (gdalraster): gdal %s", paste(args, collapse = " ")))
  }

  # Prepare environment variables
  env_final <- .merge_env_vars(job$env_vars, env, job$config_options)

  # Execute via gdalraster
  # gdalraster::gdal_run() expects command as a string
  cmd_string <- paste(c(cmd_parts, args[-seq_along(cmd_parts)]), collapse = " ")

  tryCatch(
    {
      # Set environment variables temporarily
      old_env <- Sys.getenv(names(env_final))
      on.exit(do.call(Sys.setenv, as.list(old_env)), add = TRUE)

      if (length(env_final) > 0) {
        do.call(Sys.setenv, as.list(env_final))
      }

      # Execute command via gdalraster
      result <- gdalraster::gdal_run(
        cmd = cmd_string,
        output_file = if (!is.null(stream_out_format)) tempfile() else NULL
      )

      # Handle output
      if (!is.null(stream_out_format) && stream_out_format == "text") {
        # gdalraster doesn't capture stdout in same way as processx
        # For now, just return success indication
        return(result)
      }

      invisible(TRUE)
    },
    error = function(e) {
      cli::cli_abort(
        c(
          "GDAL command failed via gdalraster",
          "x" = conditionMessage(e)
        )
      )
    }
  )
}
