test_that("Format detection identifies hybrid format", {
  spec <- list(
    gdalg = list(
      type = "gdal_streamed_alg",
      command_line = "gdal raster pipeline ! read input.tif"
    ),
    metadata = list(),
    r_job_specs = list()
  )

  format_type <- .gdalcli_detect_format(spec)
  expect_equal(format_type, "hybrid")
})


test_that("Format detection identifies pure GDALG at root", {
  spec <- list(
    type = "gdal_streamed_alg",
    command_line = "gdal raster pipeline ! read input.tif"
  )

  format_type <- .gdalcli_detect_format(spec)
  expect_equal(format_type, "pure_gdalg")
})


test_that("Format detection identifies legacy format", {
  spec <- list(
    steps = list(
      list(operation = "read", input = "test.tif")
    ),
    name = "test"
  )

  format_type <- .gdalcli_detect_format(spec)
  expect_equal(format_type, "legacy")
})


test_that("Format detection returns unknown for unrecognized format", {
  spec <- list(unknown_field = "value")

  format_type <- .gdalcli_detect_format(spec)
  expect_equal(format_type, "unknown")
})
