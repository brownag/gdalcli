#' GDAL Dynamic API R6 Classes
#'
#' @description
#' Internal R6 classes that form the dynamic API structure for gdalcli.
#' These classes provide the runtime-adaptive interface that mirrors Python's
#' `gdal.alg` module structure while integrating with the lazy evaluation
#' framework.
#'
#' @details
#' **GdalApi** is the top-level object accessible as `gdal` in the namespace.
#' It contains GdalApiSub instances for each command group (raster, vector, etc.).
#' Each GdalApiSub contains dynamically created functions for GDAL commands.
#'
#' This implementation uses R6 reference semantics to allow dynamic member
#' addition at runtime, which is not possible with S3 or S7 classes.
#'
#' @keywords internal

#' GdalApi R6 Class
#'
#' Top-level object for the dynamic GDAL API.
#'
#' @keywords internal
#' @export
GdalApi <- R6::R6Class(
  "GdalApi",
  public = list(
    gdal_version = NULL,
    cache_file = NULL,

    initialize = function() {
      # Check for gdalraster availability
      if (!requireNamespace("gdalraster", quietly = TRUE)) {
        cli::cli_abort(
          c(
            "gdalraster package required for dynamic API",
            "i" = "Install with: install.packages('gdalraster')"
          )
        )
      }

      # Get GDAL version
      self$gdal_version <- gdalraster::gdal_version()[["version"]]

      # Setup cache
      cache_dir <- tools::R_user_dir("gdalcli", "cache")
      if (!dir.exists(cache_dir)) {
        dir.create(cache_dir, recursive = TRUE, showWarnings = FALSE)
      }

      cache_base <- file.path(cache_dir, "gdal_api")
      cache_hash <- digest::digest(self$gdal_version)
      self$cache_file <- paste0(cache_base, "_", cache_hash, ".rds")

      # Load from cache or build fresh
      if (file.exists(self$cache_file)) {
        private$load_from_cache()
      } else {
        private$build_api_structure()
        private$save_to_cache()
      }
    },

    get_groups = function() {
      names(self)
    }
  ),
  private = list(
    build_api_structure = function() {
      tryCatch(
        {
          # Get all available commands from gdalraster
          cmds <- gdalraster::gdal_commands()

          # Validate that commands is a list
          if (!is.list(cmds) || length(cmds) == 0) {
            cli::cli_abort("No GDAL commands available from gdalraster")
          }

          # Group commands by their first level (raster, vector, mdim, vsi, driver)
          # Use safer method to extract first element
          groups <- unique(sapply(
            cmds,
            function(x) if (is.character(x) && length(x) > 0) x[1] else NA_character_
          ))
          groups <- groups[!is.na(groups)]

          if (length(groups) == 0) {
            cli::cli_abort("Could not parse command groups from gdalraster")
          }

          # For each group, create a GdalApiSub instance
          for (group in groups) {
            # Filter commands for this group - safer method
            group_cmds <- lapply(cmds, function(cmd_path) {
              if (is.character(cmd_path) && length(cmd_path) > 0 && cmd_path[1] == group) {
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
            sub_api <- GdalApiSub$new(group, group_cmds)

            # Add to self (reference semantics allows dynamic addition)
            self[[group]] <- sub_api
          }

          cli::cli_inform(
            "Dynamic GDAL API built successfully (GDAL {self$gdal_version})"
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
    },

    load_from_cache = function() {
      tryCatch(
        {
          cached <- readRDS(self$cache_file)

          # Restore groups from cache
          for (group_name in names(cached$groups)) {
            self[[group_name]] <- cached$groups[[group_name]]
          }

          cli::cli_inform(
            "Dynamic GDAL API loaded from cache (GDAL {self$gdal_version})"
          )
        },
        error = function(e) {
          cli::cli_warn("Cache load failed, rebuilding...")
          private$build_api_structure()
          private$save_to_cache()
        }
      )
    },

    save_to_cache = function() {
      tryCatch(
        {
          # Collect all GdalApiSub instances
          groups_to_cache <- list()
          for (group_name in setdiff(names(self), c("gdal_version", "cache_file"))) {
            obj <- self[[group_name]]
            if (R6::is.R6(obj) && inherits(obj, "GdalApiSub")) {
              groups_to_cache[[group_name]] <- obj
            }
          }

          # Save to RDS
          cache_data <- list(
            gdal_version = self$gdal_version,
            groups = groups_to_cache
          )
          saveRDS(cache_data, self$cache_file)

          cli::cli_inform("API structure cached to {.file {self$cache_file}}")
        },
        error = function(e) {
          cli::cli_warn("Failed to save cache: {conditionMessage(e)}")
        }
      )
    }
  )
)

#' GdalApiSub R6 Class
#'
#' Intermediate node representing a command group (e.g., `gdal$raster`).
#'
#' @keywords internal
#' @export
GdalApiSub <- R6::R6Class(
  "GdalApiSub",
  public = list(
    group_name = NULL,
    commands = NULL,

    initialize = function(group_name, command_list) {
      self$group_name <- group_name
      self$commands <- command_list

      # Create function for each command in this group
      private$build_subcommands(command_list)
    },

    get_subcommands = function() {
      # Return names of all functions that are not private fields
      setdiff(names(self), c("group_name", "commands", "get_subcommands"))
    }
  ),
  private = list(
    build_subcommands = function(command_list) {
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
            func <- private$create_gdal_function(cmd_path)
            # Add to self with the command name
            self[[cmd_name]] <- func
          },
          error = function(e) {
            cli::cli_warn("Failed to create function for {paste(cmd_path, collapse=' ')}: {conditionMessage(e)}")
          }
        )
      }
    },

    create_gdal_function = function(cmd_path) {
      # Capture the command path in closure
      captured_cmd <- cmd_path

      # Create function using rlang::new_function
      # First, parse the command usage to get proper formals
      usage_info <- tryCatch(
        {
          gdalraster::gdal_usage(paste(captured_cmd, collapse = " "))
        },
        error = function(e) ""
      )

      # Parse to extract argument information
      parsed_sig <- private$parse_gdal_usage(captured_cmd, usage_info)

      # Build the function body
      func_body <- substitute({
        # Capture the call with all arguments
        call_args <- match.call(expand.dots = FALSE)

        # Remove the function name from the call
        call_args[[1]] <- NULL

        # Convert to list
        arg_list <- as.list(call_args)

        # Handle ... specially - preserve unevaluated expressions
        dots <- list()
        if ("..." %in% names(call_args)) {
          dots <- eval(call_args[[which(names(call_args) == "...")]])
        }

        # Create gdal_job
        new_gdal_job(
          command_path = CMD_PATH,
          arguments = arg_list
        )
      }, list(CMD_PATH = captured_cmd))

      # Use rlang to create function with full formals
      rlang::new_function(
        args = parsed_sig$formals,
        body = func_body,
        env = parent.env(environment())
      )
    },

    parse_gdal_usage = function(cmd_path, usage_text) {
      # Start with basic signature structure
      formals <- alist(... = )

      # Try to extract more detail from usage text
      # For now, use basic ... and expand when parser is complete
      arg_info <- data.frame(
        name = character(0),
        type = character(0),
        required = logical(0),
        default = character(0)
      )

      list(
        formals = formals,
        arg_info = arg_info
      )
    }
  )
)
