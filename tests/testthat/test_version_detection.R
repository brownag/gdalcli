# Tests for GDAL Version Detection and Advanced Features Framework

test_that(".gdal_get_version returns a valid version string", {
  version <- gdalcli:::.gdal_get_version()
  expect_type(version, "character")
  expect_length(version, 1)
  # Should be either "unknown" or match pattern X.Y.Z
  if (version != "unknown") {
    expect_match(version, "^[0-9]+\\.[0-9]+\\.[0-9]+$")
  }
})

test_that(".gdal_get_version caches result", {
  gdalcli:::.clear_feature_cache()

  version1 <- gdalcli:::.gdal_get_version()
  cache1 <- gdalcli:::.get_feature_cache()

  version2 <- gdalcli:::.gdal_get_version()
  cache2 <- gdalcli:::.get_feature_cache()

  expect_identical(version1, version2)
  expect_identical(cache1, cache2)
})

test_that(".gdal_has_feature accepts valid feature names", {
  expect_no_error(gdalcli:::.gdal_has_feature("explicit_args"))
  expect_no_error(gdalcli:::.gdal_has_feature("arrow_vectors"))
  expect_no_error(gdalcli:::.gdal_has_feature("gdalg_native"))
})

test_that(".gdal_has_feature returns logical", {
  result_explicit <- gdalcli:::.gdal_has_feature("explicit_args")
  expect_type(result_explicit, "logical")
  expect_length(result_explicit, 1)

  result_arrow <- gdalcli:::.gdal_has_feature("arrow_vectors")
  expect_type(result_arrow, "logical")

  result_gdalg <- gdalcli:::.gdal_has_feature("gdalg_native")
  expect_type(result_gdalg, "logical")
})

test_that(".gdal_has_feature caches results", {
  gdalcli:::.clear_feature_cache()

  # First call populates cache
  result1 <- gdalcli:::.gdal_has_feature("explicit_args")
  cache1 <- length(gdalcli:::.get_feature_cache())

  # Second call uses cache (no new entries added)
  result2 <- gdalcli:::.gdal_has_feature("explicit_args")
  cache2 <- length(gdalcli:::.get_feature_cache())

  expect_identical(result1, result2)
  expect_equal(cache1, cache2)
})

test_that("explicit_args feature detection respects GDAL version", {
  # If GDAL < 3.12, feature should be unavailable
  if (!gdal_check_version("3.12", op = ">=")) {
    expect_false(gdalcli:::.gdal_has_feature("explicit_args"))
  }

  # If GDAL >= 3.12, depends on gdalraster support
  if (gdal_check_version("3.12", op = ">=")) {
    result <- gdalcli:::.gdal_has_feature("explicit_args")
    expect_type(result, "logical")
  }
})

test_that("gdalg_native feature requires GDAL 3.11+", {
  result <- gdalcli:::.gdal_has_feature("gdalg_native")

  if (gdal_check_version("3.11", op = ">=")) {
    # Should be TRUE or FALSE depending on driver availability
    expect_type(result, "logical")
  } else {
    # Must be FALSE for GDAL < 3.11
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
  expect_true(any(grepl("GDAL Advanced Features Report", output)))
  expect_true(any(grepl("Feature Availability", output)))
  expect_true(any(grepl("Dependent Packages", output)))
})

test_that(".clear_feature_cache removes all entries", {
  # Populate cache
  gdalcli:::.gdal_has_feature("explicit_args")
  gdalcli:::.gdal_has_feature("arrow_vectors")

  cache_before <- gdalcli:::.get_feature_cache()
  expect_length(cache_before, 2)  # Both features cached

  # Clear cache
  gdalcli:::.clear_feature_cache()
  cache_after <- gdalcli:::.get_feature_cache()
  expect_length(cache_after, 0)
})

test_that(".get_feature_cache returns list", {
  gdalcli:::.clear_feature_cache()

  cache_empty <- gdalcli:::.get_feature_cache()
  expect_type(cache_empty, "list")
  expect_length(cache_empty, 0)

  gdalcli:::.gdal_has_feature("explicit_args")
  cache_populated <- gdalcli:::.get_feature_cache()
  expect_type(cache_populated, "list")
  expect_length(cache_populated, 1)
})

test_that("version_matrix reflects actual GDAL version", {
  caps <- gdal_capabilities()
  vm <- caps$version_matrix

  # Current version should match environment
  current <- gdal_check_version("3.11", op = ">=")
  expect_equal(vm$is_3_11, current || gdal_check_version("3.12", op = ">="))
})

test_that("feature cache is consistent across calls", {
  gdalcli:::.clear_feature_cache()

  # Multiple calls should return same result
  result1 <- gdalcli:::.gdal_has_feature("explicit_args")
  result2 <- gdalcli:::.gdal_has_feature("explicit_args")
  result3 <- gdalcli:::.gdal_has_feature("explicit_args")

  expect_identical(result1, result2)
  expect_identical(result2, result3)
})
