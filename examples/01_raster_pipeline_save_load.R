#!/usr/bin/env Rscript
# Integration Example 1: Raster Processing Pipeline with Metadata
# 
# This example demonstrates:
# - Creating a multi-step raster processing pipeline
# - Saving with metadata (name, description, custom tags)
# - Loading from hybrid format
# - Verifying metadata preservation
#
# Uses built-in sample data (sample_clay_content.tif)

devtools::load_all()

separator <- paste(rep("=", 70), collapse = "")

cat("\n", separator, "\n", sep = "")
cat("Example 1: Raster Pipeline with Metadata (Real Data)\n")
cat(separator, "\n\n", sep = "")

# Use the built-in sample data
sample_raster <- system.file("extdata/sample_clay_content.tif", package = "gdalcli")
output_dir <- tempdir()
output_raster <- file.path(output_dir, "processed_clay.tif")

cat("1. Using sample raster data:\n")
cat("   Input:", basename(sample_raster), "\n")
cat("   Output directory:", output_dir, "\n\n")

# Create a realistic raster processing pipeline
# Reproject to UTM -> Scale values -> Convert to COG
pipeline <- gdal_raster_reproject(
  input = sample_raster,
  output = file.path(output_dir, "reprojected.tif"),
  dst_crs = "EPSG:32618"  # UTM Zone 18N
) |>
  gdal_raster_scale(
    src_min = 0,
    src_max = 100,
    dst_min = 0,
    dst_max = 255
  ) |>
  gdal_raster_convert(
    output = output_raster,
    output_format = "COG"
  )

cat("2. Created pipeline with 3 operations:\n")
cat("   - Reproject to UTM Zone 18N\n")
cat("   - Scale values from 0-100 to 0-255\n")
cat("   - Convert to Cloud Optimized GeoTIFF\n\n")

# Define metadata for the pipeline
metadata <- list(
  data_source = "SSURGO Clay Content",
  processing_stage = "normalized",
  quality_level = "production",
  curation_date = as.character(Sys.Date())
)

# Save to hybrid format (.gdalcli.json)
pipeline_file <- file.path(output_dir, "clay_processing.gdalcli.json")
cat("3. Saving pipeline to:", pipeline_file, "\n\n")

tryCatch({
  gdal_save_pipeline(
    pipeline,
    path = pipeline_file,
    name = "Clay Content Normalization",
    description = "Reproject SSURGO clay content to UTM, normalize values to 0-255 range, save as COG",
    custom_tags = metadata,
    verbose = TRUE
  )
  
  if (file.exists(pipeline_file)) {
    cat("\n✓ Pipeline saved successfully\n\n")
    
    file_info <- file.info(pipeline_file)
    cat("   File size:", round(file_info$size / 1024, 2), "KB\n")
    cat("   Created:", as.character(file_info$mtime), "\n\n")
  }
}, error = function(e) {
  cat("✗ Error saving pipeline:", conditionMessage(e), "\n")
})

# Load the pipeline back
cat("4. Loading pipeline from disk...\n\n")
tryCatch({
  loaded_pipeline <- gdal_load_pipeline(pipeline_file)
  
  cat("✓ Pipeline loaded successfully\n\n")
  cat("   Pipeline name:", loaded_pipeline$name, "\n")
  cat("   Number of jobs:", length(loaded_pipeline$jobs), "\n")
  cat("   Description:", substr(loaded_pipeline$description, 1, 60), "...\n\n")
  
  # Display the saved file structure
  cat("5. Hybrid Format Structure:\n")
  cat(paste(rep("-", 70), collapse = ""), "\n\n")
  
  saved_json <- jsonlite::fromJSON(readLines(pipeline_file), simplifyVector = FALSE)
  
  cat("GDALG Component (RFC 104):\n")
  cat("  Type:", saved_json$gdalg$type, "\n")
  cmd_preview <- strtrim(saved_json$gdalg$command_line, 75)
  cat("  Command:", cmd_preview, "...\n\n")
  
  cat("Metadata Component:\n")
  cat("  Version:", saved_json$metadata$gdalcli_version, "\n")
  cat("  GDAL Required:", saved_json$metadata$gdal_version_required, "\n")
  cat("  Created:", saved_json$metadata$created_at, "\n")
  cat("  Pipeline:", saved_json$metadata$pipeline_name, "\n\n")
  
  cat("Custom Tags:\n")
  for (tag in names(saved_json$metadata$custom_tags)) {
    val <- saved_json$metadata$custom_tags[[tag]]
    cat("  ", tag, ":", as.character(val), "\n", sep = "")
  }
  
  cat("\nr_job_specs Component:\n")
  cat("  Number of jobs:", length(saved_json$r_job_specs), "\n")
  for (i in seq_along(saved_json$r_job_specs)) {
    job <- saved_json$r_job_specs[[i]]
    cat("  Job", i, ":", paste(job$command_path, collapse = " "), "\n")
  }
  
}, error = function(e) {
  cat("✗ Error:", conditionMessage(e), "\n")
})

cat("\n", separator, "\n", sep = "")
cat("✓ Example 1 Complete: Real data pipeline saved and loaded successfully\n")
cat(separator, "\n")
