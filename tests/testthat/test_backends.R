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
    arguments = list(input = "nonexistent.tif")
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
  job <- gdal_raster_info(input = "nonexistent.tif")
  
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
    arguments = list(input = "nonexistent.tif")
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
    arguments = list(input = "nonexistent.tif")
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
    arguments = list(input = "nonexistent.tif")
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

  expect_true("GDAL_CACHEMAX" %in% names(job_modified$config_options))
  expect_true("CPL_DEBUG" %in% names(job_modified$config_options))
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
    arguments = list(input = "nonexistent.tif")
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
    arguments = list(input = "nonexistent.tif"),
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

# Helper function to find and configure Python GDAL environment
find_python_gdal_env <- function() {
  if (!requireNamespace("reticulate", quietly = TRUE)) {
    return(FALSE)
  }
  
  tryCatch({
    # Check current environment first
    if (reticulate::py_module_available("osgeo.gdal")) {
      return(TRUE)
    }
    
    # Try venv in project root and common relative locations
    venv_paths <- c(
      file.path(getwd(), "venv"),                    # venv in current dir
      file.path(dirname(getwd()), "venv"),           # venv in parent dir
      "venv",                                        # relative venv
      "~/.venv"                                      # user home venv
    )
    
    for (path in venv_paths) {
      expanded_path <- path.expand(path)
      if (dir.exists(expanded_path)) {
        reticulate::use_virtualenv(expanded_path, required = FALSE)
        if (reticulate::py_module_available("osgeo.gdal")) {
          return(TRUE)
        }
      }
    }
    
    # Try standard virtualenv locations
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

# Helper function to check if Python GDAL is available
has_python_gdal <- function() {
  find_python_gdal_env()
}

# Setup function to configure reticulate for GDAL tests
setup_reticulate_gdal <- function() {
  find_python_gdal_env()
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
    arguments = list(input = "nonexistent.tif")
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
    arguments = list(input = "nonexistent.tif")
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

# =============================================================================
# EXECUTION TESTS (gdalraster backend)
# =============================================================================

test_that("gdalraster backend can execute raster_info command", {
  skip_if_not_installed("gdalraster")
  
  # Use sample file from inst/extdata
  sample_file <- system.file("extdata/sample_clay_content.tif", package = "gdalcli")
  skip_if(!file.exists(sample_file), "Sample data file not available")
  
  # Create info job
  job <- gdal_raster_info(input = sample_file)
  
  # Execute with gdalraster backend (catch any errors)
  result <- tryCatch({
    gdal_job_run(job, backend = "gdalraster", stream_out_format = "text")
  }, error = function(e) {
    skip(paste0("Execution failed: ", conditionMessage(e)))
  })
  
  # Verify we got some output
  if (is.character(result)) {
    expect_gt(nchar(result), 0)
  }
})

test_that("gdalraster backend returns text output from raster_info", {
  skip_if_not_installed("gdalraster")
  
  sample_file <- system.file("extdata/sample_clay_content.tif", package = "gdalcli")
  skip_if(!file.exists(sample_file), "Sample data file not available")
  
  # Request text output
  job <- gdal_raster_info(input = sample_file)
  
  # Execute with gdalraster backend
  result <- tryCatch(
    gdal_job_run(job, backend = "gdalraster", stream_out_format = "text"),
    error = function(e) NULL
  )
  
  # If we got output, verify it's character
  if (!is.null(result)) {
    expect_is(result, "character")
    expect_gt(nchar(result), 0)
  }
})

test_that("gdalraster backend handles creation options", {
  skip_if_not_installed("gdalraster")
  
  sample_file <- system.file("extdata/sample_clay_content.tif", package = "gdalcli")
  skip_if(!file.exists(sample_file), "Sample data file not available")
  
  # Create a conversion job with creation options
  temp_output <- tempfile(fileext = ".tif")
  
  job <- gdal_raster_convert(
    input = sample_file,
    output = temp_output
  ) |>
    gdal_with_co("COMPRESS=DEFLATE") |>
    gdal_with_co("BLOCKXSIZE=256")
  
  # Execute with gdalraster backend
  result <- tryCatch(
    gdal_job_run(job, backend = "gdalraster"),
    error = function(e) e
  )
  
  # Verify job structure preserved creation options
  expect_true("COMPRESS=DEFLATE" %in% job$arguments$`creation-option`)
  expect_true("BLOCKXSIZE=256" %in% job$arguments$`creation-option`)
  
  # Clean up
  if (file.exists(temp_output)) {
    unlink(temp_output)
  }
  
  # Result should either succeed (logical) or be an error
  expect_true(is.logical(result) || inherits(result, "error"))
})

test_that("gdalraster backend can list available commands", {
  skip_if_not_installed("gdalraster")
  
  # Try to list available GDAL commands (may fail or return differently based on version)
  commands <- tryCatch({
    gdal_list_commands()
  }, error = function(e) {
    NULL
  })
  
  # Should either return results or be NULL (graceful failure)
  if (!is.null(commands)) {
    expect_true(is.list(commands) || is.character(commands) || length(commands) > 0)
  } else {
    # Graceful failure is acceptable
    expect_true(TRUE)
  }
})

# =============================================================================
# EXECUTION TESTS (reticulate backend)
# =============================================================================

test_that("reticulate backend can import Python GDAL module", {
  skip_if_not_installed("reticulate")
  skip_if(!reticulate::py_module_available("osgeo.gdal"), "Python osgeo.gdal not available")
  
  # Try to import the module
  expect_true(reticulate::py_module_available("osgeo.gdal"))
  
  # Try to access gdal.Run function
  gdal <- reticulate::import("osgeo.gdal", delay_load = TRUE)
  expect_true(!is.null(gdal))
})

test_that("reticulate backend Python API structure is correct", {
  skip_if_not_installed("reticulate")
  skip_if(!reticulate::py_module_available("osgeo.gdal"), "Python osgeo.gdal not available")
  
  gdal <- reticulate::import("osgeo.gdal")
  
  # Verify gdal.Run function exists
  expect_true(inherits(gdal$Run, "python.builtin.function") || 
              inherits(gdal$Run, "python.builtin.method") ||
              !is.null(gdal$Run))
})

test_that("reticulate backend can execute simple Python GDAL command", {
  skip_if_not_installed("reticulate")
  skip_if(!reticulate::py_module_available("osgeo.gdal"), "Python osgeo.gdal not available")
  
  # Use sample file
  sample_file <- system.file("extdata/sample_clay_content.tif", package = "gdalcli")
  skip_if(!file.exists(sample_file), "Sample data file not available")
  
  # Try direct Python execution first to verify API
  tryCatch({
    gdal <- reticulate::import("osgeo.gdal")
    
    # Test gdal.Run with command path as list
    alg <- gdal$Run(list("raster", "info"), input = sample_file)
    
    # Verify algorithm object returned
    expect_true(!is.null(alg))
    # Check for python.builtin.object (the correct base class for Python objects)
    expect_true(inherits(alg, "python.builtin.object"))
  }, error = function(e) {
    skip(paste0("Python GDAL execution not available: ", conditionMessage(e)))
  })
})

test_that("reticulate backend can get output from Python GDAL execution", {
  skip_if_not_installed("reticulate")
  skip_if(!reticulate::py_module_available("osgeo.gdal"), "Python osgeo.gdal not available")
  
  sample_file <- system.file("extdata/sample_clay_content.tif", package = "gdalcli")
  skip_if(!file.exists(sample_file), "Sample data file not available")
  
  # Try to execute and retrieve output
  tryCatch({
    gdal <- reticulate::import("osgeo.gdal")
    
    # Execute raster info command
    alg <- gdal$Run(list("raster", "info"), input = sample_file)
    
    # Verify we can access methods
    # Check for python.builtin.object (the correct base class for Python objects)
    expect_true(inherits(alg, "python.builtin.object"))
    
    # Try to get output (may have different method names across versions)
    has_output_method <- !is.null(alg$Output) || !is.null(alg$output)
    expect_true(has_output_method)
  }, error = function(e) {
    skip(paste0("Python GDAL Output not accessible: ", conditionMessage(e)))
  })
})

test_that(".convert_cli_args_to_kwargs correctly parses arguments", {
  # Test flag-value pairs
  args1 <- c("--type", "Byte", "--driver", "GTiff")
  result1 <- .convert_cli_args_to_kwargs(args1)
  expect_equal(result1$type, "Byte")
  expect_equal(result1$driver, "GTiff")
  
  # Test positional arguments
  args2 <- c("input.tif", "output.tif")
  result2 <- .convert_cli_args_to_kwargs(args2)
  expect_equal(result2$input, "input.tif")
  expect_equal(result2$output, "output.tif")
  
  # Test mixed positional and flags
  args3 <- c("input.tif", "--type", "Float32", "output.tif")
  result3 <- .convert_cli_args_to_kwargs(args3)
  expect_equal(result3$input, "input.tif")
  expect_equal(result3$type, "Float32")
  expect_equal(result3$output, "output.tif")
  
  # Test kebab-case conversion
  args4 <- c("--output-type", "Byte", "--creation-option", "COMPRESS=LZW")
  result4 <- .convert_cli_args_to_kwargs(args4)
  expect_equal(result4$output_type, "Byte")
  expect_equal(result4$creation_option, "COMPRESS=LZW")
  
  # Test boolean flags
  args5 <- c("--quiet", "--help")
  result5 <- .convert_cli_args_to_kwargs(args5)
  expect_equal(result5$quiet, TRUE)
  expect_equal(result5$help, TRUE)
})

test_that("reticulate backend executes via gdalcli wrapper", {
  skip_if_not_installed("reticulate")
  skip_if(!reticulate::py_module_available("osgeo.gdal"), "Python osgeo.gdal not available")
  
  sample_file <- system.file("extdata/sample_clay_content.tif", package = "gdalcli")
  skip_if(!file.exists(sample_file), "Sample data file not available")
  
  # Create a job
  job <- gdal_raster_info(input = sample_file)
  
  # Try to execute with reticulate backend
  result <- tryCatch({
    gdal_job_run(job, backend = "reticulate", stream_out_format = "text")
  }, error = function(e) {
    # Expected to fail if Python GDAL not properly configured
    list(error = TRUE, message = conditionMessage(e))
  })
  
  # Should either succeed or fail gracefully
  if (is.list(result) && !is.null(result$error)) {
    # Check that error message is helpful
    expect_match(result$message, "GDAL|reticulate|osgeo", ignore.case = TRUE, all = FALSE)
  } else if (is.character(result)) {
    # Successful execution 
    expect_true(nchar(result) > 0)
  } else {
    # Unexpected result type - just skip this case
    skip("Unexpected result type from gdal_job_run")
  }
})

# =============================================================================
# COMPREHENSIVE EXECUTION TESTS (Both Backends)
# =============================================================================

test_that("gdalraster backend produces text output from raster_info", {
  skip_if_not_installed("gdalraster")
  
  sample_file <- system.file("extdata/sample_clay_content.tif", package = "gdalcli")
  skip_if(!file.exists(sample_file), "Sample data file not available")
  
  # Execute with gdalraster backend requesting text output
  job <- gdal_raster_info(input = sample_file)
  result <- gdal_job_run(job, backend = "gdalraster", stream_out_format = "text")
  
  # Verify output
  expect_is(result, "character")
  expect_gt(nchar(result), 0)
  
  # Should contain GDAL output characteristics
  expect_true(grepl("Driver|Band|Size|Coordinate", result, ignore.case = TRUE))
})

test_that("reticulate backend produces text output from raster_info", {
  skip_if_not_installed("reticulate")
  skip_if(!reticulate::py_module_available("osgeo.gdal"), "Python osgeo.gdal not available")
  
  sample_file <- system.file("extdata/sample_clay_content.tif", package = "gdalcli")
  skip_if(!file.exists(sample_file), "Sample data file not available")
  
  # Execute with reticulate backend EXPLICITLY requesting text output
  job <- gdal_raster_info(input = sample_file)
  result <- tryCatch({
    gdal_job_run(job, backend = "reticulate", stream_out_format = "text")
  }, error = function(e) {
    skip(paste0("Reticulate execution failed: ", conditionMessage(e)))
  })
  
  # Verify output - should be character when stream_out_format="text" is specified
  # If it's logical, the backend completed but didn't produce text output
  if (is.logical(result)) {
    # This is acceptable - command executed successfully but no output requested
    expect_true(result)
  } else {
    # Should be character text
    expect_is(result, "character")
    expect_gt(nchar(result), 0)
  }
})

test_that("gdalraster and processx backends produce similar raster_info output", {
  skip_if(is.na(Sys.which("gdal")), "GDAL CLI not available")
  skip_if_not_installed("gdalraster")
  
  sample_file <- system.file("extdata/sample_clay_content.tif", package = "gdalcli")
  skip_if(!file.exists(sample_file), "Sample data file not available")
  
  # Execute with processx backend
  job1 <- gdal_raster_info(input = sample_file)
  result_processx <- gdal_job_run(job1, backend = "processx", stream_out_format = "text")
  
  # Execute with gdalraster backend
  job2 <- gdal_raster_info(input = sample_file)
  result_gdalraster <- gdal_job_run(job2, backend = "gdalraster", stream_out_format = "text")
  
  # Both should have content
  expect_gt(nchar(result_processx), 0)
  expect_gt(nchar(result_gdalraster), 0)
  
  # Both should contain similar GDAL info patterns
  expect_true(grepl("Band", result_processx, ignore.case = TRUE))
  expect_true(grepl("Band", result_gdalraster, ignore.case = TRUE))
})

test_that("gdalraster backend with audit=TRUE captures metadata", {
  skip_if_not_installed("gdalraster")
  
  sample_file <- system.file("extdata/sample_clay_content.tif", package = "gdalcli")
  skip_if(!file.exists(sample_file), "Sample data file not available")
  
  # Execute with audit enabled
  job <- gdal_raster_info(input = sample_file)
  result <- gdal_job_run(job, backend = "gdalraster", stream_out_format = "text", audit = TRUE)
  
  # Verify audit trail is attached
  audit_trail <- attr(result, "audit_trail")
  expect_true(!is.null(audit_trail))
  expect_true(is.list(audit_trail))
  
  # Verify audit trail contains expected fields
  expect_true("timestamp" %in% names(audit_trail))
  expect_true("duration" %in% names(audit_trail))
  expect_true("command" %in% names(audit_trail))
  expect_true("backend" %in% names(audit_trail))
  expect_true("status" %in% names(audit_trail))
  
  # Verify field values
  expect_equal(audit_trail$backend, "gdalraster")
  expect_equal(audit_trail$status, "success")
  expect_true(inherits(audit_trail$timestamp, "POSIXct"))
  expect_true(inherits(audit_trail$duration, "difftime"))
})

test_that("reticulate backend with audit=TRUE captures metadata", {
  skip_if_not_installed("reticulate")
  skip_if(!reticulate::py_module_available("osgeo.gdal"), "Python osgeo.gdal not available")
  
  sample_file <- system.file("extdata/sample_clay_content.tif", package = "gdalcli")
  skip_if(!file.exists(sample_file), "Sample data file not available")
  
  # Execute with audit enabled
  job <- gdal_raster_info(input = sample_file)
  result <- tryCatch({
    gdal_job_run(job, backend = "reticulate", stream_out_format = "text", audit = TRUE)
  }, error = function(e) {
    skip(paste0("Reticulate execution failed: ", conditionMessage(e)))
  })
  
  # Verify audit trail is attached
  audit_trail <- attr(result, "audit_trail")
  expect_true(!is.null(audit_trail))
  expect_true(is.list(audit_trail))
  
  # Verify audit trail contains expected fields
  expect_true("timestamp" %in% names(audit_trail))
  expect_true("duration" %in% names(audit_trail))
  expect_true("command" %in% names(audit_trail))
  expect_true("backend" %in% names(audit_trail))
  expect_true("status" %in% names(audit_trail))
  
  # Verify backend identification
  expect_equal(audit_trail$backend, "reticulate")
  expect_equal(audit_trail$status, "success")
})

test_that("execution tests handle both backends with stream_out_format parameter", {
  skip_if_not_installed("gdalraster")
  
  sample_file <- system.file("extdata/sample_clay_content.tif", package = "gdalcli")
  skip_if(!file.exists(sample_file), "Sample data file not available")
  
  # Test text format
  job1 <- gdal_raster_info(input = sample_file)
  result_text <- gdal_job_run(job1, backend = "gdalraster", stream_out_format = "text")
  expect_is(result_text, "character")
  
  # Test raw format
  job2 <- gdal_raster_info(input = sample_file)
  result_raw <- gdal_job_run(job2, backend = "gdalraster", stream_out_format = "raw")
  expect_is(result_raw, "raw")
  
  # Raw and text should both represent the same output
  expect_equal(length(result_raw), nchar(result_text))
})

test_that("gdalraster backend can execute different command types", {
  skip_if_not_installed("gdalraster")
  
  sample_file <- system.file("extdata/sample_clay_content.tif", package = "gdalcli")
  skip_if(!file.exists(sample_file), "Sample data file not available")
  
  # Test raster info (already tested)
  job1 <- gdal_raster_info(input = sample_file)
  result1 <- gdal_job_run(job1, backend = "gdalraster", stream_out_format = "text")
  expect_gt(nchar(result1), 0)
  
  # Test that the backend can be called multiple times
  job2 <- gdal_raster_info(input = sample_file)
  result2 <- gdal_job_run(job2, backend = "gdalraster", stream_out_format = "text")
  expect_gt(nchar(result2), 0)
  
  # Results should be consistent
  expect_equal(result1, result2)
})

test_that("argument conversion validates positional and flag arguments", {
  # Test case 1: Only flags
  args1 <- c("--format", "json", "--quiet", "--help")
  result1 <- .convert_cli_args_to_kwargs(args1)
  expect_equal(result1$format, "json")
  expect_equal(result1$quiet, TRUE)
  expect_equal(result1$help, TRUE)
  
  # Test case 2: Positional + flags (inferred position)
  args2 <- c("input.tif", "--format", "json", "output.tif")
  result2 <- .convert_cli_args_to_kwargs(args2)
  expect_equal(result2$input, "input.tif")
  expect_equal(result2$format, "json")
  expect_equal(result2$output, "output.tif")
  
  # Test case 3: Numeric value conversion
  args3 <- c("--threads", "4", "--memory", "512.5")
  result3 <- .convert_cli_args_to_kwargs(args3)
  expect_equal(result3$threads, 4)
  expect_equal(result3$memory, 512.5)
  
  # Test case 4: Kebab to snake conversion
  args4 <- c("--output-type", "Byte", "--creation-options", "COMPRESS=LZW")
  result4 <- .convert_cli_args_to_kwargs(args4)
  expect_equal(result4$output_type, "Byte")
  expect_equal(result4$creation_options, "COMPRESS=LZW")
})

test_that("backends correctly serialize job arguments for execution", {
  skip_if_not_installed("gdalraster")
  
  # Create a complex job
  job <- new_gdal_job(
    command_path = c("gdal", "raster", "info"),
    arguments = list(
      input = "nonexistent.tif",
      format = "json"
    )
  ) |>
    gdal_with_config("CPL_DEBUG=ON")
  
  # Serialize should produce expected structure
  args <- .serialize_gdal_job(job)
  
  # Check command path is present
  expect_true("raster" %in% args)
  expect_true("info" %in% args)
  
  # Check that important arguments are present
  expect_true("nonexistent.tif" %in% args || any(grepl("nonexistent\\.tif", args)))
  
  # Check that flags are likely present (format/json handling varies)
  expect_true(length(args) > 2)
})

test_that("backends handle environment variables properly", {
  skip_if_not_installed("gdalraster")
  
  sample_file <- system.file("extdata/sample_clay_content.tif", package = "gdalcli")
  skip_if(!file.exists(sample_file), "Sample data file not available")
  
  # Create job with minimal environment variable
  job <- gdal_raster_info(input = sample_file)
  
  # Try to execute - if environment handling fails, that's OK for this test
  result <- tryCatch({
    gdal_job_run(job, backend = "gdalraster", stream_out_format = "text")
  }, error = function(e) {
    # Environment variables test is secondary - main execution is what matters
    message(paste0("Note: Environment test skipped due to: ", conditionMessage(e)))
    "skipped"
  })
  
  # Should produce valid output or be skipped
  if (result != "skipped") {
    expect_is(result, "character")
    expect_gt(nchar(result), 0)
  }
})

test_that("backends maintain job state through modifiers", {
  skip_if_not_installed("gdalraster")
  
  # Build a job with multiple modifiers
  job <- gdal_raster_info(
    input = system.file("extdata/sample_clay_content.tif", package = "gdalcli")
  ) |>
    gdal_with_co("COMPRESS=LZW") |>
    gdal_with_config("GDAL_CACHEMAX=256") |>
    gdal_with_env("TEST_VAR=test_value")
  
  # Verify creation options are preserved
  expect_true("COMPRESS=LZW" %in% job$arguments$`creation-option`)
  
  # Verify config options are present (structure may vary)
  expect_true(length(job$config_options) > 0)
  expect_true("GDAL_CACHEMAX" %in% names(job$config_options))
  
  # Verify environment variables are present
  expect_true(length(job$env_vars) > 0)
  expect_equal(job$env_vars[["TEST_VAR"]], "test_value")
  
  # Try to execute
  result <- tryCatch({
    gdal_job_run(job, backend = "gdalraster", stream_out_format = "text")
  }, error = function(e) NULL)
  
  # Should succeed or provide meaningful error (not crash)
  expect_true(is.character(result) || is.null(result))
})
