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
    config_options = as.character(config_options),
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

  if (!is.null(x$pipeline)) {
    cat(sprintf("Pipeline History: %d prior jobs\n", length(x$pipeline$jobs)))
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


#' Build a GDAL pipeline string from a sequence of gdal_job objects.
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
build_pipeline_from_jobs <- function(jobs) {
  if (length(jobs) == 0) {
    rlang::abort("jobs vector cannot be empty")
  }

  pipeline_parts <- character()

  for (i in seq_along(jobs)) {
    job <- jobs[[i]]
    if (!inherits(job, "gdal_job")) {
      rlang::abort(sprintf("jobs[[%d]] must be a gdal_job object", i))
    }

    # Extract the command step name from command_path
    # e.g., c("raster", "reproject") -> "reproject"
    # For pipeline, we need step names like "read", "reproject", "write"
    cmd_path <- job$command_path

    # Handle both "gdal" prefixed and non-prefixed paths
    if (length(cmd_path) > 0 && cmd_path[1] == "gdal") {
      cmd_path <- cmd_path[-1]
    }

    if (length(cmd_path) < 2) {
      rlang::abort(sprintf("Invalid command path for job %d: %s", i, paste(cmd_path, collapse = " ")))
    }

    # Get the command type (raster/vector) and operation
    cmd_type <- cmd_path[1]  # "raster" or "vector"
    operation <- cmd_path[2]  # The actual operation name

    # Map GDAL commands to pipeline step names
    # Comprehensive mappings based on available GDAL pipeline steps
    step_mapping <- list(
      # Raster operations
      "raster" = c(
        # I/O
        "convert" = "write",
        "create" = "write",
        "tile" = "write",
        # Analysis & transformation
        "reproject" = "reproject",
        "clip" = "clip",
        "edit" = "edit",
        "select" = "select",
        "scale" = "scale",
        "unscale" = "unscale",
        "resize" = "resize",
        "calc" = "calc",
        "reclassify" = "reclassify",
        "hillshade" = "hillshade",
        "slope" = "slope",
        "aspect" = "aspect",
        "roughness" = "roughness",
        "tpi" = "tpi",
        "tri" = "tri",
        # Cleanup
        "fill_nodata" = "fillnodata",
        "fill-nodata" = "fillnodata",
        "clean_collar" = "cleancol",
        "clean-collar" = "cleancol",
        "sieve" = "sieve",
        # Other
        "mosaic" = "mosaic",
        "stack" = "stack",
        "info" = "read"  # info can be read-only pipeline step
      ),
      # Vector operations
      "vector" = c(
        # I/O
        "convert" = "write",
        # Analysis & transformation
        "reproject" = "reproject",
        "clip" = "clip",
        "filter" = "filter",
        "select" = "select",
        "sql" = "sql",
        "intersection" = "intersection",
        "info" = "read"
      )
    )

    # Get the appropriate mapping for this command type
    type_mapping <- step_mapping[[cmd_type]]
    if (is.null(type_mapping)) {
      rlang::abort(sprintf("Unknown command type '%s' in job %d", cmd_type, i))
    }

    # Map the operation to a step name
    step_name <- if (operation %in% names(type_mapping)) {
      type_mapping[operation]
    } else {
      operation  # Use operation as-is if no mapping exists
    }

    # Build step arguments
    step_args <- character()
    args <- job$arguments
    args_copy <- args  # Keep copy for later processing

    # Special handling for different steps - handle I/O
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
    } else {
      # For intermediate steps, don't include input/output since data flows through pipeline
      args_copy$input <- NULL
      args_copy$output <- NULL
    }

    # Convert remaining arguments to CLI flags for pipeline context
    # Skip arguments that shouldn't be in pipeline (like pipeline, input_format, output_format)
    skip_args <- c("pipeline", "input_format", "output_format", "open_option",
                    "creation_option", "layer_creation_option", "input_layer",
                    "output_layer", "overwrite", "update", "append", "overwrite_layer")

    for (arg_name in names(args_copy)) {
      arg_val <- args_copy[[arg_name]]

      # Skip certain arguments that don't apply in pipeline context
      if (arg_name %in% skip_args) {
        next
      }

      if (!is.null(arg_val)) {
        # Convert R argument name to CLI flag (keep underscores or convert to hyphens)
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
#' This function implements the argument merging logic for piping support.
#' Explicit arguments override piped job arguments, and input propagation
#' is handled automatically.
#'
#' @param job_args List of arguments from the piped gdal_job.
#' @param new_args List of arguments passed to the current function.
#'
#' @return Merged list of arguments.
#'
#' @keywords internal
merge_gdal_job_arguments <- function(job_args, new_args) {
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
  # Handle slot access using base list access to avoid recursion
  if (name %in% c("command_path", "arguments", "config_options", "env_vars", "stream_in", "stream_out_format", "pipeline", "arg_mapping")) {
    return(.subset2(x, name))
  }
  
  # Handle convenience methods
  switch(name,
    "run" = function(...) gdal_job_run(x, ...),
    "print" = function(...) print(x, ...),
    "with_co" = function(...) gdal_with_co(x, ...),
    "with_config" = function(...) gdal_with_config(x, ...),
    "with_env" = function(...) gdal_with_env(x, ...),
    "with_lco" = function(...) gdal_with_lco(x, ...),
    "with_oo" = function(...) gdal_with_oo(x, ...),
    "merge" = function(other, ...) merge_gdal_job_arguments(x$arguments, other$arguments),
    "clone" = function(...) {
      new_gdal_job(
        command_path = x$command_path,
        arguments = x$arguments,
        config_options = x$config_options,
        env_vars = x$env_vars,
        stream_in = x$stream_in,
        stream_out_format = x$stream_out_format,
        pipeline = x$pipeline,
        arg_mapping = x$arg_mapping
      )
    },
    # Default: signal error
    rlang::abort(sprintf("Unknown slot or method: %s", name))
  )
}


#' Double Bracket Access for GDAL Job Objects
#'
#' Provides access to `gdal_job` slots using double brackets `[[`.
#' This is consistent with standard R list behavior.
#'
#' @param x A `gdal_job` object.
#' @param i The slot name or index.
#' @param ... Additional arguments (unused).
#'
#' @return The slot value.
#'
#' @export
`[[.gdal_job` <- function(x, i, ...) {
  # Allow both named and indexed access
  if (is.character(i)) {
    # Named access
    if (i %in% names(x)) {
      return(x[[i]])
    } else {
      rlang::abort(sprintf("Unknown slot: %s", i))
    }
  } else if (is.numeric(i)) {
    # Indexed access (treat as list)
    return(x[[i]])
  } else {
    rlang::abort("Invalid index type")
  }
}


#' Double Bracket Assignment for GDAL Job Objects
#'
#' Allows modification of `gdal_job` slots using double brackets `[[<-`.
#' Note: This creates a new job object (immutable pattern).
#'
#' @param x A `gdal_job` object.
#' @param i The slot name.
#' @param value The new value.
#'
#' @return A new `gdal_job` object with the modified slot.
#'
#' @export
`[[<-.gdal_job` <- function(x, i, value) {
  if (!is.character(i)) {
    rlang::abort("Slot names must be character strings")
  }
  
  # Validate slot name
  valid_slots <- c("command_path", "arguments", "config_options", "env_vars", "stream_in", "stream_out_format", "pipeline")
  if (!(i %in% valid_slots)) {
    rlang::abort(sprintf("Unknown slot: %s. Valid slots: %s", i, paste(valid_slots, collapse = ", ")))
  }
  
  # Create new job with modified slot
  new_job <- x  # Copy all slots
  new_job[[i]] <- value
  
  # Ensure it remains a gdal_job object
  class(new_job) <- c("gdal_job", "list")
  new_job
}


# ============================================================================
# Print Method for GDAL Jobs
# ============================================================================

#' Print Method for GDAL Jobs
