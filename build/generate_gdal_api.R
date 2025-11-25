#!/usr/bin/env Rscript

library(processx)
library(jsonlite)
library(glue)
library(rvest)
library(httr)
library(xml2)
library(magrittr)

# ============================================================================
# Step 0: Helper Functions
# ============================================================================

# ============================================================================
# Step 0a: GDAL Version Handling (PHASE 1 - NEW)
# ============================================================================

#' Parse GDAL version from "gdal --version" output
#'
#' Extracts version components from GDAL version string.
#' Example input: "GDAL 3.11.4, released 2024-11-10"
#' Returns: list(full = "3.11.4", major = 3, minor = 11, patch = 4)
#'
#' @param version_str Character string from `gdal --version`
#'
#' @return List with version components (full, major, minor, patch, rc)
#'
.parse_gdal_version <- function(version_str) {
  version_str <- trimws(version_str)

  # Extract version number (first component after GDAL prefix)
  # Examples: "GDAL 3.11.4, ..." or "3.11.4"
  match <- regexpr("[0-9]+\\.[0-9]+\\.[0-9]+(rc[0-9]+)?", version_str)
  if (match == -1) {
    return(NULL)
  }

  full_version <- regmatches(version_str, match)

  # Parse semantic version
  parts <- strsplit(full_version, "\\.")[[1]]

  result <- list(
    full = full_version,
    major = as.integer(parts[1]),
    minor = as.integer(parts[2]),
    patch = if (length(parts) > 2) {
      # Handle rc suffixes like "4rc1"
      patch_str <- parts[3]
      as.integer(sub("rc[0-9]+", "", patch_str))
    } else {
      0L
    }
  )

  # Capture RC info if present
  if (grepl("rc[0-9]+", full_version)) {
    rc_match <- regexpr("rc[0-9]+", full_version)
    result$rc <- regmatches(full_version, rc_match)
  }

  result
}

#' Get GDAL version at runtime
#'
#' Runs `gdal --version` and returns parsed version components.
#'
#' @return List with version components, or NULL if GDAL not available
#'
.get_gdal_version <- function() {
  gdal_check <- tryCatch(
    processx::run("gdal", "--version", error_on_status = TRUE),
    error = function(e) NULL
  )

  if (is.null(gdal_check)) {
    return(NULL)
  }

  version_str <- trimws(gdal_check$stdout)
  .parse_gdal_version(version_str)
}

#' Generate GitHub branch reference for GDAL version
#'
#' Maps version to appropriate GitHub branch/tag.
#' - For development: "master" or "main"
#' - For releases: version tags like "v3.11.4"
#'
#' @param version_parsed List from .parse_gdal_version()
#'
#' @return Character string with GitHub branch/tag name
#'
.get_github_ref <- function(version_parsed) {
  if (is.null(version_parsed)) {
    return("master")  # Default fallback
  }

  # For now, use version tags for releases
  # This can be enhanced to handle alpha/beta/rc builds
  sprintf("v%s", version_parsed$full)
}

#' Write GDAL version metadata to file
#'
#' Creates inst/GDAL_VERSION_INFO.json with generation metadata
#'
#' @param version_parsed List from .parse_gdal_version()
#' @param output_file Path to write metadata JSON
#'
#' @return Invisibly TRUE if successful
#'
.write_gdal_version_info <- function(version_parsed, output_file = "inst/GDAL_VERSION_INFO.json") {
  if (is.null(version_parsed)) {
    return(invisible(FALSE))
  }

  # Ensure output directory exists
  output_dir <- dirname(output_file)
  if (!dir.exists(output_dir)) {
    dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  }

  metadata <- list(
    generated_at = Sys.time(),
    gdal_version = version_parsed$full,
    gdal_version_parsed = version_parsed,
    generation_date = as.character(Sys.Date()),
    r_version = paste(R.version$major, R.version$minor, sep = "."),
    packages = list(
      processx = as.character(packageVersion("processx")),
      jsonlite = as.character(packageVersion("jsonlite")),
      rvest = as.character(packageVersion("rvest")),
      httr = as.character(packageVersion("httr"))
    )
  )

  # Write as JSON
  json_content <- jsonlite::toJSON(metadata, pretty = TRUE, auto_unbox = TRUE)
  writeLines(json_content, output_file)

  cat(sprintf("Wrote GDAL version metadata to %s\n", output_file))
  invisible(TRUE)
}

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

#' Construct the documentation URL for a GDAL command.
#'
#' Maps a command path (e.g., c("gdal", "raster", "info")) to the corresponding
#' GDAL documentation URL. Uses version-aware base URL if version provided.
#'
#' @param full_path Character vector representing the command hierarchy.
#' @param base_url Base URL for GDAL documentation. If NULL, uses stable docs.
#' @param gdal_version List from .parse_gdal_version() for version-aware URLs.
#'
#' @return Character string containing the full documentation URL.
#'
construct_doc_url <- function(full_path, base_url = NULL, gdal_version = NULL) {
  # Phase 2: Use version-aware base URL if version provided
  if (is.null(base_url)) {
    if (!is.null(gdal_version)) {
      # Use version tag for documentation
      version_str <- gdal_version$full
      base_url <- sprintf("https://gdal.org/en/%s/programs", version_str)
    } else {
      # Fallback to stable docs
      base_url <- "https://gdal.org/en/stable/programs"
    }
  }

  # Convert command path to documentation filename
  # e.g., c("gdal", "raster", "info") -> "gdal_raster_info"
  doc_name <- paste(full_path, collapse = "_")
  url <- sprintf("%s/%s.html", base_url, doc_name)
  url
}


#' Fetch GDAL examples from OSGeo/gdal GitHub RST source files
#'
#' Attempts to fetch examples directly from the RST (reStructuredText) source files
#' in the OSGeo/gdal repository. RST files have a deterministic structure with
#' .. example:: directives, making parsing more reliable than HTML.
#'
#' @param command_name Character string with the command name (e.g., "gdal_raster_info").
#' @param timeout Numeric timeout in seconds for HTTP request (default: 10).
#' @param verbose Logical whether to print debug messages.
#' @param gdal_version List from .parse_gdal_version() for version-aware GitHub refs.
#'
#' @return List with elements:
#'   - status: HTTP status code (200 for success, else error code)
#'   - examples: Character vector of extracted example commands
#'   - source: "rst" to indicate source type
#'
fetch_examples_from_rst <- function(command_name, timeout = 10, verbose = FALSE, gdal_version = NULL) {
  result <- list(
    status = NA_integer_,
    examples = character(0),
    source = "rst"
  )

  if (is.null(verbose)) verbose <- FALSE
  if (!is.logical(verbose)) verbose <- FALSE

  # Convert command name to RST filename
  # e.g., "gdal_raster_info" -> "gdal_raster_info.rst"
  rst_filename <- paste0(command_name, ".rst")

  # Build raw GitHub URL for RST file
  # Phase 2: Use version-aware GitHub reference
  github_ref <- if (!is.null(gdal_version)) {
    .get_github_ref(gdal_version)
  } else {
    "master"
  }

  rst_url <- sprintf(
    "https://raw.githubusercontent.com/OSGeo/gdal/%s/doc/source/programs/%s",
    github_ref,
    rst_filename
  )
  
  if (verbose) {
    cat(sprintf("  [DEBUG] Attempting to fetch RST examples from %s\n", rst_url))
  }
  
  # Attempt to fetch the RST file
  response <- tryCatch(
    {
      httr::GET(rst_url, httr::timeout(timeout))
    },
    error = function(e) {
      if (verbose) cat(sprintf("    [DEBUG] Error fetching RST: %s\n", e$message))
      return(NULL)
    }
  )
  
  if (is.null(response)) {
    result$status <- 0
    return(result)
  }
  
  status_code <- httr::status_code(response)
  result$status <- status_code
  
  if (status_code != 200) {
    if (verbose) {
      cat(sprintf("    [DEBUG] RST fetch returned status %d\n", status_code))
    }
    return(result)
  }
  
  # Extract content as text
  rst_content <- httr::content(response, as = "text", encoding = "UTF-8")
  
  # Parse RST file to extract examples section
  # RST format: 
  #   Examples
  #   --------
  #   
  #   .. example::
  #      :title: Some title
  #      
  #      $ gdal command here
  
  examples <- .extract_examples_from_rst(rst_content)
  
  if (length(examples) > 0) {
    result$examples <- examples
    if (verbose) {
      cat(sprintf("    [OK] Found %d examples in RST\n", length(examples)))
    }
  } else {
    if (verbose) {
      cat("    [DEBUG] No examples found in RST\n")
    }
  }
  
  return(result)
}


#' Extract example commands from RST content
#'
#' Helper function to parse RST content and extract code-block:: bash commands.
#'
#' @param rst_content Character string containing RST file content.
#'
#' @return Character vector of extracted example commands.
#'
.extract_examples_from_rst <- function(rst_content) {
  examples <- character(0)
  
  # Split content into lines for processing
  lines <- strsplit(rst_content, "\n", fixed = TRUE)[[1]]
  
  # Find "Examples" section (case-insensitive)
  examples_idx <- which(grepl("^Examples\\s*$", lines, ignore.case = TRUE))
  
  if (length(examples_idx) == 0) {
    return(examples)
  }
  
  # Start from the Examples heading
  start_idx <- examples_idx[1]
  
  # Find all code blocks starting from Examples section
  for (i in (start_idx + 1):length(lines)) {
    line <- lines[i]
    
    # Look for code-block directive: .. code-block:: bash
    if (grepl("^\\s*\\.\\.\\s+code-block::\\s+bash", line, ignore.case = TRUE)) {
      # Get the indentation of the code block
      block_indent <- nchar(line) - nchar(trimws(line))
      
      # Collect lines until we hit a non-indented line or end of content
      code_lines <- character(0)
      j <- i + 1
      
      while (j <= length(lines)) {
        code_line <- lines[j]
        
        # Skip empty lines at the start
        if (length(code_lines) == 0 && !nzchar(trimws(code_line))) {
          j <- j + 1
          next
        }
        
        # Check if this line is still part of the code block (more indented)
        line_indent <- nchar(code_line) - nchar(trimws(code_line))
        
        if (nzchar(trimws(code_line)) && line_indent <= block_indent) {
          # We've hit a non-code line, exit the block
          break
        }
        
        # Remove indentation and add to code lines
        if (nzchar(trimws(code_line))) {
          # Remove the common indentation
          trimmed_line <- sub(sprintf("^\\s{%d}", block_indent + 4), "", code_line)
          code_lines <- c(code_lines, trimmed_line)
        }
        
        j <- j + 1
      }
      
      # Join code lines and extract command (remove shell prompt if present)
      if (length(code_lines) > 0) {
        code_block <- paste(code_lines, collapse = " ")
        
        # Remove shell prompt ($) and leading/trailing whitespace
        code_block <- gsub("^\\s*\\$\\s*", "", code_block)
        code_block <- trimws(code_block)
        
        if (nzchar(code_block)) {
          examples <- c(examples, code_block)
        }
      }
      
      # Move to where the code block ended
      i <- j - 1
    }
  }
  
  return(examples)
}


#' Scrape GDAL documentation for a specific program.
#'
#' Attempts to fetch and parse the HTML documentation page for a GDAL program,
#' extracting description, parameter details, and examples.
#'
#' @param url Character string containing the documentation URL.
#' @param timeout Numeric timeout in seconds for HTTP request.
#' @param command_name Character string with the subcommand name (e.g., "create" for "gdal vsi sozip create").
#'   Used to find the correct section when multiple commands are on the same page.
#'
#' @return List containing:
#'   - status: HTTP status code or error message
#'   - description: Main narrative description (or NA)
#'   - param_details: Named list mapping parameter names to descriptions
#'   - examples: Character vector of code examples
#'   - raw_html: The parsed HTML (or NA if failed)
#'
scrape_gdal_docs <- function(url, timeout = 10, verbose = FALSE, command_name = NULL) {
  # Ensure verbose is a logical
  if (is.null(verbose)) verbose <- FALSE
  if (!is.logical(verbose)) verbose <- FALSE
  
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
      cat(sprintf("  [WARN] Error fetching %s: %s\n", url, e$message))
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
      cat(sprintf("  [WARN] Error parsing HTML from %s\n", url))
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

  # Extract code examples from <pre> tags or <div> blocks within Examples section
  # Filter to only include executable CLI commands (starting with 'gdal' or '$')
  examples <- tryCatch(
    {
      # Get all headings (h1-h6)
      all_headings <- page %>% rvest::html_elements("h1, h2, h3, h4, h5, h6")
      heading_texts <- all_headings %>% rvest::html_text()
      heading_names <- all_headings %>% lapply(function(x) xml2::xml_name(x)) %>% unlist()
      heading_texts_clean <- iconv(trimws(heading_texts), "UTF-8", "ASCII", sub="")

      example_texts <- character(0)

      # If command_name is provided, look for a section header matching the subcommand
      # (e.g., "gdal vsi sozip create" for the create subcommand)
      target_section_idx <- NA_integer_

      if (!is.null(command_name) && nzchar(command_name)) {
        # Look for a heading that contains the command_name
        # Convert to lowercase for matching
        cmd_lower <- tolower(command_name)
        for (i in seq_along(heading_texts)) {
          if (grepl(cmd_lower, tolower(heading_texts[i]))) {
            target_section_idx <- i
            break
          }
        }
      }

      # If we found a target section header, look for Examples after it
      if (!is.na(target_section_idx)) {
        # Find the next "Examples" heading after the target section
        remaining_headings <- heading_texts_clean[(target_section_idx + 1):length(heading_texts_clean)]
        examples_idx_relative <- grep("^\\s*Examples?\\s*$", remaining_headings, ignore.case = TRUE)[1]

        if (!is.na(examples_idx_relative)) {
          examples_idx <- target_section_idx + examples_idx_relative
          examples_heading <- all_headings[examples_idx]

          # Look for examples in following siblings or in a section element
          # Get all div and pre elements that follow
          following_divs <- xml2::xml_find_all(examples_heading, "following-sibling::div | following-sibling::pre")
          
          # Also check inside a following section element
          following_section <- xml2::xml_find_first(examples_heading, "following-sibling::section[1]")
          if (!is.na(following_section)) {
            section_divs <- xml2::xml_find_all(following_section, ".//div")
            following_divs <- c(following_divs, section_divs)
          }

          for (elem in following_divs[1:min(5, length(following_divs))]) {
            elem_text <- trimws(xml2::xml_text(elem))
            if (!is.na(elem_text) && nzchar(elem_text)) {
              # Check if this looks like a command (starts with gdal or $)
              lines <- strsplit(elem_text, "\n")[[1]]
              command_lines <- character(0)

              for (line in lines) {
                line <- trimws(line)
                if (grepl("^\\$\\s*gdal", line) || grepl("^gdal\\s", line) || grepl("^gdal$", line)) {
                  line <- sub("^\\$\\s*", "", line)
                  command_lines <- c(command_lines, line)
                }
              }

              if (length(command_lines) > 0) {
                example_texts <- c(example_texts, paste(command_lines, collapse = "\n"))
              }
            }
          }
        }
      }

      # Fallback: if no subcommand matching or no examples found, look for generic Examples h2
      if (length(example_texts) == 0) {
        # Look for standalone "Examples" h2 heading
        h2_elements <- page %>% rvest::html_elements("h2")
        h2_texts <- h2_elements %>% rvest::html_text()
        h2_texts_clean <- iconv(trimws(h2_texts), "UTF-8", "ASCII", sub="")
        example_h2_idx <- grep("^\\s*Examples?\\s*$", h2_texts_clean, ignore.case = TRUE)[1]

        if (!is.na(example_h2_idx)) {
          examples_heading <- h2_elements[example_h2_idx]
          
          # The examples may be in several following section elements
          # Get all following section siblings
          following_sections <- xml2::xml_find_all(examples_heading, "following-sibling::section")
          
          if (length(following_sections) > 0) {
            # Iterate through up to 5 example sections
            for (section_idx in seq_len(min(5, length(following_sections)))) {
              section_elem <- following_sections[section_idx]
              
              # Look for pre tags within this section (they may be nested in div.highlight)
              pres <- xml2::xml_find_all(section_elem, ".//pre")
              
              if (length(pres) > 0) {
                for (pre in pres) {
                  pre_text <- rvest::html_text(pre)
                  if (!is.na(pre_text) && nzchar(pre_text)) {
                    # The text from pre may have extra whitespace/newlines due to HTML formatting
                    # Clean it up to get actual command lines
                    lines <- strsplit(pre_text, "\n")[[1]]
                    command_lines <- character(0)
                    
                    for (line in lines) {
                      line <- trimws(line)
                      # Skip empty lines and lines that look like HTML artifacts
                      if (!nzchar(line)) next
                      
                      # Check if this looks like a command (starts with gdal or $)
                      if (grepl("^\\$\\s*gdal", line) || grepl("^gdal\\s", line) || grepl("^gdal$", line)) {
                        line <- sub("^\\$\\s*", "", line)
                        command_lines <- c(command_lines, line)
                      }
                    }
                    
                    if (length(command_lines) > 0) {
                      example_texts <- c(example_texts, paste(command_lines, collapse = "\n"))
                    }
                  }
                }
              }
            }
          }
        }
      }

      example_texts
    },
    error = function(e) {
      # Note: verbose is captured from outer scope
      if (!is.na(verbose) && verbose) {
        cat(sprintf("    [WARN] Error extracting examples: %s\n", e$message))
      }
      character(0)
    }
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
    # Check for @filename patterns (file lists in GDAL)
    # Type 1: @filename with extension (@input_files.txt)
    if (grepl("^@[a-zA-Z0-9._/-]+\\.[a-zA-Z0-9]+$", token)) return(TRUE)
    # Type 2: @filename without extension (@list)
    if (grepl("^@[a-zA-Z0-9._-]+$", token)) return(TRUE)
    # Type 3: In composite argument after pipe (@query.sql in "text"|@query.sql)
    if (grepl("\\|@[a-zA-Z0-9._/-]+", token)) return(TRUE)
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
  # Use a list to store options to handle repeatable flags (like -co appearing multiple times)
  options_list <- list()  # List of list(flag_name, value) pairs
  
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
        # Store as list entry to preserve repeats
        options_list[[length(options_list) + 1]] <- list(name = flag_name, value = value)
        i <- i + 1
      } else {
        # Remove leading dashes
        flag_name <- sub("^--?", "", token)

        # Determine if this flag takes a value based on patterns
        # Single-letter flags that take values: -i, -o, -b, -co, -of, -ot, -e, -f, -t, -a
        # Long flags with obvious value patterns: --calc, --dataset, --sql, etc.
        flag_takes_value <- FALSE
        
        # Single-letter flags that commonly take values
        if (nchar(flag_name) == 1 && flag_name %in% c("i", "o", "b", "co", "of", "ot", "e", "f", "t", "a", "s")) {
          flag_takes_value <- TRUE
        }
        # Long flags that typically take values (heuristic)
        else if (nchar(flag_name) > 1 && !grepl("^no-|^disable|^skip", flag_name)) {
          # It's a long flag that probably takes a value if it's not a negative/disable flag
          flag_takes_value <- TRUE
        }

        # Check if next token could be a value
        if (flag_takes_value && i < length(tokens) && !grepl("^-", tokens[i + 1])) {
          # This flag likely has a value
          next_token <- tokens[i + 1]
          # Store as list entry to preserve repeats
          options_list[[length(options_list) + 1]] <- list(name = flag_name, value = next_token)
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

  # Convert options_list to named vector format for backward compatibility
  # options_list contains all option entries including repeats; we preserve them in result$options
  if (length(options_list) > 0) {
    option_values <- sapply(options_list, function(x) x$value)
    option_names <- sapply(options_list, function(x) x$name)
    result$options <- option_values
    names(result$options) <- option_names
    # Also store the original list to track repeats
    result$options_list <- options_list
  }

  result
}


#' Convert a parsed CLI command to an R function call.
#'
#' Takes parsed CLI components and converts them into valid R code that creates
#' a gdal_job object (without calling gdal_job_run).
#'
#' @param parsed_cli List from parse_cli_command().
#' @param r_function_name Character string of the R function name.
#' @param input_args List of input arguments metadata from GDAL JSON (optional).
#'
#' @return Character string containing R code to create gdal_job.
#'
convert_cli_to_r_example <- function(parsed_cli, r_function_name, input_args = NULL, arg_mapping = NULL) {
  if (is.null(parsed_cli) || length(parsed_cli) == 0) {
    # Fallback: simple function call with no args
    return(sprintf("job <- %s()", r_function_name))
  }

  # Build argument assignments
  args <- character()

  # Get parameter metadata from input_args and arg_mapping
  # arg_mapping has priority since it contains already-normalized R names
  param_metadata <- list()
  positional_param_names <- character(0)
  
  # If we have arg_mapping, use it (this is the authoritative source for R parameter names)
  if (!is.null(arg_mapping) && length(arg_mapping) > 0) {
    # arg_mapping is a list: R_name -> {gdal_name, type, min_count, max_count, default, is_positional}
    for (r_name in names(arg_mapping)) {
      mapping_entry <- arg_mapping[[r_name]]
      max_count <- if (!is.null(mapping_entry$max_count)) mapping_entry$max_count else 1
      is_pos <- if (!is.null(mapping_entry$is_positional) && !is.na(mapping_entry$is_positional)) mapping_entry$is_positional else FALSE
      
      param_metadata[[r_name]] <- list(gdal_name = r_name, max_count = max_count, is_positional = is_pos)
      
      # Only track positional parameters for building positional_param_names
      if (isTRUE(is_pos)) {
        positional_param_names <- c(positional_param_names, r_name)
      }
    }
  } else if (!is.null(input_args) && length(input_args) > 0) {
    # Fallback to building from input_args if no arg_mapping
    # Convert to list if it's a dataframe
    if (is.data.frame(input_args)) {
      args_list <- lapply(1:nrow(input_args), function(i) as.list(input_args[i, ]))
    } else {
      args_list <- input_args
    }
    
    # Build metadata for each parameter
    for (arg in args_list) {
      if (!is.null(arg$name)) {
        gdal_name <- as.character(arg$name)
        gdal_short <- sub("^-+", "", gdal_name)
        
        # Try to infer R name from GDAL name
        # Common mappings: -i/-input -> input, -o/-output -> output, -d/-dataset -> dataset
        r_name <- gdal_short
        if (grepl("^i$|input", gdal_short, ignore.case = TRUE)) {
          r_name <- "input"
        } else if (grepl("^o$|output", gdal_short, ignore.case = TRUE)) {
          r_name <- "output"
        } else if (grepl("^d$|dataset", gdal_short, ignore.case = TRUE)) {
          r_name <- "dataset"
        } else if (grepl("^s$|src", gdal_short, ignore.case = TRUE)) {
          r_name <- "src_dataset"
        } else if (grepl("dest", gdal_short, ignore.case = TRUE)) {
          r_name <- "dest_dataset"
        } else {
          # Just normalize to underscores
          r_name <- gsub("-", "_", gdal_short)
        }
        
        max_count <- if (!is.null(arg$max_count)) arg$max_count else 1
        param_metadata[[r_name]] <- list(gdal_name = gdal_name, max_count = max_count)
        positional_param_names <- c(positional_param_names, r_name)
      }
    }
  }
  
  # Common fallback names if we don't have metadata
  if (length(positional_param_names) == 0) {
    positional_param_names <- c("dataset", "input", "output", "src_dataset", "dest_dataset")
  }

  # Handle positional arguments: check for multi-valued parameters
  if (length(parsed_cli$positional_args) > 0) {
    # If we have more than 2 positional args, check if first parameter is multi-valued
    if (length(parsed_cli$positional_args) > 2 && length(positional_param_names) > 0) {
      first_param <- positional_param_names[1]
      first_param_max_count <- param_metadata[[first_param]]$max_count
      
      # If first parameter accepts multiple values, combine all but last arg into a vector
      if (!is.null(first_param_max_count) && first_param_max_count > 1) {
        # All args except the last go to the first parameter as a vector
        input_files <- parsed_cli$positional_args[-length(parsed_cli$positional_args)]
        output_file <- parsed_cli$positional_args[length(parsed_cli$positional_args)]
        
        # Remove quotes and format as R vector
        input_files <- gsub("^\"|\"$", "", input_files)
        output_file <- gsub("^\"|\"$", "", output_file)
        
        # Create vector syntax
        if (length(input_files) == 1) {
          input_vector_str <- sprintf('"%s"', input_files)
        } else {
          input_vector_str <- sprintf('c(%s)', paste(sprintf('"%s"', input_files), collapse = ", "))
        }
        
        args <- c(args, sprintf('%s = %s', first_param, input_vector_str))
        
        # Add output as the last positional parameter
        if (length(positional_param_names) > 1) {
          output_param <- positional_param_names[2]
          args <- c(args, sprintf('%s = "%s"', output_param, output_file))
        } else {
          # Fallback to "output" if we don't have a second param name
          args <- c(args, sprintf('output = "%s"', output_file))
        }
      } else {
        # First parameter doesn't accept multiple values - skip this example
        return(NULL)
      }
    } else {
      # 1-2 positional args: map sequentially to parameter names
      for (j in seq_along(parsed_cli$positional_args)) {
        if (j <= length(positional_param_names)) {
          arg_name <- positional_param_names[j]
        } else {
          arg_name <- paste0("arg", j)
        }
        # Remove existing quotes if present to avoid double-quoting
        val <- parsed_cli$positional_args[j]
        val <- gsub("^\"|\"$", "", val)  # Remove leading/trailing quotes
        
        # Check if this is a composite argument
        param_meta <- if (!is.null(arg_mapping[[arg_name]])) arg_mapping[[arg_name]] else NULL
        max_count <- if (!is.null(param_meta)) param_meta$max_count else 1
        min_count <- if (!is.null(param_meta)) param_meta$min_count else 0
        
        # Detect composite: fixed-count with commas
        is_composite <- (max_count == min_count && max_count > 1 && grepl(",", val))
        
        if (is_composite) {
          # Parse composite argument
          parts <- strsplit(val, ",\\s*")[[1]]
          
          # Determine if numeric (common for bbox, resolution, etc.)
          is_numeric_arg <- grepl("bbox|resolution|size|extent|bounds|pixel|offset", arg_name, ignore.case = TRUE)
          
          if (is_numeric_arg) {
            # Try to convert to numeric
            numeric_parts <- suppressWarnings(as.numeric(parts))
            if (!any(is.na(numeric_parts))) {
              # All numeric
              arg_value <- sprintf('c(%s)', paste(numeric_parts, collapse = ", "))
            } else {
              # Not all numeric - keep as strings
              parts_quoted <- sprintf('"%s"', parts)
              arg_value <- sprintf('c(%s)', paste(parts_quoted, collapse = ", "))
            }
          } else {
            # Keep as strings
            parts_quoted <- sprintf('"%s"', parts)
            arg_value <- sprintf('c(%s)', paste(parts_quoted, collapse = ", "))
          }
          args <- c(args, sprintf('%s = %s', arg_name, arg_value))
        } else {
          # Single value - determine quoting based on type
          is_numeric_val <- grepl("^-?\\d+(\\.\\d+)?$", val)
          
          if (is_numeric_val && !grepl("^0\\d", val)) {
            # Numeric - don't quote
            args <- c(args, sprintf('%s = %s', arg_name, val))
          } else {
            # String - quote
            args <- c(args, sprintf('%s = "%s"', arg_name, val))
          }
        }
      }
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
  # Handle repeatable options specially by grouping them into vectors
  if (length(parsed_cli$options) > 0) {
    # Get valid parameter names from input_args metadata if available
    # Build mapping from GDAL flag names to R parameter names
    gdal_to_r_mapping <- character(0)
    valid_params <- character(0)
    
    if (!is.null(input_args) && length(input_args) > 0) {
      # Convert input_args to list if it's a dataframe
      if (is.data.frame(input_args)) {
        args_list <- lapply(1:nrow(input_args), function(i) as.list(input_args[i, ]))
      } else {
        args_list <- input_args
      }
      
      # Build mapping from GDAL name -> R name
      for (arg in args_list) {
        if (!is.null(arg$name)) {
          gdal_name <- as.character(arg$name)
          # Remove leading dashes and normalize
          gdal_short <- sub("^-+", "", gdal_name)
          # Convert to R name (replace hyphens with underscores)
          r_name <- gsub("-", "_", gdal_short)
          gdal_to_r_mapping[gdal_short] <- r_name
          valid_params <- c(valid_params, r_name)
        }
      }
    }

    # If we have the options_list (preserving repeats), use that for grouping
    if (!is.null(parsed_cli$options_list) && length(parsed_cli$options_list) > 0) {
      # Group options by flag name
      option_groups <- list()
      for (opt_entry in parsed_cli$options_list) {
        opt_name_cli <- opt_entry$name
        opt_value <- opt_entry$value
        
        # Map to R parameter name
        opt_name_r <- if (opt_name_cli %in% names(gdal_to_r_mapping)) {
          gdal_to_r_mapping[[opt_name_cli]]
        } else {
          gsub("-", "_", opt_name_cli)
        }
        
        # Only include if valid parameter or no metadata
        if (length(valid_params) == 0 || opt_name_r %in% valid_params) {
          # Group by parameter name
          if (!(opt_name_r %in% names(option_groups))) {
            option_groups[[opt_name_r]] <- list()
          }
          
          # Remove existing quotes
          opt_value <- gsub("^\"|\"$", "", opt_value)
          option_groups[[opt_name_r]] <- c(option_groups[[opt_name_r]], opt_value)
        }
      }
      
      # Convert groups to arguments, handling both repeatable and composite arguments
      for (opt_name_r in names(option_groups)) {
        values <- option_groups[[opt_name_r]]
        
        # Check if this is a composite argument (fixed-count comma-separated values)
        # by looking at arg_mapping
        param_meta <- if (!is.null(arg_mapping[[opt_name_r]])) arg_mapping[[opt_name_r]] else NULL
        max_count <- if (!is.null(param_meta)) param_meta$max_count else 1
        min_count <- if (!is.null(param_meta)) param_meta$min_count else 0
        
        # Detect composite argument: single value with commas and fixed max_count > 1
        is_composite <- (length(values) == 1 && max_count == min_count && max_count > 1 && grepl(",", values[[1]]))
        
        if (is_composite) {
          # Parse composite argument: "x1,x2,x3,x4" -> c(x1, x2, x3, x4)
          # Determine if numeric or character based on parameter name patterns
          parts <- strsplit(values[[1]], ",\\s*")[[1]]
          
          # Try to detect if numeric (common for bbox, resolution, etc.)
          is_numeric_arg <- grepl("bbox|resolution|size|extent|bounds|pixel|offset", opt_name_r, ignore.case = TRUE)
          
          if (is_numeric_arg) {
            # Try to convert to numeric
            numeric_parts <- suppressWarnings(as.numeric(parts))
            if (!any(is.na(numeric_parts))) {
              # All numeric - create numeric vector
              arg_value <- sprintf('c(%s)', paste(numeric_parts, collapse = ", "))
            } else {
              # Not all numeric - keep as strings
              parts_quoted <- sprintf('"%s"', parts)
              arg_value <- sprintf('c(%s)', paste(parts_quoted, collapse = ", "))
            }
          } else {
            # Keep as character strings
            parts_quoted <- sprintf('"%s"', parts)
            arg_value <- sprintf('c(%s)', paste(parts_quoted, collapse = ", "))
          }
          args <- c(args, sprintf('%s = %s', opt_name_r, arg_value))
        }
        # Check for repeatable options (multiple values for same parameter)
        else if (length(values) > 1) {
          # Multiple values - create c() vector (repeatable option)
          values_quoted <- sprintf('"%s"', values)
          arg_value <- sprintf('c(%s)', paste(values_quoted, collapse = ", "))
          args <- c(args, sprintf('%s = %s', opt_name_r, arg_value))
        } 
        # Single value - quote if string, otherwise as-is
        else if (length(values) == 1) {
          # Check if value looks numeric
          val <- values[[1]]
          is_numeric_val <- grepl("^-?\\d+(\\.\\d+)?$", val)
          
          if (is_numeric_val && !grepl("^0\\d", val)) {
            # Numeric value - don't quote
            args <- c(args, sprintf('%s = %s', opt_name_r, val))
          } else {
            # String value - quote
            args <- c(args, sprintf('%s = "%s"', opt_name_r, val))
          }
        }
      }
    } else {
      # Fallback to old behavior if options_list not available
      option_names <- names(parsed_cli$options)
      for (i in seq_along(parsed_cli$options)) {
        opt_name_cli <- option_names[i]
        opt_value <- parsed_cli$options[i]

        opt_name_r <- if (opt_name_cli %in% names(gdal_to_r_mapping)) {
          gdal_to_r_mapping[[opt_name_cli]]
        } else {
          gsub("-", "_", opt_name_cli)
        }

        opt_value <- gsub("^\"|\"$", "", opt_value)

        if (length(valid_params) == 0 || opt_name_r %in% valid_params) {
          args <- c(args, sprintf('%s = "%s"', opt_name_r, opt_value))
        }
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
#' @return List with methods: get(url), set(url, data), get_csv(), save_csv()
#'
create_doc_cache <- function(cache_dir = ".gdal_doc_cache") {
  if (!dir.exists(cache_dir)) {
    dir.create(cache_dir, showWarnings = FALSE)
  }

  csv_file <- file.path(cache_dir, "descriptions.csv")

  # Load descriptions from CSV if it exists
  load_descriptions <- function() {
    if (file.exists(csv_file)) {
      tryCatch(
        {
          read.csv(csv_file, stringsAsFactors = FALSE)
        },
        error = function(e) {
          data.frame(command_path = character(), description = character())
        }
      )
    } else {
      data.frame(command_path = character(), description = character())
    }
  }

  # Save descriptions to CSV
  save_descriptions <- function(descriptions) {
    tryCatch(
      {
        write.csv(descriptions, csv_file, row.names = FALSE, quote = TRUE)
      },
      error = function(e) {
        warning(sprintf("Failed to save descriptions to %s", csv_file))
      }
    )
  }

  descriptions_df <- load_descriptions()

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
    },

    get_description = function(command_path) {
      # command_path is a character vector like c("gdal", "raster", "calc")
      # Convert to string for lookup
      path_str <- paste(command_path, collapse = "_")
      # Reload descriptions from disk in case they were saved during this run
      current_df <- load_descriptions()
      rows <- which(current_df$command_path == path_str)
      if (length(rows) > 0) {
        return(current_df$description[rows[1]])
      }
      NA_character_
    },

    save_description = function(command_path, description) {
      path_str <- paste(command_path, collapse = "_")
      # Check if already exists
      rows <- which(descriptions_df$command_path == path_str)
      if (length(rows) > 0) {
        # Update
        descriptions_df$description[rows[1]] <<- description
      } else {
        # Add new row
        descriptions_df <<- rbind(descriptions_df, data.frame(
          command_path = path_str,
          description = description,
          stringsAsFactors = FALSE
        ))
      }
      save_descriptions(descriptions_df)
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
fetch_enriched_docs <- function(full_path, cache = NULL, verbose = FALSE, url = NULL, command_name = NULL, gdal_version = NULL) {
  # Ensure verbose is a logical
  if (is.null(verbose)) verbose <- FALSE
  if (!is.logical(verbose)) verbose <- FALSE

  # Phase 2: Construct version-aware base path for URL normalization
  version_path <- if (!is.null(gdal_version)) {
    gdal_version$full
  } else {
    "stable"
  }

  # Use provided URL from GDAL JSON, or construct one if not provided
  if (is.null(url) || !nzchar(url)) {
    url <- construct_doc_url(full_path, gdal_version = gdal_version)
  }

  # Normalize URL: ensure it includes /en/{version}/ path if not present
  # GDAL JSON URLs may be like https://gdal.org/programs/... or https://gdal.org/en/stable/programs/...
  version_pattern <- sprintf("/en/[0-9.]+|/en/stable", version_path)
  if (!grepl(version_pattern, url)) {
    url <- gsub("https://gdal.org/", sprintf("https://gdal.org/en/%s/", version_path), url)
  }

  # For driver commands that may have driver-specific URLs, try /programs/ variant first
  # This handles cases like gdal_driver_gpkg_repack which should use /programs/gdal_driver_gpkg_repack.html
  # instead of /drivers/vector/gpkg.html
  primary_url <- url
  alternate_url <- NULL

  if (length(full_path) > 2 && full_path[2] == "driver") {
    # This is a driver command - construct the /programs/ variant
    programs_url <- construct_doc_url(full_path, gdal_version = gdal_version)
    if (!grepl(version_pattern, programs_url)) {
      programs_url <- gsub("https://gdal.org/", sprintf("https://gdal.org/en/%s/", version_path), programs_url)
    }

    # If the provided URL is a /drivers/ URL, we should try /programs/ first
    if (grepl("/drivers/", url)) {
      # Swap them - try /programs/ first as it's more likely to exist
      alternate_url <- url
      primary_url <- programs_url
    }
  }

  # Check cache first (if available) - only for primary URL
  if (!is.null(cache)) {
    cached <- cache$get(primary_url)
    if (!is.null(cached)) {
      if (verbose) cat(sprintf("  [OK] Cached RDS: %s\n", primary_url))
      return(cached)
    }
  }

  # Initialize result structure
  result <- list(
    status = NA_integer_,
    description = NA_character_,
    param_details = list(),
    examples = character(0),
    raw_html = NA
  )

  # STRATEGY: Try RST extraction first (more reliable)
  # Then fall back to HTML scraping if RST doesn't have examples
  # Build command name for RST lookup (e.g., c("gdal", "raster", "info") -> "gdal_raster_info")
  command_name_for_rst <- paste(full_path, collapse = "_")

  if (verbose) {
    cat(sprintf("  ⟳ Fetching RST examples: %s\n", command_name_for_rst))
  }

  # Attempt to fetch examples from RST first
  rst_result <- fetch_examples_from_rst(command_name_for_rst, verbose = verbose, gdal_version = gdal_version)
  
  if (rst_result$status == 200 && length(rst_result$examples) > 0) {
    if (verbose) {
      cat(sprintf("  [OK] Got %d examples from RST\n", length(rst_result$examples)))
    }
    # Use RST examples
    result$examples <- rst_result$examples
    result$status <- 200
    result$source_examples <- "rst"
    
    # Cache the result
    if (!is.null(cache)) {
      cache$set(primary_url, result)
    }
    return(result)
  }

  # RST didn't have examples, try HTML scraping
  if (verbose) {
    cat(sprintf("  ⟳ Fetching HTML: %s\n", primary_url))
  }
  
  docs <- scrape_gdal_docs(primary_url, verbose = verbose, command_name = command_name)

  # If primary URL failed with 404 and we have an alternate, try that
  if (docs$status == 404 && !is.null(alternate_url)) {
    if (verbose) cat(sprintf("  [404] Trying alternate: %s\n", alternate_url))
    docs <- scrape_gdal_docs(alternate_url, verbose = verbose, command_name = command_name)
  }

  # Handle 404: try fallback URLs with parent commands
  if (docs$status == 404 && length(full_path) > 2) {
    # Try using parent command URL (e.g., for gdal_vector_geom_buffer, try gdal_vector page)
    # This handles cases where subcommands don't have individual doc pages
    parent_path <- full_path[1:(length(full_path)-1)]
    parent_url <- construct_doc_url(parent_path, gdal_version = gdal_version)

    # Normalize parent URL (Phase 2: Use version-aware pattern)
    if (!grepl(version_pattern, parent_url)) {
      parent_url <- gsub("https://gdal.org/", sprintf("https://gdal.org/en/%s/", version_path), parent_url)
    }

    if (verbose) cat(sprintf("  [404] Trying parent: %s\n", parent_url))
    docs <- scrape_gdal_docs(parent_url, verbose = verbose, command_name = command_name)

    # If parent also fails, try the grandparent (for deeply nested commands)
    if (docs$status == 404 && length(full_path) > 3) {
      grandparent_path <- full_path[1:(length(full_path)-2)]
      grandparent_url <- construct_doc_url(grandparent_path, gdal_version = gdal_version)

      # Normalize grandparent URL (Phase 2: Use version-aware pattern)
      if (!grepl(version_pattern, grandparent_url)) {
        grandparent_url <- gsub("https://gdal.org/", sprintf("https://gdal.org/en/%s/", version_path), grandparent_url)
      }

      if (verbose) cat(sprintf("  [404] Trying grandparent: %s\n", grandparent_url))
      docs <- scrape_gdal_docs(grandparent_url, verbose = verbose, command_name = command_name)
    }
  }

  # Cache the result using primary URL
  if (!is.null(cache) && docs$status == 200) {
    cache$set(primary_url, docs)
    # Also save description to CSV for persistence
    if (!is.na(docs$description) && nzchar(docs$description)) {
      cache$save_description(full_path, docs$description)
    }
  } else if (!is.null(cache) && (!is.na(docs$description) && nzchar(docs$description))) {
    # Even if fetch failed, save the description we got
    cache$save_description(full_path, docs$description)
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
      name = ifelse(is.null(api_spec$name), "", api_spec$name),
      description = ifelse(is.null(api_spec$description), "", api_spec$description),
      url = ifelse(is.null(api_spec$url), "", api_spec$url),
      input_arguments = if (is.null(api_spec$input_arguments)) list() else api_spec$input_arguments,
      input_output_arguments = if (is.null(api_spec$input_output_arguments)) list() else api_spec$input_output_arguments
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
#' @param gdal_version List from .parse_gdal_version() for version-aware documentation.
#'
#' @return A string containing the complete R function code (including roxygen).
#'
generate_function <- function(endpoint, cache = NULL, verbose = FALSE, gdal_version = NULL) {
  # Ensure verbose is a logical
  if (is.null(verbose)) verbose <- FALSE
  if (!is.logical(verbose)) verbose <- FALSE

  full_path <- endpoint$full_path
  command_name <- if (is.null(endpoint$name)) tail(full_path, 1) else endpoint$name
  description <- if (is.null(endpoint$description)) "GDAL command." else endpoint$description
  input_args <- if (is.null(endpoint$input_arguments)) list() else endpoint$input_arguments
  input_output_args <- if (is.null(endpoint$input_output_arguments)) list() else endpoint$input_output_arguments

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
    # For regular functions, the first positional argument accepts either:
    # - A gdal_job object (piped from previous operation)
    # - The actual data (e.g., input filename, dataset)
    # Detection happens in the function body via inherits(first_arg, "gdal_job")
    args_signature <- paste(r_args$signature, collapse = ",\n  ")
  }

  # Attempt to fetch enriched documentation
  enriched_docs <- NULL
  family <- generate_family_tag(full_path)

  if (!is.null(cache)) {
    # Extract the url from the endpoint JSON if available
    endpoint_url <- if (is.null(endpoint$url)) NULL else endpoint$url
    enriched_docs <- fetch_enriched_docs(full_path, cache = cache, verbose = verbose, url = endpoint_url, command_name = command_name, gdal_version = gdal_version)
  }

  # Generate roxygen documentation with enrichment
  roxygen_doc <- tryCatch({
    generate_roxygen_doc(func_name, description, r_args$arg_names, enriched_docs, family, input_args, input_output_args, full_path, is_base_gdal, r_args$arg_mapping, cache, command_name, verbose = verbose)
  }, error = function(e) {
    cat(sprintf("\n[ERROR] roxygen_doc generation failed for %s:\n", func_name))
    cat(sprintf("  Message: %s\n", conditionMessage(e)))
    cat(sprintf("  Call: %s\n", paste(deparse(e$call), collapse = "\n")))
    stop(e)
  })

  # Generate function body
  func_body <- generate_function_body(full_path, input_args, input_output_args, r_args$arg_names, r_args$arg_mapping, is_pipeline, is_base_gdal)

  # Header comment indicating this file is auto-generated
  header <- "# ===================================================================\n# This file is AUTO-GENERATED by build/generate_gdal_api.R\n# Do not edit directly. Changes will be overwritten on regeneration.\n# ===================================================================\n"

  # Combine into complete function
  # Use paste0 instead of sprintf to avoid interpreting % in roxygen_doc as format specifiers
  function_code <- paste0(
    header, "\n",
    roxygen_doc,
    "#' @export\n",
    func_name, " <- function(", args_signature, ") {\n",
    func_body,
    "\n}\n"
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

  # First, convert both to lists if they're dataframes
  if (is.data.frame(input_output_args)) {
    io_list <- lapply(1:nrow(input_output_args), function(i) as.list(input_output_args[i, ]))
  } else if (length(input_output_args) > 0) {
    io_list <- input_output_args
  } else {
    io_list <- list()
  }
  
  if (is.data.frame(input_args)) {
    in_list <- lapply(1:nrow(input_args), function(i) as.list(input_args[i, ]))
  } else if (length(input_args) > 0) {
    in_list <- input_args
  } else {
    in_list <- list()
  }

  # Extract input-like parameters from input_args and move them to the front
  # GDAL's spec mixes input parameters with option parameters in input_arguments
  # We need to reorder: inputs first, then outputs, then other options
  
  input_params <- list()     # input, inputs, source, etc.
  output_params <- list()    # output, destination, target, etc.
  option_params <- list()    # everything else
  
  # Classify all parameters from both lists
  # Parameters from input_output_arguments are ALWAYS positional by definition
  for (i in seq_along(io_list)) {
    param <- io_list[[i]]
    param_name <- if (is.null(param$name)) "" else as.character(param$name)
    
    # Parameters from input_output_arguments are positional
    # Mark them with a special flag
    param$.from_io_args <- TRUE
    param$.is_positional <- TRUE
    
    # Classify based on name
    # Match exactly: "input", "inputs", "source", "dataset" (no suffixes like "_format")
    is_input <- grepl("^(input|inputs|source|dataset)$", param_name, ignore.case = TRUE) && !grepl("output", param_name, ignore.case = TRUE)
    is_output <- grepl("^(output|destination|target)$", param_name, ignore.case = TRUE) && !grepl("input", param_name, ignore.case = TRUE)
    
    if (is_input) {
      input_params[[length(input_params) + 1]] <- param
    } else if (is_output) {
      output_params[[length(output_params) + 1]] <- param
    } else {
      option_params[[length(option_params) + 1]] <- param
    }
  }
  
  # Process parameters from input_arguments
  for (i in seq_along(in_list)) {
    param <- in_list[[i]]
    param_name <- if (is.null(param$name)) "" else as.character(param$name)
    
    # Parameters from input_arguments are NOT positional by default,
    # but those matching input/output patterns will be reclassified and marked positional
    param$.from_io_args <- FALSE
    
    # Classify based on name
    # Match exactly: "input", "inputs", "source", "dataset" (no suffixes like "_format")
    is_input <- grepl("^(input|inputs|source|dataset)$", param_name, ignore.case = TRUE) && !grepl("output", param_name, ignore.case = TRUE)
    is_output <- grepl("^(output|destination|target)$", param_name, ignore.case = TRUE) && !grepl("input", param_name, ignore.case = TRUE)
    
    if (is_input) {
      # Parameters classified as "input" are positional (will come first in sig)
      param$.is_positional <- TRUE
      input_params[[length(input_params) + 1]] <- param
    } else if (is_output) {
      # Parameters classified as "output" are positional
      param$.is_positional <- TRUE
      output_params[[length(output_params) + 1]] <- param
    } else {
      # Parameters that don't match input/output patterns are optional flags
      param$.is_positional <- FALSE
      option_params[[length(option_params) + 1]] <- param
    }
  }
  
  # Combine in correct order: inputs first, then outputs, then options
  args_list <- c(input_params, output_params, option_params)
  
  if (is.null(args_list) || length(args_list) == 0) {
    return(list(signature = signature, arg_names = arg_names, arg_mapping = arg_mapping))
  }

  # Check for mixed required/optional to ensure R signature validity
  # First pass: mark which are required
  required_status <- sapply(seq_along(args_list), function(i) {
    arg <- args_list[[i]]
    is_req <- ifelse(is.null(arg$required), FALSE, arg$required)
    if (is.na(is_req)) FALSE else is_req
  })
  
  # Strategy: We want inputs before outputs ALWAYS, even if output is required
  # Because the semantic meaning (input→process→output) is more important than
  # the technical requirement of having required params first in R signatures.
  # We'll handle this by making optional inputs still come before required outputs.
  
  # Find the positions of input/output params in args_list
  arg_names_list <- sapply(args_list, function(p) 
    if(is.null(p$name)) "" else as.character(p$name))
  
  input_indices <- which(grepl("^(input|inputs|source|dataset)($|[_-])", arg_names_list, ignore.case = TRUE) & !grepl("output", arg_names_list, ignore.case = TRUE))
  output_indices <- which(grepl("^(output|destination|target)($|[_-])", arg_names_list, ignore.case = TRUE) & !grepl("input", arg_names_list, ignore.case = TRUE))
  
  if (length(input_indices) > 0 && length(output_indices) > 0) {
    # We have both inputs and outputs - ensure inputs come first
    # Get indices of non-input, non-output params
    other_indices <- setdiff(seq_along(args_list), c(input_indices, output_indices))
    
    # Reorder required/optional within each group to maintain R signature validity
    input_required <- input_indices[required_status[input_indices]]
    input_optional <- input_indices[!required_status[input_indices]]
    output_required <- output_indices[required_status[output_indices]]
    output_optional <- output_indices[!required_status[output_indices]]
    other_required <- other_indices[required_status[other_indices]]
    other_optional <- other_indices[!required_status[other_indices]]
    
    # Final order: input_required, input_optional, output_required, output_optional, other_required, other_optional
    ordered_args_indices <- c(input_required, input_optional, output_required, output_optional, other_required, other_optional)
  } else if (any(required_status)) {
    # No special input/output handling needed, just ensure required before optional
    required_indices <- which(required_status)
    optional_indices <- which(!required_status)
    ordered_args_indices <- c(required_indices, optional_indices)
  } else {
    # All optional or all required
    ordered_args_indices <- seq_along(args_list)
  }

  for (idx in ordered_args_indices) {
    arg <- args_list[[idx]]
    gdal_name <- if (is.null(arg$name)) {
      if (is.null(arg[[1]])) "" else as.character(arg[[1]][1])
    } else {
      as.character(arg$name)
    }
    if (is.null(gdal_name) || !nzchar(gdal_name)) {
      warning("Argument at position ", idx, " has no name")
      next
    }

    r_name <- gsub("-", "_", gdal_name)
    # Prefix with capital X if name starts with a digit (invalid in R)
    if (grepl("^[0-9]", r_name)) {
      r_name <- paste0("X", r_name)
    }
    arg_type <- ifelse(is.null(arg$type), "string", arg$type)
    min_count <- ifelse(is.null(arg$min_count), 0, arg$min_count)
    max_count <- ifelse(is.null(arg$max_count), 1, arg$max_count)
    default_val <- arg$default

    # Determine R type and default
    is_required <- ifelse(is.null(arg$required), FALSE, arg$required)
    
    # Detect if this is a positional parameter
    # Parameters from input_output_arguments are always positional
    is_positional <- ifelse(is.null(arg$.is_positional), FALSE, arg$.is_positional)
    
    if (is_required) {
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
      is_positional = is_positional
    )
  }

  list(
    signature = signature,
    arg_names = arg_names,
    arg_mapping = arg_mapping
  )
}


#' Extract a short title from a longer description.
#'
#' Attempts to create a concise title by taking the first clause or sentence.
#' Removes trailing periods and common suffixes.
#'
#' @param description Character string with the full description.
#'
#' @return Character string with a shorter title (typically first 50-80 chars).
#'
extract_short_title <- function(description) {
  if (is.na(description) || !nzchar(description)) {
    return(description)
  }

  # Remove trailing period or period+space
  title <- sub("\\.$", "", description)
  title <- sub("\\. *$", "", title)

  # If the description has multiple sentences (ends with period), take first sentence
  if (grepl("\\. ", description)) {
    first_sentence <- strsplit(description, "\\. ")[[1]][1]
    if (nzchar(first_sentence)) {
      title <- first_sentence
    }
  }

  # If the description has common suffixes like "by X" or "using X", optionally trim
  # But keep them for now as they can be informative

  # Limit title length for readability (roxygen typically prefers titles under 80 chars)
  if (nchar(title) > 80) {
    # Try to truncate at a natural boundary (space before 80 chars)
    # Find last space before 80 chars
    substring_80 <- substr(title, 1, 80)
    last_space <- regexpr(" [^ ]*$", substring_80)
    if (last_space > 0) {
      title <- substr(title, 1, last_space[1] - 1)
    } else {
      # No space found, just truncate
      title <- substr(title, 1, 80)
    }
    # Add ellipsis if truncated
    title <- paste0(title, "...")
  }

  title
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
#' @param cache Documentation cache object (optional).
#' @param command_name Character string with the GDAL command name (optional).
#'
generate_roxygen_doc <- function(func_name, description, arg_names, enriched_docs = NULL, family = NULL, input_args = NULL, input_output_args = NULL, full_path = NULL, is_base_gdal = FALSE, arg_mapping = NULL, cache = NULL, command_name = NULL, verbose = FALSE) {
  # Ensure verbose is a logical
  if (is.null(verbose)) verbose <- FALSE
  if (!is.logical(verbose)) verbose <- FALSE
  
  # Helper to format multi-line text for roxygen2 (each line needs #')
  # Wrap gsub/sub to add line number tracking
  safe_gsub <- function(pattern, replacement, x, ..., func_name = "", linenum = 0) {
    tryCatch({
      gsub(pattern, replacement, x, ...)
    }, error = function(e) {
      stop(sprintf("gsub error in %s (line ~%d): pattern='%s', replacement='%s', x_class=%s, x_length=%d: %s",
                   func_name, linenum, pattern, replacement, 
                   class(x)[1], length(x), conditionMessage(e)))
    })
  }

  format_roxygen_text <- function(text) {
    if (is.na(text) || !nzchar(text)) return("")
    if (!is.character(text)) {
      warning(sprintf("format_roxygen_text received non-character input: %s", class(text)))
      return("")
    }
    # Split on newlines and add #' prefix to each line
    lines <- strsplit(text, "\n")[[1]]
    paste(paste0("#' ", trimws(lines)), collapse = "\n")
  }

  wrap_command_in_backticks <- function(text, cmd_name) {
    if (is.na(text) || !nzchar(text) || is.na(cmd_name) || !nzchar(cmd_name)) {
      return(text)
    }
    # Match the command name at the start of the text (case-sensitive, with optional spaces/punctuation)
    # Pattern: command_name (possibly with spaces replacing underscores) followed by a space
    pattern <- sprintf("^%s\\s+", gsub("_", " ", cmd_name))
    if (grepl(pattern, text)) {
      # Extract the matched part and wrap it in backticks
      matched_part <- sub(pattern, "", text)
      # Only proceed if there's content after the command name
      if (nzchar(matched_part) && nchar(matched_part) < nchar(text)) {
        original_cmd <- substring(text, 1, nchar(text) - nchar(matched_part))
        result <- paste0("`", trimws(original_cmd), "` ", matched_part)
        return(result)
      }
    }
    # If simple command name didn't match, try to find the full command path in the text
    # e.g., if cmd_name is "create" but text starts with "gdal driver gti create"
    if (length(full_path) > 0) {
      full_pattern <- sprintf("^%s\\s+", paste(gsub("_", " ", full_path), collapse = " "))
      if (grepl(full_pattern, text)) {
        matched_part <- sub(full_pattern, "", text)
        # Only proceed if there's content after the command path
        if (nzchar(matched_part) && nchar(matched_part) < nchar(text)) {
          original_cmd <- substring(text, 1, nchar(text) - nchar(matched_part))
          result <- paste0("`", trimws(original_cmd), "` ", matched_part)
          return(result)
        }
      }
    }
    return(text)
  }

  # Check if this is a pipeline function (needed early for title formatting)
  is_pipeline <- func_name %in% c("gdal_raster_pipeline", "gdal_vector_pipeline")

  # Build title with command name prefix if available
  title <- extract_short_title(description)
  if (!is.null(command_name) && nzchar(command_name) && !is_base_gdal && !is_pipeline) {
    title <- sprintf("%s: %s", command_name, title)
  }
  
  doc <- sprintf("#' @title %s\n", title)

  # Use enriched description if available, otherwise try cached description, otherwise use API description
  enriched_desc <- NA_character_
  
  # First try enriched_docs from fetch (more detailed HTML description)
  if (!is.null(enriched_docs) && !is.na(enriched_docs$description) && nzchar(enriched_docs$description)) {
    enriched_desc <- enriched_docs$description
  }
  
  # If not found via fetch, try persistent cache (CSV)
  if ((is.na(enriched_desc) || !nzchar(enriched_desc)) && !is.null(cache)) {
    cached_desc <- cache$get_description(full_path)
    if (!is.na(cached_desc) && nzchar(cached_desc)) {
      enriched_desc <- cached_desc
    }
  }
  
  # If no enriched description, use the GDAL JSON API description (always available)
  if (is.na(enriched_desc) || !nzchar(enriched_desc)) {
    enriched_desc <- description
  }

  if (is.character(enriched_desc) && length(enriched_desc) > 0 &&
      !is.na(enriched_desc[1]) && nzchar(enriched_desc[1])) {
    # Wrap command name in backticks for code formatting
    desc_with_backticks <- wrap_command_in_backticks(enriched_desc[1], command_name)
    # Escape special roxygen2 markup characters in description
    escaped_desc <- desc_with_backticks
    if (is.character(escaped_desc) && length(escaped_desc) > 0 && nzchar(escaped_desc)) {
      tryCatch({
        # Add line tracking for debugging
        if (Sys.getenv("DEBUG_GSUB") == "true") cat(sprintf("[DEBUG] About to gsub { on desc for %s\n", func_name))
        escaped_desc <- safe_gsub("\\{", "\\\\{", escaped_desc, func_name = func_name, linenum = 1224)  # Escape {
        if (Sys.getenv("DEBUG_GSUB") == "true") cat(sprintf("[DEBUG] About to gsub } on desc for %s\n", func_name))
        escaped_desc <- safe_gsub("\\}", "\\\\}", escaped_desc, func_name = func_name, linenum = 1225)  # Escape }
      }, error = function(e) {
        stop(sprintf("Error escaping description for %s: %s", func_name, e$message))
      })
    }
    formatted_desc <- format_roxygen_text(escaped_desc)
    # Add the GDAL documentation URL link
    doc_url <- construct_doc_url(full_path)
    doc <- paste0(doc, sprintf("#' @description\n%s\n#' \n#' See \\url{%s} for detailed GDAL documentation.\n", formatted_desc, doc_url))
  } else {
    # Fallback: this should rarely happen now
    # Wrap command name in backticks for code formatting
    desc_with_backticks <- wrap_command_in_backticks(description, command_name)
    formatted_desc <- format_roxygen_text(desc_with_backticks)
    # Add the GDAL documentation URL link
    doc_url <- construct_doc_url(full_path)
    doc <- paste0(doc, sprintf("#' @description\n%s\n#' \n#' See \\url{%s} for detailed GDAL documentation.\n", formatted_desc, doc_url))
  }

  # For pipeline functions, add jobs parameter documentation
  if (is_pipeline) {
    doc <- paste0(doc, "#' @param jobs A vector of gdal_job objects to execute in sequence, or NULL to use pipeline string\n")
  } else if (is_base_gdal) {
    doc <- paste0(doc, "#' @param x A filename (for 'gdal info'), a pipeline string (for 'gdal pipeline'), a command vector, or a gdal_job object from a piped operation\n")
  }
  # Note: For regular functions, the first positional argument is NOT documented separately
  # because it's either a gdal_job (detected via inherits()) or the actual data argument

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
          gdal_name <- ifelse(is.null(row_list$name), NA_character_, row_list$name)
          if (!is.na(gdal_name)) {
            r_name <- gsub("-", "_", gdal_name)
            if (grepl("^[0-9]", r_name)) r_name <- paste0("X", r_name)
            arg_metadata_map[[r_name]] <- row_list
          }
        }
      } else if (is.list(all_input_args)) {
        for (i in seq_along(all_input_args)) {
          arg <- all_input_args[[i]]
          gdal_name <- ifelse(is.null(arg$name), NA_character_, arg$name)
          if (!is.na(gdal_name)) {
            r_name <- gsub("-", "_", gdal_name)
            if (grepl("^[0-9]", r_name)) r_name <- paste0("X", r_name)
            arg_metadata_map[[r_name]] <- arg
          }
        }
      }
    }

    for (arg_name in arg_names) {
      # Get metadata for this argument - use if() not ifelse() to preserve list type
      if (is.null(arg_metadata_map[[arg_name]])) {
        arg_meta <- list()
      } else {
        arg_meta <- arg_metadata_map[[arg_name]]
      }
      
      # Build parameter description
      param_desc <- ""
      
      # Start with the description from JSON
      if (!is.null(arg_meta$description) && is.character(arg_meta$description) && nzchar(arg_meta$description)) {
        param_desc <- arg_meta$description
        # Escape special roxygen2 markup characters in description
        if (is.character(param_desc) && length(param_desc) > 0) {
          param_desc <- safe_gsub("\\{", "\\\\{", param_desc, func_name = func_name, linenum = 1302)  # Escape {
          param_desc <- safe_gsub("\\}", "\\\\}", param_desc, func_name = func_name, linenum = 1303)  # Escape }
          # Escape square brackets with backslash
          param_desc <- safe_gsub("\\[", "\\\\[", param_desc, func_name = func_name, linenum = 1305)
          param_desc <- safe_gsub("\\]", "\\\\]", param_desc, func_name = func_name, linenum = 1306)
        }
      }
      
      # Add type information
      arg_type <- ifelse(is.null(arg_meta$type), "unknown", arg_meta$type)
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

      # For the first positional argument (data arg), add note about gdal_job piping
      if (!is_pipeline && !is_base_gdal && arg_names[1] == arg_name) {
        param_desc <- paste0(
          param_desc,
          ". Can also be a [gdal_job] object to extend a pipeline"
        )
      }

      doc <- paste0(doc, sprintf("#' @param %s %s\n", arg_name, param_desc))
    }
  }

  doc <- paste0(doc, sprintf("#' @return A [gdal_job] object.\n"))

  # Add family tag if provided
  if (!is.null(family) && nzchar(family)) {
    doc <- paste0(doc, sprintf("#' @family %s\n", family))
  }

  # Add examples: convert CLI examples to R code (required from enriched docs)
  doc <- paste0(doc, "#' @examples\n")

  examples_added <- 0

  # Examples are fetched from enriched_docs, but are optional
  # (some commands may not have examples yet in the GDAL documentation)
  if (!is.null(enriched_docs) && !is.null(enriched_docs$examples) && length(enriched_docs$examples) > 0) {
    # We have examples - use them
    has_examples <- TRUE
  } else {
    has_examples <- FALSE
  }
  
  if (verbose && !has_examples) {
    cat(sprintf("  [WARN] No examples found for %s (status=%d)\n", func_name, if (is.null(enriched_docs)) NA else enriched_docs$status))
  }
  
  if (has_examples) {
    # Parse and convert CLI examples to R code
    # Only take the first example to avoid duplicates
    for (i in seq_len(min(1, length(enriched_docs$examples)))) {
      cli_example <- trimws(enriched_docs$examples[i])
    if (nzchar(cli_example)) {
      # Store original for fallback/error messages
      cli_example_original <- cli_example
      
      # Clean up the CLI example: remove line continuations (backslash-newline patterns)
      # Handle various formats: "\ \n", "\\\n", "  \  \n  ", etc.
      # Use perl=TRUE for extended regex patterns
      cli_example <- gsub("\\s*\\\\\\s*$", " ", cli_example, perl = TRUE)  # Line-ending backslash
      cli_example <- gsub("\\\\\\s*\n\\s*", " ", cli_example)  # Backslash-newline (any spaces)
      cli_example <- gsub("\n\\s+", " ", cli_example)  # Newlines with leading whitespace
      cli_example <- gsub("\\s+", " ", cli_example)  # Normalize multiple spaces to single space
      cli_example <- trimws(cli_example)
      
      # Parse the CLI command
      parsed_cli <- parse_cli_command(cli_example)

      # Convert to R code, passing arg_mapping so parameter names are correct
      r_code <- convert_cli_to_r_example(parsed_cli, func_name, c(input_output_args, input_args), arg_mapping = arg_mapping)

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
          # Include source URL and GDAL command in the comment instead of generic "Example usage"
          example_comment <- "#' # Example"
          
          # Add source URL if available
          if (!is.null(enriched_docs) && !is.null(enriched_docs$url) && nzchar(enriched_docs$url)) {
            example_comment <- paste0(example_comment, " (from ", enriched_docs$url, ")")
          }
          
          # Add original GDAL command (already includes "gdal" or subcommand)
          if (!is.null(cli_example_original) && nzchar(cli_example_original)) {
            # Check if cli_example_original starts with "gdal" or a subcommand
            cli_display <- if (grepl("^gdal ", cli_example_original)) {
              cli_example_original
            } else {
              paste0("gdal ", cli_example_original)
            }
            example_comment <- paste0(example_comment, "\n#' # ", cli_display)
          }
          
          example_comment <- paste0(example_comment, "\n")
          doc <- paste0(doc, example_comment)
        }
        # Add the R code (with roxygen prefix on each line if multi-line)
        # Split by newlines and add #' prefix to each
        code_lines <- strsplit(r_code, "\n")[[1]]
        formatted_code <- paste(paste0("#' ", code_lines), collapse = "\n")
        doc <- paste0(doc, formatted_code, "\n")

        # Add gdal_job_run() call wrapped in dontrun
        doc <- paste0(doc, "#' \\dontrun{\n")
        doc <- paste0(doc, "#'   result <- gdal_job_run(job)\n")
        doc <- paste0(doc, "#' }\n")

        examples_added <- examples_added + 1
      }
    }
    }
  }

  # If we didn't add any examples, add an informative placeholder
  if (examples_added == 0) {
    doc <- paste0(doc, "#' \\dontrun{\n")
    if (exists("cli_example_original") && nzchar(cli_example_original)) {
      doc <- paste0(doc, sprintf("#' # TODO: Convert this GDAL CLI example to R parameters:\n"))
      doc <- paste0(doc, sprintf("#' # Original: %s\n", cli_example_original))
      doc <- paste0(doc, sprintf("#' # For help on available parameters, run: ?%s\n", func_name))
      doc <- paste0(doc, sprintf("#' job <- %s()\n", func_name))
    } else {
      doc <- paste0(doc, sprintf("#' # TODO: No examples available for %s.\n", func_name))
      doc <- paste0(doc, sprintf("#' # See GDAL documentation: https://gdal.org/programs/%s.html\n", 
                                  tolower(gsub("_", "-", func_name))))
      doc <- paste0(doc, sprintf("#' job <- %s()\n", func_name))
    }
    doc <- paste0(doc, "#' # gdal_job_run(job)\n")
    doc <- paste0(doc, "#' }\n")
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
    # Handle first argument: can be either a gdal_job (piped) or actual data (fresh call)
    # Check if first argument exists and is a gdal_job
    first_arg_name <- if (length(arg_names) > 0) arg_names[1] else NULL
    
    body_lines <- c(body_lines, "  new_args <- list()")

    if (length(arg_names) > 0) {
      for (i in seq_along(arg_names)) {
        arg_name <- arg_names[i]
        body_lines <- c(
          body_lines,
          sprintf("  if (!missing(%s)) new_args[[%s]] <- %s", arg_name, deparse(arg_name), arg_name)
        )
      }
    }

    # Handle the new pattern: first argument can be gdal_job OR data
    if (!is.null(first_arg_name)) {
      body_lines <- c(body_lines, "")
      body_lines <- c(body_lines, sprintf("  # Check if first argument is a piped gdal_job or actual data"))
      body_lines <- c(body_lines, sprintf("  if (!missing(%s) && inherits(%s, 'gdal_job')) {", first_arg_name, first_arg_name))
      body_lines <- c(body_lines, sprintf("    # First argument is a piped job - extend the pipeline"))
      body_lines <- c(body_lines, sprintf("    # Remove first_arg from new_args since it's the job, not data"))
      body_lines <- c(body_lines, sprintf("    piped_job <- %s", first_arg_name))
      body_lines <- c(body_lines, sprintf("    new_args[[%s]] <- NULL", deparse(first_arg_name)))
      body_lines <- c(body_lines, sprintf("    new_args <- Filter(Negate(is.null), new_args)"))
      body_lines <- c(body_lines, sprintf("    return(extend_gdal_pipeline(piped_job, %s, new_args))", path_json))
      body_lines <- c(body_lines, "  }")
      body_lines <- c(body_lines, "")
      body_lines <- c(body_lines, sprintf("  # First argument is actual data or missing - create new job"))
      body_lines <- c(body_lines, sprintf("  merged_args <- new_args"))
    } else {
      # No arguments at all
      body_lines <- c(body_lines, "  merged_args <- new_args")
    }
  }

  # Create gdal_job object
  body_lines <- c(body_lines, "")
  
  # Create arg_mapping list as a literal R list (embedded in the function)
  # This allows .serialize_gdal_job to use metadata about composite arguments
  if (length(arg_mapping) > 0) {
    mapping_lines <- "  .arg_mapping <- list("
    for (i in seq_along(arg_mapping)) {
      arg_name <- names(arg_mapping)[i]
      meta <- arg_mapping[[i]]
      min_count <- if (is.null(meta$min_count)) "0" else meta$min_count
      max_count <- if (is.null(meta$max_count)) "1" else meta$max_count
      mapping_lines <- c(mapping_lines, sprintf("    %s = list(min_count = %s, max_count = %s),", arg_name, min_count, max_count))
    }
    # Remove trailing comma from last entry
    mapping_lines[length(mapping_lines)] <- sub(",$", "", mapping_lines[length(mapping_lines)])
    mapping_lines <- c(mapping_lines, "  )")
    body_lines <- c(body_lines, mapping_lines)
    body_lines <- c(body_lines, "")
  } else {
    body_lines <- c(body_lines, "  .arg_mapping <- NULL")
    body_lines <- c(body_lines, "")
  }
  
  if (is_pipeline) {
    body_lines <- c(
      body_lines,
      sprintf("  new_gdal_job(command_path = %s, arguments = args, arg_mapping = .arg_mapping)", path_json)
    )
  } else {
    body_lines <- c(
      body_lines,
      sprintf("  new_gdal_job(command_path = %s, arguments = merged_args, arg_mapping = .arg_mapping)", path_json)
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
  writeLines(function_code, con = output_file)
  output_file
}


# ============================================================================
#' Analyze and detect parameter ordering issues across all generated functions
#'
#' This function scans all generated R functions to identify cases where optional
#' parameters appear before required positional parameters. Required positional
#' arguments should always come first (after the 'job' parameter).
#'
#' @return Data frame with function names and parameter ordering analysis
#'
analyze_parameter_ordering <- function(r_dir = "R") {
  if (!dir.exists(r_dir)) {
    return(data.frame())
  }
  
  r_files <- list.files(r_dir, pattern = "^gdal_.*\\.R$", full.names = TRUE)
  issues <- list()
  
  for (file_path in r_files) {
    content <- readLines(file_path)
    
    # Find function definition
    func_pattern <- "^(gdal_\\w+) <- function\\((.+)\\) \\{"
    func_line <- grep(func_pattern, content)
    
    if (length(func_line) == 0) next
    func_line <- func_line[1]
    
    # Extract function name and signature
    match <- regmatches(content[func_line], regexec(func_pattern, content[func_line]))
    if (length(match[[1]]) < 3) next
    
    func_name <- match[[1]][2]
    params_str <- match[[1]][3]
    
    # Parse parameters
    param_parts <- strsplit(params_str, ",")[[1]]
    param_names <- character()
    param_has_default <- logical()
    
    for (p in param_parts) {
      p <- trimws(p)
      if (nzchar(p)) {
        # Extract parameter name (before '=' if it has a default)
        param_name <- sub("\\s*=.*$", "", p)
        has_default <- grepl("=", p)
        
        param_names <- c(param_names, param_name)
        param_has_default <- c(param_has_default, has_default)
      }
    }
    
    # Check for issue: optional parameter before required parameter
    # Typically: job (no default), required_param (no default), optional_param (has default)
    # Problem: job, optional_param (has default), required_param (no default)
    
    if (length(param_names) >= 3) {
      # Skip 'job' parameter
      rest_names <- param_names[-1]
      rest_defaults <- param_has_default[-1]
      
      # Find first parameter with a default (optional)
      first_optional <- which(rest_defaults)[1]
      # Find last parameter without a default (required)
      last_required <- tail(which(!rest_defaults), 1)
      
      if (!is.na(first_optional) && !is.na(last_required) && first_optional < last_required) {
        issues[[length(issues) + 1]] <- list(
          func_name = func_name,
          file = file_path,
          params = rest_names,
          has_defaults = rest_defaults,
          issue_desc = sprintf("Optional param '%s' appears before required param '%s'",
                               rest_names[first_optional], rest_names[last_required])
        )
      }
    }
  }
  
  if (length(issues) == 0) {
    return(data.frame(func_name = character(), issue = character()))
  }
  
  # Convert to data frame
  df <- data.frame(
    func_name = sapply(issues, function(x) x$func_name),
    file = sapply(issues, function(x) x$file),
    issue = sapply(issues, function(x) x$issue_desc),
    stringsAsFactors = FALSE
  )
  
  return(df)
}


#' Apply automatic parameter ordering fixups based on required vs optional status
#'
#' Scans all generated functions and reorders parameters so that required positional
#' parameters (those without defaults) always come before optional parameters.
#'
apply_automatic_signature_fixups <- function(r_dir = "R") {
  if (!dir.exists(r_dir)) {
    return(invisible(FALSE))
  }
  
  r_files <- list.files(r_dir, pattern = "^gdal_.*\\.R$", full.names = TRUE)
  fixed_count <- 0
  
  for (file_path in r_files) {
    content <- readLines(file_path)
    original_content <- content
    
    # Find function definition
    func_pattern <- "^(gdal_\\w+) <- function\\((.+)\\) \\{"
    func_line <- grep(func_pattern, content)
    
    if (length(func_line) == 0) next
    func_line <- func_line[1]
    
    # Extract function name and parameters
    match <- regmatches(content[func_line], regexec(func_pattern, content[func_line]))
    if (length(match[[1]]) < 3) next
    
    func_name <- match[[1]][2]
    params_str <- match[[1]][3]
    
    # Parse parameters more carefully
    params <- character()
    current_param <- ""
    paren_depth <- 0
    
    for (i in 1:nchar(params_str)) {
      char <- substr(params_str, i, i)
      
      if (char == "(") paren_depth <- paren_depth + 1
      else if (char == ")") paren_depth <- paren_depth - 1
      else if (char == "," && paren_depth == 0) {
        params <- c(params, trimws(current_param))
        current_param <- ""
        next
      }
      
      current_param <- paste0(current_param, char)
    }
    if (nzchar(current_param)) {
      params <- c(params, trimws(current_param))
    }
    
    if (length(params) < 2) next
    
    # Categorize parameters: job, required (no default), optional (has default)
    job_param <- params[grepl("^job", params)]
    
    rest_params <- params[!grepl("^job", params)]
    required_params <- rest_params[!grepl("=", rest_params)]
    optional_params <- rest_params[grepl("=", rest_params)]
    
    # Check if reordering is needed
    # Correct order: job, required_params..., optional_params...
    correct_order <- c(job_param, required_params, optional_params)
    current_order <- params
    
    if (identical(correct_order, current_order)) {
      next  # Already correct
    }
    
    # Rebuild the function signature
    new_signature_line <- sprintf("%s <- function(%s) {",
                                  func_name,
                                  paste(correct_order, collapse = ", "))
    
    content[func_line] <- new_signature_line
    
    # Write back if changed
    if (!identical(content, original_content)) {
      writeLines(content, file_path)
      cat(sprintf("  [OK] %s - reordered parameters\n", func_name))
      fixed_count <- fixed_count + 1
    }
  }
  
  if (fixed_count > 0) {
    cat(sprintf("\n[OK] Applied %d parameter ordering fixes\n", fixed_count))
  } else {
    cat("[OK] No parameter ordering issues found\n")
  }
  
  invisible(fixed_count > 0)
}


# Main Execution
# ============================================================================

main <- function() {
  # Phase 1: Check if GDAL is available and get version
  gdal_version <- .get_gdal_version()

  if (is.null(gdal_version)) {
    cat("ERROR: GDAL command not found.\n")
    cat("Please ensure GDAL >= 3.11 is installed and in your PATH.\n")
    cat("Test with: gdal --version\n")
    return(invisible(NULL))
  }

  cat("Crawling GDAL API...\n")
  cat(sprintf("Using: GDAL %s\n", gdal_version$full))
  cat(sprintf("GitHub Reference: v%s\n\n", gdal_version$full))

  # Write version metadata to file for runtime introspection
  .write_gdal_version_info(gdal_version)

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

  cat(sprintf("[OK] Found %d GDAL command endpoints.\n\n", length(endpoints)))

  # Initialize documentation cache (web enrichment is mandatory)
  cat("Initializing documentation cache for web enrichment...\n")
  doc_cache <- create_doc_cache(".gdal_doc_cache")
  cat("(Web enrichment is required for examples)\n\n")

  generated_files <- character()
  failed_count <- 0

  for (endpoint_name in names(endpoints)) {
    endpoint <- endpoints[[endpoint_name]]
    func_name <- paste(gsub("-", "_", endpoint$full_path), collapse = "_")

    tryCatch(
      {
        if (func_name %in% c("gdal", "gdal_raster", "gdal_vector", "gdal_mdim")) {
          cat(sprintf("  [DEBUG] Generating %s...\n", func_name))
        }
        # Phase 2: Pass gdal_version to generate_function for version-aware URLs
        function_code <- generate_function(endpoint, cache = doc_cache, verbose = TRUE, gdal_version = gdal_version)
        if (func_name %in% c("gdal", "gdal_raster", "gdal_vector", "gdal_mdim")) {
          cat(sprintf("  [DEBUG] Writing %s...\n", func_name))
        }
        output_file <- write_function_file(func_name, function_code)
        generated_files <- c(generated_files, output_file)
        cat(sprintf("  [OK] %s\n", func_name))
      },
      error = function(e) {
        error_msg <- conditionMessage(e)
        error_class <- class(e)[1]
        error_info <- sprintf("[%s] %s", error_class, error_msg)
        cat(sprintf("  [FAILED] %s: %s\n", func_name, error_info))
        failed_count <<- failed_count + 1
      }
    )
  }

  cat(sprintf("\n[OK] Generated %d functions successfully.\n", length(generated_files)))
  if (failed_count > 0) {
    cat(sprintf("[WARN] %d functions failed to generate.\n", failed_count))
  }
  
  # Analyze and report parameter ordering issues
  cat("\nAnalyzing parameter ordering across all functions...\n")
  issues <- analyze_parameter_ordering("R")
  if (nrow(issues) > 0) {
    cat(sprintf("[WARN] Found %d functions with potential parameter ordering issues:\n", nrow(issues)))
    for (i in 1:nrow(issues)) {
      cat(sprintf("  - %s: %s\n", issues$func_name[i], issues$issue[i]))
    }
    cat("\nApplying automatic parameter ordering fixes...\n")
    apply_automatic_signature_fixups("R")
  } else {
    cat("[OK] All functions have correct parameter ordering\n")
  }
  
  cat(sprintf("[OK] Run roxygen2::roxygenise() to update documentation.\n\n"))

  invisible(generated_files)
}

# Run if executed directly
if (!interactive()) {
  main()
}
