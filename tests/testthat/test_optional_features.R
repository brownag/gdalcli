# Tests for GDAL Version Detection and Optional Features Framework

test_that(".gdal_get_version returns a valid version string", {
  version <- .gdal_get_version()
  expect_type(version, "character")
  expect_length(version, 1)
  # Should be either "unknown" or match pattern X.Y.Z
  if (version != "unknown") {
    expect_match(version, "^[0-9]+\\.[0-9]+\\.[0-9]+$")
  }
})

test_that(".gdal_has_feature accepts valid feature names", {
  expect_no_error(.gdal_has_feature("explicit_args"))
  expect_no_error(.gdal_has_feature("arrow_vectors"))
  expect_no_error(.gdal_has_feature("gdalg_native"))
  expect_no_error(.gdal_has_feature("gdal_commands"))
  expect_no_error(.gdal_has_feature("gdal_usage"))
})

test_that(".gdal_has_feature returns logical", {
  result_explicit <- .gdal_has_feature("explicit_args")
  expect_type(result_explicit, "logical")
  expect_length(result_explicit, 1)

  result_arrow <- .gdal_has_feature("arrow_vectors")
  expect_type(result_arrow, "logical")

  result_gdalg <- .gdal_has_feature("gdalg_native")
  expect_type(result_gdalg, "logical")

  result_commands <- .gdal_has_feature("gdal_commands")
  expect_type(result_commands, "logical")

  result_usage <- .gdal_has_feature("gdal_usage")
  expect_type(result_usage, "logical")
})

test_that("explicit_args feature detection respects GDAL version", {
  # If GDAL < 3.12, feature should be unavailable
  if (!gdal_check_version("3.12", op = ">=")) {
    expect_false(.gdal_has_feature("explicit_args"))
  }

  # If GDAL >= 3.12, depends on gdalraster support
  if (gdal_check_version("3.12", op = ">=")) {
    result <- .gdal_has_feature("explicit_args")
    expect_type(result, "logical")
  }
})

test_that("gdalg_native feature requires GDAL 3.11+", {
  result <- .gdal_has_feature("gdalg_native")

  if (gdal_check_version("3.11", op = ">=")) {
    # Should be TRUE or FALSE depending on driver availability
    expect_type(result, "logical")
  } else {
    # Must be FALSE for GDAL < 3.11
    expect_false(result)
  }
})

test_that("gdal_commands feature requires gdalraster", {
  result <- .gdal_has_feature("gdal_commands")

  if (requireNamespace("gdalraster", quietly = TRUE)) {
    expect_type(result, "logical")
  } else {
    expect_false(result)
  }
})

test_that("gdal_usage feature requires gdalraster", {
  result <- .gdal_has_feature("gdal_usage")

  if (requireNamespace("gdalraster", quietly = TRUE)) {
    expect_type(result, "logical")
  } else {
    expect_false(result)
  }
})

test_that("gdal_capabilities returns structured list", {
  caps <- gdal_capabilities()

  expect_s3_class(caps, "gdal_capabilities")
  expect_named(caps, c("version", "version_matrix", "features", "packages"))

  # Check structure of each element
  expect_type(caps$version, "character")
  expect_type(caps$version_matrix, "list")
  expect_type(caps$features, "list")
  expect_type(caps$packages, "list")
})

test_that("gdal_capabilities version_matrix has correct structure", {
  caps <- gdal_capabilities()
  vm <- caps$version_matrix

  expect_named(vm, c("minimum_required", "current", "is_3_11", "is_3_12", "is_3_13"))
  expect_type(vm$minimum_required, "character")
  expect_type(vm$current, "character")
  expect_type(vm$is_3_11, "logical")
  expect_type(vm$is_3_12, "logical")
  expect_type(vm$is_3_13, "logical")
})

test_that("gdal_capabilities features are logical", {
  caps <- gdal_capabilities()

  expect_type(caps$features$explicit_args, "logical")
  expect_type(caps$features$arrow_vectors, "logical")
  expect_type(caps$features$gdalg_native, "logical")
})

test_that("gdal_capabilities packages list installed versions", {
  caps <- gdal_capabilities()

  expect_named(caps$packages, c("gdalraster", "arrow"))
  expect_type(caps$packages$gdalraster, "character")
  expect_type(caps$packages$arrow, "character")

  # Should either be "not installed" or version string
  for (pkg in c("gdalraster", "arrow")) {
    expect_true(
      caps$packages[[pkg]] == "not installed" ||
        grepl("^[0-9]", caps$packages[[pkg]])
    )
  }
})

test_that("print.gdal_capabilities produces output", {
  caps <- gdal_capabilities()

  # Capture printed output
  output <- capture.output(print(caps))

  expect_type(output, "character")
  expect_true(any(grepl("GDAL Capabilities Report", output)))
  expect_true(any(grepl("Optional Features", output)))
  expect_true(any(grepl("Dependent Packages", output)))
})

test_that("version_matrix reflects actual GDAL version", {
  caps <- gdal_capabilities()
  vm <- caps$version_matrix

  # Current version should match environment
  current <- gdal_check_version("3.11", op = ">=")
  expect_equal(vm$is_3_11, current || gdal_check_version("3.12", op = ">="))
})
