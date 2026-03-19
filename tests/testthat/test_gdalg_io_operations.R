test_that("gdalg_write and gdalg_read round-trip", {
  gdalg <- new_gdalg(
    command_line = "gdal raster pipeline ! read input.tif ! reproject --dst-crs EPSG:3857"
  )

  # Write to temporary file
  tmpfile <- tempfile(fileext = ".gdalg.json")
  on.exit(unlink(tmpfile), add = TRUE)

  result_path <- gdalg_write(gdalg, tmpfile)

  expect_true(file.exists(tmpfile))
  expect_equal(result_path, tmpfile)

  # Read back
  loaded_gdalg <- gdalg_read(tmpfile)

  expect_true(inherits(loaded_gdalg, "gdalg"))
  expect_equal(loaded_gdalg$type, gdalg$type)
  expect_equal(loaded_gdalg$command_line, gdalg$command_line)
})


test_that("gdalg_write rejects overwrite without permission", {
  gdalg <- new_gdalg("gdal raster pipeline ! read input.tif")

  tmpfile <- tempfile(fileext = ".gdalg.json")
  on.exit(unlink(tmpfile), add = TRUE)

  # Write first time
  gdalg_write(gdalg, tmpfile)

  # Try to overwrite without permission
  expect_error(
    gdalg_write(gdalg, tmpfile, overwrite = FALSE),
    "File already exists"
  )

  # Overwrite with permission
  result <- gdalg_write(gdalg, tmpfile, overwrite = TRUE)
  expect_true(file.exists(result))
})


test_that("gdalg_read rejects non-existent files", {
  expect_error(
    gdalg_read("/nonexistent/path/file.gdalg.json"),
    "File not found"
  )
})


test_that("gdalg_read rejects invalid JSON", {
  tmpfile <- tempfile(fileext = ".gdalg.json")
  on.exit(unlink(tmpfile), add = TRUE)

  writeLines("{ invalid json }", tmpfile)

  expect_error(
    gdalg_read(tmpfile),
    "Failed to parse GDALG JSON"
  )
})


test_that("gdalg_read rejects invalid GDALG spec", {
  tmpfile <- tempfile(fileext = ".gdalg.json")
  on.exit(unlink(tmpfile), add = TRUE)

  # Valid JSON but missing required fields
  writeLines('{"type": "wrong_type"}', tmpfile)

  expect_error(
    gdalg_read(tmpfile),
    "Invalid GDALG specification"
  )
})


test_that("Pretty printing is applied by default", {
  gdalg <- new_gdalg("gdal raster pipeline ! read input.tif")

  tmpfile <- tempfile(fileext = ".gdalg.json")
  on.exit(unlink(tmpfile), add = TRUE)

  gdalg_write(gdalg, tmpfile, pretty = TRUE)

  content <- readLines(tmpfile)

  # Pretty-printed JSON should have multiple lines
  expect_gt(length(content), 1)
})
