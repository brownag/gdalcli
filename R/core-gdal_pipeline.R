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
is_virtual_path <- function(path) {
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
#' @param ... Additional arguments passed to individual job execution.
#' @param verbose Logical. If `TRUE`, prints progress information. Default `FALSE`.
#'
#' @return Invisibly returns `TRUE` on successful completion.
#'
#' @seealso
#' [gdal_job_run.gdal_job()], [render_gdal_pipeline()]
#'
#' @export
gdal_job_run.gdal_pipeline <- function(x, ..., verbose = FALSE) {
  if (length(x$jobs) == 0) {
    if (verbose) cli::cli_alert_info("Pipeline is empty - nothing to execute")
    return(invisible(TRUE))
  }

  if (verbose) {
    cli::cli_alert_info(sprintf("Executing pipeline with %d jobs", length(x$jobs)))
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
    }, error = function(e) {
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


#' Render GDAL Pipeline as GDAL Pipeline Command
#'
#' @description
#' Converts a `gdal_pipeline` into a GDAL pipeline command string that can be
#' executed directly with `gdal pipeline`.
#'
#' @param pipeline A `gdal_pipeline` object.
#' @param ... Additional arguments (unused).
#'
#' @return A character string containing the GDAL pipeline command.
#'
#' @seealso
#' [render_shell_script()], [gdal_job_run.gdal_pipeline()]
#'
#' @export
render_gdal_pipeline <- function(pipeline, ...) {
  UseMethod("render_gdal_pipeline")
}


#' @rdname render_gdal_pipeline
#' @export
render_gdal_pipeline.gdal_job <- function(pipeline, ...) {
  if (!is.null(pipeline$pipeline)) {
    render_gdal_pipeline(pipeline$pipeline, ...)
  } else {
    # No pipeline history, render just this job
    args <- .serialize_gdal_job(pipeline)
    paste(c("gdal", args), collapse = " ")
  }
}

#' @rdname render_gdal_pipeline
#' @export
render_gdal_pipeline.gdal_pipeline <- function(pipeline, ...) {
  if (length(pipeline$jobs) == 0) {
    return("gdal pipeline")
  }

  # For now, render as a sequence of separate GDAL commands
  # TODO: Implement proper GDAL pipeline syntax when available
  commands <- character()
  for (i in seq_along(pipeline$jobs)) {
    job <- pipeline$jobs[[i]]
    args <- .serialize_gdal_job(job)
    cmd <- paste(c("gdal", args), collapse = " ")
    commands <- c(commands, cmd)
  }

  paste(commands, collapse = " && ")
}


#' Render GDAL Pipeline as Shell Script
#'
#' @description
#' Converts a `gdal_pipeline` into a shell script that executes the jobs sequentially.
#'
#' @param pipeline A `gdal_pipeline` object.
#' @param shell Character string specifying shell type: `"bash"` (default) or `"zsh"`.
#' @param ... Additional arguments (unused).
#'
#' @return A character string containing the shell script.
#'
#' @seealso
#' [render_gdal_pipeline()], [gdal_job_run.gdal_pipeline()]
#'
#' @export
render_shell_script <- function(pipeline, shell = "bash", ...) {
  UseMethod("render_shell_script")
}


#' @rdname render_shell_script
#' @export
render_shell_script.gdal_job <- function(pipeline, shell = "bash", ...) {
  if (!is.null(pipeline$pipeline)) {
    render_shell_script(pipeline$pipeline, shell = shell, ...)
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
render_shell_script.gdal_pipeline <- function(pipeline, shell = "bash", ...) {
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
    script_lines <- c(script_lines, sprintf("# %s", pipeline$name))
  }
  if (!is.null(pipeline$description)) {
    script_lines <- c(script_lines, sprintf("# %s", pipeline$description))
  }
  script_lines <- c(script_lines, "")

  # Add set -e for error handling
  script_lines <- c(script_lines, "set -e", "")

  # Add each job as a separate command
  for (i in seq_along(pipeline$jobs)) {
    job <- pipeline$jobs[[i]]

    # Serialize the job to command line
    args <- .serialize_gdal_job(job)
    cmd <- paste(c("gdal", args), collapse = " ")

    script_lines <- c(script_lines, sprintf("# Job %d", i))
    script_lines <- c(script_lines, cmd, "")
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
set_name.gdal_pipeline <- function(pipeline, name) {
  new_gdal_pipeline(
    pipeline$jobs,
    name = name,
    description = pipeline$description
  )
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
      if (!is_virtual_path(new_input)) {
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
        if (!is_virtual_path(last_output)) {
          connection_path <- last_output
        }
      }

      # If we have a connection path, set it as input for the new job
      if (!is.null(connection_path)) {
        if ("input" %in% names(new_job$arguments)) {
          if (is_virtual_path(new_job$arguments$input)) {
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
      if (!is_virtual_path(new_input)) {
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
        if (!is_virtual_path(job_output)) {
          connection_path <- job_output
        }
      }

      # If we have a connection path, set it as input for the new job
      if (!is.null(connection_path)) {
        if ("input" %in% names(new_job$arguments)) {
          if (is_virtual_path(new_job$arguments$input)) {
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


#' Handle Job Input for Pipeline Extension
#'
#' @description
#' Processes the job parameter to determine if pipeline extension
#' should occur or if arguments should be merged for job modification.
#'
#' @param job A gdal_job object or NULL.
#' @param new_args List of new arguments passed to the function.
#' @param full_path Character vector representing the command path.
#'
#' @return A list with elements:
#'   - should_extend: Logical indicating if pipeline should be extended.
#'   - job: The job object to extend from (if extending).
#'   - merged_args: Arguments for creating a new job (if not extending).
#'
handle_job_input <- function(job, new_args, full_path) {
  # If no job provided, create new job with merged arguments
  if (is.null(job)) {
    return(list(
      should_extend = FALSE,
      job = NULL,
      merged_args = new_args
    ))
  }

  # Validate job object
  if (!inherits(job, 'gdal_job')) {
    rlang::abort('job must be a gdal_job object or NULL')
  }

  # For base pipe integration, we always want to create/extend a pipeline
  # If job has a pipeline, extend it
  # If job has no pipeline, create one starting with this job
  return(list(
    should_extend = TRUE,
    job = job,
    merged_args = NULL
  ))
}