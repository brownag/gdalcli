#' Execute a GDAL Job
#'
#' @description
#' `gdal_job_run()` is an S3 generic function that executes a GDAL command specification.
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
#' @param backend Character string specifying the backend to use: `"processx"` (subprocess-based,
#'   always available if GDAL installed), `"gdalraster"` (C++ bindings, if gdalraster installed),
#'   or `"reticulate"` (Python osgeo.gdal via reticulate, if available).
#'   If `NULL` (default), auto-selects the best available backend:
#'   gdalraster if available, otherwise processx.
#'   Control auto-selection with `options(gdalcli.backend = 'gdalraster')` or
#'   `options(gdalcli.backend = 'processx')`.
#'   You can also set default output format and verbosity globally:
#'   `options(gdalcli.stream_out_format = 'text')` and
#'   `options(gdalcli.verbose = TRUE)`.
#' @param stream_in An R object to be streamed to `/vsistdin/`. Can be `NULL`,
#'   a character string, or raw vector. If provided, overrides `x$stream_in`.
#' @param stream_out_format Character string: `NULL` (default, no streaming),
#'   `"text"` (return stdout as character), `"raw"` (return as raw bytes),
#'   `"json"` (capture output, parse as JSON, return as R list/vector), or
#'   `"stdout"` (print to stdout in real-time).
#'   If provided, overrides `x$stream_out_format`.
#'   If not provided, uses `options(gdalcli.stream_out_format)` if set.
#' @param env A named character vector of environment variables for the subprocess.
#'   These are merged with `x$env_vars`, with explicit `env` values taking precedence.
#' @param verbose Logical. If `TRUE`, prints the command being executed.
#'   If not provided, uses `options(gdalcli.verbose)` if set, otherwise defaults to `FALSE`.
#'
#' @return
#' Depends on the streaming configuration:
#' - If `stream_out_format = NULL` (default): Invisibly returns `TRUE` on success.
#'   Raises an R .error if the GDAL process fails.
#' - If `stream_out_format = "text"`: Returns the stdout as a character string.
#' - If `stream_out_format = "raw"`: Returns the stdout as a raw vector.
#' - If `stream_out_format = "json"`: Parses stdout as JSON and returns the result.
#' - If `stream_out_format = "stdout"`: Prints output to stdout in real-time, invisibly returns `TRUE`.
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
#' gdal_job_run(job)
#'
#' # With input streaming
#' geojson_string <- '{type: "FeatureCollection", ...}'
#' job <- gdal_vector_convert(
#'   input = "/vsistdin/",
#'   output = "output.gpkg"
#' )
#' gdal_job_run(job, stream_in = geojson_string)
#'
#' # With output streaming
#' job <- gdal_vector_info("input.gpkg", output_format = "JSON")
#' json_result <- gdal_job_run(job, stream_out = "text")
#' }
#'
#' @export
gdal_job_run <- function(x, ..., backend = NULL) {
  # If this is a pipeline object, delegate to pipeline method
  if (inherits(x, "gdal_pipeline")) {
    return(gdal_job_run.gdal_pipeline(x, ...))
  }

  # If this job has a pipeline history, run the pipeline instead
  if (inherits(x, "gdal_job") && !is.null(x$pipeline)) {
    return(gdal_job_run(x$pipeline, ...))
  }

  # Handle backend selection
  if (is.null(backend)) {
    # Auto-select backend based on availability and user preference
    backend <- getOption("gdalcli.backend", "auto")

    if (backend == "auto") {
      # Auto-select: prefer gdalraster if available and functional
      if (.check_gdalraster_version("2.2.0", quietly = TRUE)) {
        backend <- "gdalraster"
      } else {
        backend <- "processx"  # fallback
      }
    }
  }

  # Dispatch to appropriate backend
  if (backend == "gdalraster") {
    if (!requireNamespace("gdalraster", quietly = TRUE)) {
      cli::cli_abort(
        c(
          "gdalraster package required for gdalraster backend",
          "i" = "Install with: install.packages('gdalraster')",
          "i" = "Or use backend = 'processx' (default fallback)"
        )
      )
    }
    return(.gdal_job_run_gdalraster(x, ...))
  } else if (backend == "reticulate") {
    if (!requireNamespace("reticulate", quietly = TRUE)) {
      cli::cli_abort(
        c(
          "reticulate package required for reticulate backend",
          "i" = "Install with: install.packages('reticulate')",
          "i" = "Or use backend = 'processx' (default fallback)"
        )
      )
    }
    return(.gdal_job_run_reticulate(x, ...))
  } else if (backend == "processx") {
    return(gdal_job_run.gdal_job(x, ...))
  } else {
    cli::cli_abort(
      c(
        "Unknown backend: {backend}",
        "i" = "Supported backends: 'processx', 'gdalraster', 'reticulate'",
        "i" = "Set option: options(gdalcli.backend = 'gdalraster')"
      )
    )
  }
}


#' @rdname gdal_job_run
#' @export
#' @method gdal_job_run gdal_job
gdal_job_run.gdal_job <- function(x,
                              stream_in = NULL,
                              stream_out_format = NULL,
                              env = NULL,
                              verbose = FALSE,
                              ...) {
  # Check if processx backend is available
  if (!requireNamespace("processx", quietly = TRUE)) {
    cli::cli_abort(
      c(
        "processx package required for default execution backend",
        "i" = "Install with: install.packages('processx')",
        "i" = "Or specify an alternative backend: backend = 'gdalraster' or 'reticulate'",
        "i" = "See ?gdal_job_run for backend options and installation guidance"
      )
    )
  }

  # If this job has a pipeline history, run the pipeline instead
  if (!is.null(x$pipeline)) {
    return(gdal_job_run(x$pipeline, ..., verbose = verbose))
  }

  # Resolve streaming parameters (explicit args override job specs, which override global options)
  stream_in_final <- if (!is.null(stream_in)) stream_in else x$stream_in
  
  # Resolve stream_out_format with priority: explicit arg > job spec > global option > NULL
  stream_out_final <- if (!is.null(stream_out_format)) {
    stream_out_format
  } else if (!is.null(x$stream_out_format)) {
    x$stream_out_format
  } else {
    getOption("gdalcli.stream_out_format", NULL)
  }
  
  # Resolve verbose with priority: explicit arg > global option > FALSE
  verbose_final <- if (!is.na(verbose) && is.logical(verbose)) {
    verbose
  } else {
    getOption("gdalcli.verbose", FALSE)
  }

  # Serialize job to GDAL command arguments
  args <- .serialize_gdal_job(x)

  # Merge environment variables
  env_final <- .merge_env_vars(x$env_vars, env, x$config_options)

  # Configure input/output streams
  stdin_arg <- if (!is.null(stream_in_final)) stream_in_final else NULL
  # For "stdout" format, use TRUE to pipe directly to parent stdout
  # For other formats, use "|" to capture output
  stdout_arg <- if (stream_out_final == "stdout") TRUE else if (!is.null(stream_out_final)) "|" else NULL

  if (verbose_final) {
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
    if (stream_out_final == "stdout") {
      # Output already printed to stdout during execution
      invisible(TRUE)
    } else if (stream_out_final == "text") {
      return(result$stdout)
    } else if (stream_out_final == "raw") {
      return(charToRaw(result$stdout))
    } else if (stream_out_final == "json") {
      # Try to parse as JSON
      tryCatch({
        return(yyjsonr::read_json_str(result$stdout))
      }, .error = function(e) {
        cli::cli_warn(
          c(
            "Failed to parse output as JSON",
            "x" = conditionMessage(e),
            "i" = "Returning raw stdout instead"
          )
        )
        return(result$stdout)
      })
    }
  }

  invisible(TRUE)
}


#' Serialize a gdal_job to GDAL CLI Arguments
#'
#' Converts a gdal_job to GDAL CLI arguments.
#'
#' @param job A [gdal_job] object.
#'
#' @return A character vector of arguments ready for processx.
#'
#' @keywords internal
#' @noRd
.serialize_gdal_job <- function(job) {
  # Skip the "gdal" prefix if present
  command_parts <- if (length(job$command_path) > 0 && job$command_path[1] == "gdal") job$command_path[-1] else job$command_path
  args <- command_parts

  # Separate positional and option arguments
  positional_args_list <- list()
  option_args <- character()

  # Get arg_mapping if available (contains min_count/max_count for proper serialization)
  arg_mapping <- if (!is.null(job$arg_mapping)) job$arg_mapping else list()

  # Process regular arguments
  for (i in seq_along(job$arguments)) {
    arg_name <- names(job$arguments)[i]
    arg_value <- job$arguments[[i]]

    if (is.null(arg_value)) {
      # Skip NULL arguments
      next
    }

    # Check if this is a positional argument (no -- prefix needed)
    positional_arg_names <- c("input", "output", "src_dataset", "dest_dataset", "dataset")
    is_positional <- arg_name %in% positional_arg_names

    if (is_positional) {
      # Store positional arguments to add in correct order later
      positional_args_list[[arg_name]] <- arg_value
    } else {
      # Option arguments: add --flag
      # Special flag mappings for arguments that use different CLI flags
      flag_mapping <- c(
        "resolution" = "--resolution",
        "size" = "--ts",
        "extent" = "--te"
      )
      cli_flag <- if (arg_name %in% names(flag_mapping)) flag_mapping[arg_name] else paste0("--", gsub("_", "-", arg_name))

      # Handle different value types
      if (is.logical(arg_value)) {
        if (arg_value) {
          option_args <- c(option_args, cli_flag)
        }
      } else if (length(arg_value) > 1) {
        # Determine if this is a composite (fixed-count) or repeatable argument
        # by checking arg_mapping if available
        arg_meta <- arg_mapping[[arg_name]]
        is_composite <- FALSE
        
        if (!is.null(arg_meta) && !is.null(arg_meta$min_count) && !is.null(arg_meta$max_count)) {
          # Composite argument: min_count == max_count and both > 1
          is_composite <- arg_meta$min_count == arg_meta$max_count && arg_meta$min_count > 1
        }

        if (is_composite) {
          # Composite argument: comma-separated value (e.g., bbox=2,49,3,50)
          option_args <- c(option_args, cli_flag, paste(as.character(arg_value), collapse = ","))
        } else {
          # Repeatable argument: --flag val1 --flag val2 ...
          for (val in arg_value) {
            option_args <- c(option_args, cli_flag, as.character(val))
          }
        }
      } else {
        # Single-value arguments
        option_args <- c(option_args, cli_flag, as.character(arg_value))
      }
    }
  }

  # Add option arguments first (GDAL expects [options] then positional args)
  args <- c(args, option_args)

  # Add positional arguments in correct order: inputs first, then outputs
  # GDAL commands follow: [options] input [input2 ...] output
  positional_order <- c("input", "src_dataset", "dataset", "output", "dest_dataset")
  for (arg_name in positional_order) {
    if (arg_name %in% names(positional_args_list)) {
      arg_value <- positional_args_list[[arg_name]]
      if (length(arg_value) > 1) {
        # Multiple positional values (rare)
        args <- c(args, arg_value)
      } else {
        args <- c(args, as.character(arg_value))
      }
    }
  }

  args
}


#' Merge Environment Variables with Config Options
#'
#' Combines environment variables from multiple sources.
#'
#' @param job_env Named character vector of env vars from the job.
#' @param explicit_env Named character vector of explicit env vars passed to gdal_job_run.
#' @param config_opts Named character vector of GDAL config options.
#'
#' @return A named character vector of all environment variables to pass to processx.
#'
#' @keywords internal
#' @noRd
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


#' Default gdal_job_run Method
#'
#' @keywords internal
#' @export
#' @method gdal_job_run default
gdal_job_run.default <- function(x, ...) {
  rlang::abort(
    c(
      sprintf("No gdal_job_run method available for class '%s'.", class(x)[1]),
      "i" = "gdal_job_run() is designed for gdal_job objects."
    ),
    class = "gdalcli_unsupported_gdal_job_run"
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
#' @noRd
.gdal_job_run_gdalraster <- function(job,
                               stream_in = NULL,
                               stream_out_format = NULL,
                               env = NULL,
                               verbose = FALSE,
                               audit = FALSE,
                               ...) {
  # If this job has a pipeline history, run the pipeline instead
  if (inherits(job, "gdal_job") && !is.null(job$pipeline)) {
    return(gdal_job_run(job$pipeline, backend = "gdalraster", ...))
  }

  # Check gdalraster is available
  if (!requireNamespace("gdalraster", quietly = TRUE)) {
    cli::cli_abort(
      c(
        "gdalraster package required for this operation",
        "i" = "Install with: install.packages('gdalraster')"
      )
    )
  }

  # Capture explicit args if audit is enabled
  explicit_args <- NULL
  if (audit && .gdal_has_feature("explicit_args")) {
    explicit_args <- tryCatch({
      gdal_job_get_explicit_args(job)
    }, error = function(e) {
      NULL
    })
  }

  # Prepare environment variables
  env_final <- .merge_env_vars(job$env_vars, env, job$config_options)

  # Set environment variables
  if (length(env_final) > 0) {
    old_env <- Sys.getenv(names(env_final))
    on.exit({
      do.call(Sys.setenv, as.list(old_env))
    }, add = TRUE)
    do.call(Sys.setenv, as.list(env_final))
  }

  # Serialize the job to GDAL CLI arguments
  args_serialized <- .serialize_gdal_job(job)

  if (length(args_serialized) < 2) {
    cli::cli_abort("Invalid command path - need at least module and operation")
  }

  # Extract command path (module + operation) and remaining arguments
  cmd <- args_serialized[1:2]  # e.g., c("raster", "info")
  remaining_args <- if (length(args_serialized) > 2) args_serialized[-(1:2)] else character()

  if (verbose) {
    cli::cli_alert_info(sprintf("Executing (gdalraster): gdal %s", paste(args_serialized, collapse = " ")))
  }

  # Use gdalraster::gdal_alg() to execute the command
  tryCatch({
    # Define positional argument names (arguments that don't use -- prefix)
    positional_arg_names <- c("input", "output", "src_dataset", "dest_dataset", "dataset")

    # Collect positional and option arguments separately
    positional_args <- character()
    option_args <- character()

    # Parse remaining arguments
    i <- 1
    while (i <= length(remaining_args)) {
      arg_token <- remaining_args[i]

      # Check if this is a flag (starts with --)
      if (startsWith(arg_token, "--")) {
        # This is an option argument
        option_args <- c(option_args, arg_token)

        # Check if next element is a value (not a flag)
        if (i + 1 <= length(remaining_args) && !startsWith(remaining_args[i + 1], "--")) {
          option_args <- c(option_args, remaining_args[i + 1])
          i <- i + 2
        } else {
          i <- i + 1
        }
      } else {
        # This is a positional argument
        positional_args <- c(positional_args, arg_token)
        i <- i + 1
      }
    }

    # Combine: option args first, then positional args
    final_args <- c(option_args, positional_args)

    # Instantiate the algorithm with command and all arguments
    # We pass all args to gdal_alg since gdalraster needs positional args
    # to be specified together with the command
    alg <- tryCatch({
      gdalraster::gdal_alg(cmd = cmd, args = final_args)
    }, .error = function(alg_e) {
      # Check if this is a GDAL error from the constructor
      alg_msg <- conditionMessage(alg_e)
      if (grepl("GDAL FAILURE", alg_msg)) {
        matches <- regmatches(alg_msg, regexec("GDAL FAILURE [0-9]+: ([^\\n]+)", alg_msg))
        if (length(matches[[1]]) > 1) {
          gdal_error <- matches[[1]][2]
          stop(gdal_error)
        }
      }
      # Re-throw if not a GDAL error
      stop(alg_e)
    })

    # Capture execution start time for audit trail
    exec_start <- Sys.time()

    # Run the algorithm
    tryCatch({
      alg$run()
    }, .error = function(run_e) {
      # Check if this is a GDAL error
      run_msg <- conditionMessage(run_e)
      if (grepl("GDAL FAILURE", run_msg)) {
        matches <- regmatches(run_msg, regexec("GDAL FAILURE [0-9]+: ([^\\n]+)", run_msg))
        if (length(matches[[1]]) > 1) {
          gdal_error <- matches[[1]][2]
          stop(gdal_error)
        }
      }
      # Re-throw if not a GDAL error
      stop(run_e)
    })

    # Capture execution end time
    exec_end <- Sys.time()

    # Handle output based on streaming format
    result <- NULL
    if (!is.null(stream_out_format)) {
      # Get the algorithm output
      output_text <- alg$output()
      if (stream_out_format == "stdout") {
        # Print to stdout
        cat(output_text)
        result <- NULL  # Don't return the output
      } else if (stream_out_format == "text") {
        result <- output_text
      } else if (stream_out_format == "raw") {
        result <- charToRaw(output_text)
      } else if (stream_out_format == "json") {
        # Try to parse as JSON
        tryCatch({
          result <- yyjsonr::read_json_str(output_text)
        }, .error = function(e) {
          cli::cli_warn(
            c(
              "Failed to parse output as JSON",
              "x" = conditionMessage(e),
              "i" = "Returning raw stdout instead"
            )
          )
          result <<- output_text
        })
      }
    }

    # Attach audit metadata if requested
    if (audit && !is.null(result)) {
      audit_trail <- list(
        timestamp = exec_start,
        duration = difftime(exec_end, exec_start, units = "secs"),
        command = paste(c("gdal", args_serialized), collapse = " "),
        backend = "gdalraster",
        explicit_args = explicit_args,
        status = "success"
      )
      attr(result, "audit_trail") <- audit_trail
    }

    if (!is.null(result)) {
      return(result)
    }

    invisible(TRUE)
  }, .error = function(e) {
    # Try to extract GDAL error from the error message
    error_msg <- conditionMessage(e)
    
    # If the error message contains GDAL FAILURE, extract it
    if (grepl("GDAL FAILURE", error_msg)) {
      # Look for the GDAL error pattern
      matches <- regmatches(error_msg, regexec("GDAL FAILURE [0-9]+: ([^\\n]+)", error_msg))
      if (length(matches[[1]]) > 1) {
        gdal_error <- matches[[1]][2]
        cli::cli_abort(gdal_error)
      }
    }
    
    # Fallback: re-throw the original error
    cli::cli_abort(
      c(
        "GDAL command failed via gdalraster",
        "x" = error_msg
      )
    )
  })
}


#' Execute GDAL Pipeline via gdalraster Backend
#'
#' Native pipeline execution using gdalraster::gdal_alg().
#' Builds a native GDAL pipeline string and executes it directly.
#'
#' @param pipeline A `gdal_pipeline` object
#' @param stream_out_format Output streaming format ("text", "raw", "json", or NULL)
#' @param env Environment variables for execution
#' @param verbose Logical, print details
#'
#' @return Result based on stream_out_format or invisibly TRUE
#'
#' @keywords internal
#' @noRd
.gdal_job_run_native_pipeline_gdalraster <- function(pipeline,
                                                      stream_out_format = NULL,
                                                      env = NULL,
                                                      verbose = FALSE) {
  if (length(pipeline$jobs) == 0) {
    if (verbose) cli::cli_alert_info("Pipeline is empty - nothing to execute")
    return(invisible(TRUE))
  }

  # Build native pipeline string
  pipeline_str <- .render_native_pipeline(pipeline)

  # Determine pipeline type from first job
  first_job <- pipeline$jobs[[1]]
  cmd_path <- first_job$command_path
  if (length(cmd_path) > 0 && cmd_path[1] == "gdal") {
    cmd_path <- cmd_path[-1]
  }
  pipeline_type <- if (length(cmd_path) > 0) cmd_path[1] else "raster"

  # Build arguments: c(cmd_type, "pipeline", pipeline_str)
  args <- c(pipeline_type, "pipeline", pipeline_str)

  # Collect config options from all pipeline jobs
  config_opts <- character()
  for (job in pipeline$jobs) {
    if (length(job$config_options) > 0) {
      for (cfg_name in names(job$config_options)) {
        config_opts[[cfg_name]] <- job$config_options[[cfg_name]]
      }
    }
  }

  # Collect environment variables from all pipeline jobs
  env_final <- character()
  for (job in pipeline$jobs) {
    if (length(job$env_vars) > 0) {
      env_final <- c(env_final, job$env_vars)
    }
  }

  # Merge with explicit env (explicit takes precedence)
  if (!is.null(env)) {
    env_final <- c(env_final, env)
  }

  # Remove duplicates (keep last)
  if (length(env_final) > 0) {
    env_final <- env_final[!duplicated(names(env_final), fromLast = TRUE)]
  }

  if (verbose) {
    cli::cli_alert_info(sprintf("Native pipeline (gdalraster): %s", paste(args, collapse = " ")))
  }

  # Set environment variables temporarily
  if (length(env_final) > 0) {
    old_env <- Sys.getenv(names(env_final))
    on.exit(do.call(Sys.setenv, as.list(old_env)), add = TRUE)
    do.call(Sys.setenv, as.list(env_final))
  }

  tryCatch({
    # Create and run algorithm
    alg <- gdalraster::gdal_alg(args, config_options = config_opts)
    
    # Parse for argv[0] (gdalraster may need it)
    result <- alg$run()

    # Handle output based on streaming format
    if (!is.null(stream_out_format)) {
      output_text <- alg$output()
      if (stream_out_format == "stdout") {
        # Print to stdout
        cat(output_text)
      } else if (stream_out_format == "text") {
        return(output_text)
      } else if (stream_out_format == "raw") {
        return(charToRaw(output_text))
      } else if (stream_out_format == "json") {
        tryCatch({
          return(yyjsonr::read_json_str(output_text))
        }, .error = function(e) {
          cli::cli_warn(
            c(
              "Failed to parse pipeline output as JSON",
              "x" = conditionMessage(e),
              "i" = "Returning raw output instead"
            )
          )
          return(output_text)
        })
      }
    }

    invisible(TRUE)
  }, .error = function(e) {
    cli::cli_abort(
      c(
        "Native GDAL pipeline execution failed via gdalraster",
        "x" = conditionMessage(e)
      )
    )
  })
}


#' Execute GDAL Job via Reticulate (Python)
#'
#' Backend that uses Python's osgeo.gdal module via reticulate.
#' This allows use of gdal.Run() Python API alongside gdalcli.
#'
#' @param job A [gdal_job] object
#' @param ... Additional arguments (ignored)
#'
#' @keywords internal
#' @noRd
.gdal_job_run_reticulate <- function(job,
                               stream_in = NULL,
                               stream_out_format = NULL,
                               env = NULL,
                               verbose = FALSE,
                               audit = FALSE,
                               ...) {
  # Check reticulate is available
  if (!requireNamespace("reticulate", quietly = TRUE)) {
    cli::cli_abort(
      c(
        "reticulate package required for this operation",
        "i" = "Install with: install.packages('reticulate')"
      )
    )
  }

  # Check Python GDAL is available
  if (!reticulate::py_module_available("osgeo.gdal")) {
    cli::cli_abort("Python osgeo.gdal module required for reticulate backend")
  }

  # Capture explicit args if audit is enabled
  explicit_args <- NULL
  if (audit && .gdal_has_feature("explicit_args")) {
    explicit_args <- tryCatch({
      gdal_job_get_explicit_args(job)
    }, error = function(e) {
      NULL
    })
  }

  # Resolve streaming parameters (explicit args override job specs)
  stream_in_final <- if (!is.null(stream_in)) stream_in else job$stream_in
  stream_out_final <- if (!is.null(stream_out_format)) stream_out_format else job$stream_out_format

  # Serialize the job to GDAL CLI arguments
  cli_args <- .serialize_gdal_job(job)

  if (verbose) {
    cli::cli_alert_info(sprintf("Executing (reticulate): gdal %s", paste(cli_args, collapse = " ")))
  }

  # Prepare environment variables
  env_final <- .merge_env_vars(job$env_vars, env, job$config_options)

  # Set environment variables temporarily (only if there are any to set)
  if (length(env_final) > 0) {
    old_env <- Sys.getenv(names(env_final))
    on.exit({
      do.call(Sys.setenv, as.list(old_env))
    }, add = TRUE)
    do.call(Sys.setenv, as.list(env_final))
  }

  # Capture execution start time for audit trail
  exec_start <- Sys.time()

  tryCatch({
    # Import GDAL Python module and sys for stdout capture
    gdal_py <- reticulate::import("osgeo.gdal")
    py_sys <- reticulate::import("sys")
    py_io <- reticulate::import("io")

    # Extract command path (e.g., c("raster", "info"))
    if (length(cli_args) < 2) {
      cli::cli_abort("Invalid command: need at least two arguments (command type and operation)")
    }

    # Build command path as list: ["raster", "info"] or ["vector", "translate"]
    command_path <- cli_args[1:2]

    # Get remaining arguments
    remaining_args <- if (length(cli_args) > 2) cli_args[-(1:2)] else character()

    # Convert CLI arguments to Python kwargs dictionary
    kwargs <- .convert_cli_args_to_kwargs(remaining_args)

    # Handle input streaming: write stream_in data to /vsistdin/
    if (!is.null(stream_in_final)) {
      # Convert stream_in to character if needed
      stdin_data <- if (is.raw(stream_in_final)) {
        rawToChar(stream_in_final)
      } else if (is.character(stream_in_final)) {
        paste(stream_in_final, collapse = "\n")
      } else {
        as.character(stream_in_final)
      }

      # Write to /vsistdin/ using GDAL's VSI functions
      py_gdal_vsi <- reticulate::import("osgeo.gdal")
      py_vsi_file <- py_gdal_vsi$VSIFOpenL("/vsistdin/", "w")
      
      if (!is.null(py_vsi_file)) {
        py_gdal_vsi$VSIFWriteL(stdin_data, 1L, nchar(stdin_data), py_vsi_file)
        py_gdal_vsi$VSIFCloseL(py_vsi_file)
      }
    }

    # Setup stdout capture if needed
    captured_stdout <- NULL
    old_stdout <- NULL

    if (!is.null(stream_out_final)) {
      # Capture stdout in Python
      old_stdout <- py_sys$stdout
      captured_stdout <- py_io$StringIO()
      py_sys$stdout <- captured_stdout
    }

    # Call gdal.Run() with command path and kwargs
    if (verbose) {
      cli::cli_alert_info(sprintf("Python gdal.Run(c('%s', '%s'), ...)", command_path[1], command_path[2]))
    }

    # Use gdal.Run() with list command path and dict kwargs
    alg <- gdal_py$Run(
      as.list(command_path),  # Convert to Python list
      reticulate::dict(kwargs)  # Convert to Python dict
    )

    if (is.null(alg)) {
      cli::cli_abort("gdal.Run() returned NULL - possible execution failure")
    }

    # Restore stdout before processing output
    if (!is.null(old_stdout)) {
      py_sys$stdout <- old_stdout
    }

    # Capture execution end time
    exec_end <- Sys.time()

    # Output format: we need to call alg.Output() to get results
    has_output_method <- !is.null(alg) && (inherits(alg, "python.object"))

    # Try to get output if requested
    if (!is.null(stream_out_final) && has_output_method) {
      # First try captured stdout
      captured_output <- NULL
      if (!is.null(captured_stdout)) {
        tryCatch({
          captured_output <- captured_stdout$getvalue()
        }, error = function(e) {
          captured_output <<- NULL
        })
      }

      # Try Output() method (capital O) if no captured stdout
      output_result <- if (!is.null(captured_output) && nchar(captured_output) > 0) {
        captured_output
      } else {
        tryCatch({
          if (!is.null(alg$Output)) {
            alg$Output()
          } else if (!is.null(alg$output)) {
            alg$output()
          } else {
            NULL
          }
        }, error = function(e) {
          cli::cli_warn(sprintf("Could not retrieve output: %s", conditionMessage(e)))
          NULL
        })
      }

      # Process output if available
      if (!is.null(output_result)) {
        if (stream_out_final == "stdout") {
          # Print to stdout
          output_text <- if (is.character(output_result)) {
            output_result
          } else {
            as.character(output_result)
          }
          cat(output_text)
          invisible(TRUE)
        } else if (stream_out_final == "text") {
          # Convert to text if needed
          output_text <- if (is.character(output_result)) {
            output_result
          } else {
            as.character(output_result)
          }
          
          # Attach audit metadata if requested
          if (audit) {
            audit_trail <- list(
              timestamp = exec_start,
              duration = difftime(exec_end, exec_start, units = "secs"),
              command = paste(c("gdal", cli_args), collapse = " "),
              backend = "reticulate",
              explicit_args = explicit_args,
              status = "success"
            )
            attr(output_text, "audit_trail") <- audit_trail
          }
          
          return(output_text)
        } else if (stream_out_final == "raw") {
          output_text <- if (is.character(output_result)) {
            output_result
          } else {
            as.character(output_result)
          }
          raw_output <- charToRaw(output_text)
          
          # Attach audit metadata if requested
          if (audit) {
            audit_trail <- list(
              timestamp = exec_start,
              duration = difftime(exec_end, exec_start, units = "secs"),
              command = paste(c("gdal", cli_args), collapse = " "),
              backend = "reticulate",
              explicit_args = explicit_args,
              status = "success"
            )
            attr(raw_output, "audit_trail") <- audit_trail
          }
          
          return(raw_output)
        } else if (stream_out_final == "json") {
          # Try to parse as JSON
          output_text <- if (is.character(output_result)) {
            output_result
          } else {
            as.character(output_result)
          }
          tryCatch({
            json_result <- yyjsonr::read_json_str(output_text)
            
            # Attach audit metadata if requested
            if (audit) {
              audit_trail <- list(
                timestamp = exec_start,
                duration = difftime(exec_end, exec_start, units = "secs"),
                command = paste(c("gdal", cli_args), collapse = " "),
                backend = "reticulate",
                explicit_args = explicit_args,
                status = "success"
              )
              attr(json_result, "audit_trail") <- audit_trail
            }
            
            return(json_result)
          }, error = function(e) {
            cli::cli_warn(
              c(
                "Failed to parse output as JSON",
                "x" = conditionMessage(e),
                "i" = "Returning raw output instead"
              )
            )
            return(output_text)
          })
        }
      }
    }

    # Attach audit metadata if requested (even when no output)
    if (audit) {
      audit_trail <- list(
        timestamp = exec_start,
        duration = difftime(exec_end, exec_start, units = "secs"),
        command = paste(c("gdal", cli_args), collapse = " "),
        backend = "reticulate",
        explicit_args = explicit_args,
        status = "success"
      )
      return(structure(TRUE, audit_trail = audit_trail))
    }

    invisible(TRUE)
  }, error = function(e) {
    # Restore stdout on error
    tryCatch({
      py_sys <- reticulate::import("sys")
      if (!is.null(old_stdout)) {
        py_sys$stdout <- old_stdout
      }
    }, error = function(e2) {
      # Silently ignore restoration errors
    })

    error_msg <- conditionMessage(e)
    cli::cli_abort(
      c(
        "GDAL command failed via reticulate",
        "x" = error_msg,
        "i" = "Verify Python GDAL is installed: pip install GDAL",
        "i" = "Check GDAL version is 3.11+"
      )
    )
  })
}


#' Convert CLI Arguments to Python kwargs Dictionary
#'
#' Converts GDAL CLI-style arguments (--flag value) to Python function kwargs.
#' Converts kebab-case flag names to snake_case for Python compatibility.
#'
#' @param cli_args Character vector of CLI arguments from .serialize_gdal_job()
#'
#' @return Named list suitable for conversion to Python dict
#'
#' @keywords internal
#' @noRd
.convert_cli_args_to_kwargs <- function(cli_args) {
  kwargs <- list()

  if (length(cli_args) == 0) {
    return(kwargs)
  }

  i <- 1
  positional_count <- 0

  while (i <= length(cli_args)) {
    arg <- cli_args[i]

    if (startsWith(arg, "--")) {
      # Flag argument
      flag_name <- substring(arg, 3)  # Remove "--"

      # Convert kebab-case to snake_case
      param_name <- gsub("-", "_", flag_name)

      # Check if next element is a value (not a flag)
      if (i + 1 <= length(cli_args) && !startsWith(cli_args[i + 1], "--")) {
        # Next element is the value
        value <- cli_args[i + 1]

        # Try to convert numeric values
        if (!grepl("[^0-9.-]", value)) {
          tryCatch({
            value <- as.numeric(value)
          }, warning = function(w) {
            # Keep as character if numeric conversion fails
          })
        }

        kwargs[[param_name]] <- value
        i <- i + 2
      } else {
        # Flag without value (boolean flag)
        kwargs[[param_name]] <- TRUE
        i <- i + 1
      }
    } else {
      # Positional argument (no flag prefix)
      positional_count <- positional_count + 1

      # Map positional args to common parameter names
      # This assumes GDAL command structure: input output [other_positional]
      if (positional_count == 1) {
        kwargs[["input"]] <- arg
      } else if (positional_count == 2) {
        kwargs[["output"]] <- arg
      } else {
        # Use generic names for additional positional args
        kwargs[[sprintf("arg_%d", positional_count)]] <- arg
      }

      i <- i + 1
    }
  }

  kwargs
}
