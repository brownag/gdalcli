#' Programmatic GDAL Command Invocation
#'
#' @description
#' Call any gdalcli-wrapped GDAL command dynamically by name or function
#' reference.
#' Provides a do.call-style interface that complements the lazy evaluation
#' model,
#' enabling metaprogramming, serialization, and boilerplate reduction for
#' repetitive command patterns.
#'
#' @param what Character string (e.g., `"gdal_raster_clip"`, `"gdal_vector_convert"`)
#'   or a function object (e.g., `gdal_raster_clip`).
#' @param args Named list of arguments to pass to the function. Arguments are
#'   processed exactly as if they were passed directly to the wrapped function.
#' @param modifiers Optional list of modifier functions to apply in sequence.
#'   Each element should be a function that accepts a [gdal_job] and returns a
#'   modified [gdal_job]. Example: `list(function(x) gdal_with_co(x, "COMPRESS=DEFLATE"), function(x) gdal_with_config(x, "CPL_DEBUG" = "ON"))`.
#'   Modifiers are applied after the base command is constructed, in list order.
#'
#' @return
#' A [gdal_job] object ready to be piped (`|>`) to [gdal_job_run()], extended
#' with additional modifiers, or serialized for later execution.
#'
#' @details
#' `gdal_call()` provides three main use cases:
#'
#' **1. Dynamic command selection**: When the command name is not known until
#'   runtime (e.g., constructed from user input or configuration):
#'   ```r
#'   cmd_name <- paste0("gdal_", input_type, "_", operation)
#'   job <- gdal_call(cmd_name, user_args)
#'   ```
#'
#' **2. Programmatic execution of repetitive patterns**: Reducing boilerplate when
#'   running similar commands with different inputs:
#'   ```r
#'   commands <- list(
#'     list("gdal_raster_clip", list(input = "a.tif", output = "a_clipped.tif", ...)),
#'     list("gdal_raster_clip", list(input = "b.tif", output = "b_clipped.tif", ...))
#'   )
#'   results <- lapply(commands, function(x) {
#'     gdal_call(x[[1]], x[[2]]) |> gdal_job_run()
#'   })
#'   ```
#'
#' **3. Serialization and metaprogramming**: Integration with other languages or
#'   serialization formats (e.g., JSON-based job specifications):
#'   ```r
#'   spec <- jsonlite::fromJSON('{"command": "gdal_raster_convert", "args": {...}}')
#'   job <- gdal_call(spec$command, spec$args)
#'   ```
#'
#' The function integrates seamlessly with gdalcli's pipe-friendly interface and
#' modifier composition model.
#'
#' @examples
#' \dontrun{
#' # By function reference
#' job <- gdal_call(gdal_raster_info, list(input = "input.tif"))
#'
#' # By character string
#' job <- gdal_call("gdal_raster_clip", list(
#'   input = "input.tif",
#'   output = "output.tif",
#'   projwin = c(0, 100, 100, 0)
#' ))
#'
#' # With modifiers applied in sequence
#' job <- gdal_call("gdal_raster_convert",
#'   list(input = "input.tif", output = "output.tif"),
#'   modifiers = list(
#'     gdal_with_co("COMPRESS=DEFLATE"),
#'     gdal_with_config("GDAL_CACHEMAX" = "512")
#'   )
#' )
#'
#' # Use in pipeline
#' result <- gdal_call("gdal_raster_info", list(input = "file.tif")) |>
#'   gdal_job_run()
#'
#' # Programmatic execution
#' files <- c("a.tif", "b.tif", "c.tif")
#' results <- lapply(files, function(f) {
#'   gdal_call("gdal_raster_info", list(input = f)) |>
#'     gdal_job_run()
#' })
#' }
#'
#' @seealso
#' [gdal_list_callable_commands()] to discover available commands,
#' [gdal_job_run()] to execute a job,
#' [gdal_with_co()], [gdal_with_config()], [gdal_with_env()] for modifiers.
#'
#' @export
gdal_call <- function(what, args = list(), modifiers = NULL) {
  # Validate args is a list
  if (!is.list(args)) {
    rlang::abort(c(
      "x" = "args must be a named list",
      "i" = sprintf("Got: %s", class(args)[[1L]])
    ))
  }

  # Resolve function reference or character name to function
  if (is.character(what)) {
    if (length(what) != 1L) {
      rlang::abort(c(
        "x" = "what must be a single character string or function",
        "i" = sprintf("Got character vector of length %d", length(what))
      ))
    }

    # Check if function exists in gdalcli namespace
    if (!exists(what, envir = asNamespace("gdalcli"), mode = "function")) {
      rlang::abort(c(
        "x" = sprintf("Function '%s' not found in gdalcli", what),
        "i" = "Use gdal_list_callable_commands() to see available commands"
      ))
    }

    fn <- get(what, envir = asNamespace("gdalcli"))
  } else if (is.function(what)) {
    fn <- what
  } else {
    rlang::abort(c(
      "x" = "what must be a character string or function",
      "i" = sprintf("Got: %s", class(what)[[1L]])
    ))
  }

  # Call function with provided arguments using rlang::exec for proper splicing
  job <- tryCatch(
    rlang::exec(fn, !!!args),
    error = function(e) {
      rlang::abort(c(
        "x" = sprintf("Error calling function with provided arguments"),
        "i" = conditionMessage(e)
      ), parent = e)
    }
  )

  # Validate result is a gdal_job
  if (!inherits(job, "gdal_job")) {
    rlang::abort(c(
      "x" = "Function did not return a gdal_job object",
      "i" = sprintf("Got: %s", paste(class(job), collapse = ", "))
    ))
  }

  # Apply modifiers in sequence if provided
  if (!is.null(modifiers)) {
    if (!is.list(modifiers)) {
      rlang::abort(c(
        "x" = "modifiers must be a list of functions or NULL",
        "i" = sprintf("Got: %s", class(modifiers)[[1L]])
      ))
    }

    for (i in seq_along(modifiers)) {
      modifier <- modifiers[[i]]

      if (!is.function(modifier)) {
        rlang::abort(c(
          "x" = sprintf("modifiers[[%d]] is not a function", i),
          "i" = sprintf("Got: %s", class(modifier)[[1L]])
        ))
      }

      tryCatch(
        job <- modifier(job),
        error = function(e) {
          rlang::abort(c(
            "x" = sprintf("Error applying modifier %d", i),
            "i" = conditionMessage(e)
          ), parent = e)
        }
      )

      # Validate that modifier returned a gdal_job
      if (!inherits(job, "gdal_job")) {
        rlang::abort(c(
          "x" = sprintf("Modifier %d did not return a gdal_job object", i),
          "i" = sprintf("Got: %s", paste(class(job), collapse = ", "))
        ))
      }
    }
  }

  job
}


#' List Available GDAL Commands
#'
#' @description
#' Discover and list all gdalcli-wrapped GDAL commands available for invocation
#' via [gdal_call()]. Useful for programmatic exploration of available
#' functionality and command composition.
#'
#' @param type Optional character string to filter by command type. One of:
#'   `"raster"`, `"vector"`, `"vsi"`, `"driver"`, `"mdim"`, `"pipeline"`, or
#'   `NULL` (default) to return all commands.
#' @param simplify Logical. If `TRUE` (default), returns a character vector of
#'   command names. If `FALSE`, returns a data frame with additional metadata
#'   (command name, type, function object).
#'
#' @return
#' If `simplify = TRUE`: A character vector of command names suitable for use
#' as the `what` argument to [gdal_call()].
#'
#' If `simplify = FALSE`: A data frame with columns:
#' - `command` (character): Function name (e.g., `"gdal_raster_info"`)
#' - `type` (character): Command type (e.g., `"raster"`, `"vector"`)
#' - `func` (list): Function object (use with `gdal_call(df$func[[i]], ...)`)
#'
#' @examples
#' \dontrun{
#' # Get all available commands
#' all_commands <- gdal_list_callable_commands()
#' head(all_commands, 10)
#'
#' # Filter to raster commands only
#' raster_commands <- gdal_list_callable_commands(type = "raster")
#'
#' # Get detailed metadata
#' details <- gdal_list_callable_commands(simplify = FALSE)
#' head(details)
#'
#' # Use in programmatic iteration
#' vector_cmds <- gdal_list_callable_commands(type = "vector", simplify = FALSE)
#' for (i in seq_nrow(vector_cmds)) {
#'   cat(vector_cmds$command[[i]], "\n")
#' }
#' }
#'
#' @seealso [gdal_call()] to invoke commands dynamically.
#'
#' @export
gdal_list_callable_commands <- function(type = NULL, simplify = TRUE) {
  # Get all exported symbols from gdalcli namespace
  all_exports <- getNamespaceExports("gdalcli")

  # Filter to gdal_* functions only
  gdal_fns <- all_exports[startsWith(all_exports, "gdal_")]

  # Further filter out non-command functions (e.g., gdal_job_run, gdal_with_*)
  # Keep only the actual command wrappers (gdal_<type>_<command>)
  gdal_fns <- gdal_fns[grepl("^gdal_[a-z]+_", gdal_fns)]

  # Exclude modifier/utility functions
  exclude_patterns <- c(
    "^gdal_with_", "^gdal_job_", "gdal_load_", "gdal_save_",
    "gdal_call", "gdal_list_", "gdal_has_", "gdal_check_",
    "gdal_compose", "gdal_capabilities", "gdal_driver_",
    "gdal_auth_", "gdal_.*_get_", "^gdal_create_"
  )

  for (pattern in exclude_patterns) {
    gdal_fns <- gdal_fns[!grepl(pattern, gdal_fns)]
  }

  # Extract command type from function name
  extract_type <- function(fn_names) {
    # gdal_<type>_<command> -> type
    sub("^gdal_([^_]+)_.*", "\\1", fn_names)
  }

  types <- extract_type(gdal_fns)

  # Filter by type if specified
  if (!is.null(type)) {
    if (!is.character(type) || length(type) != 1L) {
      rlang::abort(c(
        "x" = "type must be a single character string or NULL",
        "i" = sprintf("Got: %s", paste(type, collapse = ", "))
      ))
    }

    valid_types <- c("raster", "vector", "vsi", "driver", "mdim", "pipeline")
    if (!type %in% valid_types) {
      rlang::abort(c(
        "x" = sprintf("type '%s' not recognized", type),
        "i" = sprintf("Valid types: %s", paste(valid_types, collapse = ", "))
      ))
    }

    mask <- types == type
    gdal_fns <- gdal_fns[mask]
    types <- types[mask]
  }

  # Sort alphabetically
  sort_idx <- order(gdal_fns)
  gdal_fns <- gdal_fns[sort_idx]
  types <- types[sort_idx]

  if (simplify) {
    return(gdal_fns)
  }

  # Return detailed data frame
  data.frame(
    command = gdal_fns,
    type = types,
    func = I(lapply(gdal_fns, function(fn_name) {
      get(fn_name, envir = asNamespace("gdalcli"), mode = "function")
    })),
    stringsAsFactors = FALSE,
    row.names = NULL
  )
}
