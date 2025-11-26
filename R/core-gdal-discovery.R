#' Discover GDAL CLI Commands and Help
#'
#' @description
#' Utility functions for discovering available GDAL CLI commands and getting help
#' for specific operations. These functions wrap gdalraster's discovery functions
#' when available.
#'
#' `gdal_list_commands()` lists all available GDAL CLI algorithms across modules.
#' This is useful for discovering what operations are available without needing
#' to refer to external documentation.
#'
#' `gdal_command_help()` displays detailed help for a specific GDAL command,
#' including usage, available options, and descriptions.
#'
#' @param command Optional command/module name to filter results. If provided,
#'   lists only commands matching the pattern. Format: "module.operation" or
#'   "module" to see all operations in that module.
#' @param output Character string: `"data.frame"` (default) returns results as
#'   a data frame suitable for inspection in RStudio, or `"list"` to return
#'   raw list output.
#'
#' @return
#' For `gdal_list_commands()`:
#' - If `output = "data.frame"`: A data frame with columns for command/module/operation
#' - If `output = "list"`: A list of available commands
#'
#' For `gdal_command_help()`:
#' - Character string containing the command help/usage information
#'
#' @examples
#' \dontrun{
#' # List all available commands
#' gdal_list_commands()
#'
#' # List all raster commands
#' gdal_list_commands("raster")
#'
#' # Get help for a specific command
#' gdal_command_help("raster.info")
#' }
#'
#' @export
gdal_list_commands <- function(command = NULL, output = "data.frame") {
  # Check if gdalraster is available with command discovery support
  if (!.check_gdalraster_version("2.2.0", quietly = TRUE)) {
    cli::cli_abort(
      c(
        "gdalraster package required for command discovery",
        "i" = "Install with: install.packages('gdalraster')",
        "i" = "Requires gdalraster version 2.2.0 or later"
      )
    )
  }

  # Verify gdal_commands function exists
  if (!.gdal_has_feature("gdal_commands", quietly = TRUE)) {
    cli::cli_abort(
      c(
        "GDAL command discovery not available",
        "i" = "Requires gdalraster >= 2.2.0 with GDAL 3.11+"
      )
    )
  }

  tryCatch({
    # Call gdalraster::gdal_commands() to get list of available commands
    all_commands <- gdalraster::gdal_commands()

    # Filter if command pattern is provided
    if (!is.null(command)) {
      # Support both "module.operation" and "module" formats
      pattern <- if (grepl("\\.", command)) {
        # Exact match format
        paste0("^", gsub("\\.", "\\\\.", command), "$")
      } else {
        # Prefix match for module names
        paste0("^", command, "\\.")
      }
      matching <- all_commands[grepl(pattern, all_commands)]

      if (length(matching) == 0) {
        cli::cli_warn(
          c(
            "No commands match the pattern: {command}",
            "i" = "Use gdal_list_commands() to see all available commands"
          )
        )
        return(character())
      }

      all_commands <- matching
    }

    # Return based on requested output format
    if (output == "data.frame") {
      # Parse command strings (format: "module.operation") into a data frame
      parts <- strsplit(all_commands, "\\.")
      df <- data.frame(
        command = all_commands,
        module = sapply(parts, function(x) x[1]),
        operation = sapply(parts, function(x) paste(x[-1], collapse = ".")),
        stringsAsFactors = FALSE
      )
      return(df)
    } else if (output == "list") {
      return(all_commands)
    } else {
      cli::cli_abort("output must be 'data.frame' or 'list'")
    }
  }, .error = function(e) {
    cli::cli_abort(
      c(
        "Failed to retrieve GDAL commands",
        "x" = conditionMessage(e),
        "i" = "Ensure GDAL 3.11+ is installed and gdalraster is properly configured"
      )
    )
  })
}


#' @rdname gdal_list_commands
#' @param command Character string: the command to get help for,
#'   in format "module.operation" (e.g., "raster.info", "vector.convert")
#' @export
gdal_command_help <- function(command) {
  if (missing(command) || !is.character(command) || length(command) != 1) {
    cli::cli_abort("command must be a single character string (e.g., 'raster.info')")
  }

  # Check if gdalraster is available with help support
  if (!.check_gdalraster_version("2.2.0", quietly = TRUE)) {
    cli::cli_abort(
      c(
        "gdalraster package required for command help",
        "i" = "Install with: install.packages('gdalraster')",
        "i" = "Requires gdalraster version 2.2.0 or later"
      )
    )
  }

  # Verify gdal_usage function exists
  if (!.gdal_has_feature("gdal_usage", quietly = TRUE)) {
    cli::cli_abort(
      c(
        "GDAL command help not available",
        "i" = "Requires gdalraster >= 2.2.0 with GDAL 3.11+"
      )
    )
  }

  # Parse the command format (module.operation or module operation)
  cmd_parts <- if (grepl("\\.", command)) {
    strsplit(command, "\\.")[[1]]
  } else {
    strsplit(command, " ")[[1]]
  }

  if (length(cmd_parts) < 2) {
    cli::cli_abort(
      c(
        "Invalid command format: {command}",
        "i" = "Use format: 'module.operation' (e.g., 'raster.info')"
      )
    )
  }

  tryCatch({
    # Call gdalraster::gdal_usage() to get help for this command
    help_text <- gdalraster::gdal_usage(cmd_parts)
    return(help_text)
  }, .error = function(e) {
    cli::cli_abort(
      c(
        "Failed to retrieve help for command: {command}",
        "x" = conditionMessage(e),
        "i" = "Verify the command name with gdal_list_commands()"
      )
    )
  })
}


#' Check GDAL Version Requirements
#'
#' @description
#' Helper function to check if the installed GDAL version meets minimum requirements.
#' Useful when certain features require specific GDAL versions.
#'
#' @param minimum Character string: minimum required GDAL version (e.g., "3.12").
#' @param op Character string: comparison operator. One of: `"=="`, `"!="`,
#'   `"<"`, `"<="`, `">"`, `">="`. Defaults to `">="`.
#'
#' @return
#' Logical `TRUE` if version requirement is met, `FALSE` otherwise.
#' Raises an .error if the version check fails.
#'
#' @examples
#' \dontrun{
#' # Check if GDAL is at least version 3.11
#' gdal_check_version("3.11")
#'
#' # Check if GDAL is version 3.12 or later
#' gdal_check_version("3.12", op = ">=")
#'
#' # Use in conditional logic
#' if (gdal_check_version("3.12")) {
#'   # Use GDAL 3.12+ features
#' }
#' }
#'
#' @export
gdal_check_version <- function(minimum = "3.11", op = ">=") {
  # Check valid operator
  valid_ops <- c("==", "!=", "<", "<=", ">", ">=")
  if (!op %in% valid_ops) {
    cli::cli_abort(
      "op must be one of: {paste(valid_ops, collapse = ', ')}"
    )
  }

  # Get current GDAL version using gdalraster if available
  current_version <- tryCatch({
    if (requireNamespace("gdalraster", quietly = TRUE)) {
      # Get version from gdalraster
      # gdal_version() returns a character vector with multiple elements:
      # [1] = long description
      # [2] = numeric version (e.g., "3110400")
      # [3] = release date
      # [4] = simple version (e.g., "3.11.4") <- use this one
      version_info <- gdalraster::gdal_version()

      if (is.character(version_info) && length(version_info) >= 4) {
        # Use the 4th element which is the simple version string
        version_info[4]
      } else if (is.character(version_info) && length(version_info) > 0) {
        # Fallback: parse from the first element
        matches <- regmatches(
          version_info[1],
          regexpr("[0-9]+\\.[0-9]+\\.[0-9]+", version_info[1])
        )
        if (length(matches) > 0) {
          trimws(matches[1])
        } else {
          cli::cli_abort("Could not extract GDAL version from gdalraster")
        }
      } else {
        cli::cli_abort("Could not extract GDAL version from gdalraster")
      }
    } else {
      # Fallback: try to get from gdal command-line
      result <- tryCatch(
        processx::run("gdal", c("--version"), error_on_status = FALSE),
        .error = function(e) NULL
      )

      if (!is.null(result) && result$status == 0) {
        # Parse version from output like "GDAL 3.11.4 "Eganville", released..."
        # Extract version number from stdout and trim whitespace
        matches <- regmatches(
          result$stdout,
          regexpr("[0-9]+\\.[0-9]+\\.[0-9]+", result$stdout)
        )
        if (length(matches) > 0) {
          trimws(matches[1])
        } else {
          cli::cli_abort("Could not parse GDAL version from output")
        }
      } else {
        cli::cli_abort(
          c(
            "Could not determine GDAL version",
            "i" = "Ensure GDAL is installed and in PATH"
          )
        )
      }
    }
  }, .error = function(e) {
    cli::cli_abort(
      c(
        "Failed to get GDAL version",
        "x" = conditionMessage(e)
      )
    )
  })

  # Parse versions to numeric for comparison
  parse_version <- function(v) {
    v <- trimws(v)
    parts <- suppressWarnings(as.numeric(strsplit(v, "\\.")[[1]]))

    # Handle parsing errors
    if (any(is.na(parts))) {
      cli::cli_abort("Invalid version format: {v}")
    }

    # Return as numeric: major * 10000 + minor * 100 + patch
    parts[1] * 10000 + (if (length(parts) > 1) parts[2] * 100 else 0) +
      (if (length(parts) > 2) parts[3] else 0)
  }

  current_numeric <- parse_version(current_version)
  minimum_numeric <- parse_version(minimum)

  # Perform comparison
  result <- switch(op,
    "==" = current_numeric == minimum_numeric,
    "!=" = current_numeric != minimum_numeric,
    "<" = current_numeric < minimum_numeric,
    "<=" = current_numeric <= minimum_numeric,
    ">" = current_numeric > minimum_numeric,
    ">=" = current_numeric >= minimum_numeric,
    FALSE
  )

  return(result)
}
