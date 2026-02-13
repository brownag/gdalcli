test_that("new_gdalcli_spec creates valid spec object", {
  gdalg <- new_gdalg(
    command_line = "gdal raster pipeline ! read input.tif"
  )

  metadata <- list(
    format_version = "1.0",
    pipeline_name = "Test Pipeline"
  )

  r_job_specs <- list(
    list(
      command_path = c("gdal", "raster", "info"),
      arguments = list(input = "test.tif")
    )
  )

  spec <- new_gdalcli_spec(gdalg, metadata, r_job_specs)

  expect_true(inherits(spec, "gdalcli_spec"))
  expect_true(inherits(spec$gdalg, "gdalg"))
  expect_true(is.list(spec$metadata))
  expect_true(is.list(spec$r_job_specs))
})


test_that("new_gdalcli_spec auto-converts list to gdalg", {
  gdalg_list <- list(
    type = "gdal_streamed_alg",
    command_line = "gdal raster pipeline ! read input.tif"
  )

  spec <- new_gdalcli_spec(gdalg_list)

  expect_true(inherits(spec$gdalg, "gdalg"))
})


test_that("validate_gdalcli_spec rejects invalid specs", {
  # Not a gdalcli_spec object
  expect_error(validate_gdalcli_spec(list()))

  # Invalid gdalg component
  bad_spec <- structure(
    list(
      gdalg = list(),  # Not a gdalg object
      metadata = list(),
      r_job_specs = list()
    ),
    class = c("gdalcli_spec", "list")
  )
  expect_error(validate_gdalcli_spec(bad_spec))
})


test_that("print.gdalcli_spec displays summary", {
  gdalg <- new_gdalg("gdal raster pipeline ! read input.tif")
  spec <- new_gdalcli_spec(
    gdalg,
    list(
      pipeline_name = "Test",
      gdalcli_version = "0.5.0",
      created_at = "2024-01-01",
      custom_tags = list(tag1 = "value1")
    ),
    list(list(command_path = c("gdal", "raster", "info")))
  )

  expect_output(print(spec), "GDALCLI Hybrid Specification")
})


test_that("gdalcli_spec_to_list converts to plain list", {
  gdalg <- new_gdalg("gdal raster pipeline ! read input.tif")
  metadata <- list(format_version = "1.0", pipeline_name = "Test")
  r_job_specs <- list(list(command_path = c("gdal", "raster", "info")))

  spec <- new_gdalcli_spec(gdalg, metadata, r_job_specs)
  list_repr <- gdalcli_spec_to_list(spec)

  expect_true(is.list(list_repr))
  expect_true(is.list(list_repr$gdalg))
  expect_true(is.list(list_repr$metadata))
  expect_true(is.list(list_repr$r_job_specs))
})
