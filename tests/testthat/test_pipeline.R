test_that("pipeline creation and basic execution works", {
  # Create a simple pipeline
  job1 <- gdal_raster_info(input = "test.tif")
  job2 <- gdal_raster_convert(input = "test.tif", output = "output.jpg")

  # Create pipeline
  pipeline <- new_gdal_pipeline(list(job1, job2))
  expect_s3_class(pipeline, "gdal_pipeline")
  expect_length(pipeline$jobs, 2)
  expect_s3_class(pipeline$jobs[[1]], "gdal_job")
  expect_s3_class(pipeline$jobs[[2]], "gdal_job")
})

test_that("pipeline operator creates correct pipeline", {
  # Test pipeline operator
  job <- gdal_raster_info(input = "input.tif") |>
    gdal_raster_convert(output = "output.jpg")

  expect_s3_class(job, "gdal_job")
  expect_s3_class(job$pipeline, "gdal_pipeline")
  expect_length(job$pipeline$jobs, 2)
})

test_that("serialize_gdal_job handles argument ordering correctly", {
  # Test positional arguments come before options
  job <- gdal_vector_rasterize(
    input = "input.shp",
    output = "output.tif",
    burn = 1,
    resolution = c(10, 10)
  )

  args <- .serialize_gdal_job(job)

  # Should start with command parts, then positional args, then options
  expect_equal(unname(args[1:3]), c("vector", "rasterize", "input.shp"))
  expect_equal(unname(args[4]), "output.tif")

  # Options should come after positional args
  burn_idx <- which(args == "--burn")
  resolution_idx <- which(args == "--resolution")

  expect_true(burn_idx > 4)  # After positional args
  expect_true(resolution_idx > 4)
})

test_that("serialize_gdal_job handles flag mappings correctly", {
  # Test resolution maps to --resolution, not --tr
  job <- gdal_vector_rasterize(
    input = "input.shp",
    output = "output.tif",
    resolution = c(10, 10)
  )

  args <- .serialize_gdal_job(job)

  # Should use --resolution, not --tr
  expect_true("--resolution" %in% args)
  expect_false("--tr" %in% args)

  resolution_idx <- which(args == "--resolution")
  expect_equal(unname(args[resolution_idx + 1]), "10,10")
})

test_that("serialize_gdal_job handles comma-separated multi-value args", {
  # Test bbox uses comma separation - use gdal_raster_create which has bbox
  job <- gdal_raster_create(
    output = "output.tif",
    size = c(100, 100),
    bbox = c(-180, -90, 180, 90)
  )

  args <- .serialize_gdal_job(job)

  # Should have comma-separated bbox
  bbox_idx <- which(args == "--bbox")
  expect_equal(unname(args[bbox_idx + 1]), "-180,-90,180,90")
})

test_that("pipeline connections work correctly", {
  # Test that pipeline connects outputs to inputs
  job <- gdal_vector_reproject(
    input = "input.shp",
    output = "temp.gpkg",
    dst_crs = "EPSG:4326"
  ) |>
  gdal_vector_rasterize(
    output = "output.tif",
    burn = 1,
    resolution = c(10, 10)
  )

  # Check that the rasterize job has input set to temp.gpkg
  pipeline <- job$pipeline
  rasterize_job <- pipeline$jobs[[2]]

  expect_equal(rasterize_job$arguments$input, "temp.gpkg")
})

test_that("pipeline uses temp files for connections when needed", {
  # Test pipeline with jobs that produce outputs
  job <- gdal_vector_reproject(
    input = "input.shp",
    output = "temp.gpkg",
    dst_crs = "EPSG:4326"
  ) |>
  gdal_vector_rasterize(
    output = "output.tif",
    burn = 1
  )

  pipeline <- job$pipeline
  rasterize_job <- pipeline$jobs[[2]]

  # The rasterize job should have input set to temp.gpkg
  expect_true("input" %in% names(rasterize_job$arguments))
  expect_equal(rasterize_job$arguments$input, "temp.gpkg")
})

test_that("pipeline execution handles temp file cleanup", {
  # This test would require mocking file operations
  # For now, just test that the pipeline runs without error
  skip("Requires file system mocking")

  # In a real test, we'd:
  # 1. Create a pipeline that uses temp files
  # 2. Mock tempfile() and file.exists()
  # 3. Verify temp files are created and cleaned up
})

test_that("pipeline execution fails gracefully on errors", {
  # Create a pipeline with invalid arguments
  job <- gdal_raster_info(input = "nonexistent.tif") |>
    gdal_raster_convert(output = "output.jpg")

  # Should fail at first job
  expect_error(
    gdal_run(job),
    "Pipeline failed at job 1"
  )
})

test_that("pipeline with virtual paths doesn't override user outputs", {
  # Test that user-specified outputs are preserved
  job <- gdal_vector_reproject(
    input = "input.shp",
    output = "user_output.gpkg",
    dst_crs = "EPSG:4326"
  ) |>
  gdal_vector_rasterize(
    output = "user_raster.tif",
    burn = 1
  )

  pipeline <- job$pipeline

  # First job should still output to user_output.gpkg
  reproject_job <- pipeline$jobs[[1]]
  expect_equal(reproject_job$arguments$output, "user_output.gpkg")

  # Second job should input from user_output.gpkg and output to user_raster.tif
  rasterize_job <- pipeline$jobs[[2]]
  expect_equal(rasterize_job$arguments$input, "user_output.gpkg")
  expect_equal(rasterize_job$arguments$output, "user_raster.tif")
})

test_that("render_gdal_pipeline creates correct command strings", {
  job <- gdal_raster_info(input = "input.tif") |>
    gdal_raster_convert(output = "output.jpg")

  rendered <- render_gdal_pipeline(job)
  expect_type(rendered, "character")
  expect_true(grepl("gdal raster info", rendered))
  expect_true(grepl("gdal raster convert", rendered))
})

test_that("render_shell_script creates executable script", {
  job <- gdal_raster_info(input = "input.tif") |>
    gdal_raster_convert(output = "output.jpg")

  script <- render_shell_script(job)
  expect_type(script, "character")
  expect_true(grepl("#!/bin/bash", script))
  expect_true(grepl("set -e", script))
  expect_true(grepl("gdal raster info", script))
  expect_true(grepl("gdal raster convert", script))
})

test_that("pipeline metadata can be set and retrieved", {
  job <- gdal_raster_info(input = "input.tif") |>
    gdal_raster_convert(output = "output.jpg")

  # Set metadata
  job <- set_name(job, "Test Pipeline")
  job <- set_description(job, "A test pipeline")

  expect_equal(job$pipeline$name, "Test Pipeline")
  expect_equal(job$pipeline$description, "A test pipeline")
})

test_that("get_jobs returns correct job list", {
  job1 <- gdal_raster_info(input = "input.tif")
  job2 <- gdal_raster_convert(input = "input.tif", output = "output.jpg")

  pipeline <- new_gdal_pipeline(list(job1, job2))
  jobs <- get_jobs(pipeline)

  expect_length(jobs, 2)
  expect_s3_class(jobs[[1]], "gdal_job")
  expect_s3_class(jobs[[2]], "gdal_job")
})

test_that("add_job extends pipeline correctly", {
  job1 <- gdal_raster_info(input = "input.tif")
  job2 <- gdal_raster_convert(input = "input.tif", output = "output.jpg")

  pipeline <- new_gdal_pipeline(list(job1))
  extended <- add_job(pipeline, job2)

  expect_length(extended$jobs, 2)
  expect_equal(extended$jobs[[2]], job2)
})

test_that("empty pipeline renders correctly", {
  pipeline <- new_gdal_pipeline(list())
  expect_length(pipeline$jobs, 0)

  rendered <- render_gdal_pipeline(pipeline)
  expect_equal(rendered, "gdal pipeline")
})

test_that("is_virtual_path correctly identifies virtual paths", {
  expect_true(is_virtual_path("/vsimem/temp.tif"))
  expect_true(is_virtual_path("/vsis3/bucket/key"))
  expect_true(is_virtual_path("/vsizip/archive.zip/file.txt"))

  expect_false(is_virtual_path("regular_file.tif"))
  expect_false(is_virtual_path("/home/user/file.tif"))
  expect_false(is_virtual_path("C:/windows/file.tif"))
})