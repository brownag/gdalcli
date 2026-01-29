# Tests for GDALG Format Driver Native Serialization Support

test_that("gdal_has_gdalg_driver detects driver availability", {
  # Test that function returns a logical value
  result <- gdal_has_gdalg_driver()
  expect_type(result, "logical")
  expect_length(result, 1)
})


test_that("gdalg_write creates valid JSON file", {
  # Create a valid gdalg object
  gdalg <- new_gdalg("gdal raster pipeline ! read test.tif")

  tmpfile <- tempfile(fileext = ".gdalg.json")
  on.exit(unlink(tmpfile), add = TRUE)

  # gdalg_write uses pure R JSON generation
  expect_no_error(
    gdalg_write(gdalg, tmpfile, overwrite = TRUE)
  )

  # Verify file was created
  expect_true(file.exists(tmpfile))
})

test_that("gdalg_write creates valid GDALG JSON via GDAL", {
  skip_if_not(gdal_has_gdalg_driver(), "GDALG driver not available")

  gdalg <- new_gdalg("gdal raster pipeline ! read test.tif ! reproject --dst-crs EPSG:4326")

  tmpfile <- tempfile(fileext = ".gdalg.json")
  on.exit(unlink(tmpfile), add = TRUE)

  result <- gdalg_write(gdalg, tmpfile, overwrite = TRUE)
  expect_equal(result, tmpfile)

  # File should exist
  expect_true(file.exists(tmpfile))

  # File should contain valid JSON
  json_data <- jsonlite::read_json(tmpfile)
  expect_type(json_data, "list")

  expect_true(!is.null(json_data$type))
  expect_true(!is.null(json_data$command_line))
  expect_equal(json_data$type, "gdal_streamed_alg")
})

test_that("gdalg_write round-trip loads correctly with gdalg_read", {
  skip_if_not(gdal_has_gdalg_driver(), "GDALG driver not available")

  original_gdalg <- new_gdalg(
    "gdal raster pipeline ! read test.tif ! reproject --dst-crs EPSG:4326",
    relative_paths = TRUE
  )

  tmpfile <- tempfile(fileext = ".gdalg.json")
  on.exit(unlink(tmpfile), add = TRUE)

  # Write via GDAL
  gdalg_write(original_gdalg, tmpfile, overwrite = TRUE)

  # Read back
  loaded_gdalg <- gdalg_read(tmpfile)
  expect_s3_class(loaded_gdalg, "gdalg")
  expect_equal(loaded_gdalg$command_line, original_gdalg$command_line)
  expect_equal(loaded_gdalg$type, "gdal_streamed_alg")
})

test_that("gdalg_write refuses overwrite without permission", {
  skip_if_not(gdal_has_gdalg_driver(), "GDALG driver not available")

  gdalg <- new_gdalg("gdal raster pipeline ! read test.tif")

  tmpfile <- tempfile(fileext = ".gdalg.json")
  on.exit(unlink(tmpfile), add = TRUE)

  # Write first time
  gdalg_write(gdalg, tmpfile, overwrite = TRUE)
  expect_true(file.exists(tmpfile))

  # Try to overwrite without permission
  expect_error(
    gdalg_write(gdalg, tmpfile, overwrite = FALSE),
    "File already exists"
  )

  # Overwrite with permission should work
  expect_no_error(
    gdalg_write(gdalg, tmpfile, overwrite = TRUE)
  )
})

test_that("gdal_save_pipeline_native requires valid pipeline", {
  skip_if_not(gdal_has_gdalg_driver(), "GDALG driver not available")

  # Error on invalid pipeline
  expect_error(
    gdal_save_pipeline_native("not a pipeline", tempfile()),
    "Expected gdal_pipeline or gdal_job"
  )
})

