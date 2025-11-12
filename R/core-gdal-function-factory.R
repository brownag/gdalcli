#' GDAL Function Factory
#'
#' @description
#' Metaprogramming utilities to create user-facing GDAL functions
#' dynamically from command signatures.
#'
#' @details
#' The factory uses `rlang::new_function()` to create functions with
#' proper named arguments that return `gdal_job` objects. This enables
#' full IDE autocompletion and type checking.
#'
#' @keywords internal

#' Create Function from GDAL Command Signature
#'
#' Factory function that creates a proper R function from a parsed
#' GDAL command signature.
#'
#' @param cmd_path Character vector of command hierarchy
#' @param parsed_sig List from parse_gdal_usage()
#'
#' @return A function that returns a gdal_job object
#'
#' @keywords internal
create_function_from_signature <- function(cmd_path, parsed_sig) {
  # Validate inputs
  if (!is.character(cmd_path) || length(cmd_path) == 0) {
    cli::cli_abort("cmd_path must be a non-empty character vector")
  }

  # Capture command path in closure
  captured_cmd_path <- cmd_path
  captured_formals <- parsed_sig$formals

  # Create function body
  func_body <- build_function_body(captured_cmd_path)

  # Create the function using rlang
  new_func <- rlang::new_function(
    args = captured_formals,
    body = func_body,
    env = parent.frame()
  )

  # Add attributes for introspection
  attr(new_func, "command_path") <- captured_cmd_path
  attr(new_func, "parsed_signature") <- parsed_sig
  attr(new_func, "dynamic") <- TRUE

  new_func
}

#' Build Function Body for GDAL Command
#'
#' Creates the body of a GDAL command function.
#'
#' @param cmd_path Character vector of command hierarchy
#'
#' @return Quoted expression for function body
#'
#' @keywords internal
build_function_body <- function(cmd_path) {
  # Build a closure that captures cmd_path
  body_expr <- substitute({
    # Capture all arguments including ...
    call_args <- match.call(expand.dots = FALSE)

    # Remove function name from call
    call_args[[1]] <- NULL

    # Convert remaining args to named list
    arg_list <- list()
    for (name in names(call_args)) {
      if (name == "...") {
        # Handle ... specially - expand it
        dots <- eval(call_args[[name]])
        if (is.list(dots)) {
          arg_list <- c(arg_list, dots)
        }
      } else {
        # Regular argument - evaluate it
        arg_list[[name]] <- eval(call_args[[name]], envir = parent.frame())
      }
    }

    # Create and return gdal_job
    new_gdal_job(
      command_path = CMD_PATH,
      arguments = arg_list
    )
  }, list(CMD_PATH = cmd_path))

  body_expr
}

#' Create Wrapper Function for GDAL Command
#'
#' Higher-level wrapper that creates a complete GDAL command function
#' with documentation and validation.
#'
#' @param cmd_path Character vector of command hierarchy
#' @param cmd_name Character name for the function
#' @param usage_text Optional help text from GDAL
#'
#' @return A function object ready to be assigned
#'
#' @keywords internal
create_gdal_command_function <- function(cmd_path, cmd_name = NULL, usage_text = "") {
  # Default to last component of path as function name
  if (is.null(cmd_name)) {
    cmd_name <- cmd_path[length(cmd_path)]
  }

  # Parse usage if provided
  parsed_sig <- parse_gdal_usage(cmd_path, usage_text)

  # Create the function
  func <- create_function_from_signature(cmd_path, parsed_sig)

  # Add documentation string if available
  if (nzchar(usage_text)) {
    # Extract a summary line from usage text
    summary <- extract_summary_from_usage(usage_text)
    attr(func, "summary") <- summary
  }

  func
}

#' Extract Summary from GDAL Usage Text
#'
#' Extracts a brief summary line from GDAL help text.
#'
#' @param usage_text Help text from GDAL command
#'
#' @return Character string with summary or empty string
#'
#' @keywords internal
extract_summary_from_usage <- function(usage_text) {
  if (!nzchar(usage_text)) {
    return("")
  }

  # Get first non-empty line after "Usage:"
  lines <- strsplit(usage_text, "\n")[[1]]

  # Find the first descriptive line (usually after Usage section)
  for (i in seq_along(lines)) {
    line <- trimws(lines[i])

    # Skip usage line itself
    if (grepl("^[Uu]sage", line)) {
      next
    }

    # Skip empty lines
    if (!nzchar(line)) {
      next
    }

    # Skip lines that look like option definitions
    if (grepl("^-", line)) {
      next
    }

    # Found a descriptive line
    return(line)
  }

  ""
}

#' Validate GDAL Function
#'
#' Checks that a created function has proper structure.
#'
#' @param func Function to validate
#'
#' @return Logical, invisibly TRUE if valid, error otherwise
#'
#' @keywords internal
validate_gdal_function <- function(func) {
  if (!is.function(func)) {
    cli::cli_abort("Expected a function, got {typeof(func)}")
  }

  # Check for required attributes
  if (!("command_path" %in% names(attributes(func)))) {
    cli::cli_warn("Function missing command_path attribute")
  }

  invisible(TRUE)
}
