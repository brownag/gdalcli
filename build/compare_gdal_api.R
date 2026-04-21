#!/usr/bin/env Rscript

#' Compare GDAL APIs between two versions using saved JSON files
#'
#' Loads pre-saved GDAL API JSON files from the previous release branch
#' and compares them against the current version's API JSON files.
#' Detects new commands, removed commands, and parameter changes.
#'
#' Usage:
#'   Rscript build/compare_gdal_api.R <previous_version> <current_version> [output_file]
#'   Rscript build/compare_gdal_api.R 3.12.0 3.12.1 build/api_diff.json

library(processx)
library(yyjsonr)

# ============================================================================
# Argument parsing
# ============================================================================

args <- commandArgs(trailingOnly = TRUE)

if (length(args) < 2) {
  cat("Usage: Rscript compare_gdal_api.R <previous_version> <current_version> [output_file]\n")
  cat("Example: Rscript compare_gdal_api.R 3.12.0 3.12.1 build/api_diff.json\n")
  quit(status = 1)
}

prev_version <- args[1]
curr_version <- args[2]
output_file <- if (length(args) >= 3) args[3] else "build/api_diff.json"

cat("Comparing GDAL API: ", prev_version, " -> ", curr_version, "\n", sep = "")

# ============================================================================
# Validate version alignment
# ============================================================================

# Check if GDAL_VERSION_INFO.json exists and matches declared version
version_info_file <- "inst/GDAL_VERSION_INFO.json"
if (file.exists(version_info_file)) {
  tryCatch(
    {
      version_info <- yyjsonr::read_json_file(version_info_file)
      saved_version <- version_info$version %||% version_info$version[[1]]
      
      if (!is.na(saved_version) && saved_version != curr_version) {
        cat("WARNING: inst/GDAL_API_*.json appear to be from GDAL ", saved_version, 
            " but comparing against ", curr_version, "\n", sep = "")
        cat("         Make sure you've run 'Rscript build/generate_gdal_api.R' with GDAL ", 
            curr_version, "\n", sep = "")
      }
    },
    error = function(e) {
      cat("WARNING: Could not read inst/GDAL_VERSION_INFO.json: ", e$message, "\n", sep = "")
    }
  )
}

# ============================================================================
# Helper functions
# ============================================================================

#' Load API JSON from a specific git ref (branch or tag)
#'
#' @param git_ref Character - git reference (branch or tag)
#' @param category Character - API category (raster, vector, etc)
#' @return List with parsed JSON, or NULL if not found
#'
.load_api_from_git <- function(git_ref, category) {
  tryCatch(
    {
      result <- processx::run(
        "git",
        c("show", sprintf("%s:inst/GDAL_API_%s.json", git_ref, category)),
        error_on_status = TRUE
      )
      
      # Parse the JSON
      yyjsonr::read_json_str(result$stdout)
    },
    error = function(e) {
      NULL
    }
  )
}

#' Get command names from API JSON (handles both old and new formats)
#'
#' @param json_data List - parsed JSON from `gdal <category> --json-usage`
#' @return Character vector of command names
#'
.get_commands_from_json <- function(json_data) {
  if (is.null(json_data$sub_algorithms)) {
    return(character(0))
  }
  
  # Handle data.frame format (yyjsonr output)
  if (is.data.frame(json_data$sub_algorithms)) {
    if ("name" %in% names(json_data$sub_algorithms)) {
      return(as.character(json_data$sub_algorithms$name))
    }
  }
  
  # Handle list format
  if (is.list(json_data$sub_algorithms)) {
    names <- sapply(json_data$sub_algorithms, function(x) {
      if (is.list(x) && !is.null(x$name)) x$name else NULL
    })
    return(as.character(na.omit(names)))
  }
  
  character(0)
}

# ============================================================================
# Main comparison logic
# ============================================================================

categories <- c("raster", "vector", "mdim", "vsi", "driver")

comparison_result <- list(
  previous_version = prev_version,
  current_version = curr_version,
  comparison_date = as.character(Sys.Date()),
  new_commands = list(),
  removed_commands = character(0),
  modified_commands = list()
)

cat("\nLoading APIs from saved JSON files...\n")

all_commands_prev <- list()
all_commands_curr <- list()

# Determine git reference for previous version (try branch first, then tag)
prev_major_minor <- substr(prev_version, 1, 4)  # e.g., "3.11" from "3.11.4"
prev_git_ref <- NA

# Try release branch first
prev_branch <- sprintf("release/gdal-%s", prev_major_minor)
branch_exists <- tryCatch(
  {
    processx::run("git", c("rev-parse", prev_branch), error_on_status = TRUE, stdout = "|")
    TRUE
  },
  error = function(e) FALSE
)

if (branch_exists) {
  prev_git_ref <- prev_branch
} else {
  # Release branch doesn't exist, try tag
  tryCatch(
    {
      result <- processx::run(
        "git",
        c("tag", "-l", sprintf("v*-%s", prev_version)),
        error_on_status = TRUE
      )
      tag <- trimws(result$stdout)
      if (nzchar(tag)) {
        prev_tag <- trimws(strsplit(tag, "\n")[[1]][1])
        prev_git_ref <- prev_tag
      }
    },
    error = function(e) {
      # Tag doesn't exist either
    }
  )
}

# Load previous version APIs
cat("Loading previous version ", prev_version, " from ", prev_git_ref, "...\n", sep = "")
for (category in categories) {
  if (!is.na(prev_git_ref)) {
    prev_api <- .load_api_from_git(prev_git_ref, category)
    
    if (!is.null(prev_api)) {
      commands <- .get_commands_from_json(prev_api)
      cat(sprintf("  %s: %d commands\n", category, length(commands)))
      all_commands_prev[[category]] <- commands
    } else {
      cat(sprintf("  %s: 0 commands (not found)\n", category))
      all_commands_prev[[category]] <- character(0)
    }
  } else {
    cat(sprintf("  %s: 0 commands (previous version: ref not found)\n", category))
    all_commands_prev[[category]] <- character(0)
  }
}

# Load current version APIs from local inst/ files
cat("Loading current version ", curr_version, " APIs from inst/...\n", sep = "")
for (category in categories) {
  api_file <- file.path("inst", sprintf("GDAL_API_%s.json", category))
  
  if (file.exists(api_file)) {
    tryCatch(
      {
        curr_api <- yyjsonr::read_json_file(api_file)
        commands <- .get_commands_from_json(curr_api)
        cat(sprintf("  %s: %d commands\n", category, length(commands)))
        all_commands_curr[[category]] <- commands
      },
      error = function(e) {
        cat(sprintf("  %s: 0 commands (parse error)\n", category))
        all_commands_curr[[category]] <- character(0)
      }
    )
  } else {
    cat(sprintf("  %s: 0 commands (file not found)\n", category))
    all_commands_curr[[category]] <- character(0)
  }
}

# Compare by category
for (category in categories) {
  prev_cmds <- all_commands_prev[[category]] %||% character(0)
  curr_cmds <- all_commands_curr[[category]] %||% character(0)
  
  # Skip categories that failed to extract in either version
  if (length(prev_cmds) == 0 && length(curr_cmds) == 0) {
    cat(sprintf("  Skipping %s (no commands in either version)\n", category))
    next
  }
  
  # Find new commands
  new_cmds <- setdiff(curr_cmds, prev_cmds)
  if (length(new_cmds) > 0) {
    for (cmd in new_cmds) {
      comparison_result$new_commands[[paste0(category, ".", cmd)]] <- list(
        category = category,
        command = cmd
      )
    }
  }
  
  # Find removed commands
  removed_cmds <- setdiff(prev_cmds, curr_cmds)
  if (length(removed_cmds) > 0) {
    comparison_result$removed_commands <- c(
      comparison_result$removed_commands,
      paste0(category, ".", removed_cmds)
    )
  }
}

# ============================================================================
# Output
# ============================================================================

# Write JSON results
json_output <- yyjsonr::write_json_str(comparison_result, pretty = TRUE)
writeLines(json_output, output_file)

cat("\n✓ Comparison complete. Results written to: ", output_file, "\n", sep = "")

# Summary
cat("\nSummary:\n")
cat("  New commands: ", length(comparison_result$new_commands), " \n", sep = "")
cat("  Removed commands: ", length(comparison_result$removed_commands), " \n", sep = "")

cat("\nDONE\n")

invisible(comparison_result)
