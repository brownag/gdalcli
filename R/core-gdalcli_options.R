#' Manage gdalcli Options
#'
#' Get and set package options for gdalcli. Options control default behaviors
#' for execution, output, and logging.
#'
#' @param ... Named arguments to set options. Option names should be provided
#'   without the "gdalcli." prefix (e.g., `backend = "processx"` not
#'   `gdalcli.backend = "processx"`). If no arguments are provided, returns
#'   a list of all option values.
#'
#' @details
#'
#' ## Available Options
#'
#' - `backend`: Which backend to use for command execution. Options are:
#'   - `"auto"` (default): Automatically select based on available backends
#'   - `"gdalraster"`: Use gdalraster backend (faster, direct API calls)
#'   - `"processx"`: Use processx backend (universal, subprocess-based)
#'   - `"reticulate"`: Use reticulate backend (Python GDAL bindings)
#'
#' - `stream_out_format`: Format for streaming output. Options are:
#'   - `NULL` (default): No streaming format preference
#'   - `"text"`: Use text format for streaming output
#'   - `"binary"`: Use binary format for streaming output
#'
#' - `verbose`: Enable verbose output during job execution.
#'   - `FALSE` (default): No verbose output
#'   - `TRUE`: Print detailed execution information
#'
#' - `audit_logging`: Enable audit logging of executed commands.
#'   - `FALSE` (default): No audit logging
#'   - `TRUE`: Log all commands to audit trail (requires setting up audit handler)
#'
#' @return
#' When called without arguments, returns a named list of all option values.
#' When called with arguments, invisibly returns the previous values as a list.
#'
#' @examples
#' # Get current option values
#' gdalcli_options()
#'
#' # Set options
#' gdalcli_options(backend = "processx", verbose = TRUE)
#'
#' # Set multiple options at once
#' gdalcli_options(
#'   backend = "gdalraster",
#'   verbose = FALSE,
#'   audit_logging = TRUE
#' )
#'
#' @export
gdalcli_options <- function(...) {
  # Define default option values
  defaults <- list(
    backend = "auto",
    stream_out_format = NULL,
    verbose = FALSE,
    audit_logging = FALSE
  )

  # Get current values
  current <- list(
    backend = getOption("gdalcli.backend", defaults$backend),
    stream_out_format = getOption("gdalcli.stream_out_format", defaults$stream_out_format),
    verbose = getOption("gdalcli.verbose", defaults$verbose),
    audit_logging = getOption("gdalcli.audit_logging", defaults$audit_logging)
  )

  # Collect arguments to set
  args <- list(...)

  # If no arguments, return current values
  if (length(args) == 0) {
    return(current)
  }

  # Validate and set options
  valid_names <- names(defaults)
  provided_names <- names(args)

  # Check for invalid option names
  invalid <- setdiff(provided_names, valid_names)
  if (length(invalid) > 0) {
    stop(
      "Unknown option(s): ", paste0("'", invalid, "'", collapse = ", "),
      "\nValid options are: ", paste0("'", valid_names, "'", collapse = ", ")
    )
  }

  # Validate backend option if being set
  if (!is.null(args$backend)) {
    valid_backends <- c("auto", "gdalraster", "processx", "reticulate")
    if (!args$backend %in% valid_backends) {
      stop(
        "Invalid backend: '", args$backend, "'",
        "\nValid backends are: ", paste0("'", valid_backends, "'", collapse = ", ")
      )
    }
  }

  # Set each option with "gdalcli." prefix
  for (name in provided_names) {
    option_name <- paste0("gdalcli.", name)
    options(stats::setNames(list(args[[name]]), option_name))
  }

  # Return previous values invisibly
  invisible(current)
}
