# Tests for GDALG Format Driver Native Serialization Support

test_that("gdal_has_gdalg_driver detects driver availability", {
  # Test that function returns a logical value
  result <- gdal_has_gdalg_driver()
  expect_type(result, "logical")
  expect_length(result, 1)
})

test_that("gdal_save_pipeline_native requires valid pipeline", {
  skip_if_not(gdal_has_gdalg_driver(), "GDALG driver not available")

  # Error on invalid pipeline
  expect_error(
    gdal_save_pipeline_native("not a pipeline", tempfile()),
    "pipeline must be a gdal_pipeline"
  )
})

test_that("gdal_save_pipeline method parameter is functional", {
  # Test that method parameter exists and can be set
  temp_json <- tempfile(fileext = ".gdalcli.json")
  on.exit(unlink(temp_json), add = TRUE)

  # Create a minimal pipeline for testing
  pipeline <- new_gdal_pipeline(
    jobs = list(
      new_gdal_job(
        command_path = c("raster", "info"),
        arguments = list(input = "test.tif")
      )
    )
  )

  # method="json" should work (backward compatible)
  expect_no_error(
    gdal_save_pipeline(pipeline, temp_json, method = "json")
  )
  expect_true(file.exists(temp_json))

  # Verify it's valid JSON
  gdalg_data <- jsonlite::read_json(temp_json)
  expect_type(gdalg_data, "list")
})

test_that("gdal_save_pipeline auto-detection works", {
  temp_auto <- tempfile(fileext = ".gdalcli.json")
  on.exit(unlink(temp_auto), add = TRUE)

  pipeline <- new_gdal_pipeline(
    jobs = list(
      new_gdal_job(
        command_path = c("raster", "info"),
        arguments = list(input = "test.tif")
      )
    )
  )

  # Auto method should work without errors
  expect_no_error(
    gdal_save_pipeline(pipeline, temp_auto, method = "auto")
  )
  expect_true(file.exists(temp_auto))
})

test_that("gdal_save_pipeline preserves backward compatibility", {
  temp_old <- tempfile(fileext = ".gdalcli.json")
  on.exit(unlink(temp_old), add = TRUE)

  pipeline <- new_gdal_pipeline(
    jobs = list(
      new_gdal_job(
        command_path = c("raster", "info"),
        arguments = list(input = "test.tif")
      )
    )
  )

  # Old code without method parameter should work
  expect_no_error(
    gdal_save_pipeline(pipeline, temp_old)
  )
  expect_true(file.exists(temp_old))

  # Verify it's valid JSON
  gdalg_data <- jsonlite::read_json(temp_old)
  expect_type(gdalg_data, "list")
})
