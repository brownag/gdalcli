#' GDALG Transpiler: Convert R Job Objects to RFC 104 Command Strings
#'
#' Internal module for transpiling gdalcli job/pipeline objects into RFC 104
#' compliant command strings suitable for GDALG serialization.
#'
#' @noRd
#' @keywords internal


#' Quote a String for Shell Execution
#'
#' Implements robust shell-style quoting using single quotes with proper
#' escaping of single quotes via '"'"' technique (close quote, escaped quote, open quote).
#' This is safe for both POSIX and Windows shells.
#'
#' @param str Character string to quote.
#'
#' @return Character string with appropriate shell quoting applied.
#'
#' @details
#' Quoting rules:
#' - Alphanumeric, underscore, dash, dot, forward slash, colon: no quoting needed
#' - Anything else: wrap in single quotes, escaping embedded single quotes as '"'"'
#' - Empty string: quoted as ''
#'
#' @keywords internal
#' @noRd
.quote_argument <- function(str) {
  # Characters that are safe without quoting (alphanumeric + common safe chars)
  # This covers most common filenames and simple arguments
  if (grepl("^[a-zA-Z0-9/_.:=-]*$", str)) {
    return(str)
  }

  # If the string contains single quotes, we need to handle them specially
  # Replace each ' with '"'"' (end quote, escaped quote in double quotes, start quote)
  escaped <- gsub("'", "'\"'\"'", str, fixed = TRUE)

  # Wrap in single quotes
  paste0("'", escaped, "'")
}


#' Format an Argument Value for RFC 104 CLI
#'
#' Converts an R value (character, numeric, logical, vector) into the appropriate
#' RFC 104 CLI format, handling type conversion, quoting, and repetition logic.
#'
#' @param value The R value to format (character, numeric, logical, or vector)
#' @param arg_name Character string naming the argument, for context
#' @param arg_mapping List containing metadata about the argument (min_count, max_count, etc.)
#'   from the job's arg_mapping attribute. Used to determine if vectors should be
#'   comma-separated (composite) or repeated flags.
#'
#' @return Character vector of the formatted argument and value(s), ready to append
#'   to a command line. For logical TRUE, returns just the flag; for logical FALSE,
#'   returns character(0) (nothing). For values, returns a vector with the flag and
#'   value(s), either as individual elements or comma-separated depending on composite mode.
#'
#' @keywords internal
#' @noRd
.format_rfc104_argument <- function(value, arg_name, arg_mapping) {
  if (is.null(value)) {
    return(character(0))
  }

  # Generate the CLI flag from argument name
  # Special mappings for common deviations
  flag_mapping <- c(
    "resolution" = "--resolution",
    "size" = "--ts",
    "extent" = "--te"
  )
  cli_flag <- if (arg_name %in% names(flag_mapping)) {
    flag_mapping[arg_name]
  } else {
    paste0("--", gsub("_", "-", arg_name))
  }

  # Handle logical/boolean arguments
  if (is.logical(value)) {
    if (value) {
      return(cli_flag)  # Just the flag for TRUE
    } else {
      return(character(0))  # Nothing for FALSE
    }
  }

  # Check if this is a composite (fixed-count, comma-separated) argument
  is_composite <- FALSE
  arg_meta <- arg_mapping[[arg_name]]
  if (!is.null(arg_meta) && !is.null(arg_meta$min_count) && !is.null(arg_meta$max_count)) {
    is_composite <- arg_meta$min_count == arg_meta$max_count && arg_meta$min_count > 1
  }

  # Handle vector values
  if (length(value) > 1) {
    if (is_composite) {
      # Composite: comma-separated
      formatted_values <- sapply(value, function(v) .quote_argument(as.character(v)), USE.NAMES = FALSE)
      return(c(cli_flag, paste(formatted_values, collapse = ",")))
    } else {
      # Repeatable: repeated flags
      formatted_values <- sapply(value, function(v) .quote_argument(as.character(v)), USE.NAMES = FALSE)
      # Interleave flag with each value
      result <- character()
      for (val in formatted_values) {
        result <- c(result, cli_flag, val)
      }
      return(result)
    }
  }

  # Single value: quote and return
  formatted_value <- .quote_argument(as.character(value))
  c(cli_flag, formatted_value)
}


#' Convert a Single gdal_job to an RFC 104 CLI Step String
#'
#' Transforms a gdal_job object into a single step in an RFC 104 pipeline.
#' This handles positional argument ordering and option formatting.
#'
#' @param job A gdal_job object
#'
#' @return Character string representing this job as a single RFC 104 CLI step
#'   (without the "!" delimiter; that's added by the pipeline function).
#'
#' @keywords internal
#' @noRd
.job_to_rfc104_step <- function(job) {
  # Extract command parts (skip "gdal" prefix if present)
  command_parts <- if (length(job$command_path) > 0 && job$command_path[1] == "gdal") {
    job$command_path[-1]
  } else {
    job$command_path
  }

  step_parts <- command_parts

  # Separate positional and option arguments
  positional_args_map <- list()
  option_parts <- character()

  arg_mapping <- if (!is.null(job$arg_mapping)) job$arg_mapping else list()

  # Process each argument
  for (arg_name in names(job$arguments)) {
    arg_value <- job$arguments[[arg_name]]

    if (is.null(arg_value)) {
      next
    }

    # Check if this is a positional argument
    positional_arg_names <- c("input", "output", "src_dataset", "dest_dataset", "dataset")
    is_positional <- arg_name %in% positional_arg_names

    if (is_positional) {
      positional_args_map[[arg_name]] <- arg_value
    } else {
      # Format as option argument
      formatted <- .format_rfc104_argument(arg_value, arg_name, arg_mapping)
      option_parts <- c(option_parts, formatted)
    }
  }

  # RFC 104 order: command step name [options] [positional args]
  # For pipeline steps, the step name is the last part of command_path
  # e.g., for c("raster", "convert"), step is "convert"
  step_name <- if (length(command_parts) > 1) command_parts[length(command_parts)] else command_parts[1]

  # For pipeline steps, don't include command hierarchy (raster/vector is implicit in pipeline type)
  result <- c(step_name, option_parts)

  # Add positional arguments in proper order: inputs first, then outputs
  positional_order <- c("input", "src_dataset", "dataset", "output", "dest_dataset")
  for (arg_name in positional_order) {
    if (arg_name %in% names(positional_args_map)) {
      arg_value <- positional_args_map[[arg_name]]
      if (length(arg_value) > 1) {
        formatted_values <- sapply(arg_value, function(v) .quote_argument(as.character(v)), USE.NAMES = FALSE)
        result <- c(result, formatted_values)
      } else {
        result <- c(result, .quote_argument(as.character(arg_value)))
      }
    }
  }

  # Join into a single space-separated string
  paste(result, collapse = " ")
}


#' Build RFC 104 Command Line String from a gdalcli Pipeline
#'
#' Traverses a gdal_pipeline object (DAG of jobs) and constructs an RFC 104
#' command string using the "!" delimiter between steps.
#'
#' This handles both raster and vector pipelines and produces output suitable
#' for embedding in a GDALG JSON "command_line" field.
#'
#' @param pipeline A gdal_pipeline object
#'
#' @return Character string: RFC 104 command (e.g. "gdal raster pipeline ! step1 ! step2 ! ...")
#'
#' @keywords internal
#' @noRd
.pipeline_to_rfc104_command <- function(pipeline) {
  if (!inherits(pipeline, "gdal_pipeline")) {
    stop("Expected a gdal_pipeline object", call. = FALSE)
  }

  if (length(pipeline$jobs) == 0) {
    stop("Pipeline has no jobs", call. = FALSE)
  }

  # Determine pipeline type (raster or vector) from first job's command path
  first_job <- pipeline$jobs[[1]]
  pipeline_type <- if (first_job$command_path[1] == "gdal") {
    first_job$command_path[2]
  } else {
    first_job$command_path[1]
  }

  if (!(pipeline_type %in% c("raster", "vector"))) {
    stop("Cannot determine pipeline type (raster or vector) from first job", call. = FALSE)
  }

  # Convert each job to a step string
  step_strings <- sapply(pipeline$jobs, .job_to_rfc104_step, USE.NAMES = FALSE)

  # Join with "!" delimiter
  steps_combined <- paste(step_strings, collapse = " ! ")

  # Construct full command: gdal [raster|vector] pipeline ! steps...
  paste("gdal", pipeline_type, "pipeline", "!", steps_combined)
}


#' Serialize a gdalcli Pipeline to GDALG JSON Format
#'
#' Converts a gdal_pipeline object (which represents lazy R computation specs)
#' into a GDALG JSON structure ready for writing to disk.
#'
#' The resulting JSON conforms to the GDALG specification:
#' - `type`: Always "gdal_streamed_alg"
#' - `command_line`: RFC 104 command string from the pipeline
#' - `relative_paths_relative_to_this_file`: true (default behavior)
#'
#' Pipeline name and description, if present, are NOT stored in the GDALG JSON
#' (as the spec does not allow custom keys). They COULD be embedded via a final
#' edit step if the pipeline supports metadata operations, but that is not
#' implemented by default (user can add their own edit step if needed).
#'
#' @param pipeline A gdal_pipeline object
#'
#' @return List suitable for JSON encoding via jsonlite::toJSON():
#'   list(type = "gdal_streamed_alg", command_line = "...", relative_paths_relative_to_this_file = TRUE)
#'
#' @keywords internal
#' @noRd
.pipeline_to_gdalg_spec <- function(pipeline) {
  if (!inherits(pipeline, "gdal_pipeline")) {
    stop("Expected a gdal_pipeline object", call. = FALSE)
  }

  command_line <- .pipeline_to_rfc104_command(pipeline)

  list(
    type = "gdal_streamed_alg",
    command_line = command_line,
    relative_paths_relative_to_this_file = TRUE
  )
}


#' Parse an RFC 104 Command String into Steps
#'
#' Splits a command string by "!" delimiters and tokenizes each step.
#' This is a simple tokenizer suitable for most cases but may have limitations
#' with complex quoted arguments or special characters.
#'
#' @param command_line Character string from GDALG "command_line" field
#'
#' @return List of character vectors, one per step. Each vector is the tokenized
#'   arguments for that step (e.g., c("reproject", "--dst-crs", "EPSG:4326")).
#'
#' @details
#' Limitations:
#' - Does not handle escaped quotes or quotes within tokens
#' - Assumes standard shell-style quoting
#' - May fail on very complex SQL or URI arguments
#'
#' For round-trip accuracy, store pipeline name/description externally
#' (not in the GDALG JSON, which only stores command_line).
#'
#' @keywords internal
#' @noRd
.parse_rfc104_command_string <- function(command_line) {
  # Remove leading "gdal [raster|vector] pipeline !"
  # to extract just the step chain
  command_line <- trimws(command_line)

  # Try to remove "gdal raster pipeline !" or "gdal vector pipeline !"
  if (grepl("^gdal\\s+(raster|vector)\\s+pipeline\\s+!", command_line)) {
    command_line <- sub("^gdal\\s+(raster|vector)\\s+pipeline\\s+!\\s*", "", command_line)
  }

  # Split by " ! " (whitespace-delimited exclamation)
  steps_raw <- strsplit(command_line, "\\s*!\\s*", perl = TRUE)[[1]]

  # Tokenize each step
  # Simple approach: split on whitespace, but respect quoted strings
  steps <- lapply(steps_raw, function(step_str) {
    # Skip empty steps
    step_str <- trimws(step_str)
    if (nchar(step_str) == 0) {
      return(character(0))
    }

    # Simple shell-style tokenization
    # Use strsplit for simpler and more reliable parsing
    # First, try to split respecting quoted strings:
    # 1. Find all quoted strings andmark their positions
    # 2. Split the rest by whitespace
    # 3. Reassemble
    
    # For now, use a simpler grepl-based approach that's more reliable
    # This regex matches either single-quoted strings or sequences of non-whitespace
    pattern <- "(['\"][^'\"]*['\"]|[^ \\t]+)"
    
    # Use gregexpr with the ENTIRE result to pass to regmatches
    matches <- gregexpr(pattern, step_str)
    
    if (matches[[1]][1] == -1) {
      # No matches, return emptycharacter vector
      return(character(0))
    }
    
    matched <- regmatches(step_str, matches)[[1]]

    # Remove quotes from quoted tokens
    matched <- gsub("^['\"]|['\"]$", "", matched)

    matched
  })

  # Remove empty steps
  steps[sapply(steps, length) > 0]
}



#' Reconstruct a gdal_job from RFC 104 Step Tokens
#'
#' Inverse operation of .job_to_rfc104_step(): takes a tokenized step
#' and restructures it back into a gdal_job object.
#'
#' This is used when loading a GDALG file: we parse the command_line,
#' extract individual steps, and reconstruct the original job specs.
#'
#' @param step_tokens Character vector of tokens (e.g., c("reproject", "--dst-crs", "EPSG:4326"))
#' @param pipeline_type Character: "raster" or "vector"
#' @param step_position Numeric: position in pipeline (1 = first step, typically "read")
#'
#' @return A gdal_job object with command_path, arguments, and arg_mapping reconstructed.
#'
#' @details
#' This function attempts a best-effort reconstruction. Some information is lost
#' in the round-trip (e.g., arg_mapping details, config_options, env_vars) and
#' is not recovered. If exact restoration is needed, store pipeline metadata
#' externally.
#'
#' @keywords internal
#' @noRd
.rfc104_step_to_job <- function(step_tokens, pipeline_type, step_position) {
  if (length(step_tokens) == 0) {
    stop("Empty step tokens", call. = FALSE)
  }

  # First token is the step name (e.g., "read", "reproject", "write")
  step_name <- step_tokens[1]
  rest_tokens <- step_tokens[-1]

  # Build command path
  command_path <- c("gdal", pipeline_type, step_name)

  # Parse arguments from remaining tokens
  arguments <- list()
  i <- 1
  while (i <= length(rest_tokens)) {
    token <- rest_tokens[i]

    # Check if it's a flag (starts with --)
    if (grepl("^--", token)) {
      # Remove -- prefix
      arg_name <- sub("^--", "", token)

      # Convert dashes to underscores in arg name
      arg_name <- gsub("-", "_", arg_name)

      # Check if next token is a value or another flag
      if (i < length(rest_tokens) && !grepl("^--", rest_tokens[i + 1])) {
        arg_value <- rest_tokens[i + 1]

        # Handle comma-separated values (composite arguments)
        if (grepl(",", arg_value)) {
          arg_value <- strsplit(arg_value, ",")[[1]]
        }

        # Check if we've already seen this arg (repeatable argument)
        if (arg_name %in% names(arguments)) {
          # Append to existing
          if (is.list(arguments[[arg_name]])) {
            arguments[[arg_name]] <- c(arguments[[arg_name]], arg_value)
          } else {
            arguments[[arg_name]] <- c(arguments[[arg_name]], arg_value)
          }
        } else {
          arguments[[arg_name]] <- arg_value
        }

        i <- i + 2
      } else {
        # Flag without value (boolean flag)
        arguments[[arg_name]] <- TRUE
        i <- i + 1
      }
    } else {
      # Positional argument (input or output)
      if (step_name == "read") {
        arguments[["input"]] <- token
      } else if (step_name == "write") {
        arguments[["output"]] <- token
      } else {
        # For other steps, treat as positional argument if not already assigned
        # Try to guess based on presence of input/output
        if (!("input" %in% names(arguments))) {
          arguments[["input"]] <- token
        } else if (!("output" %in% names(arguments))) {
          arguments[["output"]] <- token
        } else {
          # Append as an additional positional
          arguments[[paste0("arg_", i)]] <- token
        }
      }

      i <- i + 1
    }
  }

  # Construct the gdal_job
  # Note: arg_mapping, config_options, env_vars are NOT reconstructed
  job <- structure(
    list(
      command_path = command_path,
      arguments = arguments,
      config_options = character(),
      env_vars = character(),
      stream_in = NULL,
      stream_out_format = NULL,
      pipeline = NULL,
      arg_mapping = list()  # Empty; would need to be fetched from API spec if needed
    ),
    class = "gdal_job"
  )

  job
}


#' Reconstruct a gdal_pipeline from GDALG JSON Command String
#'
#' Parses the command_line field from a GDALG JSON spec and reconstructs
#' a gdal_pipeline object.
#'
#' @param command_line Character string from GDALG spec's "command_line" field
#'
#' @return A gdal_pipeline object with name/description set to NA
#'   (as GDALG spec does not preserve these).
#'
#' @keywords internal
#' @noRd
.gdalg_to_pipeline <- function(command_line) {
  if (!is.character(command_line) || length(command_line) != 1) {
    stop("command_line must be a single character string", call. = FALSE)
  }

  # Determine pipeline type (raster or vector)
  if (grepl("^gdal\\s+raster", command_line)) {
    pipeline_type <- "raster"
  } else if (grepl("^gdal\\s+vector", command_line)) {
    pipeline_type <- "vector"
  } else {
    stop("Cannot determine pipeline type from command_line", call. = FALSE)
  }

  # Parse the command string into steps
  steps <- .parse_rfc104_command_string(command_line)

  # Reconstruct each job from its step tokens
  jobs <- lapply(seq_along(steps), function(idx) {
    .rfc104_step_to_job(steps[[idx]], pipeline_type, idx)
  })

  # Create pipeline object
  pipeline <- structure(
    list(
      jobs = jobs,
      name = NA_character_,
      description = NA_character_
    ),
    class = "gdal_pipeline"
  )

  pipeline
}


#' Generate a Hybrid .gdalcli.json Spec (GDALG + R Metadata)
#'
#' Wraps GDALG components with R-level metadata and full job specs for
#' lossless round-trip serialization. The resulting format is simultaneously:
#' - Extractable: the `gdalg` component is a valid standalone GDALG spec
#' - Lossless: `r_job_specs` preserves full job details for exact R reconstruction
#' - Auditable: includes version info, timestamps, creation context
#' - Extensible: `custom_tags` allow arbitrary user metadata
#'
#' @param pipeline A gdal_pipeline object
#' @param custom_tags Optional named list of user-defined metadata to include
#'
#' @return List representing the complete hybrid spec with components:
#'   gdalg (type, command_line, relative_paths_relative_to_this_file),
#'   metadata (gdalcli_version, gdal_version_required, pipeline_name, etc),
#'   r_job_specs (array of job specs with command_path, arguments, arg_mapping, etc)
#'
#' @keywords internal
#' @noRd
.pipeline_to_gdalcli_spec <- function(pipeline, name = NULL, description = NULL, custom_tags = list()) {
  if (!inherits(pipeline, "gdal_pipeline")) {
    stop("Expected a gdal_pipeline object", call. = FALSE)
  }

  if (length(pipeline$jobs) == 0) {
    stop("Pipeline has no jobs", call. = FALSE)
  }

  # Extract GDALG component
  gdalg_spec <- .pipeline_to_gdalg_spec(pipeline)

  # Get package version (safely, in case package not formally installed)
  pkg_version <- tryCatch(
    as.character(utils::packageVersion("gdalcli")),
    error = function(e) "unknown"
  )

  # Use provided name/description if given, otherwise try pipeline attributes
  final_name <- name %||% (if (!is.null(pipeline$name) && !is.na(pipeline$name)) pipeline$name else NA_character_)
  final_description <- description %||% (if (!is.null(pipeline$description) && !is.na(pipeline$description)) pipeline$description else NA_character_)

  # Build metadata section
  metadata <- list(
    format_version = "1.0",
    gdalcli_version = pkg_version,
    gdal_version_required = "3.11",
    pipeline_name = final_name,
    pipeline_description = final_description,
    created_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ"),
    created_by_r_version = R.version$version.string,
    custom_tags = custom_tags
  )

  # Build r_job_specs: capture full job state for lossless round-trip
  r_job_specs <- lapply(pipeline$jobs, function(job) {
    list(
      command_path = job$command_path,
      arguments = job$arguments,
      arg_mapping = if (length(job$arg_mapping) > 0) job$arg_mapping else list(),
      config_options = job$config_options,
      env_vars = job$env_vars,
      stream_in = job$stream_in,
      stream_out_format = job$stream_out_format
    )
  })

  # Combined hybrid spec
  list(
    gdalg = gdalg_spec,
    metadata = metadata,
    r_job_specs = r_job_specs
  )
}


#' Reconstruct a gdal_pipeline from Hybrid .gdalcli.json Spec
#'
#' Loads and validates a hybrid spec, preferring lossless `r_job_specs`
#' if available for exact R state reconstruction, with fallback to GDALG
#' command_line parsing for pure GDALG format compatibility.
#'
#' Auto-detection:
#' - If spec has `r_job_specs` array: use for lossless reconstruction
#' - Else if spec has `gdalg.command_line`: parse via RFC 104 transpiler
#' - Hybrid format (.gdalcli.json v0.5.0+): both present, prefers r_job_specs
#' - Pure GDALG (.gdalg.json): only gdalg present, falls back to parsing
#'
#' @param spec List representing a hybrid or pure GDALG spec
#'
#' @return A gdal_pipeline object. If r_job_specs present, full fidelity
#'   reconstruction with all job attributes preserved. Otherwise, best-effort
#'   from GDALG command_line parsing (may lack arg_mapping, config, env details).
#'
#' @keywords internal
#' @noRd
.gdalcli_spec_to_pipeline <- function(spec) {
  # Accept both gdalcli_spec S3 objects and plain lists
  if (inherits(spec, "gdalcli_spec")) {
    spec <- list(
      gdalg = gdalg_to_list(spec$gdalg),
      metadata = spec$metadata,
      r_job_specs = spec$r_job_specs
    )
  }

  if (!inherits(spec, "list")) {
    stop("spec must be a list or gdalcli_spec object", call. = FALSE)
  }

  # Check for legacy format (.gdalcli.json pre-v0.5.0) with "steps" key
  if (!is.null(spec$steps) && is.null(spec$gdalg)) {
    stop(
      "Legacy .gdalcli.json format (pre-v0.5.0) is no longer supported.\n",
      "Please regenerate your pipeline files using gdalcli v0.5.0+",
      call. = FALSE
    )
  }

  # Validate GDALG component
  if (is.null(spec$gdalg)) {
    stop("Specification must contain 'gdalg' component", call. = FALSE)
  }

  gdalg <- spec$gdalg
  if (is.null(gdalg$type) || gdalg$type != "gdal_streamed_alg") {
    stop("spec.gdalg.type must be 'gdal_streamed_alg'", call. = FALSE)
  }

  if (is.null(gdalg$command_line)) {
    stop("spec.gdalg.command_line is required", call. = FALSE)
  }

  # Prefer r_job_specs for lossless reconstruction
  if (!is.null(spec$r_job_specs) && length(spec$r_job_specs) > 0) {
    # Reconstruct from preserved R specs (full fidelity)
    jobs <- lapply(spec$r_job_specs, function(job_spec) {
      # Use %||% operator for handling NULL values
      get_or_default <- function(x, default) if (is.null(x)) default else x

      structure(
        list(
          command_path = get_or_default(job_spec$command_path, character()),
          arguments = get_or_default(job_spec$arguments, list()),
          arg_mapping = get_or_default(job_spec$arg_mapping, list()),
          config_options = get_or_default(job_spec$config_options, character()),
          env_vars = get_or_default(job_spec$env_vars, character()),
          stream_in = job_spec$stream_in,
          stream_out_format = job_spec$stream_out_format,
          pipeline = NULL
        ),
        class = "gdal_job"
      )
    })
  } else {
    # Fallback: parse from GDALG command_line
    # (lower fidelity, but allows loading pure GDALG files)
    temp_pipeline <- .gdalg_to_pipeline(gdalg$command_line)
    jobs <- temp_pipeline$jobs
  }

  # Extract metadata if present
  name <- NA_character_
  description <- NA_character_
  if (!is.null(spec$metadata)) {
    name <- if (!is.null(spec$metadata$pipeline_name)) {
      spec$metadata$pipeline_name
    } else {
      NA_character_
    }
    description <- if (!is.null(spec$metadata$pipeline_description)) {
      spec$metadata$pipeline_description
    } else {
      NA_character_
    }
  }

  # Construct pipeline
  structure(
    list(
      jobs = jobs,
      name = name,
      description = description
    ),
    class = "gdal_pipeline"
  )
}
