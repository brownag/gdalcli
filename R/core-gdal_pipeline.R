#' Define and Create a GDAL Pipeline Specification
#'
#' @description
#' The `gdal_pipeline` S3 class represents a sequence of GDAL commands that are
#' executed in order. It extends the lazy evaluation framework to support complex
#' workflows where the output of one command becomes the input to the next.
#'
#' Pipelines can be rendered to different formats:
#' - GDAL pipeline commands (for direct execution)
#' - Shell scripts (for batch processing)
#' - Direct execution (sequential job running)
#'
#' @aliases gdal_pipeline
#'
#' @section Class Structure:
#'
#' A `gdal_pipeline` object is an S3 list with the following slots:
#'
#' - **jobs** (`list`): A list of `gdal_job` objects to be executed in sequence.
#' - **name** (`character(1)`): Optional name for the pipeline.
#' - **description** (`character(1)`): Optional description of the pipeline.
#'
#' @section Constructor:
#'
#' The `new_gdal_pipeline()` function creates a new `gdal_pipeline` object.
#' End users typically interact with pipelines through the `|>` operator.
#'
#' @param jobs A list of `gdal_job` objects.
#' @param name Optional character string naming the pipeline.
#' @param description Optional character string describing the pipeline.
#'
#' @return
#' An S3 object of class `gdal_pipeline`.
#'
#' @seealso
#' [gdal_job], [gdal_job_run()], [render_gdal_pipeline()], [render_shell_script()]
#'
#' @examples
#' \dontrun{
#' # Create individual jobs
#' job1 <- gdal_raster_info("input.tif")
#' job2 <- gdal_raster_convert(input = "/vsistdout/", output = "output.jpg")
#'
#' # Create pipeline
#' pipeline <- new_gdal_pipeline(list(job1, job2))
#'
#' # Execute pipeline
#' gdal_job_run(pipeline)
#' }
#'
#' @export
new_gdal_pipeline <- function(jobs, name = NULL, description = NULL) {
  # Validate jobs
  if (!is.list(jobs)) {
    rlang::abort("jobs must be a list")
  }

  for (i in seq_along(jobs)) {
    if (!inherits(jobs[[i]], "gdal_job")) {
      rlang::abort(sprintf("jobs[[%d]] must be a gdal_job object", i))
    }
  }

  pipeline <- list(
    jobs = jobs,
    name = name,
    description = description
  )

  class(pipeline) <- c("gdal_pipeline", "list")
  pipeline
}


#' Check if Path is Virtual File System
#'
#' @description
#' Determines if a file path uses GDAL's virtual file system (VSI).
#' Virtual file systems include /vsistdin/, /vsistdout/, /vsimem/, etc.
#'
#' @param path Character string representing a file path.
#'
#' @return Logical indicating if the path is a virtual file system path.
#'
#' @keywords internal
#' @noRd
.is_virtual_path <- function(path) {
  if (!is.character(path) || length(path) != 1) {
    return(FALSE)
  }

  # Check for common GDAL virtual file system prefixes
  virtual_prefixes <- c(
    "/vsistdin/",
    "/vsistdout/",
    "/vsimem/",
    "/vsicurl/",
    "/vsizip/",
    "/vsitar/",
    "/vsigzip/",
    "/vsicache/",
    "/vsis3/",
    "/vsigs/",
    "/vsiaz/",
    "/vsiadls/",
    "/vsicrypt/"
  )

  any(startsWith(path, virtual_prefixes))
}


#' Print Method for GDAL Pipelines
#'
#' @description
#' Provides a human-readable representation of a `gdal_pipeline` object.
#'
#' @param x A `gdal_pipeline` object.
#' @param ... Additional arguments (unused, for S3 compatibility).
#'
#' @return Invisibly returns `x`.
#'
#' @keywords internal
#' @export
print.gdal_pipeline <- function(x, ...) {
  cat("<gdal_pipeline>\n")

  if (!is.null(x$name)) {
    cat("Name: ", x$name, "\n")
  }

  if (!is.null(x$description)) {
    cat("Description: ", x$description, "\n")
  }

  cat("Jobs (", length(x$jobs), "):\n")
  for (i in seq_along(x$jobs)) {
    cat(sprintf("  %d. ", i))
    # Print job command path
    job <- x$jobs[[i]]
    if (length(job$command_path) > 0) {
      if (job$command_path[1] == "gdal") {
        cat("gdal", paste(job$command_path[-1], collapse = " "))
      } else {
        cat("gdal", paste(job$command_path, collapse = " "))
      }
    } else {
      cat("gdal")
    }
    cat("\n")
  }

    invisible(x)
}


#' Str Method for GDAL Pipelines
#'
#' @description
#' Provides a compact string representation of a `gdal_pipeline` object.
#' Avoids recursive printing that can cause C stack overflow.
#'
#' @param object A `gdal_pipeline` object.
#' @param ... Additional arguments passed to str.default.
#' @param max.level Maximum level of nesting to display (ignored for gdal_pipeline).
#' @param vec.len Maximum length of vectors to display (ignored for gdal_pipeline).
#'
#' @return Invisibly returns `object`.
#'
#' @keywords internal
#' @export
str.gdal_pipeline <- function(object, ..., max.level = 1, vec.len = 4) {
  cat("<gdal_pipeline>")
  
  if (!is.null(object$name)) {
    cat(sprintf(" [%s]", object$name))
  }
  
  cat(sprintf(" [%d jobs]", length(object$jobs)))
  
  if (!is.null(object$description)) {
    cat(sprintf(" [%s]", substr(object$description, 1, 50)))
    if (nchar(object$description) > 50) {
      cat("...")
    }
  }
  
  cat("\n")
  invisible(object)
}


#' Check if Path is Virtual File System


#' Execute a GDAL Pipeline
#'
#' @description
#' Executes a sequence of GDAL jobs in order, with output from one job
#' potentially becoming input to the next through virtual file systems.
#'
#' @param x A `gdal_pipeline` object.
#' @param execution_mode Character string: `"sequential"` (default) to run jobs as
#'   separate GDAL commands, or `"native"` to run as a single native GDAL pipeline
#'   command (via `gdal raster/vector pipeline`). Native mode is more efficient for
#'   large datasets as it avoids intermediate disk I/O.
#' @param stream_in An R object to be streamed to `/vsistdin/` for the first pipeline step.
#'   Only used in native execution mode. Default `NULL`.
#' @param stream_out_format Character string: output format for the last pipeline step.
#'   Options: `NULL` (no streaming), `"text"`, or `"raw"`. Only used in native execution mode.
#' @param env Environment variables to pass to the GDAL process. Only used in native execution mode.
#' @param ... Additional arguments passed to individual job execution.
#' @param verbose Logical. If `TRUE`, prints progress information. Default `FALSE`.
#'
#' @return Invisibly returns `TRUE` on successful completion, or (in native mode with
#'   streaming output) returns the captured output.
#'
#' @seealso
#' [render_gdal_pipeline()], [gdal_job_run.gdal_pipeline()]
#'
#' @examples
#' \dontrun{
#' # Sequential execution (default, each job runs separately)
#' pipeline <- gdal_raster_info("in.tif") |>
#'   gdal_raster_reproject(dst_crs = "EPSG:32632") |>
#'   gdal_raster_convert(output = "out.tif")
#' gdal_job_run(pipeline)
#'
#' # Native pipeline execution (single GDAL pipeline command)
#' gdal_job_run(pipeline, execution_mode = "native")
#' }
#'
#' @export
gdal_job_run.gdal_pipeline <- function(x,
                                       execution_mode = c("sequential", "native"),
                                       stream_in = NULL,
                                       stream_out_format = NULL,
                                       env = NULL,
                                       ...,
                                       verbose = FALSE) {
  execution_mode <- match.arg(execution_mode)

  if (length(x$jobs) == 0) {
    if (verbose) cli::cli_alert_info("Pipeline is empty - nothing to execute")
    return(invisible(TRUE))
  }

  if (execution_mode == "native") {
    # Native pipeline execution: run as single GDAL pipeline command
    return(.gdal_job_run_native_pipeline(
      x,
      stream_in = stream_in,
      stream_out_format = stream_out_format,
      env = env,
      verbose = verbose
    ))
  }

  # Sequential execution: run jobs separately (original behavior)
  if (verbose) {
    cli::cli_alert_info(sprintf("Executing pipeline with %d jobs (sequential mode)", length(x$jobs)))
  }

  # Collect temporary files for cleanup
  temp_files <- character()

  # Execute jobs sequentially
  for (i in seq_along(x$jobs)) {
    job <- x$jobs[[i]]

    if (verbose) {
      cli::cli_alert_info(sprintf("Running job %d/%d: %s",
        i, length(x$jobs),
        paste(c("gdal", job$command_path), collapse = " ")
      ))
    }

    # Check for temporary files in job arguments
    for (arg_name in names(job$arguments)) {
      arg_value <- job$arguments[[arg_name]]
      if (is.character(arg_value) && length(arg_value) == 1) {
        # Check if it looks like a tempfile (contains tempdir path)
        if (grepl(tempdir(), arg_value, fixed = TRUE) && grepl("\\.tmp$", arg_value)) {
          temp_files <- c(temp_files, arg_value)
        }
      }
    }

    # Execute the job
    tryCatch({
      gdal_job_run(job, ..., verbose = verbose)
    }, .error = function(e) {
      cli::cli_abort(
        c(
          sprintf("Pipeline failed at job %d", i),
          "x" = conditionMessage(e)
        )
      )
    })
  }

  # Clean up temporary files
  for (temp_file in unique(temp_files)) {
    if (file.exists(temp_file)) {
      try(unlink(temp_file), silent = TRUE)
    }
  }

  if (verbose) {
    cli::cli_alert_success("Pipeline completed successfully")
  }

  invisible(TRUE)
}


#' Execute GDAL Pipeline in Native Mode
#'
#' @description
#' Internal function that executes a gdal_pipeline as a single native GDAL
#' pipeline command (via `gdal raster/vector pipeline`).
#'
#' @param pipeline A `gdal_pipeline` object.
#' @param stream_in An R object to stream to /vsistdin/ (optional).
#' @param stream_out_format Format for output streaming: NULL, "text", or "raw".
#' @param env Environment variables for the subprocess.
#' @param verbose Logical. If TRUE, prints execution details.
#'
#' @return Invisibly returns TRUE on success, or captured output if stream_out_format is set.
#'
#' @keywords internal
#' @noRd
.gdal_job_run_native_pipeline <- function(pipeline,
                                          stream_in = NULL,
                                          stream_out_format = NULL,
                                          env = NULL,
                                          verbose = FALSE) {
  # Check processx availability
  if (!requireNamespace("processx", quietly = TRUE)) {
    cli::cli_abort(
      c(
        "processx package required for native pipeline execution",
        "i" = "Install with: install.packages('processx')"
      )
    )
  }

  if (verbose) {
    cli::cli_alert_info(sprintf("Executing pipeline with %d steps (native mode)", length(pipeline$jobs)))
  }

  # Render the native pipeline string
  pipeline_str <- .render_native_pipeline(pipeline)

  # Detect pipeline type (raster/vector) from first job
  if (length(pipeline$jobs) == 0) {
    return(invisible(TRUE))
  }

  first_job <- pipeline$jobs[[1]]
  cmd_path <- first_job$command_path
  if (length(cmd_path) > 0 && cmd_path[1] == "gdal") {
    cmd_path <- cmd_path[-1]
  }
  pipeline_type <- if (length(cmd_path) > 0) cmd_path[1] else "raster"

  # Collect all config options from all jobs
  config_flags <- character()
  for (job in pipeline$jobs) {
    if (length(job$config_options) > 0) {
      for (config_name in names(job$config_options)) {
        config_val <- job$config_options[[config_name]]
        # Add as --config KEY=VALUE pair
        config_flags <- c(config_flags,
                         sprintf("--config %s=%s", config_name, config_val))
      }
    }
  }

  # Build the full command: gdal raster/vector pipeline [--config options] <pipeline_str>
  # Config flags go between "pipeline" and the pipeline string
  args <- c(pipeline_type, "pipeline")
  if (length(config_flags) > 0) {
    # Flatten config flags into individual args (--config and KEY=VALUE as separate elements)
    config_args <- character()
    for (cfg in config_flags) {
      # Split "--config KEY=VALUE" into c("--config", "KEY=VALUE")
      parts <- strsplit(cfg, " ")[[1]]
      config_args <- c(config_args, parts)
    }
    args <- c(args, config_args)
  }
  args <- c(args, pipeline_str)

  if (verbose) {
    cli::cli_alert_info(sprintf("Command: gdal %s", paste(args, collapse = " ")))
  }

  # Prepare stdin/stdout for streaming
  stdin_arg <- if (!is.null(stream_in)) stream_in else NULL
  stdout_arg <- if (!is.null(stream_out_format)) "|" else NULL

  # Merge environment variables from all pipeline jobs
  env_final <- character()
  for (job in pipeline$jobs) {
    if (length(job$env_vars) > 0) {
      env_final <- c(env_final, job$env_vars)
    }
  }

  # Merge with explicit env parameter (explicit takes precedence)
  if (!is.null(env)) {
    env_final <- c(env_final, env)
  }

  # Remove duplicates (keep last value if key appears multiple times)
  if (length(env_final) > 0) {
    env_final <- env_final[!duplicated(names(env_final), fromLast = TRUE)]
  }

  # Execute the native pipeline command
  tryCatch({
    result <- processx::run(
      command = "gdal",
      args = args,
      stdin = stdin_arg,
      stdout = stdout_arg,
      env = if (length(env_final) > 0) env_final else NULL,
      error_on_status = TRUE
    )

    # Handle output based on streaming format
    if (!is.null(stream_out_format)) {
      if (stream_out_format == "text") {
        if (verbose) {
          cli::cli_alert_success("Native pipeline completed successfully")
        }
        return(result$stdout)
      } else if (stream_out_format == "raw") {
        if (verbose) {
          cli::cli_alert_success("Native pipeline completed successfully")
        }
        return(charToRaw(result$stdout))
      }
    }

    if (verbose) {
      cli::cli_alert_success("Native pipeline completed successfully")
    }

    invisible(TRUE)
  }, .error = function(e) {
    cli::cli_abort(
      c(
        "Native GDAL pipeline execution failed",
        "x" = conditionMessage(e),
        "i" = sprintf("Command: gdal %s", paste(args, collapse = " "))
      )
    )
  })
}


#' Render GDAL Pipeline as Native GDAL Pipeline String
#'
#' @description
#' Converts a `gdal_pipeline` object into a native GDAL pipeline string that can be
#' executed directly with `gdal raster pipeline` or `gdal vector pipeline`.
#'
#' The native pipeline format uses `! step_name args...` syntax:
#' ```
#' gdal raster pipeline ! read in.tif ! reproject --dst-crs=EPSG:32632 ! write out.tif
#' ```
#'
#' @param pipeline A `gdal_pipeline` object.
#'
#' @return A character string containing the native GDAL pipeline string (without `gdal raster/vector pipeline` prefix).
#'
#' @keywords internal
#'
#' @noRd
.render_native_pipeline <- function(pipeline) {
  UseMethod(".render_native_pipeline")
}

#' @rdname .render_native_pipeline
#' @keywords internal
#' @noRd
.render_native_pipeline.gdal_pipeline <- function(pipeline) {
  if (length(pipeline$jobs) == 0) {
    return("")
  }

  # Use .build_pipeline_from_jobs to generate the native pipeline string
  .build_pipeline_from_jobs(pipeline$jobs)
}

#' Render GDAL Pipeline as GDAL Pipeline Command
#'
#' @description
#' Converts a `gdal_pipeline` into a GDAL pipeline command string that can be
#' executed directly with `gdal raster/vector pipeline`.
#'
#' By default, renders as a sequence of separate GDAL commands (`gdal cmd1 && gdal cmd2`).
#' Set `format = "native"` to generate native GDAL pipeline syntax.
#'
#' @param pipeline A `gdal_pipeline` object.
#' @param format Character string: `"shell_chain"` (default, separate commands with &&)
#'   or `"native"` (native GDAL pipeline syntax with ! delimiters).
#' @param ... Additional arguments (unused).
#'
#' @return A character string containing the GDAL pipeline command.
#'
#' @seealso
#' [render_shell_script()], [gdal_job_run.gdal_pipeline()]
#'
#' @export
render_gdal_pipeline <- function(pipeline, format = c("shell_chain", "native"), ...) {
  format <- match.arg(format)
  UseMethod("render_gdal_pipeline")
}


#' @rdname render_gdal_pipeline
#' @export
render_gdal_pipeline.gdal_job <- function(pipeline, format = c("shell_chain", "native"), ...) {
  format <- match.arg(format)

  if (!is.null(pipeline$pipeline)) {
    render_gdal_pipeline(pipeline$pipeline, format = format, ...)
  } else {
    # No pipeline history, render just this job
    args <- .serialize_gdal_job(pipeline)
    paste(c("gdal", args), collapse = " ")
  }
}

#' @rdname render_gdal_pipeline
#' @export
render_gdal_pipeline.gdal_pipeline <- function(pipeline, format = c("shell_chain", "native"), ...) {
  format <- match.arg(format)

  if (length(pipeline$jobs) == 0) {
    return("gdal pipeline")
  }

  if (format == "native") {
    # Render as native GDAL pipeline string
    # First, detect if raster or vector based on first job
    first_job <- pipeline$jobs[[1]]
    cmd_type <- if (!is.null(first_job$command_path) && length(first_job$command_path) > 0) {
      first_job$command_path[if (first_job$command_path[1] == "gdal") 2 else 1]
    } else {
      "raster"  # Default to raster
    }

    pipeline_str <- .render_native_pipeline(pipeline)
    paste("gdal", cmd_type, "pipeline", pipeline_str)
  } else {
    # Render as sequence of separate GDAL commands (shell chain)
    commands <- character()
    for (i in seq_along(pipeline$jobs)) {
      job <- pipeline$jobs[[i]]
      args <- .serialize_gdal_job(job)
      cmd <- paste(c("gdal", args), collapse = " ")
      commands <- c(commands, cmd)
    }

    paste(commands, collapse = " && ")
  }
}


#' Render GDAL Pipeline as Shell Script
#'
#' @description
#' Converts a `gdal_pipeline` into a shell script that executes the jobs.
#'
#' By default, generates separate commands chained with `&&`. Set `format = "native"`
#' to generate a shell script using a single native GDAL pipeline command instead.
#'
#' @param pipeline A `gdal_pipeline` object.
#' @param shell Character string specifying shell type: `"bash"` (default) or `"zsh"`.
#' @param format Character string: `"commands"` (default, separate commands with &&)
#'   or `"native"` (single native GDAL pipeline command). Default is `"commands"`.
#' @param ... Additional arguments (unused).
#'
#' @return A character string containing the shell script.
#'
#' @details
#' When `format = "commands"`, the script executes each job as a separate GDAL command,
#' which is safer for hybrid workflows mixing pipeline and non-pipeline operations.
#'
#' When `format = "native"`, the script uses a single `gdal raster/vector pipeline`
#' command, which is more efficient as it avoids intermediate disk I/O.
#'
#' @seealso
#' [render_gdal_pipeline()], [gdal_job_run.gdal_pipeline()]
#'
#' @export
render_shell_script <- function(pipeline, shell = "bash", format = c("commands", "native"), ...) {
  format <- match.arg(format)
  UseMethod("render_shell_script")
}


#' @rdname render_shell_script
#' @export
render_shell_script.gdal_job <- function(pipeline, shell = "bash", format = c("commands", "native"), ...) {
  format <- match.arg(format)

  if (!is.null(pipeline$pipeline)) {
    render_shell_script(pipeline$pipeline, shell = shell, format = format, ...)
  } else {
    # No pipeline history, render just this job as a simple script
    args <- .serialize_gdal_job(pipeline)
    cmd <- paste(c("gdal", args), collapse = " ")

    script_lines <- character()
    if (shell == "bash") {
      script_lines <- c(script_lines, "#!/bin/bash")
    } else if (shell == "zsh") {
      script_lines <- c(script_lines, "#!/bin/zsh")
    } else {
      script_lines <- c(script_lines, sprintf("#!/bin/%s", shell))
    }
    script_lines <- c(script_lines, "", "set -e", "", cmd, "")

    paste(script_lines, collapse = "\n")
  }
}

#' @rdname render_shell_script
#' @export
render_shell_script.gdal_pipeline <- function(pipeline, shell = "bash", format = c("commands", "native"), ...) {
  format <- match.arg(format)

  if (length(pipeline$jobs) == 0) {
    return("# Empty pipeline")
  }

  script_lines <- character()

  # Add shebang
  if (shell == "bash") {
    script_lines <- c(script_lines, "#!/bin/bash")
  } else if (shell == "zsh") {
    script_lines <- c(script_lines, "#!/bin/zsh")
  } else {
    script_lines <- c(script_lines, sprintf("#!/bin/%s", shell))
  }

  script_lines <- c(script_lines, "")

  # Add description if present
  if (!is.null(pipeline$name)) {
    script_lines <- c(script_lines, sprintf("# Pipeline: %s", pipeline$name))
  }
  if (!is.null(pipeline$description)) {
    script_lines <- c(script_lines, sprintf("# %s", pipeline$description))
  }
  if (!is.null(pipeline$name) || !is.null(pipeline$description)) {
    script_lines <- c(script_lines, "")
  }

  # Add set -e for .error handling
  script_lines <- c(script_lines, "set -e", "")

  if (format == "native") {
    # Render as native GDAL pipeline command
    # First, collect all config options from all jobs
    config_flags <- character()
    for (job in pipeline$jobs) {
      if (length(job$config_options) > 0) {
        for (config_name in names(job$config_options)) {
          config_val <- job$config_options[[config_name]]
          # Add as --config KEY=VALUE pair
          config_flags <- c(config_flags,
                           sprintf("--config %s=%s", config_name, config_val))
        }
      }
    }

    # Build pipeline type and pipeline string (without the "gdal raster pipeline" prefix)
    first_job <- pipeline$jobs[[1]]
    cmd_path <- first_job$command_path
    if (length(cmd_path) > 0 && cmd_path[1] == "gdal") {
      cmd_path <- cmd_path[-1]
    }
    pipeline_type <- if (length(cmd_path) > 0) cmd_path[1] else "raster"

    # Get just the pipeline string part (steps with !)
    pipeline_str <- .render_native_pipeline(pipeline)

    # Build full command with config options if any
    if (length(config_flags) > 0) {
      config_str <- paste(config_flags, collapse = " ")
      cmd <- sprintf("gdal %s pipeline %s %s", pipeline_type, config_str, pipeline_str)
    } else {
      cmd <- sprintf("gdal %s pipeline %s", pipeline_type, pipeline_str)
    }

    script_lines <- c(script_lines, "# Native GDAL pipeline execution", cmd, "")
  } else {
    # Render as separate GDAL commands (original behavior)
    # Add each job as a separate command
    for (i in seq_along(pipeline$jobs)) {
      job <- pipeline$jobs[[i]]

      # Serialize the job to command line
      args <- .serialize_gdal_job(job)
      cmd <- paste(c("gdal", args), collapse = " ")

      script_lines <- c(script_lines, sprintf("# Job %d", i))
      script_lines <- c(script_lines, cmd, "")
    }
  }

  # Join all lines
  paste(script_lines, collapse = "\n")
}
#' Add Job to Pipeline
#'
#' @description
#' Adds a new job to an existing pipeline.
#'
#' @param pipeline A `gdal_pipeline` object.
#' @param job A `gdal_job` object to add.
#'
#' @return A new `gdal_pipeline` object with the job added.
#'
#' @export
add_job <- function(pipeline, job) {
  UseMethod("add_job")
}


#' @rdname add_job
#' @export
add_job.gdal_pipeline <- function(pipeline, job) {
  if (!inherits(job, "gdal_job")) {
    rlang::abort("job must be a gdal_job object")
  }

  new_gdal_pipeline(
    c(pipeline$jobs, list(job)),
    name = pipeline$name,
    description = pipeline$description
  )
}


#' Get Pipeline Jobs
#'
#' @description
#' Returns the list of jobs in a pipeline.
#'
#' @param pipeline A `gdal_pipeline` object.
#'
#' @return A list of `gdal_job` objects.
#'
#' @export
get_jobs <- function(pipeline) {
  UseMethod("get_jobs")
}


#' @rdname get_jobs
#' @export
get_jobs.gdal_pipeline <- function(pipeline) {
  pipeline$jobs
}


#' Set Pipeline Name
#'
#' @description
#' Sets or updates the name of a pipeline.
#'
#' @param pipeline A `gdal_pipeline` object.
#' @param name Character string for the pipeline name.
#'
#' @return A new `gdal_pipeline` object with the updated name.
#'
#' @export
set_name <- function(pipeline, name) {
  UseMethod("set_name")
}


#' @rdname set_name
#' @export
set_name.gdal_pipeline <- function(pipeline, name) {
  new_gdal_pipeline(
    pipeline$jobs,
    name = name,
    description = pipeline$description
  )
}


#' Set Pipeline Description
#'
#' @description
#' Sets or updates the description of a pipeline.
#'
#' @param pipeline A `gdal_pipeline` object.
#' @param description Character string for the pipeline description.
#'
#' @return A new `gdal_pipeline` object with the updated description.
#'
#' @export
set_description <- function(pipeline, description) {
  UseMethod("set_description")
}


#' @rdname set_name
#' @export
set_name.gdal_job <- function(pipeline, name) {
  if (!is.null(pipeline$pipeline)) {
    # Modify the attached pipeline
    new_pipeline <- set_name(pipeline$pipeline, name)
    # Create new job with updated pipeline
    new_gdal_job(
      command_path = pipeline$command_path,
      arguments = pipeline$arguments,
      config_options = pipeline$config_options,
      env_vars = pipeline$env_vars,
      stream_in = pipeline$stream_in,
      stream_out_format = pipeline$stream_out_format,
      pipeline = new_pipeline
    )
  } else {
    # No pipeline, just return the job unchanged
    pipeline
  }
}

#' @rdname set_description
#' @export
set_description.gdal_pipeline <- function(pipeline, description) {
  new_gdal_pipeline(
    pipeline$jobs,
    name = pipeline$name,
    description = description
  )
}

#' @rdname set_description
#' @export
set_description.gdal_job <- function(pipeline, description) {
  if (!is.null(pipeline$pipeline)) {
    # Modify the attached pipeline
    new_pipeline <- set_description(pipeline$pipeline, description)
    # Create new job with updated pipeline
    new_gdal_job(
      command_path = pipeline$command_path,
      arguments = pipeline$arguments,
      config_options = pipeline$config_options,
      env_vars = pipeline$env_vars,
      stream_in = pipeline$stream_in,
      stream_out_format = pipeline$stream_out_format,
      pipeline = new_pipeline
    )
  } else {
    # No pipeline, just return the job unchanged
    pipeline
  }
}


#' Extend Pipeline with New Job
#'
#' @description
#' Creates a new job and adds it to the pipeline of an existing job,
#' effectively extending the pipeline. If the job has no pipeline,
#' creates a new pipeline starting with the job.
#'
#' Automatically connects outputs to inputs using virtual file systems
#' when not explicitly specified.
#'
#' @param job A `gdal_job` object that may or may not contain a pipeline.
#' @param command_path Character vector specifying the GDAL command path.
#' @param arguments List of arguments for the new job.
#'
#' @return A new `gdal_job` object with the extended pipeline.
#'
#' @export
extend_gdal_pipeline <- function(job, command_path, arguments) {
  if (!inherits(job, "gdal_job")) {
    rlang::abort("job must be a gdal_job object")
  }

  # Create the new job to add to the pipeline
  new_job <- new_gdal_job(
    command_path = command_path,
    arguments = arguments
  )

  # Check if the job already has a pipeline
  if (!is.null(job$pipeline)) {
    # Extend existing pipeline
    # Get the last job in the current pipeline to potentially modify its output
    current_jobs <- job$pipeline$jobs
    last_job <- current_jobs[[length(current_jobs)]]

    # Check if we need to connect output to input automatically
    needs_connection <- FALSE

    # Check if the new job has an input argument
    if ("input" %in% names(new_job$arguments)) {
      new_input <- new_job$arguments$input
      if (!.is_virtual_path(new_input)) {
        # User specified explicit input, don't connect
        needs_connection <- FALSE
      } else {
        needs_connection <- TRUE
      }
    } else {
      # No input specified for new job, we should connect
      needs_connection <- TRUE
    }

    if (needs_connection) {
      # Get the output from the last job to use as input for the new job
      connection_path <- NULL
      if ("output" %in% names(last_job$arguments)) {
        last_output <- last_job$arguments$output
        if (!.is_virtual_path(last_output)) {
          connection_path <- last_output
        }
      }

      # If we have a connection path, set it as input for the new job
      if (!is.null(connection_path)) {
        if ("input" %in% names(new_job$arguments)) {
          if (.is_virtual_path(new_job$arguments$input)) {
            new_job$arguments$input <- connection_path
          }
        } else {
          new_job$arguments$input <- connection_path
        }
      }
    }

    extended_pipeline <- add_job(job$pipeline, new_job)

    # Return a new job that represents the extended pipeline
    new_gdal_job(
      command_path = job$command_path,
      arguments = job$arguments,
      config_options = job$config_options,
      env_vars = job$env_vars,
      stream_in = job$stream_in,
      stream_out_format = job$stream_out_format,
      pipeline = extended_pipeline
    )
  } else {
    # No existing pipeline - create a new one starting with the current job
    # Check if we need to connect the first job to the new job
    needs_connection <- FALSE

    # Check if the new job has an input argument
    if ("input" %in% names(new_job$arguments)) {
      new_input <- new_job$arguments$input
      if (!.is_virtual_path(new_input)) {
        # User specified explicit input, don't connect
        needs_connection <- FALSE
      } else {
        needs_connection <- TRUE
      }
    } else {
      # No input specified for new job, we should connect
      needs_connection <- TRUE
    }

    if (needs_connection) {
      # Get the output from the current job to use as input for the new job
      connection_path <- NULL
      if ("output" %in% names(job$arguments)) {
        job_output <- job$arguments$output
        if (!.is_virtual_path(job_output)) {
          connection_path <- job_output
        }
      }

      # If we have a connection path, set it as input for the new job
      if (!is.null(connection_path)) {
        if ("input" %in% names(new_job$arguments)) {
          if (.is_virtual_path(new_job$arguments$input)) {
            new_job$arguments$input <- connection_path
          }
        } else {
          new_job$arguments$input <- connection_path
        }
      }
    }

    new_pipeline <- new_gdal_pipeline(list(job, new_job))

    # Return a new job that represents the new pipeline
    # Use the same properties as the input job, but with the new pipeline
    new_gdal_job(
      command_path = job$command_path,
      arguments = job$arguments,
      config_options = job$config_options,
      env_vars = job$env_vars,
      stream_in = job$stream_in,
      stream_out_format = job$stream_out_format,
      pipeline = new_pipeline
    )
  }
}


#' Process GDAL Pipeline (Convenience Wrapper)
#'
#' @description
#' Convenience function that automatically detects whether a pipeline contains
#' raster or vector operations and delegates to the appropriate `gdal_raster_pipeline()`
#' or `gdal_vector_pipeline()` function.
#'
#' This function is useful when you want a single unified interface to process
#' pipelines without needing to explicitly choose the raster or vector variant.
#'
#' @param jobs A list or vector of `gdal_job` objects to execute in sequence,
#'   or NULL to use pipeline string
#' @param pipeline A pipeline string (ignored if jobs is provided)
#' @param input Input dataset path(s)
#' @param output Output dataset path
#' @param ... Additional arguments passed to `gdal_raster_pipeline()` or `gdal_vector_pipeline()`
#'
#' @return A `gdal_job` object representing the pipeline.
#'
#' @details
#' The pipeline type is determined by examining the first job's command_path:
#' - If the first job is a raster command, `gdal_raster_pipeline()` is used
#' - If the first job is a vector command, `gdal_vector_pipeline()` is used
#' - Default is raster if type cannot be determined
#'
#' @examples
#' \dontrun{
#' # Auto-detect based on job type
#' job1 <- gdal_raster_reproject(input = "input.tif", dst_crs = "EPSG:32632")
#' job2 <- gdal_raster_convert(output = "output.tif")
#'
#' # This will automatically use gdal_raster_pipeline
#' pipeline <- gdal_pipeline(jobs = list(job1, job2))
#' }
#'
#' @export
gdal_pipeline <- function(jobs = NULL, pipeline = NULL, input = NULL, output = NULL, ...) {
  # If pipeline string is provided directly, determine type and delegate
  if (!is.null(pipeline) && is.null(jobs)) {
    # Default to raster if type not determinable from pipeline string
    return(gdal_raster_pipeline(pipeline = pipeline, input = input, output = output, ...))
  }

  # If jobs provided, detect type from first job
  if (!is.null(jobs)) {
    if (!is.list(jobs) && !is.vector(jobs)) {
      rlang::abort('jobs must be a list or vector of gdal_job objects')
    }

    if (length(jobs) == 0) {
      rlang::abort('jobs cannot be empty')
    }

    # Get the first job
    first_job <- jobs[[1]]
    if (!inherits(first_job, 'gdal_job')) {
      rlang::abort('first element of jobs must be a gdal_job object')
    }

    # Determine pipeline type from first job's command_path
    cmd_path <- first_job$command_path
    if (length(cmd_path) > 0 && cmd_path[1] == "gdal") {
      cmd_path <- cmd_path[-1]
    }

    pipeline_type <- if (length(cmd_path) > 0) cmd_path[1] else "raster"

    # Delegate to appropriate pipeline function
    if (pipeline_type == "vector") {
      return(gdal_vector_pipeline(jobs = jobs, input = input, output = output, ...))
    } else {
      # Default to raster for any other type
      return(gdal_raster_pipeline(jobs = jobs, input = input, output = output, ...))
    }
  }

  # No jobs or pipeline provided
  rlang::abort('Either jobs or pipeline must be provided')
}


#' @keywords internal