#' Define and Create a GDAL Job Specification
#'
#' @description
#' The `gdal_job` S3 class is the central data structure that encapsulates a GDAL command
#' specification. It implements the lazy evaluation framework, where commands are constructed
#' as objects and only executed when passed to [gdal_run()].
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
#'
#' @return
#' An S3 object of class `gdal_job`.
#'
#' @seealso
#' [gdal_run()], [gdal_with_co()], [gdal_with_config()], [gdal_with_env()]
#'
#' @examples
#' # Low-level constructor (typically used internally by auto-generated functions)
#' job <- new_gdal_job(
#'   command_path = c("vector", "convert"),
#'   arguments = list(input = "/path/to/input.shp", output = "/path/to/output.gpkg")
#' )
#'
#' # High-level constructor (end-user API)
#' job <- gdal_vector_convert(
#'   input = "/path/to/input.shp",
#'   output = "/path/to/output.gpkg"
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
                         stream_out_format = NULL) {
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
    stream_out_format = stream_out_format
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
  cat("Command:  gdal", paste(x$command_path, collapse = " "), "\n")

  if (length(x$arguments) > 0) {
    cat("Arguments:\n")
    for (i in seq_along(x$arguments)) {
      arg_name <- names(x$arguments)[i]
      arg_val <- x$arguments[[i]]

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

      cat(sprintf("  --%s: %s\n", arg_name, val_str))
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

  invisible(x)
}
