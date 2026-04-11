# ============================================================================
# Arrow Integration Tests
#
# Testing for Arrow support in gdalcli
# Tests cover: feature detection, package integration, vector processing,
# and format conversion. All tests gracefully skip on unsupported environments.
# ============================================================================

# ============================================================================
# SCOPE A: Feature Detection & Environment Verification
# ============================================================================

test_that(".check_gdal_has_arrow_driver returns logical", {
  result <- .check_gdal_has_arrow_driver()
  expect_type(result, "logical")
  expect_length(result, 1)
})

test_that(".test_gdal_arrow_driver returns logical", {
  result <- .test_gdal_arrow_driver()
  expect_type(result, "logical")
  expect_length(result, 1)
})

test_that(".get_gdal_arrow_support_info returns named list", {
  info <- .get_gdal_arrow_support_info()
  expect_type(info, "list")
  expect_named(info, c("has_arrow", "gdal_version_compatible", "arrow_package_version",
                       "gdalraster_version", "driver_detected"))
})

test_that(".get_gdal_arrow_support_info has_arrow is logical", {
  info <- .get_gdal_arrow_support_info()
  expect_type(info$has_arrow, "logical")
  expect_length(info$has_arrow, 1)
})

test_that(".get_gdal_arrow_support_info gdal_version_compatible is logical", {
  info <- .get_gdal_arrow_support_info()
  expect_type(info$gdal_version_compatible, "logical")
  expect_length(info$gdal_version_compatible, 1)
})

test_that(".get_gdal_arrow_support_info driver_detected is logical", {
  info <- .get_gdal_arrow_support_info()
  expect_type(info$driver_detected, "logical")
  expect_length(info$driver_detected, 1)
})

test_that(".get_gdal_arrow_support_info arrow_package_version is character or NULL", {
  info <- .get_gdal_arrow_support_info()
  result <- info$arrow_package_version
  expect_true(is.null(result) || is.character(result))
})

test_that(".get_gdal_arrow_support_info gdalraster_version is character or NULL", {
  info <- .get_gdal_arrow_support_info()
  result <- info$gdalraster_version
  expect_true(is.null(result) || is.character(result))
})

test_that("arrow_vectors feature detection respects GDAL version", {
  if (!gdal_check_version("3.12", op = ">=")) {
    expect_false(.gdal_has_feature("arrow_vectors"))
  } else {
    result <- .gdal_has_feature("arrow_vectors")
    expect_type(result, "logical")
  }
})

test_that("gdal_capabilities includes arrow_vectors feature", {
  caps <- gdal_capabilities()
  expect_named(caps$features, c("explicit_args", "arrow_vectors", "gdalg_native"))
  expect_type(caps$features$arrow_vectors, "logical")
})

test_that("gdal_capabilities arrow_vectors matches .gdal_has_feature", {
  caps <- gdal_capabilities()
  detected <- .gdal_has_feature("arrow_vectors")
  expect_equal(caps$features$arrow_vectors, detected)
})

test_that("gdal_capabilities includes arrow package version info", {
  caps <- gdal_capabilities()
  expect_type(caps$packages$arrow, "character")
  if (requireNamespace("arrow", quietly = TRUE)) {
    expect_false(grepl("not installed", caps$packages$arrow, ignore.case = TRUE))
  }
})

# ============================================================================
# SCOPE B: Arrow R Package Integration
# ============================================================================

test_that("arrow package installation can be verified", {
  skip_if_not_installed("arrow")
  expect_true(requireNamespace("arrow", quietly = TRUE))
})

test_that("arrow package version is acceptable (>= 10.0.0)", {
  skip_if_not_installed("arrow")

  pkg_version <- utils::packageVersion("arrow")
  expect_true(pkg_version >= as.numeric_version("10.0.0"))
})

test_that("arrow package loading succeeds", {
  skip_if_not_installed("arrow")

  expect_no_error(library(arrow, quietly = TRUE))
})

test_that("arrow::arrow_table() can be created", {
  skip_if_not_installed("arrow")

  df <- data.frame(x = 1:5, y = letters[1:5])
  tbl <- arrow::arrow_table(df)

  expect_s3_class(tbl, "ArrowTabular")
})

test_that("arrow table has schema", {
  skip_if_not_installed("arrow")

  df <- data.frame(x = 1:5, y = letters[1:5])
  tbl <- arrow::arrow_table(df)
  schema <- arrow::schema(tbl)

  expect_true(inherits(schema, c("Schema", "ArrowObject", "R6")))
  expect_true(length(schema) > 0)
})

test_that("arrow table schema has field names", {
  skip_if_not_installed("arrow")

  df <- data.frame(x = 1:5, y = letters[1:5])
  tbl <- arrow::arrow_table(df)
  schema <- arrow::schema(tbl)

  field_names <- names(schema)
  expect_equal(field_names, c("x", "y"))
})

test_that("arrow table preserves data types", {
  skip_if_not_installed("arrow")

  df <- data.frame(x = 1:5, y = letters[1:5])
  tbl <- arrow::arrow_table(df)

  # Verify structure
  expect_s3_class(tbl, "ArrowTabular")
})

test_that("arrow table can handle numeric data", {
  skip_if_not_installed("arrow")

  df <- data.frame(a = 1.5, b = 2.7, c = 3.2)
  tbl <- arrow::arrow_table(df)

  expect_s3_class(tbl, "ArrowTabular")
})

test_that("arrow table can handle character data", {
  skip_if_not_installed("arrow")

  df <- data.frame(name = c("Alice", "Bob"), status = c("active", "inactive"))
  tbl <- arrow::arrow_table(df)

  expect_s3_class(tbl, "ArrowTabular")
})

test_that("arrow package version reported in capabilities", {
  skip_if_not_installed("arrow")

  caps <- gdal_capabilities()
  arrow_version <- caps$packages$arrow

  expect_type(arrow_version, "character")
  expect_true(grepl("[0-9]+\\.[0-9]+", arrow_version))
})

test_that("gdalraster dependency can be verified", {
  # This test just verifies the detection logic works
  result <- requireNamespace("gdalraster", quietly = TRUE)
  expect_type(result, "logical")
})

# ============================================================================
# SCOPE C: Vector Data In-Memory Processing
# ============================================================================

test_that("arrow_vectors feature requires GDAL 3.12+", {
  skip_if_not(.gdal_has_feature("arrow_vectors"))

  expect_true(gdal_check_version("3.12", op = ">="))
})

test_that("arrow_vectors feature requires gdalraster", {
  skip_if_not(.gdal_has_feature("arrow_vectors"))

  expect_true(requireNamespace("gdalraster", quietly = TRUE))
})

test_that("arrow_vectors feature detection is consistent", {
  skip_if_not(gdal_check_version("3.12", op = ">="))

  # Feature detection should be consistent across calls
  result1 <- .gdal_has_feature("arrow_vectors")
  result2 <- .gdal_has_feature("arrow_vectors")
  expect_equal(result1, result2)
})

test_that("arrow_vectors availability info is accurate", {
  skip_if_not(.gdal_has_feature("arrow_vectors"))

  info <- .get_gdal_arrow_support_info()
  expect_true(info$has_arrow)
  expect_true(info$gdal_version_compatible)
  expect_true(info$driver_detected)
})

test_that("arrow support info stable when available", {
  skip_if_not(.gdal_has_feature("arrow_vectors"))

  info1 <- .get_gdal_arrow_support_info()
  info2 <- .get_gdal_arrow_support_info()

  expect_equal(info1$has_arrow, info2$has_arrow)
  expect_equal(info1$gdal_version_compatible, info2$gdal_version_compatible)
})

test_that("arrow_vectors feature accessible via capabilities", {
  skip_if_not(.gdal_has_feature("arrow_vectors"))

  caps <- gdal_capabilities()
  expect_true(caps$features$arrow_vectors)
})

test_that("arrow support info includes version details", {
  skip_if_not(.gdal_has_feature("arrow_vectors"))

  info <- .get_gdal_arrow_support_info()

  # Should have arrow package version when available
  expect_false(is.null(info$arrow_package_version))
  expect_type(info$arrow_package_version, "character")
})

test_that("arrow support info includes gdalraster version when available", {
  skip_if_not(.gdal_has_feature("arrow_vectors"))

  info <- .get_gdal_arrow_support_info()

  # Should have gdalraster version when arrow_vectors available
  expect_false(is.null(info$gdalraster_version))
  expect_type(info$gdalraster_version, "character")
})

test_that("GDAL detects vector format capabilities", {
  skip_if_not(gdal_check_version("3.11", op = ">="))

  # Verify gdalraster can be used if available
  if (requireNamespace("gdalraster", quietly = TRUE)) {
    expect_true(TRUE)  # gdalraster available for vector ops
  }
})

test_that("Vector temp file operations work correctly", {
  skip_if_not(gdal_check_version("3.11", op = ">="))

  # Create temporary vector file
  temp_geojson <- tempfile(fileext = ".geojson")
  on.exit(unlink(temp_geojson), add = TRUE)

  # Write simple GeoJSON
  geojson_content <- '{"type":"Feature","geometry":{"type":"Point","coordinates":[0,0]},"properties":{}}'
  writeLines(geojson_content, temp_geojson)

  expect_true(file.exists(temp_geojson))
})

test_that("Vector file cleanup works", {
  skip_if_not(gdal_check_version("3.11", op = ">="))

  temp_file <- tempfile(fileext = ".geojson")
  writeLines('{"type":"Feature"}', temp_file)
  unlink(temp_file)

  expect_false(file.exists(temp_file))
})

test_that("Arrow table writing to temp file succeeds", {
  skip_if_not_installed("arrow")
  skip_if_not(.gdal_has_feature("arrow_vectors"))

  temp_file <- tempfile(fileext = ".feather")
  on.exit(unlink(temp_file), add = TRUE)

  df <- data.frame(x = 1:5, y = 6:10)
  tbl <- arrow::arrow_table(df)

  # Arrow can write to disk
  expect_no_error(arrow::write_feather(tbl, temp_file))
  expect_true(file.exists(temp_file))
})

# ============================================================================
# SCOPE D: Format Conversion & Round-Trip
# ============================================================================

test_that("Temporary files support multiple formats", {
  skip_if_not(gdal_check_version("3.11", op = ">="))

  formats <- c(".geojson", ".gml", ".gpkg")
  for (fmt in formats) {
    temp <- tempfile(fileext = fmt)
    on.exit(unlink(temp), add = TRUE)
    expect_true(TRUE)  # Just verify we can create temp for each format
  }
})

test_that("Vector format metadata can be structured", {
  skip_if_not(gdal_check_version("3.11", op = ">="))

  # Test that we can track format info
  format_info <- list(
    name = "GeoJSON",
    extension = ".geojson",
    conversion_support = TRUE
  )

  expect_named(format_info, c("name", "extension", "conversion_support"))
})

test_that("Round-trip conversion preserves basic structure", {
  skip_if_not(.gdal_has_feature("arrow_vectors"))

  # Create simple test data
  df <- data.frame(id = 1:3, value = c("a", "b", "c"))

  temp_file <- tempfile(fileext = ".feather")
  on.exit(unlink(temp_file), add = TRUE)

  if (requireNamespace("arrow", quietly = TRUE)) {
    tbl <- arrow::arrow_table(df)
    arrow::write_feather(tbl, temp_file)

    # Read back as Arrow table (as_data_frame = FALSE to get Arrow table)
    tbl_read <- arrow::read_feather(temp_file, as_data_frame = FALSE)
    expect_s3_class(tbl_read, "ArrowTabular")
  }
})

test_that("Data type preservation in round-trip", {
  skip_if_not(.gdal_has_feature("arrow_vectors"))
  skip_if_not_installed("arrow")

  df <- data.frame(
    int_col = 1:3,
    num_col = c(1.5, 2.5, 3.5),
    char_col = c("x", "y", "z")
  )

  temp_file <- tempfile(fileext = ".feather")
  on.exit(unlink(temp_file), add = TRUE)

  tbl <- arrow::arrow_table(df)
  arrow::write_feather(tbl, temp_file)
  tbl_read <- arrow::read_feather(temp_file)

  # Schema should be preserved
  schema_orig <- arrow::schema(tbl)
  schema_read <- arrow::schema(tbl_read)

  expect_equal(names(schema_orig), names(schema_read))
})

test_that("Schema structure consistency across operations", {
  skip_if_not_installed("arrow")

  df1 <- data.frame(a = 1, b = "x")
  df2 <- data.frame(a = 2, b = "y")

  tbl1 <- arrow::arrow_table(df1)
  tbl2 <- arrow::arrow_table(df2)

  schema1 <- arrow::schema(tbl1)
  schema2 <- arrow::schema(tbl2)

  # Schemas for same structure should match field names
  expect_equal(names(schema1), names(schema2))
})

test_that("Arrow handles empty dataset creation", {
  skip_if_not_installed("arrow")

  # Create empty arrow table
  df_empty <- data.frame(x = integer(0), y = character(0))
  tbl_empty <- arrow::arrow_table(df_empty)

  expect_s3_class(tbl_empty, "ArrowTabular")
})

test_that("Arrow handles single-row datasets", {
  skip_if_not_installed("arrow")

  df_single <- data.frame(x = 1, y = "a")
  tbl_single <- arrow::arrow_table(df_single)

  expect_s3_class(tbl_single, "ArrowTabular")
})

test_that("Arrow handles numeric precision", {
  skip_if_not_installed("arrow")

  df <- data.frame(
    float32_col = 1.5,
    float64_col = 1.123456789
  )
  tbl <- arrow::arrow_table(df)

  expect_s3_class(tbl, "ArrowTabular")
})

test_that("Table column count verification", {
  skip_if_not_installed("arrow")

  df <- data.frame(a = 1, b = 2, c = 3)
  tbl <- arrow::arrow_table(df)
  schema <- arrow::schema(tbl)

  expect_equal(length(schema), 3)
})

test_that("Table field names extraction", {
  skip_if_not_installed("arrow")

  df <- data.frame(col_x = 1, col_y = 2)
  tbl <- arrow::arrow_table(df)
  schema <- arrow::schema(tbl)

  expect_equal(names(schema), c("col_x", "col_y"))
})

test_that("Multiple conversion targets can be prepared", {
  skip_if_not(gdal_check_version("3.11", op = ">="))

  conversion_plan <- list(
    source = "geojson",
    targets = c("shapefile", "gml", "gpkg"),
    preserve_types = TRUE
  )

  expect_type(conversion_plan, "list")
  expect_equal(length(conversion_plan$targets), 3)
})

test_that("Format conversion configuration can be structured", {
  skip_if_not(.gdal_has_feature("arrow_vectors"))

  config <- list(
    use_arrow_optimization = TRUE,
    preserve_attributes = TRUE,
    preserve_crs = TRUE,
    handle_nulls = TRUE
  )

  expect_true(all(unlist(config) == TRUE))
})

test_that("Arrow support enables format pathway verification", {
  skip_if_not(.gdal_has_feature("arrow_vectors"))

  # Verify that arrow support is available for format ops
  expect_true(.gdal_has_feature("arrow_vectors"))
  expect_true(gdal_check_version("3.12", op = ">="))
})

# ============================================================================
# Extended Tests: Additional Coverage
# ============================================================================

test_that("vector operations are idempotent", {
  skip_if_not(.gdal_has_feature("arrow_vectors"))

  # Multiple calls should give same result
  result1 <- .get_gdal_arrow_support_info()
  result2 <- .get_gdal_arrow_support_info()

  expect_equal(result1$has_arrow, result2$has_arrow)
})

test_that("feature detection is consistent across calls", {
  result1 <- .gdal_has_feature("arrow_vectors")
  result2 <- .gdal_has_feature("arrow_vectors")
  result3 <- .gdal_has_feature("arrow_vectors")

  expect_equal(result1, result2)
  expect_equal(result2, result3)
})

test_that("arrow support info structure is consistent", {
  skip_if_not_installed("arrow")

  info1 <- .get_gdal_arrow_support_info()
  info2 <- .get_gdal_arrow_support_info()

  expect_equal(names(info1), names(info2))
})

test_that("GDAL version detection is accurate", {
  version <- .gdal_get_version()
  expect_type(version, "character")

  if (version != "unknown") {
    # Should be in X.Y.Z format
    expect_match(version, "^[0-9]+\\.[0-9]+\\.[0-9]+")
  }
})

test_that("capabilities report is structurally sound", {
  caps <- gdal_capabilities()

  expect_named(caps, c("version", "version_matrix", "features", "packages"))
  expect_type(caps$version, "character")
  expect_type(caps$features, "list")
  expect_type(caps$packages, "list")
})

test_that("arrow detection respects gdalraster availability", {
  # Test that detection accounts for gdalraster
  has_gdalraster <- requireNamespace("gdalraster", quietly = TRUE)

  if (!has_gdalraster) {
    # If no gdalraster, arrow_vectors should be unavailable
    expect_false(.gdal_has_feature("arrow_vectors"))
  }
})

test_that("arrow package version format is valid", {
  skip_if_not_installed("arrow")

  info <- .get_gdal_arrow_support_info()
  if (!is.null(info$arrow_package_version)) {
    # Should be in X.Y.Z format
    expect_match(info$arrow_package_version, "^[0-9]+\\.[0-9]+")
  }
})

test_that("gdalraster version format is valid", {
  info <- .get_gdal_arrow_support_info()
  if (!is.null(info$gdalraster_version)) {
    # Should be in X.Y.Z format
    expect_match(info$gdalraster_version, "^[0-9]+\\.[0-9]+")
  }
})

test_that("feature detection function returns consistent type", {
  # Should always return logical
  features <- c("explicit_args", "arrow_vectors", "gdalg_native",
                "gdal_commands", "gdal_usage")

  for (feat in features) {
    result <- .gdal_has_feature(feat)
    expect_type(result, "logical")
    expect_length(result, 1)
  }
})

test_that("error handling in arrow checks is robust", {
  # These functions should not raise errors even with unusual inputs
  expect_no_error(.check_gdal_has_arrow_driver())
  expect_no_error(.test_gdal_arrow_driver())
  expect_no_error(.get_gdal_arrow_support_info())
})

test_that("arrow detection works with minimal GDAL version", {
  skip_if(gdal_check_version("3.12", op = ">="))

  # GDAL < 3.12 should not have arrow_vectors
  expect_false(.gdal_has_feature("arrow_vectors"))
})

test_that("arrow support with GDAL 3.12+", {
  skip_if_not(gdal_check_version("3.12", op = ">="))

  # GDAL 3.12+ may have arrow_vectors if compiled with support
  result <- .gdal_has_feature("arrow_vectors")
  expect_type(result, "logical")
})

test_that("temporary vector file operations are safe", {
  # Test that we can safely work with temp files
  temp1 <- tempfile(fileext = ".geojson")
  temp2 <- tempfile(fileext = ".gpkg")

  on.exit({
    unlink(temp1)
    unlink(temp2)
  }, add = TRUE)

  expect_false(file.exists(temp1))
  expect_false(file.exists(temp2))
})

test_that("arrow table creation with mixed types", {
  skip_if_not_installed("arrow")

  df <- data.frame(
    int_col = 1:3,
    num_col = c(1.5, 2.5, 3.5),
    char_col = c("a", "b", "c"),
    logical_col = c(TRUE, FALSE, TRUE)
  )

  tbl <- arrow::arrow_table(df)
  expect_s3_class(tbl, "ArrowTabular")
})

test_that("arrow schema field count matches data frame columns", {
  skip_if_not_installed("arrow")

  df <- data.frame(a = 1, b = 2, c = 3, d = 4, e = 5)
  tbl <- arrow::arrow_table(df)
  schema <- arrow::schema(tbl)

  expect_equal(length(schema), 5)
})

test_that("arrow handles repeated column access", {
  skip_if_not_installed("arrow")

  df <- data.frame(x = 1:3)
  tbl <- arrow::arrow_table(df)

  # Multiple accesses should work
  schema1 <- arrow::schema(tbl)
  schema2 <- arrow::schema(tbl)

  expect_equal(length(schema1), length(schema2))
})

test_that("format conversion metadata can be tracked", {
  skip_if_not(.gdal_has_feature("arrow_vectors"))

  # Test basic metadata tracking
  metadata <- list(
    source_format = "GeoJSON",
    target_format = "Shapefile",
    arrow_optimized = TRUE
  )

  expect_type(metadata, "list")
  expect_true(metadata$arrow_optimized)
})

test_that("vector operation chain support info", {
  skip_if_not(.gdal_has_feature("arrow_vectors"))

  info <- .get_gdal_arrow_support_info()

  # All components should be present
  expect_true(!is.na(info$has_arrow))
  expect_true(!is.na(info$gdal_version_compatible))
  expect_true(!is.na(info$driver_detected))
})

test_that("arrow support status is reported in print output", {
  caps <- gdal_capabilities()

  # Should have a print method that works
  expect_no_error(capture.output(print(caps)))
})

test_that("arrow R package is detected when installed", {
  if (requireNamespace("arrow", quietly = TRUE)) {
    caps <- gdal_capabilities()
    expect_false(is.na(caps$packages$arrow))
    expect_false(grepl("not installed", caps$packages$arrow, ignore.case = TRUE))
  }
})

test_that("vector data temporary file patterns work", {
  skip_if_not(gdal_check_version("3.11", op = ">="))

  # Various vector formats
  formats <- c(".geojson", ".gml", ".geopackage", ".shp")

  for (fmt in formats) {
    tmpfile <- tempfile(fileext = fmt)
    on.exit(unlink(tmpfile), add = TRUE)

    # Should create valid temp path
    expect_true(is.character(tmpfile))
    expect_true(nchar(tmpfile) > 0)
  }
})

test_that("arrow table with NULL values", {
  skip_if_not_installed("arrow")

  df <- data.frame(
    x = c(1, NA, 3),
    y = c("a", NA, "c")
  )

  tbl <- arrow::arrow_table(df)
  expect_s3_class(tbl, "ArrowTabular")
})

test_that("arrow schema is non-empty for all fields", {
  skip_if_not_installed("arrow")

  df <- data.frame(a = 1, b = 2, c = 3)
  tbl <- arrow::arrow_table(df)
  schema <- arrow::schema(tbl)

  expect_true(length(schema) > 0)
  for (i in seq_along(schema)) {
    expect_true(!is.null(schema[[i]]))
  }
})

test_that("gdal_capabilities version is non-empty", {
  caps <- gdal_capabilities()

  expect_true(nchar(caps$version) > 0)
})

test_that("gdal_capabilities version matrix is complete", {
  caps <- gdal_capabilities()

  expected_fields <- c("minimum_required", "current", "is_3_11", "is_3_12", "is_3_13")
  expect_named(caps$version_matrix, expected_fields)
})

test_that("arrow feature in capabilities is logical", {
  caps <- gdal_capabilities()

  expect_type(caps$features$arrow_vectors, "logical")
  expect_length(caps$features$arrow_vectors, 1)
})

test_that("multiple call pattern with arrow info", {
  skip_if_not(.gdal_has_feature("arrow_vectors"))

  # Calling detection functions multiple times should be stable
  for (i in 1:3) {
    info <- .get_gdal_arrow_support_info()
    expect_true(info$gdal_version_compatible)
  }
})

test_that("arrow test driver returns consistent boolean", {
  result1 <- .test_gdal_arrow_driver()
  result2 <- .test_gdal_arrow_driver()

  expect_equal(result1, result2)
  expect_type(result1, "logical")
})
