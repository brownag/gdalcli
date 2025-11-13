#' GDAL Dynamic API Classes
#'
#' @description
#' Custom classes that form the dynamic API structure for gdalcli.
#' These classes provide the runtime-adaptive interface that mirrors Python's
#' `gdal.alg` module structure while integrating with the lazy evaluation
#' framework.
#'
#' @details
#' **GdalApi** is the top-level object accessible as `gdal.alg` in the namespace.
#' It contains GdalApiSub instances for each command group (raster, vector, etc.).
#' Each GdalApiSub contains dynamically created functions for GDAL commands.
#'
#' This implementation uses environments with custom `$` methods to allow dynamic member
#' addition at runtime, which is not possible with S3 or S7 classes.
#'
#' @keywords internal

#' GdalApi Class
#'
#' Top-level object for the dynamic GDAL API.
#'
#' Provides access to GDAL command groups as dynamic member objects (e.g., `gdal.alg$raster`,
#' `gdal.alg$vector`). Each group contains dynamically created functions for GDAL commands.
#' The API is cached based on GDAL version for performance.
#'
#' @return
#' The object provides access to GDAL command groups via `$` operator.
#'
#' @keywords internal
#' @export
GdalApi <- function() {
  # Create an environment for the API object
  api_env <- new.env(parent = emptyenv())

  # Add class attribute
  class(api_env) <- c("GdalApi", "environment")

  # Initialize metadata
  api_env$gdal_version <- NULL
  api_env$cache_file <- NULL
  # Groups will be stored as direct elements in the environment

  # Check for gdalraster availability
  if (!requireNamespace("gdalraster", quietly = TRUE)) {
    cli::cli_abort(
      c(
        "gdalraster package required for dynamic API",
        "i" = "Install with: install.packages('gdalraster')"
      )
    )
  }

  # Get GDAL version safely
  gdal_version_info <- gdalraster::gdal_version()
  if (is.list(gdal_version_info) && "version" %in% names(gdal_version_info)) {
    api_env$gdal_version <- gdal_version_info[["version"]]
  } else if (is.character(gdal_version_info) && length(gdal_version_info) > 0) {
    api_env$gdal_version <- gdal_version_info[1]
  } else {
    cli::cli_abort("Could not extract GDAL version from gdalraster")
  }

  # Setup cache
  cache_dir <- tools::R_user_dir("gdalcli", "cache")
  if (!dir.exists(cache_dir)) {
    dir.create(cache_dir, recursive = TRUE, showWarnings = FALSE)
  }

  cache_base <- file.path(cache_dir, "gdal_api")
  cache_hash <- digest::digest(api_env$gdal_version)
  api_env$cache_file <- paste0(cache_base, "_", cache_hash, ".rds")

  # Load from cache or build fresh
  if (file.exists(api_env$cache_file)) {
    load_from_cache(api_env)
  } else {
    build_api_structure(api_env)
    save_to_cache(api_env)
  }

  # Define the $ method for dynamic access
  api_env$`$.GdalApi` <- function(x, name) {
    # Check if it's a group
    if (exists(name, envir = x, inherits = FALSE)) {
      return(get(name, envir = x, inherits = FALSE))
    }
    # Check for special methods
    if (name == "get_groups") {
      all_elements <- ls(x, all.names = TRUE)
      group_names <- setdiff(all_elements, c("gdal_version", "cache_file"))
      return(function() group_names)
    }
    stop(sprintf("'%s' is not a valid group", name))
  }

  api_env
}

#' @export
print.GdalApi <- function(x, ...) {
  cat("<GdalApi>\n")
  cat(sprintf("GDAL version: %s\n", x$gdal_version))
  all_elements <- ls(x, all.names = TRUE)
  group_names <- setdiff(all_elements, c("gdal_version", "cache_file"))
  cat(sprintf("Number of groups: %d\n", length(group_names)))
  cat("Group names:", paste(group_names, collapse = ", "), "\n")
  invisible(x)
}

#' Build API structure for GdalApi
#' @param api_env The API environment
#' @keywords internal
build_api_structure <- function(api_env) {
  tryCatch(
    {
      # Get all available commands from gdalraster
      cmds <- gdalraster::gdal_commands()

      # Validate that commands is a data.frame with expected columns
      if (!is.data.frame(cmds) || !all(c("command", "description", "URL") %in% names(cmds))) {
        cli::cli_abort("gdal_commands() did not return expected data.frame structure")
      }

      # Group commands by their first level (raster, vector, mdim, vsi, driver)
      # cmds is a data.frame with columns: command, description, url
      command_paths <- strsplit(cmds$command, " ")
      
      # Extract first element of each command path
      groups <- unique(sapply(command_paths, `[`, 1))
      groups <- groups[!is.na(groups)]

      if (length(groups) == 0) {
        cli::cli_abort("Could not parse command groups from gdalraster")
      }

      # For each group, create a GdalApiSub instance
      for (group in groups) {
        # Filter commands for this group - iterate over data frame rows
        group_cmds <- lapply(seq_len(nrow(cmds)), function(i) {
          cmd_path <- strsplit(cmds$command[i], " ")[[1]]
          if (length(cmd_path) > 0 && cmd_path[1] == group) {
            cmd_path
          } else {
            NULL
          }
        })
        group_cmds <- Filter(Negate(is.null), group_cmds)

        if (length(group_cmds) == 0) {
          cli::cli_warn("No commands found for group: {group}")
          next
        }

        # Create GdalApiSub for this group
        sub_api <- GdalApiSub(group, group_cmds)

        # Store directly in the environment
        api_env[[group]] <- sub_api
      }

      cli::cli_inform(
        "Dynamic GDAL API built successfully (GDAL {api_env$gdal_version})"
      )
    },
    error = function(e) {
      cli::cli_abort(
        c(
          "Failed to build dynamic API structure",
          "x" = conditionMessage(e)
        )
      )
    }
  )
}

#' Load API structure from cache
#' @param api_env The API environment
#' @keywords internal
load_from_cache <- function(api_env) {
  tryCatch(
    {
      cached <- readRDS(api_env$cache_file)

      # Restore groups from cache - they are stored as direct elements
      for (group_name in cached$group_names) {
        api_env[[group_name]] <- cached$groups[[group_name]]
      }

      cli::cli_inform(
        "Dynamic GDAL API loaded from cache (GDAL {api_env$gdal_version})"
      )
    },
    error = function(e) {
      cli::cli_warn("Cache load failed, rebuilding...")
      build_api_structure(api_env)
      save_to_cache(api_env)
    }
  )
}

#' Save API structure to cache
#' @param api_env The API environment
#' @keywords internal
save_to_cache <- function(api_env) {
  tryCatch(
    {
      # Get all group names (all elements except metadata)
      all_elements <- ls(api_env, all.names = TRUE)
      group_names <- setdiff(all_elements, c("gdal_version", "cache_file"))

      # Save to RDS
      cache_data <- list(
        gdal_version = api_env$gdal_version,
        group_names = group_names,
        groups = lapply(group_names, function(name) api_env[[name]])
      )
      names(cache_data$groups) <- group_names

      saveRDS(cache_data, api_env$cache_file)

      cli::cli_inform("API structure cached to {.file {api_env$cache_file}}")
    },
    error = function(e) {
      cli::cli_warn("Failed to save cache: {conditionMessage(e)}")
    }
  )
}

#' GdalApiSub Class
#'
#' Intermediate node representing a command group (e.g., `gdal.alg$raster`).
#'
#' @param group_name Character string of the command group name (e.g., "raster", "vector").
#' @param command_list List of command paths for this group.
#'
#' @return
#' The object provides access to GDAL commands via `$` operator.
#'
#' @keywords internal
#' @export
GdalApiSub <- function(group_name, command_list) {
  # Create an environment for the sub-API object
  sub_env <- new.env(parent = emptyenv())

  # Add class attribute
  class(sub_env) <- c("GdalApiSub", "environment")

  # Initialize metadata
  sub_env$group_name <- group_name
  sub_env$commands <- command_list
  # Commands will be stored as direct elements in the environment

  # Create function for each command in this group
  for (cmd_path in command_list) {
    # cmd_path is like c("raster", "info"), we want the last part as function name
    if (!is.character(cmd_path) || length(cmd_path) == 0) {
      cli::cli_warn("Invalid command path encountered, skipping")
      next
    }

    cmd_name <- cmd_path[length(cmd_path)]

    # Create the function for this command
    tryCatch(
      {
        func <- create_gdal_function(cmd_path)
        # Store directly in the environment
        sub_env[[cmd_name]] <- func
      },
      error = function(e) {
        cli::cli_warn("Failed to create function for {paste(cmd_path, collapse=' ')}: {conditionMessage(e)}")
      }
    )
  }

  # Define the $ method for dynamic access
  sub_env$`$.GdalApiSub` <- function(x, name) {
    # Check if it's a command
    if (exists(name, envir = x, inherits = FALSE)) {
      return(get(name, envir = x, inherits = FALSE))
    }
    # Check for special methods
    if (name == "get_subcommands") {
      all_elements <- ls(x, all.names = TRUE)
      command_names <- setdiff(all_elements, c("group_name", "commands"))
      return(function() command_names)
    }
    if (name == "group_name") {
      return(get("group_name", envir = x))
    }
    if (name == "commands") {
      return(get("commands", envir = x))
    }
    stop(sprintf("'%s' is not a valid command in group '%s'", name, get("group_name", envir = x)))
  }

  sub_env
}

#' @export
print.GdalApiSub <- function(x, ...) {
  cat(sprintf("<GdalApiSub: %s>\n", get("group_name", envir = x)))
  all_elements <- ls(x, all.names = TRUE)
  command_names <- setdiff(all_elements, c("group_name", "commands"))
  cat("Available commands:", paste(command_names, collapse = ", "), "\n")
  invisible(x)
}

#' Create GDAL function for a command
#' @param cmd_path Command path vector
#' @keywords internal
create_gdal_function <- function(cmd_path) {
  # Capture the command path in closure
  captured_cmd <- cmd_path

  # Create function using rlang::new_function
  # For now, use basic signature with ...
  func_body <- substitute({
    # Capture the call with all arguments
    call_args <- match.call(expand.dots = FALSE)

    # Remove the function name from the call
    call_args[[1]] <- NULL

    # Convert to list
    arg_list <- as.list(call_args)

    # Create gdal_job
    new_gdal_job(
      command_path = CMD_PATH,
      arguments = arg_list
    )
  }, list(CMD_PATH = captured_cmd))

  # Use rlang to create function with basic formals
  rlang::new_function(
    args = alist(... = ),
    body = func_body,
    env = parent.env(environment())
  )
}
