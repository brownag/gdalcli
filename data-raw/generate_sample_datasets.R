#' Generate Sample Raster and Vector Datasets for Testing
#'
#' This script creates sample geospatial datasets using soilDB functions:
#' - Surface clay content raster from SOLUS (continuous)
#' - Mapunit polygons from SSURGO (categorical vector)
#' - Rasterized mapunit polygons (categorical raster)

# Load packages
library(soilDB)
library(sf)
library(terra)
library(gdalcli)

bbox <- sf::st_as_sf(wk::rct(
  xmin = -89.1,
  ymin = 43.0,
  xmax = -89.0,
  ymax = 43.1
, crs="OGC:CRS84")) 

  solus_data <- fetchSOLUS(
    bbox,
    variables = "claytotal",
    depth_slices = 0
  )

  if (!is.null(solus_data)) {
    message("SOLUS data fetched successfully")

    # Extract the clay raster
    clay_raster <- solus_data$claytotal_0_cm_p

    # Check if we got valid data
    if (!is.null(clay_raster)) {
      message("Clay raster dimensions: ", paste(dim(clay_raster), collapse = " x "))
      message("Clay raster CRS: ", crs(clay_raster))

      # Save as GeoTIFF
      clay_tif_path <- "inst/extdata/sample_clay_content.tif"
      writeRaster(clay_raster, clay_tif_path, overwrite = TRUE)
      message("Saved clay content raster to: ", clay_tif_path)

    } else {
      message("Warning: No clay raster data returned from SOLUS")
    }
  } else {
    message("Warning: No SOLUS data returned")
  }


#' Step 2: Query SSURGO mapunit polygons using SDA_spatialQuery
message("Querying SSURGO mapunit polygons...")

  mapunit_polygons <- SDA_spatialQuery(
    bbox, what = "mupolygon", db = "STATSGO", geomIntersection = TRUE
  ) 

  if (!is.null(mapunit_polygons) && nrow(mapunit_polygons) > 0) {
    message("Retrieved ", nrow(mapunit_polygons), " mapunit polygons")

    # Save as GPKG
    mapunit_gpkg_path <- "inst/extdata/sample_mapunit_polygons.gpkg"
    st_write(mapunit_polygons, mapunit_gpkg_path, delete_layer = TRUE)
    message("Saved mapunit polygons to: ", mapunit_gpkg_path)

  } else {
    message("Warning: No mapunit polygons returned from SDA query")
    mapunit_polygons <- NULL
  }

#' Step 3: Rasterize mapunit polygons to create categorical raster
if (!is.null(mapunit_polygons) && exists("clay_raster")) {
  message("Rasterizing mapunit polygons...")

  
    # Use the clay raster as template for extent, resolution, and CRS
    template_raster <- clay_raster

    # Create categorical raster from polygons
    # Use mukey as the categorical value
    mapunit_raster <- rasterize(
      st_transform(mapunit_polygons, crs(template_raster)),
      template_raster,
      field = "mukey"
    )

    message("Mapunit raster dimensions: ", paste(dim(mapunit_raster), collapse = " x "))

    # Save as GeoTIFF
    mapunit_raster_tif_path <- "inst/extdata/sample_mapunit_raster.tif"
    writeRaster(mapunit_raster, mapunit_raster_tif_path, overwrite = TRUE,
                datatype = "INT4U")  # Use unsigned integer for categorical data
    message("Saved mapunit raster to: ", mapunit_raster_tif_path)
}

#' Step 4: Create a summary of generated files
message("\n=== Dataset Generation Summary ===")

generated_files <- list.files("inst/extdata", pattern = "^sample_.*\\.(tif|gpkg|geojson)$", full.names = TRUE)

if (length(generated_files) > 0) {
  message("Generated files:")
  for (file in generated_files) {
    file_info <- file.info(file)
    message(sprintf("- %s (%.4f MB)",
                   basename(file),
                   file_info$size / (1024 * 1024)))
  }
} else {
  message("No files were generated")
}

#  library(gdalcli)
#
#  # Example: Get info about the clay content raster
#  clay_info <- gdal_raster_info(input = "inst/extdata/sample_clay_content.tif") |>
#    gdal_job_run(stream_out_format = "text")
#
#  # Example: Convert clay raster to different format
#  clay_converted <- gdal_raster_convert(
#    input = "inst/extdata/sample_clay_content.tif",
#    output = "inst/extdata/sample_clay_content_jpeg.tif",
#    output_format = "JPEG",
#  ) |> gdal_job_run()
#
#  # Example: Clip mapunit polygons
#  clipped_polygons <- gdal_vector_clip(
#    input = "inst/extdata/sample_mapunit_polygons.gpkg",
#    output = "inst/extdata/sample_mapunit_polygons_clipped.gpkg",   
#    bbox = st_bbox(bbox),
#    overwrite=TRUE
#  ) |> gdal_job_run(backend="processx")
