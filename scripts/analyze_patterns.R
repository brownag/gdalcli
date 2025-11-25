#!/usr/bin/env Rscript
# Analyze GDAL API to identify composite argument patterns and parameter types
# Usage: Rscript scripts/analyze_patterns.R [command1] [command2] ...
# Default: analyzes all 'gdal' commands

source("build/generate_gdal_api.R")

# Parse command line arguments (default to 'gdal' if none provided)
args <- commandArgs(trailingOnly = TRUE)
commands <- if (length(args) > 0) args else c("gdal")

cat("Crawling GDAL API for commands:", paste(commands, collapse = ", "), "...\n")
endpoints <- crawl_gdal_api(commands)

cat("Analyzing parameter patterns across", length(endpoints), "GDAL command(s)...\n\n")

# Collect statistics about parameters
composite_args <- list()
repeatable_args <- list()

for (endpoint_name in names(endpoints)) {
  endpoint <- endpoints[[endpoint_name]]
  
  if (is.null(endpoint$input_args)) next
  
  # Analyze each input argument
  for (arg in endpoint$input_args) {
    arg_name <- arg$name
    if (is.null(arg_name)) next
    
    min_count <- if (is.null(arg$min_count)) 0 else arg$min_count
    max_count <- if (is.null(arg$max_count)) 1 else arg$max_count
    
    # Check for composite patterns (fixed multi-value)
    if (max_count == min_count && min_count > 1) {
      key <- paste0(arg_name, "_count_", min_count)
      if (!(key %in% names(composite_args))) {
        composite_args[[key]] <- list(
          name = arg_name,
          count = min_count,
          endpoints = c()
        )
      }
      composite_args[[key]]$endpoints <- c(composite_args[[key]]$endpoints, endpoint_name)
    }
    # Check for repeatable arguments
    else if (max_count > 1 && max_count > min_count) {
      key <- arg_name
      if (!(key %in% names(repeatable_args))) {
        repeatable_args[[key]] <- list(
          name = arg_name,
          min = min_count,
          max = max_count,
          endpoints = c()
        )
      }
      repeatable_args[[key]]$endpoints <- c(repeatable_args[[key]]$endpoints, endpoint_name)
    }
  }
}

cat("COMPOSITE ARGUMENTS (fixed-count):\n")
if (length(composite_args) > 0) {
  for (pattern in names(composite_args)) {
    p <- composite_args[[pattern]]
    cat(sprintf("  - %s: exactly %d values (found in %d endpoints)\n", p$name, p$count, length(unique(p$endpoints))))
  }
} else {
  cat("  (None found)\n")
}

cat("\nREPEATABLE ARGUMENTS (multi-value):\n")
if (length(repeatable_args) > 0) {
  for (pattern in names(repeatable_args)) {
    p <- repeatable_args[[pattern]]
    cat(sprintf("  - %s: %d to %d values (found in %d endpoints)\n", p$name, p$min, p$max, length(unique(p$endpoints))))
  }
} else {
  cat("  (None found)\n")
}

cat("\nTotal endpoints analyzed:", length(endpoints), "\n")
