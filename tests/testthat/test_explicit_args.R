# Tests for getExplicitlySetArgs() support

test_that("gdal_job_get_explicit_args validates input", {
  expect_error(
    gdal_job_get_explicit_args("not a job"),
    "job must be a gdal_job object"
  )

  expect_error(
    gdal_job_get_explicit_args(list(command_path = c("raster", "info"))),
    "job must be a gdal_job object"
  )
})

test_that("gdal_job_get_explicit_args returns character vector", {
  skip_if_not(gdal_check_version("3.12", op = ">="))

  job <- new_gdal_job(
    command_path = c("raster", "info"),
    arguments = list(input = "test.tif")
  )

  result <- gdal_job_get_explicit_args(job)
  expect_type(result, "character")
})

test_that("gdal_job_get_explicit_args returns empty on GDAL < 3.12", {
  # This test only runs if GDAL < 3.12
  skip_if(gdal_check_version("3.12", op = ">="))

  job <- new_gdal_job(
    command_path = c("raster", "info"),
    arguments = list(input = "test.tif")
  )

  result <- gdal_job_get_explicit_args(job)
  expect_type(result, "character")
  expect_length(result, 0)
})

test_that("gdal_job_get_explicit_args respects system_only parameter", {
  skip_if_not(gdal_check_version("3.12", op = ">=") &&
              .gdal_has_feature("explicit_args"))

  job <- new_gdal_job(
    command_path = c("raster", "convert"),
    arguments = list(
      input = "input.tif",
      output = "output.tif",
      output_format = "COG"
    )
  )

  all_args <- gdal_job_get_explicit_args(job, system_only = FALSE)
  system_args <- gdal_job_get_explicit_args(job, system_only = TRUE)

  # System args should be subset of all args
  if (length(system_args) > 0) {
    expect_true(all(system_args %in% all_args))
  }
})

test_that(".create_audit_entry produces valid audit structure", {
  job <- new_gdal_job(
    command_path = c("raster", "info"),
    arguments = list(input = "test.tif")
  )

  audit <- .create_audit_entry(job, status = "success")

  expect_named(
    audit,
    c("timestamp", "job_command", "explicit_args", "status", "error", "gdal_version", "r_version")
  )

  expect_s3_class(audit$timestamp, "POSIXct")
  expect_type(audit$job_command, "character")
  expect_type(audit$explicit_args, "character")
  expect_equal(audit$status, "success")
  expect_null(audit$error)
  expect_type(audit$gdal_version, "character")
  expect_type(audit$r_version, "character")
})

test_that(".create_audit_entry captures error status", {
  job <- new_gdal_job(
    command_path = c("raster", "info"),
    arguments = list(input = "test.tif")
  )

  error_msg <- "Test error message"
  audit <- .create_audit_entry(job, status = "error", error_msg = error_msg)

  expect_equal(audit$status, "error")
  expect_equal(audit$error, error_msg)
})

test_that("gdal_job_run_with_audit executes job and returns result", {
  skip_if_not(gdal_check_version("3.11.3", op = ">="))

  test_file <- system.file("extdata", "sample_clay_content.tif", package = "gdalcli")
  skip_if(!file.exists(test_file), "Test data not available")

  job <- new_gdal_job(
    command_path = c("raster", "info"),
    arguments = list(input = test_file)
  )

  result <- gdal_job_run_with_audit(job, audit_log = FALSE, backend = "processx", stream_out_format = "text")
  expect_true(is.character(result))
})

test_that("gdal_job_run_with_audit attaches audit trail when audit_log=TRUE", {
  skip_if_not(gdal_check_version("3.11.3", op = ">="))

  test_file <- system.file("extdata", "sample_clay_content.tif", package = "gdalcli")
  skip_if(!file.exists(test_file), "Test data not available")

  job <- new_gdal_job(
    command_path = c("raster", "info"),
    arguments = list(input = test_file)
  )

  result <- gdal_job_run_with_audit(job, audit_log = TRUE, backend = "processx", stream_out_format = "text")
  
  expect_true(hasName(attributes(result), "audit_trail"))
  audit <- attr(result, "audit_trail")
  expect_equal(audit$status, "success")
  expect_null(audit$error)
})

test_that("gdal_job_run_with_audit does not attach trail when audit_log=FALSE", {
  skip_if_not(gdal_check_version("3.11.3", op = ">="))

  test_file <- system.file("extdata", "sample_clay_content.tif", package = "gdalcli")
  skip_if(!file.exists(test_file), "Test data not available")

  job <- new_gdal_job(
    command_path = c("raster", "info"),
    arguments = list(input = test_file)
  )

  result <- gdal_job_run_with_audit(job, audit_log = FALSE, backend = "processx", stream_out_format = "text")
  
  expect_false(hasName(attributes(result), "audit_trail"))
})

test_that("gdal_job_get_explicit_args handles missing options pointer", {
  job <- new_gdal_job(
    command_path = c("raster", "info"),
    arguments = list(input = "test.tif")
  )

  # Remove options pointer if it exists
  job$.options_xptr <- NULL

  # Should return empty vector without error
  result <- expect_no_error(
    suppressWarnings(gdal_job_get_explicit_args(job))
  )

  expect_type(result, "character")
})

test_that("gdal_capabilities is accessible from explicit args module", {
  # Ensure gdal_capabilities is re-exported
  expect_type(gdal_capabilities, "closure")

  # Call it to verify it works
  caps <- gdal_capabilities()
  expect_s3_class(caps, "gdal_capabilities")
})

test_that(".call_gdalraster_explicit_args handles unavailable binding", {
  # Create a dummy external pointer
  dummy_xptr <- new.env()

  # Should return empty vector when binding unavailable
  result <- .call_gdalraster_explicit_args(dummy_xptr)
  expect_type(result, "character")
})
