#!/usr/bin/env Rscript

#' Generate structured release notes from GDAL API comparison
#'
#' Creates categorized release notes highlighting new commands, parameter changes,
#' and installation instructions. Fetches GDAL GitHub release information.
#'
#' Usage:
#'   Rscript build/generate_release_notes.R <gdal_version> <package_version> [api_diff_file]
#'   Rscript build/generate_release_notes.R 3.12.1 0.3.0

library(processx)
library(yyjsonr)

# ============================================================================
# Argument parsing
# ============================================================================

args <- commandArgs(trailingOnly = TRUE)

if (length(args) < 2) {
  cat("Usage: Rscript generate_release_notes.R <gdal_version> <package_version> [api_diff_file]\n")
  cat("Example: Rscript generate_release_notes.R 3.12.1 0.3.0 build/api_diff.json\n")
  quit(status = 1)
}

gdal_version <- args[1]
package_version <- args[2]
api_diff_file <- if (length(args) >= 3) args[3] else "build/api_diff.json"

cat("Generating release notes for gdalcli v", package_version, " (GDAL ", gdal_version, ")\n", sep = "")

# ============================================================================
# Helper functions
# ============================================================================

#' Generate GDAL release URL
#' 
#' @param version Character - GDAL version (e.g. "3.12.0")
#' @return Character URL to GitHub release page
#'
.gdal_release_url <- function(version) {
  sprintf("https://github.com/OSGeo/gdal/releases/tag/v%s", version)
}

#' Extract NEWS.md entry for current package version
#'
#' Reads NEWS.md and extracts the first version entry (# gdalcli X.Y.Z ...)
#' Returns all content until the next version header or end of file.
#'
#' @param news_file Character - path to NEWS.md (default "NEWS.md")
#' @return Character vector of lines, or NULL if not found
#'
.extract_news_entry <- function(news_file = "NEWS.md") {
  if (!file.exists(news_file)) {
    return(NULL)
  }
  
  tryCatch(
    {
      lines <- readLines(news_file, warn = FALSE)
      
      # Find the first version header (# gdalcli X.Y.Z)
      header_indices <- grep("^# gdalcli", lines)
      
      if (length(header_indices) == 0) {
        return(NULL)
      }
      
      # Start from the first header
      start_idx <- header_indices[1]
      
      # Find the end (next header or end of file)
      if (length(header_indices) > 1) {
        end_idx <- header_indices[2] - 1
      } else {
        end_idx <- length(lines)
      }
      
      # Extract the entry
      entry_lines <- lines[start_idx:end_idx]
      
      # Remove trailing empty lines
      while (length(entry_lines) > 0 && trimws(entry_lines[length(entry_lines)]) == "") {
        entry_lines <- entry_lines[-length(entry_lines)]
      }
      
      entry_lines
    },
    error = function(e) {
      cat("Warning: Could not read NEWS.md: ", e$message, "\n", sep = "")
      NULL
    }
  )
}

#' Format function name for display
#'
#' Converts category.command to gdal_category_command format
#' 
#' @param category Character - category (raster, vector, etc)
#' @param command Character - command name
#' @return Character formatted function name
#'
.format_function_name <- function(category, command) {
  cmd_normalized <- gsub("[[:space:]-]", "_", tolower(command))
  sprintf("gdal_%s_%s", category, cmd_normalized)
}

# ============================================================================
# Load API diff results
# ============================================================================

api_diff <- NULL
if (file.exists(api_diff_file)) {
  tryCatch(
    {
      api_diff <- yyjsonr::read_json_file(api_diff_file)
      cat("Loaded API diff from: ", api_diff_file, " \n", sep = "")
    },
    error = function(e) {
      cat("Warning: Could not load API diff file: ", e$message, "\n", sep = "")
    }
  )
} else {
  cat("Warning: API diff file not found (", api_diff_file, "), will generate notes without changes\n", sep = "")
  api_diff <- list(
    new_commands = list(),
    removed_commands = character(0),
    modified_commands = list()
  )
}

# Load package changes from NEWS.md
news_entry <- .extract_news_entry()
if (!is.null(news_entry) && length(news_entry) > 0) {
  cat("Loaded package changes from NEWS.md\n")
}

# ============================================================================
# Generate release notes
# ============================================================================

notes <- character()

# Title section
notes <- c(notes, sprintf("Release of gdalcli v%s for GDAL %s", package_version, gdal_version))

# Package changes section (from NEWS.md)
if (!is.null(news_entry) && length(news_entry) > 0) {
  notes <- c(notes, "")
  notes <- c(notes, "## Package Changes")
  notes <- c(notes, "")
  # Skip the header line (# gdalcli X.Y.Z ...) and include the rest
  for (i in 2:length(news_entry)) {
    notes <- c(notes, news_entry[i])
  }
}

# GDAL API changes section (if we have diff data)
if (!is.null(api_diff)) {
  n_new <- length(api_diff$new_commands %||% list())
  n_removed <- length(api_diff$removed_commands %||% character(0))
  n_modified <- length(api_diff$modified_commands %||% list())
  
  if (n_new > 0 || n_removed > 0 || n_modified > 0) {
    notes <- c(notes, "")
    notes <- c(notes, "## GDAL API Changes")
    notes <- c(notes, "")
    notes <- c(notes, sprintf("This release includes support for GDAL %s with the following API changes:", gdal_version))
    notes <- c(notes, "")
    notes <- c(notes, sprintf("- **New Commands**: %d", n_new))
    notes <- c(notes, sprintf("- **Modified Commands**: %d", n_modified))
    notes <- c(notes, sprintf("- **Removed Commands**: %d", n_removed))
    
    # New commands section
    if (n_new > 0) {
      notes <- c(notes, "")
      notes <- c(notes, "### New Commands")
      notes <- c(notes, "")
      for (cmd_key in names(api_diff$new_commands)) {
        cmd_info <- api_diff$new_commands[[cmd_key]]
        func_name <- .format_function_name(cmd_info$category, cmd_info$command)
        notes <- c(notes, sprintf("- `%s` — %s", func_name, cmd_info$command))
      }
    }
    
    # Modified commands section
    if (n_modified > 0) {
      notes <- c(notes, "")
      notes <- c(notes, "### Modified Commands")
      notes <- c(notes, "")
      notes <- c(notes, "The following commands have parameter changes that may affect existing code:")
      notes <- c(notes, "")
      
      for (cmd_key in names(api_diff$modified_commands)) {
        cmd_info <- api_diff$modified_commands[[cmd_key]]
        changes <- cmd_info$parameter_changes
        
        func_name <- .format_function_name(cmd_info$category, cmd_info$command)
        notes <- c(notes, sprintf("- `%s`", func_name))
        
        if (length(changes$added) > 0) {
          notes <- c(notes, sprintf("  - **New parameters**: %s", paste(changes$added, collapse = ", ")))
        }
        
        if (length(changes$removed) > 0) {
          notes <- c(notes, sprintf("  - **Removed parameters**: %s", paste(changes$removed, collapse = ", ")))
        }
        
        if (length(changes$modified) > 0) {
          for (param_name in names(changes$modified)) {
            param_changes <- changes$modified[[param_name]]
            notes <- c(notes, "  - **Parameter changes**:")
            for (change in param_changes) {
              notes <- c(notes, sprintf("    - %s", change))
            }
          }
        }
      }
    }
    
    # Removed commands section
    if (n_removed > 0) {
      notes <- c(notes, "")
      notes <- c(notes, "### Removed Commands")
      notes <- c(notes, "")
      notes <- c(notes, "The following commands are no longer available in GDAL:")
      notes <- c(notes, "")
      for (cmd_key in api_diff$removed_commands) {
        notes <- c(notes, sprintf("- `%s`", cmd_key))
      }
    }
  }
}

# Installation section
notes <- c(notes, "")
notes <- c(notes, "## Installation")
notes <- c(notes, "")
notes <- c(notes, "Install from the release branch:")
notes <- c(notes, "")
notes <- c(notes, "```r")
notes <- c(notes, "remotes::install_github(")
notes <- c(notes, sprintf("  \"brownag/gdalcli\","))

# Parse version for branch name
version_parts <- strsplit(gdal_version, "\\.")[[1]]
major <- version_parts[1]
minor <- version_parts[2]
notes <- c(notes, sprintf("  ref = \"release/gdal-%s.%s\"", major, minor))
notes <- c(notes, ")")
notes <- c(notes, "```")
notes <- c(notes, "")
notes <- c(notes, "Or pull the Docker image:")
notes <- c(notes, "")
notes <- c(notes, "```bash")
notes <- c(notes, sprintf("docker pull ghcr.io/brownag/gdalcli:gdal-%s-latest", gdal_version))
notes <- c(notes, "```")

# Version details section
notes <- c(notes, "")
notes <- c(notes, "## Details")
notes <- c(notes, "")
notes <- c(notes, sprintf("- **GDAL Version**: %s ([Release Notes](%s))", gdal_version, .gdal_release_url(gdal_version)))
notes <- c(notes, sprintf("- **Package Version**: v%s-%s", package_version, gdal_version))
notes <- c(notes, sprintf("- **Release Branch**: `release/gdal-%s.%s`", major, minor))

# ============================================================================
# Output
# ============================================================================

notes_text <- paste(notes, collapse = "\n")
cat("\n")
cat(notes_text)
cat("\n")

invisible(notes_text)
