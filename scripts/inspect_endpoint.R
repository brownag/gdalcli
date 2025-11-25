#!/usr/bin/env Rscript
# Inspect a specific GDAL endpoint to understand its argument structure
# Usage: Rscript scripts/inspect_endpoint.R <endpoint_pattern>
# Example: Rscript scripts/inspect_endpoint.R "raster.*clip"
#          Rscript scripts/inspect_endpoint.R "vector.*buffer"

source("build/generate_gdal_api.R")

# Parse command line arguments
args <- commandArgs(trailingOnly = TRUE)
if (length(args) == 0) {
  cat("Usage: Rscript scripts/inspect_endpoint.R <endpoint_pattern>\n")
  cat("Example: Rscript scripts/inspect_endpoint.R 'raster.*clip'\n")
  quit(status = 1)
}

pattern <- args[1]

# Get the GDAL endpoints
cat("Crawling GDAL API...\n")
endpoints <- crawl_gdal_api(c("gdal"))

# Find matching endpoint(s)
matching_endpoints <- names(endpoints)[grepl(pattern, names(endpoints), ignore.case = TRUE)]

if (length(matching_endpoints) == 0) {
  cat("No endpoints matching pattern:", pattern, "\n")
  quit(status = 1)
}

cat("Found", length(matching_endpoints), "matching endpoint(s)\n\n")

# Inspect each matching endpoint
for (endpoint_name in matching_endpoints) {
  endpoint <- endpoints[[endpoint_name]]
  cat("═══════════════════════════════════════════\n")
  cat("Endpoint:", endpoint_name, "\n")
  cat("═══════════════════════════════════════════\n\n")

  cat("Input args:\n")
  if (!is.null(endpoint$input_args)) {
    for (i in seq_along(endpoint$input_args)) {
      arg <- endpoint$input_args[[i]]
      cat(sprintf("  %d. %s (min=%s, max=%s)\n", i, arg$name,
                 if (is.null(arg$min_count)) "?" else arg$min_count,
                 if (is.null(arg$max_count)) "?" else arg$max_count))
    }
  } else {
    cat("  (None)\n")
  }

  cat("\nInput/Output args:\n")
  if (!is.null(endpoint$input_output_args)) {
    for (i in seq_along(endpoint$input_output_args)) {
      arg <- endpoint$input_output_args[[i]]
      cat(sprintf("  %d. %s (min=%s, max=%s, is_input=%s, is_output=%s)\n", i, arg$name,
                 if (is.null(arg$min_count)) "?" else arg$min_count,
                 if (is.null(arg$max_count)) "?" else arg$max_count,
                 if (is.null(arg$is_input)) "?" else arg$is_input,
                 if (is.null(arg$is_output)) "?" else arg$is_output))
    }
  } else {
    cat("  (None)\n")
  }

  cat("\n")
}
