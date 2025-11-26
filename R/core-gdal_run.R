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
#'   gdalraster if available (faster, no subprocess), otherwise processx.
#'   Control auto-selection with `options(gdalcli.prefer_backend = 'gdalraster')` or
#'   `options(gdalcli.prefer_backend = 'processx')`.
#' @param stream_in An R object to be streamed to `/vsistdin/`. Can be `NULL`,
#'   a character string, or raw vector. If provided, overrides `x$stream_in`.
#' @param stream_out_format Character string: `NULL` (default, no streaming),
#'   `"text"` (return stdout as character), `"raw"` (return as raw bytes), or
#'   `"json"` (capture output, parse as JSON, return as R list/vector).
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
  # Handle backend selection
  if (is.null(backend)) {
    # Auto-select backend based on availability and user preference
    backend <- getOption("gdalcli.prefer_backend", "auto")

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
    return(gdal_job_run_gdalraster(x, ...))
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
    return(gdal_job_run_reticulate(x, ...))
  } else if (backend == "processx") {
    return(gdal_job_run.gdal_job(x, ...))
  } else {
    cli::cli_abort(
      c(
        "Unknown backend: {backend}",
        "i" = "Supported backends: 'processx', 'gdalraster', 'reticulate'",
        "i" = "Set option: options(gdalcli.prefer_backend = 'gdalraster')"
      )
    )
  }
}


#' @rdname gdal_job_run
#' @export
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
    } else if (stream_out_final == "json") {
      # Try to parse as JSON
      tryCatch({
        return(yyjsonr::read_json_str(result$stdout))
      }, error = function(e) {
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
#' @description
#' Internal function that converts a [gdal_job] specification into a final argument
#' vector suitable for passing to the `gdal` command-line executable.
#'
#' This function handles:
#' - Serializing the command path (e.g., `["vector", "convert"]` → `"vector", "convert"`)
#' - Converting argument names from snake_case to kebab-case (e.g., `dst_crs` → `dst-crs`)
#' - Flattening vector arguments (e.g., `c("COL1=val1", "COL2=val2")` for a repeatable arg)
#' - Converting logical arguments to their flag equivalents
#' - Converting composite arguments (e.g., `c(2, 49, 3, 50)` for bbox → `--bbox=2,49,3,50`)
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

  # Add positional arguments in correct order: inputs first, then outputs
  # Most GDAL commands follow: [options] input [input2 ...] output
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

  # Add option arguments
  args <- c(args, option_args)

  args
}


#' Merge Environment Variables with Config Options
#'
#' @description
#' Internal function that combines environment variables from multiple sources:
#' 1. Base environment variables from the job
#' 2. Explicit environment variables passed to gdal_job_run
#' 3. GDAL config options (converted to GDAL_CONFIG_* format if needed)
#' 4. Legacy global environment variables (for backward compatibility)
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
gdal_job_run_gdalraster <- function(job,
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

  # Prepare environment variables
  env_final <- .merge_env_vars(job$env_vars, env, job$config_options)

  # Set environment variables temporarily
  old_env <- Sys.getenv(names(env_final))
  on.exit(do.call(Sys.setenv, as.list(old_env)), add = TRUE)
  if (length(env_final) > 0) {
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
    alg <- gdalraster::gdal_alg(cmd = cmd, args = final_args)

    # Run the algorithm
    alg$run()

    # Handle output based on streaming format
    if (!is.null(stream_out_format)) {
      # Get the algorithm output
      output_text <- alg$output()
      if (stream_out_format == "text") {
        return(output_text)
      } else if (stream_out_format == "raw") {
        return(charToRaw(output_text))
      } else if (stream_out_format == "json") {
        # Try to parse as JSON
        tryCatch({
          return(yyjsonr::read_json_str(output_text))
        }, error = function(e) {
          cli::cli_warn(
            c(
              "Failed to parse output as JSON",
              "x" = conditionMessage(e),
              "i" = "Returning raw stdout instead"
            )
          )
          return(output_text)
        })
      }
    }

    invisible(TRUE)
  }, error = function(e) {
    cli::cli_abort(
      c(
        "GDAL command failed via gdalraster",
        "x" = conditionMessage(e)
      )
    )
  })
}


#' Execute GDAL Job via Reticulate (Python)
#'
#' Backend that uses Python's osgeo.gdal module via reticulate.
#' This allows use of gdal.alg Python API alongside gdalcli.
#'
#' @param job A [gdal_job] object
#' @param ... Additional arguments (ignored)
#'
#' @keywords internal
#' @noRd
gdal_job_run_reticulate <- function(job,
                               stream_in = NULL,
                               stream_out_format = NULL,
                               env = NULL,
                               verbose = FALSE,
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

  # Build command string from path and arguments
  cmd_parts <- job$command_path
  
  # Serialize arguments
  args <- .serialize_gdal_job(job)
  
  # Print command if verbose
  if (verbose) {
    cli::cli_alert_info(sprintf("Executing (reticulate): gdal %s", paste(args, collapse = " ")))
  }
  
  # Prepare environment variables
  env_final <- .merge_env_vars(job$env_vars, env, job$config_options)
  
  # Set environment variables
  if (length(env_final) > 0) {
    old_env <- Sys.getenv(names(env_final))
    on.exit(do.call(Sys.setenv, as.list(old_env)), add = TRUE)
    do.call(Sys.setenv, as.list(env_final))
  }
  
  tryCatch(
    {
      # Import GDAL Python module
      gdal_py <- reticulate::import("osgeo.gdal")
      
      # Build command string
      full_cmd <- paste(c(cmd_parts, args[-seq_along(cmd_parts)]), collapse = " ")

      # Execute via Python GDAL
      # Note: gdal.alg.compute() expects command as string
      result <- gdal_py$alg$compute(full_cmd, quiet = !verbose)

      # Handle output based on streaming format
      if (!is.null(stream_out_format)) {
        # Note: result from gdal.alg.compute() may be a string or other type
        if (is.character(result)) {
          if (stream_out_format == "text") {
            return(result)
          } else if (stream_out_format == "raw") {
            return(charToRaw(result))
          } else if (stream_out_format == "json") {
            # Try to parse as JSON
            tryCatch({
              return(yyjsonr::read_json_str(result))
            }, error = function(e) {
              cli::cli_warn(
                c(
                  "Failed to parse output as JSON",
                  "x" = conditionMessage(e),
                  "i" = "Returning raw result instead"
                )
              )
              return(result)
            })
          }
        }
      }

      invisible(TRUE)
    },
    error = function(e) {
      cli::cli_abort(
        c(
          "GDAL command failed via reticulate",
          "x" = conditionMessage(e),
          "i" = "Make sure Python osgeo package is installed: pip install GDAL"
        )
      )
    }
  )
}
