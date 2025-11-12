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

#' Recursively convert sentinel infinity strings to R's Inf
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
                example_texts <- c(example_texts, pre_text)
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
  # An endpoint has input_arguments but may also have sub_algorithms
  if (!is.null(api_spec$input_arguments) && length(api_spec$input_arguments) > 0) {
    # This is an endpoint; collect it
    endpoints[[paste(command_path, collapse = "_")]] <- list(
      full_path = command_path,
      description = api_spec$description %||% "",
      input_arguments = api_spec$input_arguments %||% list()
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

  # Build function name from command path (already includes 'gdal' prefix)
  # Replace hyphens with underscores for valid R function names
  func_name <- paste(gsub("-", "_", full_path), collapse = "_")

  # Generate R function signature
  r_args <- generate_r_arguments(input_args)
  args_signature <- paste(r_args$signature, collapse = ",\n  ")

  # Attempt to fetch enriched documentation
  enriched_docs <- NULL
  family <- generate_family_tag(full_path)

  if (!is.null(cache)) {
    enriched_docs <- fetch_enriched_docs(full_path, cache = cache, verbose = verbose)
  }

  # Generate roxygen documentation with enrichment
  roxygen_doc <- generate_roxygen_doc(func_name, description, r_args$arg_names, enriched_docs, family)

  # Generate function body
  func_body <- generate_function_body(full_path, input_args, r_args$arg_names)

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


#' Generate R function arguments from GDAL input_arguments specification.
#'
#' Returns a list with:
#'   - signature: character vector of argument specifications
#'   - arg_names: character vector of argument names
#'   - arg_mapping: list mapping R argument names to CLI flags
#'
generate_r_arguments <- function(input_args) {
  signature <- character()
  arg_names <- character()
  arg_mapping <- list()

  if (is.null(input_args) || length(input_args) == 0) {
    return(list(signature = signature, arg_names = arg_names, arg_mapping = arg_mapping))
  }

  # Convert dataframe to list of lists (jsonlite often converts JSON arrays to dataframes)
  if (is.data.frame(input_args)) {
    args_list <- lapply(1:nrow(input_args), function(i) as.list(input_args[i, ]))
  } else {
    args_list <- input_args
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
      default = default_val
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
#'
generate_roxygen_doc <- function(func_name, description, arg_names, enriched_docs = NULL, family = NULL) {
  # Helper to format multi-line text for roxygen2 (each line needs #')
  format_roxygen_text <- function(text) {
    if (is.na(text) || !nzchar(text)) return("")
    # Split on newlines and add #' prefix to each line
    lines <- strsplit(text, "\n")[[1]]
    paste(paste0("#' ", trimws(lines)), collapse = "\n")
  }

  doc <- sprintf("#' @title %s\n", description)

  # Use enriched description if available, otherwise use API description
  enriched_desc <- NA_character_
  if (!is.null(enriched_docs) && !is.na(enriched_docs$description)) {
    enriched_desc <- enriched_docs$description
  }

  if (is.character(enriched_desc) && length(enriched_desc) > 0 &&
      !is.na(enriched_desc[1]) && nzchar(enriched_desc[1])) {
    formatted_desc <- format_roxygen_text(enriched_desc[1])
    doc <- paste0(doc, sprintf("#' @description\n%s\n", formatted_desc))
  } else {
    # Fallback: include both header and description
    formatted_desc <- format_roxygen_text(description)
    doc <- paste0(doc, sprintf("#' @description\n#' Auto-generated GDAL CLI wrapper.\n%s\n", formatted_desc))
  }

  # Document each parameter with enriched descriptions if available
  if (!is.null(arg_names) && length(arg_names) > 0) {
    for (arg_name in arg_names) {
      # Try to find enriched parameter description
      param_desc <- NA_character_
      if (!is.null(enriched_docs) && !is.null(enriched_docs$param_details) &&
          length(enriched_docs$param_details) > 0) {
        param_desc <- enriched_docs$param_details[[arg_name]]
      }

      # Ensure param_desc is a character vector of length 1
      if (is.character(param_desc) && length(param_desc) > 0 &&
          !is.na(param_desc[1]) && nzchar(param_desc[1])) {
        # Clean up description: remove newlines, excessive spaces
        param_desc <- gsub("\n+", " ", param_desc[1])
        param_desc <- gsub("\\s+", " ", param_desc)
        param_desc <- trimws(param_desc)
        doc <- paste0(doc, sprintf("#' @param %s %s\n", arg_name, param_desc))
      } else {
        doc <- paste0(doc, sprintf("#' @param %s GDAL argument\n", arg_name))
      }
    }
  }

  doc <- paste0(doc, sprintf("#' @return A [gdal_job] object.\n"))

  # Add family tag if provided
  if (!is.null(family) && nzchar(family)) {
    doc <- paste0(doc, sprintf("#' @family %s\n", family))
  }

  # Add examples if available from enriched docs
  if (!is.null(enriched_docs) && length(enriched_docs$examples) > 0) {
    doc <- paste0(doc, "#' @section Examples:\n")
    doc <- paste0(doc, "#' \\preformatted{\n")

    # Add up to 2 examples
    for (i in seq_len(min(2, length(enriched_docs$examples)))) {
      example <- trimws(enriched_docs$examples[i])
      # Clean up shell prompt if present
      example <- sub("^\\$ ", "", example)
      # Add proper indentation for roxygen2
      example <- gsub("\n", "\n#' ", paste0("#' ", example))
      doc <- paste0(doc, example, "\n")
    }

    doc <- paste0(doc, "#' }\n")
  } else {
    # Fallback to simple example
    doc <- paste0(doc, sprintf("#' @examples\n#' \\dontrun{\n#' %s(...) |> gdal_run()\n#' }\n", func_name))
  }

  doc
}


#' Generate the function body for an auto-generated GDAL wrapper.
#'
generate_function_body <- function(full_path, input_args, arg_names) {
  # Ensure full_path is a character vector
  if (!is.character(full_path)) {
    full_path <- as.character(full_path)
  }
  if (length(full_path) == 1 && grepl("^c\\(", full_path[1])) {
    # It's a string representation of a vector, try to parse it
    full_path <- eval(parse(text = full_path[1]))
  }

  # Convert full_path to JSON array string
  path_json <- sprintf("c(%s)", paste(sprintf('"%s"', full_path), collapse = ", "))

  # Build argument validation and collection
  body_lines <- c()

  # Collect all arguments into a list
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

  # Create gdal_job object
  body_lines <- c(body_lines, "")
  body_lines <- c(
    body_lines,
    sprintf("  new_gdal_job(command_path = %s, arguments = args)", path_json)
  )

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
