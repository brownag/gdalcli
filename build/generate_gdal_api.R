#!/usr/bin/env Rscript
#
# GDAL API Autogeneration Script
#
# This script automatically generates R function wrappers for GDAL commands
# by parsing the output of `gdal --json-usage`. It should be run by package
# developers when updating to a new GDAL version.
#
# Usage:
#   Rscript build/generate_gdal_api.R
#
# This will populate the R/ directory with auto-generated wrapper functions.
#

library(processx)
library(jsonlite)
library(glue)
library(rvest)      # For web scraping GDAL documentation
library(httr)       # For HTTP requests with error handling
library(xml2)       # For XML/HTML parsing utilities

# ============================================================================
# Step 0: Helper Functions
# ============================================================================

# ============================================================================
# Step 0b: Documentation Enrichment Functions (NEW)
# ============================================================================
#'
#' @param obj An R object (list, dataframe, vector, or scalar)
#'
#' @return The same object with "__R_INF__" replaced by Inf
#'
.convert_infinity_strings <- function(obj) {
  if (is.null(obj)) {
    return(obj)
  }

  if (is.list(obj) && !is.data.frame(obj)) {
    # Recursively process list elements
    return(lapply(obj, .convert_infinity_strings))
  }

  if (is.data.frame(obj)) {
    # Process dataframe columns individually to avoid row mismatch
    for (col in names(obj)) {
      obj[[col]] <- .convert_infinity_strings(obj[[col]])
    }
    return(obj)
  }

  if (is.character(obj)) {
    # Replace sentinel strings with Inf (convert to numeric)
    idx <- (obj == "__R_INF__") & !is.na(obj)
    if (any(idx, na.rm = TRUE)) {
      # If all non-NA values are sentinel, convert to all Inf
      if (all(idx[!is.na(idx)])) {
        return(rep(Inf, length(obj)))
      }
    }
  }

  # For other types or mixed strings, return as-is
  obj
}


# ============================================================================
# Step 0b: Documentation Enrichment Functions (NEW)
# ============================================================================

#' Merge arguments from a piped gdal_job with new function arguments.
#'
#' This function implements the argument merging logic for piping support.
#' Explicit arguments override piped job arguments, and input propagation
#' is handled automatically.
#'
#' @param job_args List of arguments from the piped gdal_job.
#' @param new_args List of arguments passed to the current function.
#'
#' @return Merged list of arguments.
#'
merge_gdal_job_arguments <- function(job_args, new_args) {
  # Start with empty list - only propagate specific arguments
  merged <- list()

  # Override with explicit new arguments (except NULL values)
  for (arg_name in names(new_args)) {
    arg_value <- new_args[[arg_name]]
    # Only override if the new argument is not NULL (allows explicit NULL to override)
    if (!is.null(arg_value)) {
      merged[[arg_name]] <- arg_value
    }
  }

  # Handle input propagation: if no explicit input/dataset is provided,
  # try to propagate from previous job's output
  input_param_names <- c("input", "dataset", "src_dataset")
  has_explicit_input <- any(input_param_names %in% names(new_args) & !sapply(new_args[input_param_names], is.null))

  if (!has_explicit_input && length(job_args) > 0) {
    # Look for output from previous job that could be input to this one
    output_candidates <- c("output", "dest_dataset", "dst_dataset")
    for (output_name in output_candidates) {
      if (!is.null(job_args[[output_name]])) {
        # Map output to appropriate input parameter
        if ("input" %in% input_param_names) {
          merged$input <- job_args[[output_name]]
        } else if ("dataset" %in% input_param_names) {
          merged$dataset <- job_args[[output_name]]
        } else if ("src_dataset" %in% input_param_names) {
          merged$src_dataset <- job_args[[output_name]]
        }
        break  # Use first available output
      }
    }
  }

  merged
}


#' Handle job input for pipeline extension in automated GDAL functions.
#'
#' This function processes the job parameter to determine if pipeline extension
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


#' Construct the documentation URL for a GDAL command.
#'
#' Maps a command path (e.g., c("gdal", "raster", "info")) to the corresponding
#' GDAL documentation URL.
#'
#' @param full_path Character vector representing the command hierarchy.
#' @param base_url Base URL for GDAL documentation (default: stable).
#'
#' @return Character string containing the full documentation URL, or NA if not found.
#'
construct_doc_url <- function(full_path, base_url = "https://gdal.org/en/stable/programs") {
  # Convert command path to documentation filename
  # e.g., c("gdal", "raster", "info") -> "gdal_raster_info"
  doc_name <- paste(full_path, collapse = "_")
  url <- sprintf("%s/%s.html", base_url, doc_name)
  url
}


#' Scrape GDAL documentation for a specific program.
#'
#' Attempts to fetch and parse the HTML documentation page for a GDAL program,
#' extracting description, parameter details, and examples.
#'
#' @param url Character string containing the documentation URL.
#' @param timeout Numeric timeout in seconds for HTTP request.
#'
#' @return List containing:
#'   - status: HTTP status code or error message
#'   - description: Main narrative description (or NA)
#'   - param_details: Named list mapping parameter names to descriptions
#'   - examples: Character vector of code examples
#'   - raw_html: The parsed HTML (or NA if failed)
#'
scrape_gdal_docs <- function(url, timeout = 10) {
  result <- list(
    status = NA_integer_,
    description = NA_character_,
    param_details = list(),
    examples = character(0),
    raw_html = NA
  )

  # Attempt to fetch the page with timeout
  response <- tryCatch(
    {
      httr::GET(url, httr::timeout(timeout))
    },
    error = function(e) {
      cat(sprintf("  ⚠ Error fetching %s: %s\n", url, e$message))
      return(NULL)
    }
  )

  # Check if request succeeded
  if (is.null(response) || httr::status_code(response) != 200) {
    result$status <- if (is.null(response)) 0 else httr::status_code(response)
    return(result)
  }

  result$status <- 200

  # Parse HTML
  page <- tryCatch(
    {
      rvest::read_html(response)
    },
    error = function(e) {
      cat(sprintf("  ⚠ Error parsing HTML from %s\n", url))
      return(NULL)
    }
  )

  if (is.null(page)) {
    return(result)
  }

  result$raw_html <- page

  # Extract main description
  # Looking for the first paragraph after the "Description" heading
  description_node <- tryCatch(
    {
      # Find all h2 elements and get their text
      h2_elements <- page %>% rvest::html_elements("h2")
      h2_texts <- h2_elements %>% rvest::html_text()

      # Find the index of the "Description" heading
      desc_idx <- grep("Description", h2_texts, ignore.case = TRUE)[1]

      if (!is.na(desc_idx) && desc_idx > 0) {
        # Get the description heading element
        desc_heading <- h2_elements[desc_idx]
        # Find the next paragraph after this heading
        next_p <- xml2::xml_find_first(desc_heading, "./following-sibling::p[1]")
        if (!is.na(next_p)) {
          rvest::html_text(next_p)
        } else {
          NA_character_
        }
      } else {
        NA_character_
      }
    },
    error = function(e) NA_character_
  )

  if (is.character(description_node) && length(description_node) > 0 &&
      !is.na(description_node) && nzchar(description_node)) {
    result$description <- description_node
  }

  # Extract parameter descriptions from definition lists
  # Format: <dt id="cmdoption-X"><code>...</code></dt><dd>Description</dd>
  param_details <- tryCatch(
    {
      dts <- page %>% rvest::html_elements("dt[id^='cmdoption-']")

      params <- list()
      if (length(dts) > 0) {
        for (i in seq_along(dts)) {
          param_id <- rvest::html_attr(dts[i], "id")
          if (!is.na(param_id) && nzchar(param_id)) {
            param_name <- sub("cmdoption-", "", param_id)
            # Find the next dd sibling
            next_dd <- xml2::xml_find_first(dts[i], "./following-sibling::dd[1]")
            param_desc <- NA_character_
            if (!is.na(next_dd)) {
              param_desc <- rvest::html_text(next_dd)
            }
            if (!is.na(param_desc) && nzchar(param_desc)) {
              params[[param_name]] <- trimws(param_desc)
            }
          }
        }
      }
      params
    },
    error = function(e) list()
  )

  result$param_details <- param_details

  # Extract code examples from <pre> tags within Examples section
  # Filter to only include executable CLI commands (starting with 'gdal' or '$')
  examples <- tryCatch(
    {
      # Find h2 or h3 headings that contain "Example"
      all_headings <- page %>% rvest::html_elements("h2, h3")
      heading_texts <- all_headings %>% rvest::html_text()
      example_indices <- grep("Example", heading_texts, ignore.case = TRUE)

      example_texts <- character(0)

      if (length(example_indices) > 0) {
        for (idx in example_indices[1:min(3, length(example_indices))]) {
          # Get the heading element
          heading <- all_headings[idx]
          # Find all pre tags that follow this heading
          following_pres <- xml2::xml_find_all(heading, "./following::pre[1]")
          if (length(following_pres) > 0) {
            for (pre in following_pres) {
              pre_text <- rvest::html_text(pre)
              if (!is.na(pre_text) && nzchar(pre_text)) {
                # Filter: only keep lines that look like executable commands
                # A command line usually starts with '$', 'gdal', or a program name
                lines <- strsplit(pre_text, "\n")[[1]]
                command_lines <- character(0)

                for (line in lines) {
                  line <- trimws(line)
                  # Check if this is a command line (starts with shell prompt or 'gdal')
                  if (grepl("^\\$\\s*gdal", line) || grepl("^gdal\\s", line)) {
                    # Remove shell prompt if present
                    line <- sub("^\\$\\s*", "", line)
                    command_lines <- c(command_lines, line)
                  }
                }

                # Only add if we found actual command lines
                if (length(command_lines) > 0) {
                  example_texts <- c(example_texts, paste(command_lines, collapse = "\n"))
                }
              }
            }
          }
        }
      }

      example_texts
    },
    error = function(e) character(0)
  )

  result$examples <- examples

  result
}


#' Parse a CLI command string to extract command components.
#'
#' Extracts command parts, positional arguments, flags, and options from a
#' command line string like: "gdal raster info input.tif -stats -co COMPRESS=LZW"
#'
#' @param cli_command Character string containing the full CLI command.
#'
#' @return List with elements:
#'   - command_parts: Character vector of command path (e.g., c("gdal", "raster", "info"))
#'   - positional_args: Character vector of positional arguments
#'   - flags: Character vector of boolean flags (e.g., "stats")
#'   - options: Named character vector of key-value options (e.g., c(co = "COMPRESS=LZW"))
#'
parse_cli_command <- function(cli_command) {
  # Clean up: remove leading/trailing whitespace, normalize internal spaces
  cli_command <- trimws(cli_command)
  cli_command <- gsub("\\$\\s+", "", cli_command)  # Remove shell prompt

  # Split by whitespace, but be careful with quoted strings
  # For simplicity, assume no quoted arguments in examples
  tokens <- strsplit(cli_command, "\\s+")[[1]]
  tokens <- tokens[nzchar(tokens)]  # Remove empty tokens

  result <- list(
    command_parts = character(),
    positional_args = character(),
    flags = character(),
    options = character()
  )

  if (length(tokens) == 0) {
    return(result)
  }

  # Helper: determine if a token looks like a filename/path
  is_filename <- function(token) {
    # Has file extension (common patterns: .tif, .shp, .gpkg, etc.)
    if (grepl("\\.[a-zA-Z0-9]+$", token)) return(TRUE)
    # Looks like a path (has / or \ )
    if (grepl("[/\\\\]", token)) return(TRUE)
    # Known file-like patterns
    if (token %in% c("input", "output", "src", "dest", "dataset")) return(TRUE)
    return(FALSE)
  }

  # Extract command parts (start with gdal, continue until we hit a flag or file)
  i <- 1
  while (i <= length(tokens) && !grepl("^-", tokens[i])) {
    if (is_filename(tokens[i])) {
      break
    }
    result$command_parts <- c(result$command_parts, tokens[i])
    i <- i + 1
  }

  # Process remaining tokens as arguments and options
  while (i <= length(tokens)) {
    token <- tokens[i]

    if (grepl("^-", token)) {
      # This is a flag or option
      # Check if it contains an equals sign (--key=value format)
      if (grepl("=", token)) {
        # Split on the first equals sign
        parts <- strsplit(token, "=", fixed = TRUE)[[1]]
        flag_name <- sub("^--?", "", parts[1])
        value <- paste(parts[-1], collapse = "=")  # Handle values with equals signs
        result$options <- c(result$options, value)
        names(result$options)[length(result$options)] <- flag_name
        i <- i + 1
      } else {
        # Remove leading dashes
        flag_name <- sub("^--?", "", token)

        # Check if next token could be a value (not a filename and doesn't start with -)
        if (i < length(tokens) &&
            !grepl("^-", tokens[i + 1]) &&
            !is_filename(tokens[i + 1])) {
          # This flag likely has a value (simple, non-file argument)
          next_token <- tokens[i + 1]
          result$options <- c(result$options, next_token)
          names(result$options)[length(result$options)] <- flag_name
          i <- i + 2
        } else {
          # This is a boolean flag
          result$flags <- c(result$flags, flag_name)
          i <- i + 1
        }
      }
    } else {
      # This is a positional argument (filename, dataset, etc.)
      result$positional_args <- c(result$positional_args, token)
      i <- i + 1
    }
  }

  result
}


#' Convert a parsed CLI command to an R function call.
#'
#' Takes parsed CLI components and converts them into valid R code that creates
#' a gdal_job object (without calling gdal_run).
#'
#' @param parsed_cli List from parse_cli_command().
#' @param r_function_name Character string of the R function name.
#' @param input_args List of input arguments metadata from GDAL JSON (optional).
#'
#' @return Character string containing R code to create gdal_job.
#'
convert_cli_to_r_example <- function(parsed_cli, r_function_name, input_args = NULL) {
  if (is.null(parsed_cli) || length(parsed_cli) == 0) {
    # Fallback: simple function call with no args
    return(sprintf("job <- %s()", r_function_name))
  }

  # Build argument assignments
  args <- character()

  # Map common positional argument names
  positional_names <- c("input", "output", "src_dataset", "dest_dataset", "dataset")

  # Add positional arguments
  if (length(parsed_cli$positional_args) > 0) {
    # Use generic positional names for positional arguments
    # (metadata usually contains flag/option names, not positional arg placeholders)
    for (j in seq_along(parsed_cli$positional_args)) {
      if (j <= length(positional_names)) {
        arg_name <- positional_names[j]
      } else {
        arg_name <- paste0("arg", j)
      }
      # Remove existing quotes if present to avoid double-quoting
      val <- parsed_cli$positional_args[j]
      val <- gsub("^\"|\"$", "", val)  # Remove leading/trailing quotes
      args <- c(args, sprintf('%s = "%s"', arg_name, val))
    }
  }

  # Add boolean flags (convert to TRUE)
  if (length(parsed_cli$flags) > 0) {
    for (flag in parsed_cli$flags) {
      flag_name <- gsub("-", "_", flag)  # Normalize hyphens to underscores
      args <- c(args, sprintf('%s = TRUE', flag_name))
    }
  }

  # Add key-value options (only if they match known function parameters)
  if (length(parsed_cli$options) > 0) {
    option_names <- names(parsed_cli$options)
    # Get valid parameter names from input_args metadata if available
    valid_params <- character(0)
    if (!is.null(input_args) && length(input_args) > 0) {
      if (is.data.frame(input_args)) {
        valid_params <- gsub("-", "_", input_args$name)
      } else if (is.list(input_args)) {
        valid_params <- gsub("-", "_", sapply(input_args, function(x) x$name %||% NA_character_))
        valid_params <- valid_params[!is.na(valid_params)]
      }
    }

    for (i in seq_along(parsed_cli$options)) {
      opt_name <- gsub("-", "_", option_names[i])  # Normalize hyphens to underscores
      opt_value <- parsed_cli$options[i]

      # Remove existing quotes if present to avoid double-quoting
      opt_value <- gsub("^\"|\"$", "", opt_value)  # Remove leading/trailing quotes

      # Only include if it's a valid parameter or we don't have metadata
      if (length(valid_params) == 0 || opt_name %in% valid_params) {
        args <- c(args, sprintf('%s = "%s"', opt_name, opt_value))
      }
    }
  }

  # Build the function call
  if (length(args) == 0) {
    code <- sprintf("job <- %s()", r_function_name)
  } else {
    # Format arguments to avoid lines longer than 100 characters
    # Start with function name and opening paren
    func_call <- sprintf("job <- %s(", r_function_name)
    current_line_length <- nchar(func_call)
    code_lines <- c(func_call)
    
    for (i in seq_along(args)) {
      arg <- args[i]
      # Check if adding this arg would exceed 100 chars
      # Account for comma and space, plus closing paren on last arg
      if (i < length(args)) {
        arg_with_sep <- paste0(arg, ", ")
      } else {
        arg_with_sep <- arg
      }
      
      # If this is the first arg or adding it won't exceed 100 chars, add to current line
      if (i == 1) {
        # First argument goes on same line as function name
        current_line <- paste0(code_lines[length(code_lines)], arg_with_sep)
        code_lines[length(code_lines)] <- current_line
        current_line_length <- nchar(current_line)
      } else if (current_line_length + nchar(arg_with_sep) <= 95) {
        # Fits on current line (leave 5 char margin for closing paren)
        current_line <- paste0(code_lines[length(code_lines)], arg_with_sep)
        code_lines[length(code_lines)] <- current_line
        current_line_length <- nchar(current_line)
      } else {
        # Start a new line with proper indentation (4 spaces for continuation)
        # The roxygen #' prefix will be added by the calling code
        code_lines <- c(code_lines, paste0("    ", arg_with_sep))
        current_line_length <- 4 + nchar(arg_with_sep)  # 4 spaces for indentation
      }
    }
    
    # Close the function call
    code_lines[length(code_lines)] <- paste0(code_lines[length(code_lines)], ")")
    code <- paste(code_lines, collapse = "\n")
  }

  code
}


#' Generate a family tag for roxygen2 based on command hierarchy.
#'
#' Creates @family tags for grouping related commands in pkgdown documentation.
#'
#' @param full_path Character vector representing the command hierarchy.
#'
#' @return Character string suitable for use as @family tag value.
#'
generate_family_tag <- function(full_path) {
  # Group by function category: raster, vector, mdim, vsi, driver, etc.
  # Examples:
  #   c("gdal", "raster", "info") -> "gdal_raster_utilities"
  #   c("gdal", "vector", "convert") -> "gdal_vector_utilities"
  #   c("gdal", "mdim", "info") -> "gdal_mdim_utilities"

  if (length(full_path) < 2) {
    return("gdal_utilities")
  }

  # The second element (after "gdal") is the category
  category <- full_path[2]

  # Some commands don't fit standard patterns
  if (category %in% c("raster", "vector", "mdim")) {
    return(sprintf("gdal_%s_utilities", category))
  } else if (category == "driver") {
    return("gdal_driver_utilities")
  } else if (category == "vsi") {
    return("gdal_vsi_utilities")
  } else {
    return(sprintf("gdal_%s_utilities", category))
  }
}


#' Cache documentation lookups to avoid repeated HTTP requests.
#'
#' @param cache_dir Character string path to cache directory.
#'
#' @return List with methods: get(url), set(url, data)
#'
create_doc_cache <- function(cache_dir = ".gdal_doc_cache") {
  if (!dir.exists(cache_dir)) {
    dir.create(cache_dir, showWarnings = FALSE)
  }

  list(
    get = function(url) {
      cache_file <- file.path(
        cache_dir,
        paste0(digest::digest(url), ".rds")
      )
      if (file.exists(cache_file)) {
        tryCatch(
          readRDS(cache_file),
          error = function(e) NULL
        )
      } else {
        NULL
      }
    },

    set = function(url, data) {
      cache_file <- file.path(
        cache_dir,
        paste0(digest::digest(url), ".rds")
      )
      tryCatch(
        saveRDS(data, cache_file),
        error = function(e) {
          warning(sprintf("Failed to cache documentation for %s", url))
        }
      )
    }
  )
}


#' Fetch enriched documentation with caching and fallback.
#'
#' @param full_path Character vector representing the command hierarchy.
#' @param cache Documentation cache object (from create_doc_cache).
#' @param verbose Logical. Print status messages.
#'
#' @return List with enriched documentation data.
#'
fetch_enriched_docs <- function(full_path, cache = NULL, verbose = FALSE) {
  url <- construct_doc_url(full_path)

  # Check cache first (if available)
  if (!is.null(cache)) {
    cached <- cache$get(url)
    if (!is.null(cached)) {
      if (verbose) cat(sprintf("  ✓ Cached: %s\n", url))
      return(cached)
    }
  }

  # Attempt to scrape documentation
  if (verbose) cat(sprintf("  ⟳ Fetching: %s\n", url))
  docs <- scrape_gdal_docs(url)

  # Cache the result
  if (!is.null(cache) && docs$status == 200) {
    cache$set(url, docs)
  }

  docs
}


# ============================================================================
# Step 1: Recursive API Crawling
# ============================================================================

#' Recursively crawl the GDAL API and collect all command endpoints.
#'
#' @param command_path Character vector specifying the command hierarchy.
#'   Initial call: `c("gdal")`.
#'
#' @return A list where each element is a command endpoint with full_path,
#'   description, and input_arguments.
#'
crawl_gdal_api <- function(command_path = c("gdal")) {
  # Build the command string
  cmd <- paste(command_path, collapse = " ")

  # Execute gdal --json-usage
  result <- tryCatch(
    {
      res <- processx::run(
        command = command_path[1],
        args = c(command_path[-1], "--json-usage"),
        error_on_status = TRUE
      )
      res$stdout
    },
    error = function(e) {
      warning(sprintf("Error querying '%s': %s", cmd, e$message))
      NULL
    }
  )

  if (is.null(result)) {
    return(list())
  }

  # Pre-process JSON to handle Infinity values
  # GDAL uses Infinity for unbounded max_count values, which is not valid JSON
  # Replace with a sentinel string that we'll convert to Inf after parsing
  json_str <- result
  json_str <- gsub('Infinity', '"__R_INF__"', json_str, fixed = TRUE)

  # Parse JSON with minimal simplification to preserve array structure
  # simplifyVector = FALSE prevents collapsing arrays of mixed types
  # simplifyDataFrame = FALSE prevents converting array of objects to dataframes
  api_spec <- tryCatch(
    jsonlite::fromJSON(json_str, simplifyVector = FALSE, simplifyDataFrame = FALSE),
    error = function(e) {
      warning(sprintf("Failed to parse JSON from '%s': %s", cmd, e$message))
      NULL
    }
  )

  if (is.null(api_spec)) {
    return(list())
  }

  # Convert sentinel string back to R's Inf
  api_spec <- .convert_infinity_strings(api_spec)

  endpoints <- list()

  # Check if this is an endpoint (executable command)
  # An endpoint has input_arguments or input_output_arguments
  has_input_args <- !is.null(api_spec$input_arguments) && length(api_spec$input_arguments) > 0
  has_input_output_args <- !is.null(api_spec$input_output_arguments) && length(api_spec$input_output_arguments) > 0
  
  if (has_input_args || has_input_output_args) {
    # This is an endpoint; collect it
    endpoints[[paste(command_path, collapse = "_")]] <- list(
      full_path = command_path,
      description = api_spec$description %||% "",
      input_arguments = api_spec$input_arguments %||% list(),
      input_output_arguments = api_spec$input_output_arguments %||% list()
    )
  }

  # Recurse into sub-algorithms if they exist
  if (!is.null(api_spec$sub_algorithms) && length(api_spec$sub_algorithms) > 0) {
    for (i in seq_along(api_spec$sub_algorithms)) {
      sub_algo <- api_spec$sub_algorithms[[i]]

      # Sub-algorithm can be either:
      # 1. A character string (the name)
      # 2. A list with "name" and "full_path" properties
      if (is.list(sub_algo) && !is.null(sub_algo$name)) {
        # It's a list with name and potentially full_path
        sub_name <- sub_algo$name
        if (is.character(sub_name) && length(sub_name) == 1) {
          sub_path <- c(command_path, sub_name)
          sub_endpoints <- crawl_gdal_api(sub_path)
          endpoints <- c(endpoints, sub_endpoints)
        }
      } else if (is.character(sub_algo) && length(sub_algo) == 1) {
        # It's just a string
        sub_path <- c(command_path, sub_algo)
        sub_endpoints <- crawl_gdal_api(sub_path)
        endpoints <- c(endpoints, sub_endpoints)
      }
    }
  }

  endpoints
}


# ============================================================================
# Step 2: R Function Generation
# ============================================================================

#' Generate an R function string from a GDAL command endpoint.
#'
#' @param endpoint A list with full_path, description, and input_arguments.
#' @param cache Documentation cache object (from create_doc_cache), or NULL to skip enrichment.
#' @param verbose Logical. Print status messages during documentation fetching.
#'
#' @return A string containing the complete R function code (including roxygen).
#'
generate_function <- function(endpoint, cache = NULL, verbose = FALSE) {
  full_path <- endpoint$full_path
  description <- endpoint$description %||% "GDAL command."
  input_args <- endpoint$input_arguments %||% list()
  input_output_args <- endpoint$input_output_arguments %||% list()

  # Build function name from command path (already includes 'gdal' prefix)
  # Replace hyphens with underscores for valid R function names
  func_name <- paste(gsub("-", "_", full_path), collapse = "_")

  # Check if this is a pipeline function
  is_pipeline <- func_name %in% c("gdal_raster_pipeline", "gdal_vector_pipeline")

  # Check if this is the base gdal function
  is_base_gdal <- identical(full_path, c("gdal"))

  # Generate R function signature
  r_args <- generate_r_arguments(input_args, input_output_args)
  if (is_pipeline) {
    # For pipeline functions, add jobs parameter first
    args_signature <- paste(c("jobs = NULL", r_args$signature), collapse = ",\n  ")
  } else if (is_base_gdal) {
    # For base gdal function, support shortcuts: gdal(filename), gdal(pipeline), gdal(command_vector)
    args_signature <- paste(c("x = NULL", r_args$signature), collapse = ",\n  ")
  } else {
    # Add job parameter first for pipe support
    args_signature <- paste(c("job = NULL", r_args$signature), collapse = ",\n  ")
  }

  # Attempt to fetch enriched documentation
  enriched_docs <- NULL
  family <- generate_family_tag(full_path)

  if (!is.null(cache)) {
    enriched_docs <- fetch_enriched_docs(full_path, cache = cache, verbose = verbose)
  }

  # Generate roxygen documentation with enrichment
  roxygen_doc <- generate_roxygen_doc(func_name, description, r_args$arg_names, enriched_docs, family, input_args, input_output_args, full_path, is_base_gdal, r_args$arg_mapping)

  # Generate function body
  func_body <- generate_function_body(full_path, input_args, input_output_args, r_args$arg_names, r_args$arg_mapping, is_pipeline, is_base_gdal)

  # Header comment indicating this file is auto-generated
  header <- "# ===================================================================\n# This file is AUTO-GENERATED by build/generate_gdal_api.R\n# Do not edit directly. Changes will be overwritten on regeneration.\n# ===================================================================\n"

  # Combine into complete function
  function_code <- sprintf(
    "%s\n%s\n#' @export\n%s <- function(%s) {\n%s\n}\n",
    header,
    roxygen_doc,
    func_name,
    args_signature,
    func_body
  )

  function_code
}


#' Generate R function arguments from GDAL input_arguments and input_output_arguments specification.
#'
#' Returns a list with:
#'   - signature: character vector of argument specifications
#'   - arg_names: character vector of argument names
#'   - arg_mapping: list mapping R argument names to CLI flags
#'
generate_r_arguments <- function(input_args, input_output_args) {
  signature <- character()
  arg_names <- character()
  arg_mapping <- list()

  # Combine all arguments: input_output_args first (positional), then input_args (options)
  all_args <- c(input_output_args, input_args)
  
  if (is.null(all_args) || length(all_args) == 0) {
    return(list(signature = signature, arg_names = arg_names, arg_mapping = arg_mapping))
  }

  # Convert dataframe to list of lists (jsonlite often converts JSON arrays to dataframes)
  if (is.data.frame(all_args)) {
    args_list <- lapply(1:nrow(all_args), function(i) as.list(all_args[i, ]))
  } else {
    args_list <- all_args
  }

  # Track which arguments are positional (from input_output_args)
  is_positional <- rep(c(TRUE, FALSE), c(length(input_output_args %||% list()), length(input_args %||% list())))

  # Classify arguments for ordering: inputs first, outputs second, others last
  classify_arg <- function(arg) {
    name <- tolower(arg$name %||% "")
    if (grepl("input|src|source|in", name)) return("input")
    if (grepl("output|dst|destination|out", name)) return("output")
    return("other")
  }
  
  classifications <- sapply(args_list, classify_arg)
  
  # Order by classification: input, output, other
  order_indices <- order(factor(classifications, levels = c("input", "output", "other")))
  
  # Reorder args_list and is_positional accordingly
  args_list <- args_list[order_indices]
  is_positional <- is_positional[order_indices]
  
  # Special handling: if there's an "input" parameter, move it to the front
  input_idx <- which(sapply(args_list, function(arg) {
    r_name <- gsub("-", "_", arg$name %||% arg[[1]] %||% "")
    r_name == "input"
  }))
  
  if (length(input_idx) > 0 && input_idx > 1) {
    # Move input to the front
    input_arg <- args_list[[input_idx]]
    input_pos <- is_positional[input_idx]
    
    args_list <- c(list(input_arg), args_list[-input_idx])
    is_positional <- c(input_pos, is_positional[-input_idx])
  }

  for (i in seq_along(args_list)) {
    arg <- args_list[[i]]
    gdal_name <- arg$name %||% arg[[1]]
    if (is.null(gdal_name)) {
      warning("Argument at position ", i, " has no name")
      next
    }

    r_name <- gsub("-", "_", gdal_name)
    # Prefix with capital X if name starts with a digit (invalid in R)
    if (grepl("^[0-9]", r_name)) {
      r_name <- paste0("X", r_name)
    }
    arg_type <- arg$type %||% "string"
    min_count <- arg$min_count %||% 0
    max_count <- arg$max_count %||% 1
    default_val <- arg$default

    # Determine R type and default
    if (min_count > 0) {
      # Required argument (no default)
      default_str <- ""
    } else {
      # Optional argument
      if (arg_type == "boolean") {
        default_str <- " = FALSE"
      } else {
        default_str <- " = NULL"
      }
    }

    # Build signature
    if (default_str == "") {
      sig <- r_name
    } else {
      sig <- paste0(r_name, default_str)
    }

    signature <- c(signature, sig)
    arg_names <- c(arg_names, r_name)
    arg_mapping[[r_name]] <- list(
      gdal_name = gdal_name,
      type = arg_type,
      min_count = min_count,
      max_count = max_count,
      default = default_val,
      is_positional = is_positional[i]
    )
  }

  list(
    signature = signature,
    arg_names = arg_names,
    arg_mapping = arg_mapping
  )
}


#' Generate roxygen2 documentation block for auto-generated functions.
#'
#' @param func_name Character string for the function name.
#' @param description Character string from JSON API.
#' @param arg_names Character vector of argument names.
#' @param enriched_docs List from fetch_enriched_docs (optional).
#' @param family Character string for @family tag (optional).
#' @param input_args List of input arguments metadata from GDAL (optional).
#' @param input_output_args List of input/output arguments metadata from GDAL (optional).
#' @param full_path Character vector representing the command hierarchy.
#' @param is_base_gdal Logical indicating if this is the base gdal function.
#'
generate_roxygen_doc <- function(func_name, description, arg_names, enriched_docs = NULL, family = NULL, input_args = NULL, input_output_args = NULL, full_path = NULL, is_base_gdal = FALSE, arg_mapping = NULL) {
  # Helper to format multi-line text for roxygen2 (each line needs #')
  format_roxygen_text <- function(text) {
    if (is.na(text) || !nzchar(text)) return("")
    # Split on newlines and add #' prefix to each line
    lines <- strsplit(text, "\n")[[1]]
    paste(paste0("#' ", trimws(lines)), collapse = "\n")
  }

  doc <- sprintf("#' @title %s\n", description)

  # Check if this is a pipeline function
  is_pipeline <- func_name %in% c("gdal_raster_pipeline", "gdal_vector_pipeline")

  # Use enriched description if available, otherwise use API description
  enriched_desc <- NA_character_
  if (!is.null(enriched_docs) && !is.na(enriched_docs$description)) {
    enriched_desc <- enriched_docs$description
  }

  if (is.character(enriched_desc) && length(enriched_desc) > 0 &&
      !is.na(enriched_desc[1]) && nzchar(enriched_desc[1])) {
    # Escape special roxygen2 markup characters in description
    escaped_desc <- enriched_desc[1]
    escaped_desc <- gsub("\\{", "\\\\{", escaped_desc)  # Escape {
    escaped_desc <- gsub("\\}", "\\\\}", escaped_desc)  # Escape }
    formatted_desc <- format_roxygen_text(escaped_desc)
    # Add the GDAL documentation URL link
    doc_url <- construct_doc_url(full_path)
    doc <- paste0(doc, sprintf("#' @description\n%s\n#' \n#' See \\url{%s} for detailed GDAL documentation.\n", formatted_desc, doc_url))
  } else {
    # Fallback: include both header and description
    formatted_desc <- format_roxygen_text(description)
    # Add the GDAL documentation URL link
    doc_url <- construct_doc_url(full_path)
    doc <- paste0(doc, sprintf("#' @description\n#' Auto-generated GDAL CLI wrapper.\n%s\n#' \n#' See \\url{%s} for detailed GDAL documentation.\n", formatted_desc, doc_url))
  }

  # For pipeline functions, add jobs parameter first
  if (is_pipeline) {
    doc <- paste0(doc, "#' @param jobs A vector of gdal_job objects to execute in sequence, or NULL to use pipeline string\n")
  } else if (is_base_gdal) {
    doc <- paste0(doc, "#' @param x A filename (for 'gdal info'), a pipeline string (for 'gdal pipeline'), a command vector, or a gdal_job object from a piped operation\n")
  } else {
    doc <- paste0(doc, "#' @param job A gdal_job object from a piped operation, or NULL\n")
  }

  # Document each parameter with rich metadata from JSON
  if (!is.null(arg_names) && length(arg_names) > 0) {
    # Build a map of R argument names to their JSON metadata
    arg_metadata_map <- list()
    all_input_args <- c(input_output_args, input_args)
    if (!is.null(all_input_args) && length(all_input_args) > 0) {
      if (is.data.frame(all_input_args)) {
        # Convert dataframe to list of lists
        for (i in seq_len(nrow(all_input_args))) {
          row_list <- as.list(all_input_args[i, ])
          gdal_name <- row_list$name %||% NA_character_
          if (!is.na(gdal_name)) {
            r_name <- gsub("-", "_", gdal_name)
            if (grepl("^[0-9]", r_name)) r_name <- paste0("X", r_name)
            arg_metadata_map[[r_name]] <- row_list
          }
        }
      } else if (is.list(all_input_args)) {
        for (i in seq_along(all_input_args)) {
          arg <- all_input_args[[i]]
          gdal_name <- arg$name %||% NA_character_
          if (!is.na(gdal_name)) {
            r_name <- gsub("-", "_", gdal_name)
            if (grepl("^[0-9]", r_name)) r_name <- paste0("X", r_name)
            arg_metadata_map[[r_name]] <- arg
          }
        }
      }
    }

    for (arg_name in arg_names) {
      # Get metadata for this argument
      arg_meta <- arg_metadata_map[[arg_name]] %||% list()
      
      # Build parameter description
      param_desc <- ""
      
      # Start with the description from JSON
      if (!is.null(arg_meta$description) && nzchar(arg_meta$description)) {
        param_desc <- arg_meta$description
        # Escape special roxygen2 markup characters in description
        param_desc <- gsub("\\{", "\\\\{", param_desc)  # Escape {
        param_desc <- gsub("\\}", "\\\\}", param_desc)  # Escape }
        # Escape square brackets with backslash
        param_desc <- gsub("\\[", "\\\\[", param_desc)
        param_desc <- gsub("\\]", "\\\\]", param_desc)
      }
      
      # Add type information
      arg_type <- arg_meta$type %||% "unknown"
      if (arg_type == "boolean") {
        param_desc <- paste0(param_desc, " (Logical)")
      } else if (arg_type == "integer") {
        param_desc <- paste0(param_desc, " (Integer)")
      } else if (arg_type == "integer_list") {
        param_desc <- paste0(param_desc, " (Integer vector)")
      } else if (arg_type == "string_list") {
        param_desc <- paste0(param_desc, " (Character vector)")
      } else if (arg_type == "dataset") {
        param_desc <- paste0(param_desc, " (Dataset path)")
      }
      
      # Add format information if available
      if (!is.null(arg_meta$metavar) && nzchar(arg_meta$metavar)) {
        param_desc <- paste0(param_desc, ". Format: `", arg_meta$metavar, "`")
      }
      
      # Add choices if available
      if (!is.null(arg_meta$choices) && length(arg_meta$choices) > 0) {
        choices_str <- paste(arg_meta$choices, collapse = ", ")
        # Only show first 5 choices to keep it reasonable
        if (length(arg_meta$choices) > 5) {
          choices_shown <- paste(arg_meta$choices[1:5], collapse = ", ")
          param_desc <- paste0(param_desc, ". Choices: ", choices_shown, ", ...")
        } else {
          param_desc <- paste0(param_desc, ". Choices: ", choices_str)
        }
      }
      
      # Add default value if available
      if (!is.null(arg_meta$default)) {
        default_val <- arg_meta$default
        if (is.logical(default_val)) {
          default_val <- tolower(as.character(default_val))
        }
        param_desc <- paste0(param_desc, " (Default: `", default_val, "`)")
      }
      
      # Add requirement info (use different notation to avoid roxygen2 interpretation)
      if (isTRUE(arg_meta$required)) {
        param_desc <- paste0(param_desc, " (required)")
      }
      
      # Add min/max for numeric types (use parentheses instead of brackets to avoid roxygen2 link detection)
      if (!is.null(arg_meta$min_value) && !is.null(arg_meta$max_value)) {
        param_desc <- paste0(param_desc, ". Range: (`", arg_meta$min_value, "` to `", arg_meta$max_value, "`)")
      } else if (!is.null(arg_meta$min_value)) {
        param_desc <- paste0(param_desc, ". Minimum: `", arg_meta$min_value, "`")
      }
      
      # Add count info for lists
      if (!is.null(arg_meta$min_count) && !is.null(arg_meta$max_count)) {
        if (arg_meta$min_count == arg_meta$max_count) {
          param_desc <- paste0(param_desc, ". Exactly `", arg_meta$min_count, "` value(s)")
        } else {
          param_desc <- paste0(param_desc, ". `", arg_meta$min_count, "` to `", arg_meta$max_count, "` value(s)")
        }
      }
      
      # Add category info for better organization (use different notation to avoid roxygen2 interpretation)
      if (!is.null(arg_meta$category) && nzchar(arg_meta$category)) {
        if (arg_meta$category != "Base") {
          param_desc <- paste0(param_desc, " (", arg_meta$category, ")")
        }
      }

      # For pipeline functions, add note about pipeline parameter
      if (is_pipeline && arg_name == "pipeline") {
        param_desc <- paste0(param_desc, " (ignored if jobs is provided)")
      }

      doc <- paste0(doc, sprintf("#' @param %s %s\n", arg_name, param_desc))
    }
  }

  doc <- paste0(doc, sprintf("#' @return A [gdal_job] object.\n"))

  # Add family tag if provided
  if (!is.null(family) && nzchar(family)) {
    doc <- paste0(doc, sprintf("#' @family %s\n", family))
  }

  # Add examples: convert CLI examples to R code if available
  doc <- paste0(doc, "#' @examples\n")

  if (!is.null(enriched_docs) && length(enriched_docs$examples) > 0) {
    # Parse and convert CLI examples to R code
    examples_added <- 0

    for (i in seq_len(min(2, length(enriched_docs$examples)))) {
      cli_example <- trimws(enriched_docs$examples[i])
      if (nzchar(cli_example)) {
        # Parse the CLI command
        parsed_cli <- parse_cli_command(cli_example)

        # Convert to R code
        r_code <- convert_cli_to_r_example(parsed_cli, func_name, c(input_output_args, input_args))

        if (!is.null(r_code) && nzchar(r_code)) {
          # Validate that the generated code uses valid parameters
          # Extract parameter names from the example: job <- func(param1 = val1, param2 = val2)
          param_matches <- gregexpr("(\\w+)\\s*=", r_code)[[1]]
          if (param_matches[1] > -1) {
            matched_params <- regmatches(r_code, gregexpr("(\\w+)(?=\\s*=)", r_code, perl = TRUE))[[1]]

            # Check if all used parameters are valid
            valid_param_names <- if (!is.null(arg_names)) arg_names else character(0)
            invalid_params <- setdiff(matched_params, valid_param_names)

            if (length(invalid_params) > 0) {
              # Skip this example - it uses invalid parameters
              next
            }
          }

          # Add a comment describing what the example does
          if (examples_added == 0) {
            doc <- paste0(doc, "#' # Create a GDAL job (not executed)\n")
          } else {
            doc <- paste0(doc, "#' # Another example\n")
          }
          # Add the R code (with roxygen prefix on each line if multi-line)
          # Split by newlines and add #' prefix to each
          code_lines <- strsplit(r_code, "\n")[[1]]
          formatted_code <- paste(paste0("#' ", code_lines), collapse = "\n")
          doc <- paste0(doc, formatted_code, "\n")
          examples_added <- examples_added + 1
        }
      }
    }

    # Add code to inspect the job structure
    if (examples_added > 0) {
      doc <- paste0(doc, "#' \n#' # Inspect the job structure\n#' str(job)\n")
    }
  }

  if (length(enriched_docs$examples) == 0 || examples_added == 0) {
    # Fallback: provide a template example showing job creation without execution
    # Use the first parameter if available, otherwise use 'input'
    first_param <- if (!is.null(arg_names) && length(arg_names) > 0) arg_names[1] else "input"
    
    # Check if first_param is boolean
    is_boolean <- FALSE
    if (!is.null(arg_mapping[[first_param]]) && arg_mapping[[first_param]]$type == "boolean") {
      is_boolean <- TRUE
    }
    
    if (is_boolean) {
      doc <- paste0(doc, sprintf("#' # Create a GDAL job (not executed)\n#' job <- %s(%s = TRUE)\n", func_name, first_param))
    } else {
      doc <- paste0(doc, sprintf("#' # Create a GDAL job (not executed)\n#' job <- %s(%s = \"data.tif\")\n", func_name, first_param))
    }
    doc <- paste0(doc, "#' #\n#' # Inspect the job (optional)\n#' # print(job)\n")
  }

  doc
}


#' Generate the function body for an auto-generated GDAL wrapper.
#'
generate_function_body <- function(full_path, input_args, input_output_args, arg_names, arg_mapping, is_pipeline = FALSE, is_base_gdal = FALSE) {
  # Ensure full_path is a character vector
  if (!is.character(full_path)) {
    full_path <- as.character(full_path)
  }
  if (length(full_path) == 1 && grepl("^c\\(", full_path[1])) {
    # It's a string representation of a vector, try to parse it
    full_path <- eval(parse(text = full_path[1]))
  }

  # Convert full_path to JSON array string (skip "gdal" prefix)
  if (is_base_gdal) {
    # For base gdal, use c("gdal") as command_path
    path_json <- 'c("gdal")'
  } else {
    path_json <- sprintf("c(%s)", paste(sprintf('"%s"', full_path[-1]), collapse = ", "))
  }

  # Build argument validation and collection
  body_lines <- c()

  if (is_pipeline) {
    # Special handling for pipeline functions
    body_lines <- c(body_lines, "  # If jobs is provided, build pipeline string from job sequence")
    body_lines <- c(body_lines, "  if (!is.null(jobs)) {")
    body_lines <- c(body_lines, "    if (!is.list(jobs) && !is.vector(jobs)) {")
    body_lines <- c(body_lines, "      rlang::abort('jobs must be a list or vector of gdal_job objects')")
    body_lines <- c(body_lines, "    }")
    body_lines <- c(body_lines, "    for (i in seq_along(jobs)) {")
    body_lines <- c(body_lines, "      if (!inherits(jobs[[i]], 'gdal_job')) {")
    body_lines <- c(body_lines, "        rlang::abort(sprintf('jobs[[%d]] must be a gdal_job object', i))")
    body_lines <- c(body_lines, "      }")
    body_lines <- c(body_lines, "    }")
    body_lines <- c(body_lines, "    pipeline <- build_pipeline_from_jobs(jobs)")
    body_lines <- c(body_lines, "  }")
    body_lines <- c(body_lines, "")
    body_lines <- c(body_lines, "  # Collect arguments")
    body_lines <- c(body_lines, "  args <- list()")

    if (length(arg_names) > 0) {
      for (arg_name in arg_names) {
        body_lines <- c(
          body_lines,
          sprintf("  if (!missing(%s)) args[[%s]] <- %s", arg_name, deparse(arg_name), arg_name)
        )
      }
    }
  } else if (is_base_gdal) {
    # Special handling for base gdal function with shortcuts
    body_lines <- c(body_lines, "  # Handle shortcuts for base gdal function")
    body_lines <- c(body_lines, "  if (!is.null(x)) {")
    body_lines <- c(body_lines, "    # Check if x is a piped gdal_job")
    body_lines <- c(body_lines, "    if (inherits(x, 'gdal_job')) {")
    body_lines <- c(body_lines, "      # Merge arguments from piped job")
    body_lines <- c(body_lines, "      merged_args <- merge_gdal_job_arguments(x$arguments, list(")

    # Build the list of current function arguments, only including provided ones
    if (length(arg_names) > 0) {
      arg_lines <- character()
      for (i in seq_along(arg_names)) {
        arg_name <- arg_names[i]
        # Check if this argument has a default (optional)
        has_default <- arg_mapping[[arg_name]]$min_count == 0
        if (has_default) {
          # Always include optional arguments
          if (i < length(arg_names)) {
            arg_lines <- c(arg_lines, sprintf("        %s = %s,", arg_name, arg_name))
          } else {
            arg_lines <- c(arg_lines, sprintf("        %s = %s", arg_name, arg_name))
          }
        } else {
          # Only include required arguments if provided
          if (i < length(arg_names)) {
            arg_lines <- c(arg_lines, sprintf("        %s = if (!missing(%s)) %s else NULL,", arg_name, arg_name, arg_name))
          } else {
            arg_lines <- c(arg_lines, sprintf("        %s = if (!missing(%s)) %s else NULL", arg_name, arg_name, arg_name))
          }
        }
      }
      body_lines <- c(body_lines, arg_lines)
    }

    body_lines <- c(body_lines, "      ))")
    body_lines <- c(body_lines, "      return(new_gdal_job(command_path = x$command_path, arguments = merged_args))")
    body_lines <- c(body_lines, "    }")
    body_lines <- c(body_lines, "    ")
    body_lines <- c(body_lines, "    # Handle shortcut: filename -> gdal info filename")
    body_lines <- c(body_lines, "    if (is.character(x) && length(x) == 1 && !grepl('\\\\s', x)) {")
    body_lines <- c(body_lines, "      # Single string without spaces - treat as filename for gdal info")
    body_lines <- c(body_lines, "      merged_args <- list(input = x)")
    body_lines <- c(body_lines, "      return(new_gdal_job(command_path = c('info'), arguments = merged_args))")
    body_lines <- c(body_lines, "    }")
    body_lines <- c(body_lines, "    ")
    body_lines <- c(body_lines, "    # Handle shortcut: pipeline string -> gdal pipeline")
    body_lines <- c(body_lines, "    if (is.character(x) && length(x) == 1 && grepl('!', x)) {")
    body_lines <- c(body_lines, "      # Contains ! - treat as pipeline")
    body_lines <- c(body_lines, "      merged_args <- list(pipeline = x)")
    body_lines <- c(body_lines, "      return(new_gdal_job(command_path = c('pipeline'), arguments = merged_args))")
    body_lines <- c(body_lines, "    }")
    body_lines <- c(body_lines, "    ")
    body_lines <- c(body_lines, "    # Handle shortcut: command vector -> execute as gdal command")
    body_lines <- c(body_lines, "    if (is.character(x) && length(x) > 1) {")
    body_lines <- c(body_lines, "      # Vector of strings - treat as command arguments")
    body_lines <- c(body_lines, "      merged_args <- list()")
    body_lines <- c(body_lines, "      # First element is subcommand, rest are arguments")
    body_lines <- c(body_lines, "      command_path <- c(x[1])")
    body_lines <- c(body_lines, "      if (length(x) > 1) {")
    body_lines <- c(body_lines, "        # Parse remaining arguments")
    body_lines <- c(body_lines, "        for (i in 2:length(x)) {")
    body_lines <- c(body_lines, "          arg <- x[i]")
    body_lines <- c(body_lines, "          if (grepl('^--', arg)) {")
    body_lines <- c(body_lines, "            # Long option")
    body_lines <- c(body_lines, "            opt_name <- sub('^--', '', arg)")
    body_lines <- c(body_lines, "            if (i < length(x) && !grepl('^-', x[i+1])) {")
    body_lines <- c(body_lines, "              merged_args[[opt_name]] <- x[i+1]")
    body_lines <- c(body_lines, "              i <- i + 1")
    body_lines <- c(body_lines, "            } else {")
    body_lines <- c(body_lines, "              merged_args[[opt_name]] <- TRUE")
    body_lines <- c(body_lines, "            }")
    body_lines <- c(body_lines, "          } else if (grepl('^-', arg)) {")
    body_lines <- c(body_lines, "            # Short option")
    body_lines <- c(body_lines, "            opt_name <- sub('^-', '', arg)")
    body_lines <- c(body_lines, "            if (i < length(x) && !grepl('^-', x[i+1])) {")
    body_lines <- c(body_lines, "              merged_args[[opt_name]] <- x[i+1]")
    body_lines <- c(body_lines, "              i <- i + 1")
    body_lines <- c(body_lines, "            } else {")
    body_lines <- c(body_lines, "              merged_args[[opt_name]] <- TRUE")
    body_lines <- c(body_lines, "            }")
    body_lines <- c(body_lines, "          } else {")
    body_lines <- c(body_lines, "            # Positional argument")
    body_lines <- c(body_lines, "            merged_args[['input']] <- arg")
    body_lines <- c(body_lines, "          }")
    body_lines <- c(body_lines, "        }")
    body_lines <- c(body_lines, "      }")
    body_lines <- c(body_lines, "      return(new_gdal_job(command_path = command_path, arguments = merged_args))")
    body_lines <- c(body_lines, "    }")
    body_lines <- c(body_lines, "    ")
    body_lines <- c(body_lines, "    # Invalid x argument")
    body_lines <- c(body_lines, "    rlang::abort('x must be a filename string, pipeline string, command vector, or gdal_job object')")
    body_lines <- c(body_lines, "  }")
    body_lines <- c(body_lines, "  ")
    body_lines <- c(body_lines, "  # No shortcut - handle as regular command")
    body_lines <- c(body_lines, "  merged_args <- list()")

    if (length(arg_names) > 0) {
      for (arg_name in arg_names) {
        body_lines <- c(
          body_lines,
          sprintf("  if (!missing(%s)) merged_args[[%s]] <- %s", arg_name, deparse(arg_name), arg_name)
        )
      }
    }
  } else {
    # Handle job input for pipeline extension or argument merging
    body_lines <- c(body_lines, "  # Collect function arguments")
    body_lines <- c(body_lines, "  new_args <- list()")

    if (length(arg_names) > 0) {
      for (arg_name in arg_names) {
        body_lines <- c(
          body_lines,
          sprintf("  if (!missing(%s)) new_args[[%s]] <- %s", arg_name, deparse(arg_name), arg_name)
        )
      }
    }

    body_lines <- c(body_lines, sprintf("  job_input <- handle_job_input(job, new_args, %s)", path_json))
    body_lines <- c(body_lines, "  if (job_input$should_extend) {")
    body_lines <- c(body_lines, "    # Extend pipeline from existing job")
    body_lines <- c(body_lines, sprintf("    return(extend_gdal_pipeline(job_input$job, %s, new_args))", path_json))
    body_lines <- c(body_lines, "  } else {")
    body_lines <- c(body_lines, "    # Create new job with merged arguments")
    body_lines <- c(body_lines, sprintf("    merged_args <- job_input$merged_args", path_json))
    body_lines <- c(body_lines, "  }")
  }

  # Create gdal_job object
  body_lines <- c(body_lines, "")
  if (is_pipeline) {
    body_lines <- c(
      body_lines,
      sprintf("  new_gdal_job(command_path = %s, arguments = args)", path_json)
    )
  } else {
    body_lines <- c(
      body_lines,
      sprintf("  new_gdal_job(command_path = %s, arguments = merged_args)", path_json)
    )
  }

  paste(body_lines, collapse = "\n")
}


# ============================================================================
# Step 3: Write Generated Functions to Disk
# ============================================================================

#' Write a generated function to a file in R/.
#'
write_function_file <- function(func_name, function_code) {
  output_file <- file.path("R", sprintf("%s.R", func_name))

  cat(sprintf("Generating: %s\n", output_file))
  writeLines(function_code, con = output_file)

  output_file
}


# ============================================================================
# Main Execution
# ============================================================================

main <- function() {
  # Check if GDAL is available
  gdal_check <- tryCatch(
    processx::run("gdal", "--version", error_on_status = TRUE),
    error = function(e) NULL
  )

  if (is.null(gdal_check)) {
    cat("ERROR: GDAL command not found.\n")
    cat("Please ensure GDAL >= 3.11 is installed and in your PATH.\n")
    cat("Test with: gdal --version\n")
    return(invisible(NULL))
  }

  cat("Crawling GDAL API...\n")
  cat(sprintf("Using: %s\n\n", trimws(gdal_check$stdout)))

  endpoints <- crawl_gdal_api(c("gdal"))

  if (length(endpoints) == 0) {
    cat("\nWARNING: No GDAL endpoints found.\n")
    cat("Possible issues:\n")
    cat("  1. GDAL version < 3.11 (needs --json-usage support)\n")
    cat("  2. GDAL JSON parsing failed (Infinity values?)\n")
    cat("  3. GDAL not properly installed\n")
    cat("\nNo functions generated. Exiting.\n")
    return(invisible(NULL))
  }

  cat(sprintf("✓ Found %d GDAL command endpoints.\n\n", length(endpoints)))

  # Initialize documentation cache (unless disabled via environment variable)
  doc_cache <- NULL
  enable_enrichment <- Sys.getenv("SKIP_DOC_ENRICHMENT", "false") != "true"

  if (enable_enrichment) {
    cat("Initializing documentation cache for web enrichment...\n")
    doc_cache <- create_doc_cache(".gdal_doc_cache")
    cat("(Set SKIP_DOC_ENRICHMENT=true environment variable to disable)\n\n")
  } else {
    cat("Documentation enrichment disabled (SKIP_DOC_ENRICHMENT=true)\n\n")
  }

  generated_files <- character()
  failed_count <- 0

  for (endpoint_name in names(endpoints)) {
    endpoint <- endpoints[[endpoint_name]]
    # Function name combines command path (which already starts with 'gdal')
    # Also replace hyphens with underscores to get valid R function names
    func_name <- paste(gsub("-", "_", endpoint$full_path), collapse = "_")

    cat(sprintf("  Generating %s... ", func_name))

    tryCatch(
      {
        function_code <- generate_function(endpoint, cache = doc_cache, verbose = FALSE)
        output_file <- write_function_file(func_name, function_code)
        cat("OK\n")
        generated_files <- c(generated_files, output_file)
      },
      error = function(e) {
        cat(sprintf("FAILED: %s\n", e$message))
        failed_count <<- failed_count + 1
      }
    )
  }

  cat(sprintf("\n✓ Generated %d functions successfully.\n", length(generated_files)))
  if (failed_count > 0) {
    cat(sprintf("⚠ %d functions failed to generate.\n", failed_count))
  }
  cat(sprintf("✓ Run roxygen2::roxygenise() to update documentation.\n\n"))

  invisible(generated_files)
}

# Run if executed directly
if (!interactive()) {
  main()
}
