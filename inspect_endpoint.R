#!/usr/bin/env Rscript
# Examine actual examples from one function to understand parsing needs

source("build/generate_gdal_api.R")

# Get the GDAL endpoints
endpoints <- crawl_gdal_api(c("gdal"))

# Find raster_clip endpoint
for (endpoint_name in names(endpoints)) {
  if (grepl("raster.*clip", endpoint_name, ignore.case = TRUE)) {
    endpoint <- endpoints[[endpoint_name]]
    cat("Found endpoint:", endpoint_name, "\n\n")
    
    cat("Input args:\n")
    if (!is.null(endpoint$input_args)) {
      for (i in seq_along(endpoint$input_args)) {
        arg <- endpoint$input_args[[i]]
        cat(sprintf("  %d. %s (min=%s, max=%s)\n", i, arg$name, 
                   if (is.null(arg$min_count)) "?" else arg$min_count,
                   if (is.null(arg$max_count)) "?" else arg$max_count))
      }
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
    }
    
    break
  }
}
