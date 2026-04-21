#!/usr/bin/env Rscript

#' API Change Tracking and Release Notes Automation
#'
#' Unified script to:
#' 1. Compare GDAL APIs between two versions
#' 2. Generate release notes from the comparison
#' 3. Log all changes to audit trail
#'
#' Usage:
#'   Rscript build/api_change_tracking.R 3.11.4 3.12.3
#'   Rscript build/api_change_tracking.R 3.11.4 3.12.3 --release-version 0.6.0
#'   Rscript build/api_change_tracking.R --compare-git [previous_version] [current_version]

library(yyjsonr)
library(glue)

# Helper: repeat string
strrep <- function(x, n) paste0(rep(x, n), collapse = "")

# Parse command-line arguments
args <- commandArgs(trailingOnly = TRUE)

if (length(args) == 0) {
  cat("Usage: Rscript build/api_change_tracking.R [prev_version] [curr_version] [OPTIONS]\n")
  cat("\nArguments:\n")
  cat("  prev_version    Previous GDAL version (e.g., 3.11.4)\n")
  cat("  curr_version    Current GDAL version (e.g., 3.12.3)\n")
  cat("\nOptions:\n")
  cat("  --release-version VERSION  Package release version (default: 0.6.0)\n")
  cat("  --output FILE              Output diff to FILE (default: /tmp/api_diff.json)\n")
  cat("  --release-notes FILE       Output release notes to FILE\n")
  cat("  --no-compare               Skip comparison (only generate release notes)\n")
  cat("  --compare-git              Load previous version from git\n")
  cat("  --release-branch BRANCH    Git branch for previous version\n")
  cat("  --log-changes FILE         Log metadata to FILE (append-only JSONL)\n")
  cat("  --verbose                  Verbose output\n")
  quit(status = 0)
}

# Default values
prev_version <- args[1]
curr_version <- args[2]
release_version <- "0.6.0"
output_file <- "/tmp/api_diff.json"
release_notes_file <- NULL
skip_compare <- FALSE
compare_git <- FALSE
release_branch <- NULL
log_file <- NULL
verbose <- FALSE

# Parse options
i <- 3
while (i <= length(args)) {
  arg <- args[i]
  
  if (arg == "--release-version") {
    release_version <- args[i + 1]
    i <- i + 2
  } else if (arg == "--output") {
    output_file <- args[i + 1]
    i <- i + 2
  } else if (arg == "--release-notes") {
    release_notes_file <- args[i + 1]
    i <- i + 2
  } else if (arg == "--no-compare") {
    skip_compare <- TRUE
    i <- i + 1
  } else if (arg == "--compare-git") {
    compare_git <- TRUE
    i <- i + 1
  } else if (arg == "--release-branch") {
    release_branch <- args[i + 1]
    i <- i + 2
  } else if (arg == "--log-changes") {
    log_file <- args[i + 1]
    i <- i + 2
  } else if (arg == "--verbose") {
    verbose <- TRUE
    i <- i + 1
  } else {
    cat(sprintf("Warning: Unknown option '%s'\n", arg))
    i <- i + 1
  }
}

# Validate arguments
if (is.na(prev_version) || prev_version == "") {
  cat("Error: Previous version required\n")
  quit(status = 1)
}
if (is.na(curr_version) || curr_version == "") {
  cat("Error: Current version required\n")
  quit(status = 1)
}

# ============================================================================
# Step 1: Compare APIs
# ============================================================================

if (!skip_compare) {
  if (verbose) {
    cat(sprintf("Step 1: Comparing GDAL API %s -> %s\n", prev_version, curr_version))
  }
  
  # Call compare_gdal_api.R
  compare_args <- c("build/compare_gdal_api.R", prev_version, curr_version, output_file)
  
  result <- system2(
    "Rscript",
    compare_args,
    stdout = TRUE,
    stderr = TRUE
  )
  
  if (!file.exists(output_file)) {
    cat(sprintf("Error: Comparison failed. Output file not created at %s\n", output_file))
    quit(status = 1)
  }
  
  if (verbose) {
    cat("  ✓ Comparison complete\n")
  }
} else {
  if (verbose) {
    cat("Skipping comparison (--no-compare)\n")
  }
}

# ============================================================================
# Step 2: Generate Release Notes
# ============================================================================

if (!is.null(release_notes_file)) {
  if (verbose) {
    cat("Step 2: Generating release notes\n")
  }
  
  # Call generate_release_notes.R
  release_notes_args <- c(
    "build/generate_release_notes.R",
    curr_version,
    release_version,
    output_file
  )
  
  # Capture output
  release_notes_output <- system2(
    "Rscript",
    release_notes_args,
    stdout = TRUE,
    stderr = TRUE
  )
  
  # Write to file
  writeLines(release_notes_output, release_notes_file)
  
  if (verbose) {
    cat(sprintf("  ✓ Release notes written to %s\n", release_notes_file))
  }
}

# ============================================================================
# Step 3: Log Changes to Audit Trail
# ============================================================================

if (!is.null(log_file)) {
  if (verbose) {
    cat("Step 3: Logging changes to audit trail\n")
  }
  
  # Load the API diff to get summary
  api_diff <- yyjsonr::read_json_file(output_file)
  
  # Get git information if available
  git_sha <- tryCatch(
    {
      sha_result <- system2("git", c("rev-parse", "HEAD"), stdout = TRUE, stderr = FALSE)
      trimws(sha_result[1])
    },
    error = function(e) "unknown"
  )
  
  # Create log entry
  log_entry <- list(
    timestamp = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    previous_version = prev_version,
    current_version = curr_version,
    package_version = release_version,
    new_commands_count = length(api_diff$new_commands %||% list()),
    removed_commands_count = length(api_diff$removed_commands %||% list()),
    modified_commands_count = length(api_diff$modified_commands %||% list()),
    git_sha = git_sha,
    release_branch = release_branch %||% NA_character_,
    release_notes_file = release_notes_file %||% NA_character_
  )
  
  # Append to log file (create if doesn't exist)
  dir.create(dirname(log_file), showWarnings = FALSE, recursive = TRUE)
  
  log_json <- yyjsonr::write_json_str(log_entry, pretty = FALSE)
  
  if (file.exists(log_file)) {
    # Append
    existing_content <- readLines(log_file)
    writeLines(c(existing_content, log_json), log_file)
  } else {
    # Create
    writeLines(log_json, log_file)
  }
  
  if (verbose) {
    cat(sprintf("  ✓ Logged to %s\n", log_file))
  }
}

# ============================================================================
# Summary Output
# ============================================================================

cat("\n")
cat(strrep("=", 80), "\n")
cat("API Change Tracking Complete\n")
cat(strrep("=", 80), "\n\n")

cat(sprintf("Comparison:      GDAL %s -> %s\n", prev_version, curr_version))
cat(sprintf("Package version: %s\n", release_version))
cat(sprintf("Diff output:     %s\n", output_file))

if (!is.null(release_notes_file)) {
  cat(sprintf("Release notes:   %s\n", release_notes_file))
}

if (!is.null(log_file)) {
  cat(sprintf("Change log:      %s\n", log_file))
}

cat("\n")

# Load and display summary
if (file.exists(output_file)) {
  api_diff <- yyjsonr::read_json_file(output_file)
  summary <- api_diff$summary %||% list()
  
  new_count <- summary$new_commands %||% 0
  removed_count <- summary$removed_commands %||% 0
  modified_count <- summary$modified_commands %||% 0
  
  cat("Summary:\n")
  cat(sprintf("  New commands:      %d\n", new_count))
  cat(sprintf("  Removed commands:  %d\n", removed_count))
  cat(sprintf("  Modified commands: %d\n", modified_count))
  cat("\n")
  
  # Warn if no changes detected for different versions
  if (prev_version != curr_version && 
      (new_count == 0 && removed_count == 0 && modified_count == 0)) {
    cat("⚠️  WARNING: No API differences found between versions\n")
    cat("   This may indicate:\n")
    cat("   1. Previous version not found in git (check release branch exists)\n")
    cat("   2. Current version APIs not properly generated (run generate_gdal_api.R)\n")
    cat("   3. GDAL versions are actually identical\n\n")
  }
}

cat("✓ All done!\n")
