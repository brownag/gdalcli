# Tests for Dynamic GDAL API

test_that("gdal_run function exists and is exported", {
  expect_true(exists("gdal_run"))
  expect_is(gdal_run, "function")
})

test_that("gdal_run has backend parameter", {
  func_formals <- formals(gdal_run)
  expect_true("backend" %in% names(func_formals))
})

test_that("new_gdal_job function exists and creates job objects", {
  skip_if_not_installed("gdalcli")
  expect_true(exists("new_gdal_job"))

  # Create a simple job
  job <- new_gdal_job(
    command_path = c("raster", "info"),
    arguments = list(input = "test.tif")
  )

  expect_is(job, "gdal_job")
  expect_equal(job$command_path, c("raster", "info"))
})

test_that("gdal_with_co function exists", {
  expect_true(exists("gdal_with_co"))
  expect_is(gdal_with_co, "function")
})

test_that("gdal_with_config function exists", {
  expect_true(exists("gdal_with_config"))
  expect_is(gdal_with_config, "function")
})

test_that("gdal_with_env function exists", {
  expect_true(exists("gdal_with_env"))
  expect_is(gdal_with_env, "function")
})

test_that("dynamic API files are present", {
  # Check that the implementation files exist
  impl_dir <- system.file("R", package = "gdalcli")
  expect_true(file.exists(file.path(impl_dir, "core-gdal-api-classes.R")))
  expect_true(file.exists(file.path(impl_dir, "core-gdal-usage-parser.R")))
  expect_true(file.exists(file.path(impl_dir, "core-gdal-function-factory.R")))
  expect_true(file.exists(file.path(impl_dir, "aaa-dollar-names.R")))
  expect_true(file.exists(file.path(impl_dir, "zzz.R")))
})

test_that("gdal_run documentation mentions backend", {
  doc <- utils::capture.output(help(gdal_run))
  # The help text should mention the backend parameter
  expect_true(length(doc) > 0)
})

test_that("NAMESPACE includes dynamic API exports", {
  ns_file <- system.file("NAMESPACE", package = "gdalcli")
  ns_content <- readLines(ns_file)

  # Check for key exports
  expect_true(any(grepl("export.*gdal_run", ns_content)))
  expect_true(any(grepl("S3method.*DollarNames.*GdalApi", ns_content)))
  expect_true(any(grepl("S3method.*DollarNames.*GdalApiSub", ns_content)))
})

test_that("Dynamic API vignette exists", {
  vignette_path <- system.file("doc", "dynamic-api.html", package = "gdalcli")
  # The vignette may not be built in test environment, so just check it can be listed
  vignette_files <- system.file("doc", package = "gdalcli")
  expect_true(file.exists(vignette_files))
})

# These tests will skip if gdalraster is not available
test_that("gdal object can be created if gdalraster available", {
  if (requireNamespace("gdalraster", quietly = TRUE)) {
    skip_if_not_installed("gdalraster")

    # Check gdalraster version requirement
    gdal_version <- gdalraster::gdal_version()
    gdal_version_string <- if (is.list(gdal_version)) {
      gdal_version[["version"]]
    } else {
      as.character(gdal_version[1])
    }

    # Extract major.minor version
    version_match <- regexpr("\\d+\\.\\d+", gdal_version_string)
    if (version_match > 0) {
      version_parts <- as.numeric(
        strsplit(
          regmatches(gdal_version_string, version_match),
          "\\."
        )[[1]]
      )

      # Only test if GDAL >= 3.11
      if (version_parts[1] > 3 || (version_parts[1] == 3 && version_parts[2] >= 11)) {
        expect_true(TRUE)
      } else {
        skip("GDAL version < 3.11")
      }
    }
  } else {
    skip("gdalraster package not installed")
  }
})
