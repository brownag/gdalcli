#' Define and Create a GDAL Job Specification
#'
#' @description
#' The `gdal_job` S3 class is the central data structure that encapsulates a GDAL command
#' specification. It implements the lazy evaluation framework, where commands are constructed
#' as objects and only executed when passed to [gdal_job_run()].
#'
#' The class follows the S3 object system and is designed to be composable with the native
#' R pipe (`|>`). Helper functions like [gdal_with_co()], [gdal_with_config()], etc., all
#' accept and return `gdal_job` objects, enabling fluent command building.
#'
#' @aliases gdal_job
#'
#' @section Class Structure:
#'
#' A `gdal_job` object is an S3 list with the following slots:
#'
#' - **command_path** (`character`): The command hierarchy (e.g., `c("vector", "convert")`).
#' - **arguments** (`list`): A named list of validated command arguments, mapped to their
#'   final CLI flags and values.
#' - **config_options** (`character`): A named vector of GDAL `--config` options
#'   (e.g., `c("OGR_SQL_DIALECT" = "SQLITE")`).
#' - **env_vars** (`character`): A named vector of environment variables for the subprocess.
#' - **stream_in** (`ANY`): An R object to be streamed to `/vsistdin/`. Can be `NULL`,
#'   a character string, or raw vector.
#' - **stream_out_format** (`character(1)`): Specifies output streaming format:
#'   `NULL` (default, no output streaming), `"text"` (capture stdout as character string),
#'   or `"raw"` (capture as raw bytes).
#' - **pipeline** (`gdal_pipeline` or `NULL`): A pipeline object containing the sequence
#'   of jobs that were executed prior to this job, or `NULL` if this is a standalone job.
#'
#' @section Constructor:
#'
#' The `new_gdal_job()` function creates a new `gdal_job` object. This is typically used
#' internally by auto-generated wrapper functions (e.g., [gdal_vector_convert()]).
#' End users typically interact with high-level constructor functions, not `new_gdal_job()` directly.
#'
#' @param command_path A character vector specifying the command hierarchy.
#'   Example: `c("vector", "convert")` for the `gdal vector convert` command.
#' @param arguments A named list of validated arguments. Keys are argument names
#'   (e.g., `"input"`, `"output"`, `"dst-crs"`). Values are the corresponding arguments.
#' @param config_options A named character vector of config options. Default empty.
#' @param env_vars A named character vector of environment variables. Default empty.
#' @param stream_in An R object for input streaming. Default `NULL`.
#' @param stream_out_format Character string specifying output format or `NULL`. Default `NULL`.
#' @param pipeline A `gdal_pipeline` object containing the sequence of jobs that led to this job, or `NULL`. Default `NULL`.
#' @param arg_mapping A named list mapping argument names to their validation rules (min_count, max_count). Used internally for argument validation. Default `NULL`.
#'
#' @return
#' An S3 object of class `gdal_job`.
#'
#' @seealso
#' [gdal_job_run()], [gdal_with_co()], [gdal_with_config()], [gdal_with_env()]
#'
#' @examples
#' # Low-level constructor (typically used internally by auto-generated functions)
#' job <- new_gdal_job(
#'   command_path = c("vector", "convert"),
#'   arguments = list(input = "/path/to/input.shp", output_layer = "output")
#' )
#'
#' # High-level constructor (end-user API)
#' job <- gdal_vector_convert(
#'   input = "/path/to/input.shp",
#'   output_layer = "output"
#' )
#'
#' # Modify with piping
#' result <- job |>
#'   gdal_with_co("COMPRESS=LZW") |>
#'   gdal_with_config("OGR_SQL_DIALECT=SQLITE")
#'
#' @export
new_gdal_job <- function(command_path,
                         arguments = list(),
                         config_options = character(),
                         env_vars = character(),
                         stream_in = NULL,
                         stream_out_format = NULL,
                         pipeline = NULL,
                         arg_mapping = NULL) {
  # Validate command_path
  if (!is.character(command_path)) {
    rlang::abort("command_path must be a character vector.")
  }

  # Validate stream_out_format
  if (!is.null(stream_out_format)) {
    if (!stream_out_format %in% c("text", "raw")) {
      rlang::abort(
        c(
          "stream_out_format must be NULL, 'text', or 'raw'.",
          "x" = sprintf("Got: %s", stream_out_format)
        )
      )
    }
  }

  job <- list(
    command_path = command_path,
    arguments = as.list(arguments),
    config_options = if (is.character(config_options)) config_options else as.character(config_options),
    env_vars = as.character(env_vars),
    stream_in = stream_in,
    stream_out_format = stream_out_format,
    pipeline = pipeline,
    arg_mapping = arg_mapping
  )

  class(job) <- c("gdal_job", "list")
  job
}


#' Print Method for GDAL Jobs
#'
#' @description
#' Provides a human-readable representation of a `gdal_job` object for debugging.
#' Shows the command that would be executed, without actually running it.
#'
#' @param x A `gdal_job` object.
#' @param ... Additional arguments (unused, for S3 compatibility).
#'
#' @return Invisibly returns `x`.
#'
#' @keywords internal
#' @export
print.gdal_job <- function(x, ...) {
  cat("<gdal_job>\n")
  
  # If this job has a pipeline, show the full pipeline structure
  if (!is.null(x$pipeline)) {
    cat("Pipeline: ", length(x$pipeline$jobs), " step(s)\n", sep = "")
    
    for (i in seq_along(x$pipeline$jobs)) {
      job <- x$pipeline$jobs[[i]]
      
      # Get command name
      cmd_path <- job$command_path
      if (length(cmd_path) > 0 && cmd_path[1] == "gdal") {
        cmd_path <- cmd_path[-1]
      }
      cmd_name <- if (length(cmd_path) >= 2) {
        paste(cmd_path, collapse = " ")
      } else {
        "unknown"
      }
      
      # Get input/output if present
      input_str <- if (!is.null(job$arguments$input)) {
        sprintf(" (input: %s)", job$arguments$input)
      } else {
        ""
      }
      
      output_str <- if (!is.null(job$arguments$output)) {
        sprintf(" (output: %s)", job$arguments$output)
      } else {
        ""
      }
      
      cat(sprintf("  [%d] %s%s%s\n", i, cmd_name, input_str, output_str))
    }
    
    # Show wrapper-level config options if present
    if (length(x$config_options) > 0) {
      cat("Config Options:\n")
      for (i in seq_along(x$config_options)) {
        opt_name <- names(x$config_options)[i]
        opt_val <- x$config_options[i]
        cat(sprintf("  %s=%s\n", opt_name, opt_val))
      }
    }
    
    # Show wrapper-level creation options if present
    if (!is.null(x$arguments[["creation-option"]]) && length(x$arguments[["creation-option"]]) > 0) {
      cat("Creation Options:\n")
      for (co in x$arguments[["creation-option"]]) {
        cat(sprintf("  %s\n", co))
      }
    }
  } else {
    # Single job (no pipeline)
    # Check if command_path already starts with "gdal"
    if (length(x$command_path) > 0 && x$command_path[1] == "gdal") {
      cat("Command: ", paste(x$command_path, collapse = " "), "\n")
    } else {
      cat("Command:  gdal", paste(x$command_path, collapse = " "), "\n")
    }

    if (length(x$arguments) > 0) {
      cat("Arguments:\n")
      for (i in seq_along(x$arguments)) {
        arg_name <- names(x$arguments)[i]
        arg_val <- x$arguments[[i]]

        # Check if this is a positional argument
        positional_args <- c("input", "output", "src_dataset", "dest_dataset", "dataset")
        is_positional <- arg_name %in% positional_args

        # Format the argument value for display
        if (is.null(arg_val)) {
          val_str <- "NULL"
        } else if (is.logical(arg_val)) {
          val_str <- as.character(arg_val)
        } else if (length(arg_val) == 1) {
          val_str <- as.character(arg_val)
        } else {
          val_str <- paste0("[", paste(as.character(arg_val), collapse = ", "), "]")
        }

        if (is_positional) {
          cat(sprintf("  %s: %s\n", arg_name, val_str))
        } else {
          cat(sprintf("  --%s: %s\n", arg_name, val_str))
        }
      }
    }

    if (length(x$config_options) > 0) {
      cat("Config Options:\n")
      for (i in seq_along(x$config_options)) {
        opt_name <- names(x$config_options)[i]
        opt_val <- x$config_options[i]
        cat(sprintf("  %s=%s\n", opt_name, opt_val))
      }
    }

    if (length(x$env_vars) > 0) {
      cat("Environment Variables:\n")
      for (i in seq_along(x$env_vars)) {
        var_name <- names(x$env_vars)[i]
        var_val <- x$env_vars[i]
        cat(sprintf("  %s=%s\n", var_name, var_val))
      }
    }

    if (!is.null(x$stream_in)) {
      cat("Input Streaming: Yes (via /vsistdin/)\n")
    }

    if (!is.null(x$stream_out_format)) {
      cat(sprintf("Output Streaming: %s (via /vsistdout/)\n", x$stream_out_format))
    }
  }

  invisible(x)
}


#' Str Method for GDAL Jobs
#'
#' @description
#' Provides a compact string representation of a `gdal_job` object for debugging.
#' Avoids recursive printing that can cause C stack overflow.
#'
#' @param object A `gdal_job` object.
#' @param ... Additional arguments passed to str.default.
#' @param max.level Maximum level of nesting to display (ignored for gdal_job).
#' @param vec.len Maximum length of vectors to display (ignored for gdal_job).
#'
#' @return Invisibly returns `object`.
#'
#' @keywords internal
#' @export
str.gdal_job <- function(object, ..., max.level = 1, vec.len = 4) {
  cat("<gdal_job>")
  
  # Show command path
  if (length(object$command_path) > 0) {
    cmd_str <- paste(object$command_path, collapse = " ")
    cat(sprintf(" [Command: gdal %s]", cmd_str))
  }
  
  # Show key arguments count
  if (length(object$arguments) > 0) {
    cat(sprintf(" [%d args]", length(object$arguments)))
  }
  
  # Show pipeline info if present
  if (!is.null(object$pipeline)) {
    cat(sprintf(" [Pipeline: %d jobs]", length(object$pipeline$jobs)))
  }
  
  cat("\n")
  invisible(object)
}


#' Subsetting and Access Methods for GDAL Jobs
#'
#' @description
#' Provides subsetting operators for `gdal_job` objects.
#'
#' - `[` extracts specific job(s) from a pipeline, returning a `gdal_job`
#' - `length()` returns the number of pipeline jobs (or 1 if standalone)
#' - `c()` combines multiple jobs into a pipeline
#' - `$` and `[[` use standard list semantics for property access
#'
#' @param x A `gdal_job` object.
#' @param i Index, property name, or value.
#' @param name Property name for `$` and `$<-`.
#' @param value New value for assignment operators.
#' @param ... Multiple `gdal_job` objects for `c()`.
#' @param recursive Ignored (for S3 consistency).
#'
#' @examples
#' \dontrun{
#' pipeline <- gdal_raster_reproject(input = "input.tif", dst_crs = "EPSG:32632") |>
#'   gdal_raster_scale(src_min = 0, src_max = 100) |>
#'   gdal_raster_convert(output = "output.tif")
#'
#' length(pipeline)           # Returns 3
#' pipeline[1]                # First job
#' pipeline[1:2]              # First two jobs
#' pipeline$command_path      # Access property
#' pipeline$config_options <- c("OPT=VALUE")  # Set property
#'
#' job1 <- gdal_raster_reproject(input = "in.tif", dst_crs = "EPSG:32632")
#' job2 <- gdal_raster_scale(src_min = 0, src_max = 100)
#' job3 <- gdal_raster_convert(output = "out.tif")
#' combined <- c(job1, job2, job3)  # Combine into pipeline
#' }
#'
#' @name gdal_job-subsetting
#' @aliases [.gdal_job length.gdal_job [<-.gdal_job $<-.gdal_job [[<-.gdal_job c.gdal_job
NULL


#' @rdname gdal_job-subsetting
#' @export
`[.gdal_job` <- function(x, i) {
  # If no pipeline, return self (only one job)
  if (is.null(x$pipeline)) {
    if (i == 1) {
      return(x)
    } else {
      rlang::abort("Index out of bounds: job has only 1 step")
    }
  }

  # With pipeline, extract job(s) from pipeline
  if (is.numeric(i)) {
    if (any(i < 1) || any(i > length(x$pipeline$jobs))) {
      rlang::abort(sprintf("Index out of bounds: job has %d steps", length(x$pipeline$jobs)))
    }
    
    selected_jobs <- x$pipeline$jobs[i]
    
    # If selecting a single job, return it directly
    if (length(i) == 1) {
      return(selected_jobs[[1]])
    }
    
    # If selecting multiple jobs, create a new pipeline job wrapper
    new_pipeline <- new_gdal_pipeline(selected_jobs, name = x$pipeline$name, description = x$pipeline$description)
    return(new_gdal_job(
      command_path = x$command_path,
      arguments = list(),
      config_options = character(),
      env_vars = character(),
      pipeline = new_pipeline
    ))
  } else if (is.logical(i)) {
    if (length(i) != length(x$pipeline$jobs)) {
      rlang::abort(sprintf("Logical index length %d does not match job count %d", length(i), length(x$pipeline$jobs)))
    }
    return(x[which(i)])
  } else {
    rlang::abort("Index must be numeric or logical")
  }
}


#' @rdname gdal_job-subsetting
#' @export
length.gdal_job <- function(x) {
  if (is.null(x$pipeline)) 1L else length(x$pipeline$jobs)
}


#' @rdname gdal_job-subsetting
#' @export
names.gdal_job <- function(x) {
  c("command_path", "arguments", "config_options", "env_vars",
    "stream_in", "stream_out_format", "pipeline", "arg_mapping")
}

# ============================================================================
# Pipeline Building Helper Functions
# ============================================================================

#' Detect if a Job Has Output Argument
#'
#' Checks if a job has any output-related argument by looking for standard
#' output parameter names in positional order.
#'
#' @param job A gdal_job object.
#'
#' @return Logical TRUE if job has output argument, FALSE otherwise.
#'
#' @keywords internal
#' @noRd
.has_output_argument <- function(job) {
  # Check in positional order for output arguments
  output_names <- c("output", "dest_dataset", "dst_dataset", "output_layer")
  for (name in output_names) {
    if (!is.null(job$arguments[[name]])) {
      return(TRUE)
    }
  }
  FALSE
}

#' Extract Output Arguments from a Job
#'
#' Extracts all output-related arguments from a job in positional order.
#'
#' @param job A gdal_job object.
#'
#' @return A named list of output arguments (may be empty if no outputs).
#'
#' @keywords internal
#' @noRd
.get_output_arguments <- function(job) {
  output_names <- c("output", "dest_dataset", "dst_dataset", "output_layer")
  output_args <- list()
  
  for (name in output_names) {
    if (!is.null(job$arguments[[name]])) {
      output_args[[name]] <- job$arguments[[name]]
    }
  }
  
  output_args
}

#'
#' This function takes a vector of gdal_job objects and constructs a pipeline
#' string suitable for use with gdal raster/vector pipeline commands.
#'
#' @param jobs A vector or list of gdal_job objects.
#'
#' @return A character string representing the pipeline.
#'
#' @keywords internal
#'
#' @noRd
.build_pipeline_from_jobs <- function(jobs) {
  if (length(jobs) == 0) {
    rlang::abort("jobs vector cannot be empty")
  }

  pipeline_parts <- character()
  num_jobs <- length(jobs)

  for (i in seq_along(jobs)) {
    job <- jobs[[i]]
    if (!inherits(job, "gdal_job")) {
      rlang::abort(sprintf("jobs[[%d]] must be a gdal_job object", i))
    }

    # Extract and parse command path
    cmd_path <- job$command_path
    if (length(cmd_path) > 0 && cmd_path[1] == "gdal") {
      cmd_path <- cmd_path[-1]
    }

    if (length(cmd_path) < 2) {
      rlang::abort(sprintf("Invalid command path for job %d: %s", i, paste(cmd_path, collapse = " ")))
    }

    cmd_type <- cmd_path[1]  # "raster" or "vector"
    operation <- cmd_path[2]  # The actual operation name

    # Get step name from RFC 104 mappings (loaded at package load time)
    step_name <- .get_step_mapping(cmd_type, operation)

    # Determine job position
    is_first <- (i == 1)
    is_last <- (i == num_jobs)
    is_intermediate <- (!is_first && !is_last)

    # Build step arguments
    step_args <- character()
    args <- job$arguments
    args_copy <- args  # Keep copy for later processing

    # Determine if this job has output
    has_output <- .has_output_argument(job)

    # Handle input/output based on job position
    if (step_name == "read") {
      # For read step, input is positional
      if (!is.null(args_copy$input)) {
        step_args <- c(step_args, args_copy$input)
        args_copy$input <- NULL
      }
    } else if (step_name == "write") {
      # For write step, output is positional
      if (!is.null(args_copy$output)) {
        step_args <- c(step_args, args_copy$output)
        args_copy$output <- NULL
      }
    } else if (is_first) {
      # First job: emit ! read input if input exists and we're not already a read step
      if (!is.null(args_copy$input)) {
        read_step <- paste0("! read ", args_copy$input)
        pipeline_parts <- c(pipeline_parts, read_step)
        args_copy$input <- NULL
      }
    } else if (is_intermediate || is_last) {
      # Intermediate and last jobs: strip input/output from step arguments
      # (they flow through pipeline or are handled separately)
      args_copy$input <- NULL
      
      # For output args, strip them all from args_copy
      output_names <- c("output", "dest_dataset", "dst_dataset", "output_layer")
      for (name in output_names) {
        args_copy[[name]] <- NULL
      }
      
      # Check if intermediate job has multiple outputs
      if (is_intermediate && has_output) {
        output_args <- .get_output_arguments(job)
        if (length(output_args) > 1) {
          cli::cli_warn(
            c(
              "Intermediate job {i} has multiple outputs.",
              "i" = "Native GDAL pipelines work best with single outputs per step.",
              "i" = "Consider using sequential execution mode instead."
            )
          )
        }
      }
    }

    # Convert remaining arguments to CLI flags for pipeline context
    # Skip arguments that shouldn't be in pipeline
    skip_args <- c(
      "pipeline", "input_format", "output_format", "open_option",
      "creation_option", "creation-option", "layer_creation_option", "layer-creation-option",
      "input_layer", "output_layer", "overwrite", "update", "append", "overwrite_layer"
    )

    for (arg_name in names(args_copy)) {
      arg_val <- args_copy[[arg_name]]

      # Skip certain arguments that don't apply in pipeline context
      if (arg_name %in% skip_args) {
        next
      }

      if (!is.null(arg_val)) {
        # Convert R argument name to CLI flag
        cli_flag <- paste0("--", gsub("_", "-", arg_name))

        # Format the value
        if (is.logical(arg_val)) {
          if (arg_val) {
            step_args <- c(step_args, cli_flag)
          }
        } else if (is.character(arg_val)) {
          if (length(arg_val) == 1) {
            step_args <- c(step_args, cli_flag, arg_val)
          } else {
            # Multiple values - repeat flag for each
            for (v in arg_val) {
              step_args <- c(step_args, cli_flag, v)
            }
          }
        } else if (is.numeric(arg_val)) {
          step_args <- c(step_args, cli_flag, as.character(arg_val))
        }
      }
    }

    # Build the step string
    step_str <- paste(c(step_name, step_args), collapse = " ")
    pipeline_parts <- c(pipeline_parts, paste0("! ", step_str))

    # For last job, append ! write output if it has output
    if (is_last && has_output && step_name != "write") {
      output_args <- .get_output_arguments(job)
      # Use the first output for write step
      first_output <- output_args[[1]]
      if (!is.null(first_output)) {
        write_step <- paste0("! write ", first_output)
        pipeline_parts <- c(pipeline_parts, write_step)
      }
    }
  }

  # Join all parts
  pipeline <- paste(pipeline_parts, collapse = " ")

  pipeline
}


# ============================================================================
# Argument Merging for Piping Support
# ============================================================================

#' Merge arguments from a piped gdal_job with new function arguments.
#'
#' Explicit arguments override piped job arguments, and input propagation
#' is handled automatically.
#'
#' @param job_args List of arguments from the piped gdal_job.
#' @param new_args List of arguments passed to the current function.
#'
#' @return Merged list of arguments.
#'
#' @keywords internal
#' @noRd
.merge_gdal_job_arguments <- function(job_args, new_args) {
  # Start with empty list - only propagate specific arguments
  merged <- list()

  # Override with explicit new arguments (except NULL values)
  for (arg_name in names(new_args)) {
    arg_value <- new_args[[arg_name]]
    # Only override if the new argument is not NULL (allows explicit NULL to override)
    if (!is.null(arg_value)) {
      merged[[arg_name]] <- arg_value
    }
  }

  # Handle input propagation: if no explicit input/dataset is provided,
  # try to propagate from previous job's output
  input_param_names <- c("input", "dataset", "src_dataset")
  has_explicit_input <- any(input_param_names %in% names(new_args) & !sapply(new_args[input_param_names], is.null))

  if (!has_explicit_input && length(job_args) > 0) {
    # Look for output from previous job that could be input to this one
    output_candidates <- c("output", "dest_dataset", "dst_dataset")
    for (output_name in output_candidates) {
      if (!is.null(job_args[[output_name]])) {
        # Map output to appropriate input parameter
        if ("input" %in% input_param_names) {
          merged$input <- job_args[[output_name]]
        } else if ("dataset" %in% input_param_names) {
          merged$dataset <- job_args[[output_name]]
        } else if ("src_dataset" %in% input_param_names) {
          merged$src_dataset <- job_args[[output_name]]
        }
        break  # Use first available output
      }
    }
  }

  merged
}


# ============================================================================
# Dollar Names Support for Fluent API
# ============================================================================

#' Tab Completion for GDAL Job Objects
#'
#' Provides tab completion for `gdal_job` objects, showing available slots
#' and convenience methods.
#'
#' @param x A `gdal_job` object.
#' @param pattern The pattern to match (unused, for S3 compatibility).
#'
#' @return A character vector of completion candidates.
#'
#' @keywords internal
#' @export
#' @noRd
.DollarNames.gdal_job <- function(x, pattern = "") {
  # Base slots
  slots <- c(
    "command_path",
    "arguments", 
    "config_options",
    "env_vars",
    "stream_in",
    "stream_out_format",
    "pipeline"
  )
  
  # Convenience methods
  methods <- c(
    "run",           # Execute the job
    "print",         # Print job details
    "with_co",       # Add creation options
    "with_config",   # Add config options
    "with_env",      # Add environment variables
    "with_lco",      # Add layer creation options
    "with_oo",       # Add open options
    "merge",         # Merge with another job
    "clone"          # Create a copy
  )
  
  # Combine and filter by pattern
  all_names <- c(slots, methods)
  if (nzchar(pattern)) {
    all_names <- grep(pattern, all_names, value = TRUE)
  }
  
  all_names
}


#' Dollar Operator for GDAL Job Objects
#'
#' Provides access to `gdal_job` slots and convenience methods using the `$` operator.
#' This enables a fluent API for job manipulation.
#'
#' @param x A `gdal_job` object.
#' @param name The slot or method name to access.
#'
#' @return The slot value or the result of calling the convenience method.
#'
#' @examples
#' job <- gdal_raster_convert(input = "input.tif", output = "output.jpg")
#' 
#' # Access slots
#' cmd <- job$command_path
#' args <- job$arguments
#' 
#' # Use convenience methods (creates new job, doesn't execute)
#' job_with_co <- job$with_co("COMPRESS=LZW")
#' 
#' 
#' @export
`$.gdal_job` <- function(x, name) {
  # Try direct property access first using standard list semantics
  if (name %in% names(x)) {
    return(.subset2(x, name))
  }
  
  # Then try convenience methods
  switch(name,
    "run" = function(...) gdal_job_run(x, ...),
    "print" = function(...) print(x, ...),
    "with_co" = function(...) gdal_with_co(x, ...),
    "with_config" = function(...) gdal_with_config(x, ...),
    "with_env" = function(...) gdal_with_env(x, ...),
    "with_lco" = function(...) gdal_with_lco(x, ...),
    "with_oo" = function(...) gdal_with_oo(x, ...),
    "merge" = function(other, ...) .merge_gdal_job_arguments(x$arguments, other$arguments),
    "clone" = function(...) {
      props <- as.list(x)
      do.call(new_gdal_job, props)
    },
    # Default: signal error
    rlang::abort(sprintf("Unknown slot or method: %s", name))
  )
}


#' @rdname gdal_job-subsetting
#' @export
`$<-.gdal_job` <- function(x, name, value) {
  # Use base list assignment to avoid recursion through [[<-
  x_list <- unclass(x)
  x_list[[name]] <- value
  class(x_list) <- c("gdal_job", "list")
  x_list
}


#' @rdname gdal_job-subsetting
#' @export
`[[<-.gdal_job` <- function(x, i, value) {
  # Use base list assignment to avoid recursion
  x_list <- unclass(x)
  x_list[[i]] <- value
  class(x_list) <- c("gdal_job", "list")
  x_list
}


#' @rdname gdal_job-subsetting
#' @export
`[<-.gdal_job` <- function(x, i, value) {
  if (is.null(x$pipeline)) {
    rlang::abort("Cannot use [<- on a standalone job (no pipeline)")
  }
  
  # Ensure value is a list of gdal_job objects
  if (inherits(value, "gdal_job")) {
    value <- list(value)
  } else if (!is.list(value)) {
    rlang::abort("Replacement value must be a gdal_job or list of gdal_job objects")
  }
  
  # Check all items are gdal_job objects
  for (v in value) {
    if (!inherits(v, "gdal_job")) {
      rlang::abort("All items in replacement value must be gdal_job objects")
    }
  }
  
  # Replace jobs in pipeline
  new_jobs <- x$pipeline$jobs
  new_jobs[i] <- value
  
  new_pipeline <- new_gdal_pipeline(new_jobs, name = x$pipeline$name, description = x$pipeline$description)
  new_gdal_job(
    command_path = x$command_path,
    arguments = list(),
    config_options = character(),
    env_vars = character(),
    pipeline = new_pipeline
  )
}


#' @rdname gdal_job-subsetting
#' @export
c.gdal_job <- function(..., recursive = FALSE) {
  jobs <- list(...)
  
  # Flatten any nested pipelines
  flattened_jobs <- list()
  for (job in jobs) {
    if (!inherits(job, "gdal_job")) {
      rlang::abort("All arguments to c() must be gdal_job objects")
    }
    
    if (!is.null(job$pipeline)) {
      # Job is a pipeline wrapper - extract its jobs
      flattened_jobs <- c(flattened_jobs, job$pipeline$jobs)
    } else {
      # Job is standalone - add it directly
      flattened_jobs <- c(flattened_jobs, list(job))
    }
  }
  
  # Create wrapper with combined pipeline
  new_pipeline <- new_gdal_pipeline(
    flattened_jobs,
    name = NULL,
    description = "Combined pipeline"
  )
  
  new_gdal_job(
    command_path = character(),
    arguments = list(),
    config_options = character(),
    env_vars = character(),
    pipeline = new_pipeline
  )
}



# ============================================================================
# Print Method for GDAL Jobs
# ============================================================================

#' Print Method for GDAL Jobs
