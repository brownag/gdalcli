test_that("new_gdalg creates valid gdalg object", {
  gdalg <- new_gdalg(
    command_line = "gdal raster pipeline ! read input.tif ! reproject --dst-crs EPSG:3857",
    type = "gdal_streamed_alg",
    relative_paths = TRUE
  )

  expect_true(inherits(gdalg, "gdalg"))
  expect_equal(gdalg$type, "gdal_streamed_alg")
  expect_true(is.character(gdalg$command_line))
  expect_true(gdalg$relative_paths_relative_to_this_file)
})


test_that("validate_gdalg rejects invalid gdalg objects", {
  # Not a gdalg object
  expect_error(validate_gdalg(list(command_line = "test")))

  # Missing type
  bad_gdalg <- structure(
    list(command_line = "test"),
    class = c("gdalg", "list")
  )
  expect_error(validate_gdalg(bad_gdalg))

  # Wrong type value
  bad_gdalg <- structure(
    list(
      type = "wrong_type",
      command_line = "test"
    ),
    class = c("gdalg", "list")
  )
  expect_error(validate_gdalg(bad_gdalg))
})


test_that("print.gdalg works without error", {
  gdalg <- new_gdalg(
    command_line = "gdal raster pipeline ! read input.tif"
  )

  expect_output(print(gdalg), "GDALG RFC 104 Specification")
})


test_that("as_gdalg converts plain list to gdalg", {
  spec_list <- list(
    type = "gdal_streamed_alg",
    command_line = "gdal raster pipeline ! read input.tif",
    relative_paths_relative_to_this_file = TRUE
  )

  gdalg <- as_gdalg(spec_list)

  expect_true(inherits(gdalg, "gdalg"))
  expect_equal(gdalg$command_line, spec_list$command_line)
})


test_that("gdalg_to_list converts gdalg to plain list", {
  gdalg <- new_gdalg(
    command_line = "gdal raster pipeline ! read input.tif"
  )

  list_repr <- gdalg_to_list(gdalg)

  expect_true(is.list(list_repr))
  expect_equal(list_repr$type, "gdal_streamed_alg")
  expect_equal(list_repr$command_line, gdalg$command_line)
})
