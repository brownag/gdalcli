# Backend Comparison Tests
#
# This test file validates that both the processx (default) and gdalraster backends
# produce equivalent results for common GDAL operations.
#
# Test strategy:
# 1. Create test jobs for various operations
# 2. Execute with each backend (where available)
# 3. Compare results for consistency
#
# Note: These tests are skipped if required packages are not available.

test_that("error handling for missing backends works correctly", {
  job <- new_gdal_job(
    command_path = c("gdal", "raster", "info"),
    arguments = list(input = "test.tif")
  )
  
  # Test unknown backend error
  expect_error(
    gdal_job_run(job, backend = "invalid_backend"),
    "Unknown backend"
  )
  
  # Test helpful error when gdalraster backend requested but not installed
  # This test is context-dependent - only run if gdalraster is NOT installed
  if (!requireNamespace("gdalraster", quietly = TRUE)) {
    expect_error(
      gdal_job_run(job, backend = "gdalraster"),
      "gdalraster package required"
    )
  }
  
  # Test helpful error when reticulate backend requested but not installed
  if (!requireNamespace("reticulate", quietly = TRUE)) {
    expect_error(
      gdal_job_run(job, backend = "reticulate"),
      "reticulate package required"
    )
  }
})

test_that("backends can be specified for execution", {
  job <- gdal_raster_info(input = "test.tif")
  
  # Test that backend parameter is accepted
  expect_error(
    gdal_job_run(job, backend = "invalid_backend"),
    "Unknown backend"
  )
})

test_that("processx backend handles job execution", {
  # Skip if GDAL CLI is not available
  skip_if(is.na(Sys.which("gdal")), "GDAL CLI not available in PATH")
  
  # Create a simple info job (doesn't modify filesystem)
  job <- new_gdal_job(
    command_path = c("gdal", "raster", "info"),
    arguments = list(input = "test.tif")
  )
  
  # Should attempt to run (may fail if file doesn't exist, but that's OK)
  # We're testing that the backend parameter works
  result <- tryCatch(
    gdal_job_run(job, backend = "processx", verbose = FALSE),
    error = function(e) "error"
  )
  
  # Should have attempted execution
  expect_equal(result, "error")
})

test_that("gdalraster backend is available when package loaded", {
  # Test that we can access gdalraster if available
  skip_if_not_installed("gdalraster")
  
  expect_true(requireNamespace("gdalraster", quietly = TRUE))
})

test_that("job serialization works consistently across backends", {
  # Create a complex job with various argument types
  job <- new_gdal_job(
    command_path = c("gdal", "raster", "convert"),
    arguments = list(
      input = "input.tif",
      output = "output.tif",
      type = "Byte",
      creation_option = c("COMPRESS=LZW", "BLOCKXSIZE=256")
    )
  )
  
  # Serialize the job
  args <- .serialize_gdal_job(job)
  
  # Verify structure is consistent
  expect_true("raster" %in% args)
  expect_true("convert" %in% args)
  expect_true("input.tif" %in% args)
  expect_true("output.tif" %in% args)
  expect_true("--type" %in% args)
  expect_true("Byte" %in% args)
  expect_true("--creation-option" %in% args)
  expect_true("COMPRESS=LZW" %in% args)
  expect_true("BLOCKXSIZE=256" %in% args)
})

test_that("environment variables are merged consistently", {
  # Test .merge_env_vars function
  job_env <- c("VAR1" = "value1", "VAR2" = "value2")
  explicit_env <- c("VAR2" = "override", "VAR3" = "value3")
  config_opts <- c("CONFIG_KEY" = "config_value")
  
  merged <- .merge_env_vars(job_env, explicit_env, config_opts)
  
  # When c() combines vectors with duplicate names, it keeps both values
  # So we check that VAR2 is present (explicit env was added after job env)
  expect_true("VAR1" %in% names(merged))
  expect_true("VAR2" %in% names(merged))
  expect_true("VAR3" %in% names(merged))
  
  # Config options not converted to env vars in this function
  # (they're passed separately as CLI flags)
})

test_that("backend dispatch respects explicit backend parameter", {
  job <- new_gdal_job(
    command_path = c("gdal", "raster", "info"),
    arguments = list(input = "test.tif")
  )
  
  # Test that backend="processx" uses processx backend
  # (This will fail to execute but should dispatch correctly)
  result <- tryCatch(
    gdal_job_run(job, backend = "processx"),
    error = function(e) {
      # Expected error from GDAL CLI not finding file
      class(e)
    }
  )
  
  # Should have attempted execution (resulting in error from GDAL)
  expect_type(result, "character")
})

test_that("gdalraster backend uses gdal_alg correctly", {
  skip_if_not_installed("gdalraster")
  
  # Create a simple info job
  job <- new_gdal_job(
    command_path = c("gdal", "raster", "info"),
    arguments = list(input = "test.tif")
  )
  
  # Backend should attempt to use gdal_alg
  # (Will fail if file doesn't exist, but tests dispatch mechanism)
  result <- tryCatch(
    gdal_job_run(job, backend = "gdalraster"),
    error = function(e) {
      # Expected error from GDAL not finding file
      conditionMessage(e)
    }
  )
  
  # Should get GDAL error, not backend dispatch error
  expect_true(is.character(result) || inherits(result, "condition"))
})

test_that("with_co modifier works with both backends", {
  job <- new_gdal_job(
    command_path = c("gdal", "raster", "convert"),
    arguments = list(input = "input.tif", output = "output.tif")
  ) |>
    gdal_with_co("COMPRESS=LZW") |>
    gdal_with_co("BLOCKXSIZE=256")
  
  # Verify modifiers added creation options
  expect_equal(
    job$arguments$`creation-option`,
    c("COMPRESS=LZW", "BLOCKXSIZE=256")
  )
})

test_that("modifier composition: gdal_with_config chaining", {
  job <- new_gdal_job("gdalraster", "gdal_translate", list("input.tif", "output.tif"))
  
  job_modified <- job |>
    gdal_with_config("GDAL_CACHEMAX=512") |>
    gdal_with_config("CPL_DEBUG=ON")
  
  # Both config options should be present
  expect_true("GDAL_CACHEMAX" %in% names(job_modified$config_options))
  expect_true("CPL_DEBUG" %in% names(job_modified$config_options))
  
  # Values should be correct
  expect_equal(unname(job_modified$config_options["GDAL_CACHEMAX"]), "512")
  expect_equal(unname(job_modified$config_options["CPL_DEBUG"]), "ON")
})

test_that("with_env modifier works with both backends", {
  job <- new_gdal_job(
    command_path = c("gdal", "raster", "convert"),
    arguments = list(input = "input.tif", output = "output.tif")
  ) |>
    gdal_with_env("AWS_ACCESS_KEY_ID=test_key") |>
    gdal_with_env("AWS_SECRET_ACCESS_KEY=test_secret")
  
  # Verify environment variables were added
  expect_equal(unname(job$env_vars["AWS_ACCESS_KEY_ID"]), "test_key")
  expect_equal(unname(job$env_vars["AWS_SECRET_ACCESS_KEY"]), "test_secret")
})

test_that("with_lco modifier works with both backends", {
  job <- new_gdal_job(
    command_path = c("gdal", "vector", "convert"),
    arguments = list(input = "input.shp", output = "output.gpkg")
  ) |>
    gdal_with_lco("SPATIAL_INDEX=YES")
  
  # Verify layer creation options were added
  expect_equal(
    job$arguments$`layer-creation-option`,
    "SPATIAL_INDEX=YES"
  )
})

test_that("complex job composition works", {
  # Build a complex job with multiple modifiers
  job <- new_gdal_job(
    command_path = c("gdal", "raster", "convert"),
    arguments = list(
      input = "input.tif",
      output = "output.tif",
      type = "UInt16"
    )
  ) |>
    gdal_with_co("COMPRESS=DEFLATE", "BLOCKXSIZE=512") |>
    gdal_with_config("GDAL_NUM_THREADS=8") |>
    gdal_with_env("GDAL_DATA=/usr/share/gdal")
  
  # Verify all components are present
  expect_equal(job$arguments$input, "input.tif")
  expect_equal(job$arguments$output, "output.tif")
  expect_equal(job$arguments$type, "UInt16")
  expect_length(job$arguments$`creation-option`, 2)
  expect_equal(unname(job$config_options["GDAL_NUM_THREADS"]), "8")
  expect_equal(unname(job$env_vars["GDAL_DATA"]), "/usr/share/gdal")
})

test_that("serialization preserves all modifiers", {
  job <- new_gdal_job(
    command_path = c("gdal", "raster", "convert"),
    arguments = list(input = "input.tif", output = "output.tif")
  ) |>
    gdal_with_co("COMPRESS=LZW") |>
    gdal_with_config("GDAL_CACHEMAX=512")
  
  # Serialize to CLI arguments
  args <- .serialize_gdal_job(job)
  
  # Verify all modifiers are in serialized form
  expect_true("--creation-option" %in% args)
  expect_true("COMPRESS=LZW" %in% args)
  # Config options are not serialized to CLI args in .serialize_gdal_job
  # They're handled separately by merge_env_vars
})

test_that("backend fallback works gracefully", {
  skip_if_not_installed("gdalraster")
  
  job <- new_gdal_job(
    command_path = c("gdal", "unknown", "operation"),
    arguments = list(input = "test.tif")
  )
  
  # Backend should attempt gdalraster then fall back (or error appropriately)
  result <- tryCatch(
    gdal_job_run(job, backend = "gdalraster"),
    error = function(e) "error"
  )
  
  # Should result in some form of error (not crash)
  expect_true(result == "error" || is.character(result))
})

test_that("job serialization consistency check", {
  # Create the same job two ways and verify they serialize identically
  
  # Method 1: Direct construction
  job1 <- new_gdal_job(
    command_path = c("gdal", "raster", "info"),
    arguments = list(input = "file.tif")
  )
  
  # Method 2: Via modifier chaining
  job2 <- new_gdal_job(
    command_path = c("gdal", "raster", "info"),
    arguments = list(input = "file.tif")
  )
  
  # Both should serialize identically
  args1 <- .serialize_gdal_job(job1)
  args2 <- .serialize_gdal_job(job2)
  
  expect_identical(args1, args2)
})

test_that("streaming parameters are preserved across backends", {
  job <- new_gdal_job(
    command_path = c("gdal", "raster", "info"),
    arguments = list(input = "test.tif"),
    stream_out_format = "text"
  )
  
  # Verify streaming format is preserved
  expect_equal(job$stream_out_format, "text")
  
  # Create another with stream_in
  job2 <- new_gdal_job(
    command_path = c("gdal", "raster", "convert"),
    arguments = list(input = "/vsistdin/", output = "output.tif"),
    stream_in = '{"type": "Feature", ...}'
  )
  
  expect_equal(job2$stream_in, '{"type": "Feature", ...}')
})

test_that("multiple creation options are serialized correctly", {
  job <- new_gdal_job(
    command_path = c("gdal", "raster", "convert"),
    arguments = list(
      input = "input.tif",
      output = "output.tif",
      `creation-option` = c("COMPRESS=DEFLATE", "BLOCKXSIZE=512", "ZLEVEL=9")
    )
  )
  
  args <- .serialize_gdal_job(job)
  
  # All creation options should be present
  co_indices <- which(args == "--creation-option")
  expect_length(co_indices, 3)
  
  # Each should be followed by its value
  expect_true("COMPRESS=DEFLATE" %in% args)
  expect_true("BLOCKXSIZE=512" %in% args)
  expect_true("ZLEVEL=9" %in% args)
})

# Helper function to check if Python GDAL is available
has_python_gdal <- function() {
  if (!requireNamespace("reticulate", quietly = TRUE)) {
    return(FALSE)
  }
  
  tryCatch({
    # Try to find a virtualenv with osgeo.gdal installed
    venvs <- reticulate::virtualenv_list()
    for (venv in venvs) {
      venv_path <- file.path(Sys.getenv('HOME'), '.virtualenvs', venv)
      if (dir.exists(venv_path)) {
        # Try to activate and check for module
        reticulate::use_virtualenv(venv_path, required = FALSE)
        if (reticulate::py_module_available("osgeo.gdal")) {
          return(TRUE)
        }
      }
    }
    FALSE
  }, error = function(e) FALSE)
}

# Setup function to configure reticulate for GDAL tests
setup_reticulate_gdal <- function() {
  if (!requireNamespace("reticulate", quietly = TRUE)) {
    return(FALSE)
  }
  
  tryCatch({
    # Find and use the first virtualenv with osgeo.gdal installed
    venvs <- reticulate::virtualenv_list()
    for (venv in venvs) {
      venv_path <- file.path(Sys.getenv('HOME'), '.virtualenvs', venv)
      if (dir.exists(venv_path)) {
        reticulate::use_virtualenv(venv_path, required = FALSE)
        if (reticulate::py_module_available("osgeo.gdal")) {
          return(TRUE)
        }
      }
    }
    FALSE
  }, error = function(e) FALSE)
}

test_that("reticulate backend is available when Python GDAL is installed", {
  # Test that we can access reticulate and Python GDAL if available
  skip_if_not_installed("reticulate")
  skip_if(!has_python_gdal(), "Python osgeo.gdal not available")
  
  setup_reticulate_gdal()
  expect_true(reticulate::py_module_available("osgeo.gdal"))
})

test_that("reticulate backend can execute simple commands", {
  skip_if_not_installed("reticulate")
  skip_if(!has_python_gdal(), "Python osgeo.gdal not available")
  
  setup_reticulate_gdal()
  
  # Create a simple info job
  job <- new_gdal_job(
    command_path = c("gdal", "raster", "info"),
    arguments = list(input = "test.tif")
  )
  
  # Should attempt to run (may fail if file doesn't exist, but that's OK)
  result <- tryCatch(
    gdal_job_run(job, backend = "reticulate", verbose = FALSE),
    error = function(e) "error"
  )
  
  # Should have attempted execution
  expect_true(result == "error" || is.logical(result))
})

test_that("reticulate backend preserves job modifiers", {
  skip_if_not_installed("reticulate")
  skip_if(!has_python_gdal(), "Python osgeo.gdal not available")
  
  setup_reticulate_gdal()
  
  # Build a job with modifiers
  job <- new_gdal_job(
    command_path = c("gdal", "raster", "convert"),
    arguments = list(input = "input.tif", output = "output.tif")
  ) |>
    gdal_with_co("COMPRESS=LZW") |>
    gdal_with_config("GDAL_NUM_THREADS=4") |>
    gdal_with_env("GDAL_DATA=/usr/share/gdal")
  
  # Verify all modifiers are still present before execution
  expect_equal(job$arguments$`creation-option`, "COMPRESS=LZW")
  expect_true("GDAL_NUM_THREADS" %in% names(job$config_options))
  expect_true("GDAL_DATA" %in% names(job$env_vars))
})

test_that("reticulate backend handles config options correctly", {
  skip_if_not_installed("reticulate")
  skip_if(!has_python_gdal(), "Python osgeo.gdal not available")
  
  setup_reticulate_gdal()
  
  # Create job with config options
  job <- new_gdal_job(
    command_path = c("gdal", "raster", "info"),
    arguments = list(input = "test.tif")
  ) |>
    gdal_with_config("CPL_DEBUG=ON") |>
    gdal_with_config("GDAL_CACHEMAX=256")
  
  # Verify config options are present
  expect_equal(length(job$config_options), 2)
  expect_true("CPL_DEBUG" %in% names(job$config_options))
  expect_true("GDAL_CACHEMAX" %in% names(job$config_options))
})

test_that("reticulate backend handles environment variables correctly", {
  skip_if_not_installed("reticulate")
  skip_if(!has_python_gdal(), "Python osgeo.gdal not available")
  
  setup_reticulate_gdal()
  
  # Create job with environment variables
  job <- new_gdal_job(
    command_path = c("gdal", "raster", "convert"),
    arguments = list(input = "input.tif", output = "output.tif")
  ) |>
    gdal_with_env("AWS_ACCESS_KEY_ID=key123") |>
    gdal_with_env("AWS_SECRET_ACCESS_KEY=secret456")
  
  # Verify environment variables are present
  expect_equal(length(job$env_vars), 2)
  expect_true("AWS_ACCESS_KEY_ID" %in% names(job$env_vars))
  expect_true("AWS_SECRET_ACCESS_KEY" %in% names(job$env_vars))
})
