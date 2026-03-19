test_that("step mappings are loaded at package startup", {
  # Mappings should be initialized in environment by .onLoad
  expect_false(is.null(.gdalcli_env$step_mappings))
  expect_true(is.list(.gdalcli_env$step_mappings))
})


test_that("step_mappings has expected modules", {
  mappings <- .gdalcli_env$step_mappings
  expect_true("raster" %in% names(mappings))
  expect_true("vector" %in% names(mappings))
})


test_that(".get_step_mapping returns correct mappings for raster operations", {
  # Test known raster write operations
  expect_equal(.get_step_mapping("raster", "convert"), "write")
  expect_equal(.get_step_mapping("raster", "create"), "write")
  expect_equal(.get_step_mapping("raster", "tile"), "write")

  # Test known raster read operations
  expect_equal(.get_step_mapping("raster", "info"), "read")

  # Test known raster transformation operations
  expect_equal(.get_step_mapping("raster", "reproject"), "reproject")
  expect_equal(.get_step_mapping("raster", "clip"), "clip")
  expect_equal(.get_step_mapping("raster", "calc"), "calc")
})


test_that(".get_step_mapping returns correct mappings for vector operations", {
  # Test known vector write operations
  expect_equal(.get_step_mapping("vector", "convert"), "write")

  # Test known vector read operations
  expect_equal(.get_step_mapping("vector", "info"), "read")

  # Test known vector transformation operations
  expect_equal(.get_step_mapping("vector", "reproject"), "reproject")
  expect_equal(.get_step_mapping("vector", "clip"), "clip")
  expect_equal(.get_step_mapping("vector", "filter"), "filter")
})


test_that(".get_step_mapping returns operation name as fallback for unknown operations", {
  # For unknown operations, should return the operation name itself
  expect_equal(.get_step_mapping("raster", "unknown_op_xyz"), "unknown_op_xyz")
  expect_equal(.get_step_mapping("vector", "unknown_op_abc"), "unknown_op_abc")
})


test_that(".get_step_mapping returns operation name for unknown modules", {
  # For unknown modules, should return the operation name itself
  expect_equal(.get_step_mapping("unknown_module", "operation"), "operation")
})


test_that("step mappings are used correctly in pipeline building", {
  # Create a simple raster pipeline with multiple operations
  pipeline <- gdal_raster_reproject(
    input = "test.tif",
    dst_crs = "EPSG:4326"
  ) |>
    gdal_raster_convert(output = "output.tif")

  # Build the native pipeline string
  native_str <- render_gdal_pipeline(pipeline, format = "native")

  # The pipeline should use the mapped step names
  # "reproject" operation should map to "reproject" step (no change)
  expect_true(grepl("! reproject", native_str))

  # "convert" operation should map to "write" step
  expect_true(grepl("! write", native_str))
})


test_that("step mapping fallback works when mappings file is missing", {
  # This tests the .get_default_step_mappings() function
  defaults <- .get_default_step_mappings()

  expect_true(is.list(defaults))
  expect_true("raster" %in% names(defaults))
  expect_true("vector" %in% names(defaults))

  # Check specific mappings
  expect_equal(defaults$raster["convert"], c(convert = "write"))
  expect_equal(defaults$raster["info"], c(info = "read"))
  expect_equal(defaults$vector["convert"], c(convert = "write"))
  expect_equal(defaults$vector["info"], c(info = "read"))
})


test_that("all critical raster mappings are present", {
  critical_ops <- c("convert", "info", "reproject", "clip", "calc")

  for (op in critical_ops) {
    mapping <- .get_step_mapping("raster", op)
    expect_false(is.null(mapping))
    expect_true(is.character(mapping))
    expect_true(length(mapping) > 0)
  }
})


test_that("all critical vector mappings are present", {
  critical_ops <- c("convert", "info", "reproject", "clip")

  for (op in critical_ops) {
    mapping <- .get_step_mapping("vector", op)
    expect_false(is.null(mapping))
    expect_true(is.character(mapping))
    expect_true(length(mapping) > 0)
  }
})


test_that("step mappings are consistent for duplicate operation names", {
  # Some operations may have multiple names (e.g., "fill-nodata" vs "fill_nodata")
  # If both are present, they should map to the same step

  # Get current mappings
  mappings <- .gdalcli_env$step_mappings
  if (!is.null(mappings$raster)) {
    if ("fill_nodata" %in% names(mappings$raster) &&
        "fill-nodata" %in% names(mappings$raster)) {
      m1 <- .get_step_mapping("raster", "fill_nodata")
      m2 <- .get_step_mapping("raster", "fill-nodata")
      expect_equal(m1, m2)
    }

    # Test clean_collar variants if present
    if ("clean_collar" %in% names(mappings$raster) &&
        "clean-collar" %in% names(mappings$raster)) {
      m1 <- .get_step_mapping("raster", "clean_collar")
      m2 <- .get_step_mapping("raster", "clean-collar")
      expect_equal(m1, m2)
    }
  }
})
