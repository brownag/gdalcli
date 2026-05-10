test_that("gdal_call invokes functions by character name", {
  job <- gdal_call("gdal_raster_info", list(input = "nonexistent.tif"))
  expect_s3_class(job, "gdal_job")
  expect_equal(job$arguments$input, "nonexistent.tif")
})

test_that("gdal_call invokes functions by function reference", {
  job <- gdal_call(gdal_raster_info, list(input = "nonexistent.tif"))
  expect_s3_class(job, "gdal_job")
  expect_equal(job$arguments$input, "nonexistent.tif")
})

test_that("gdal_call with character and function reference produce same result", {
  args <- list(input = "test.tif", output = "output.tif")

  job1 <- gdal_call("gdal_raster_convert", args)
  job2 <- gdal_call(gdal_raster_convert, args)

  expect_identical(job1$command_path, job2$command_path)
  expect_identical(job1$arguments$input, job2$arguments$input)
  expect_identical(job1$arguments$output, job2$arguments$output)
})

test_that("gdal_call errors on non-existent function", {
  expect_error(
    gdal_call("gdal_nonexistent_command", list()),
    "not found in gdalcli"
  )
})

test_that("gdal_call errors on non-character, non-function what", {
  expect_error(
    gdal_call(123, list()),
    "what must be a character string or function"
  )
})

test_that("gdal_call errors on non-list args", {
  expect_error(
    gdal_call("gdal_raster_info", c(input = "test.tif")),
    "args must be a named list"
  )
})

test_that("gdal_call applies modifiers in sequence", {
  modifiers <- list(
    function(x) gdal_with_co(x, "COMPRESS=DEFLATE"),
    function(x) gdal_with_co(x, "TILED=YES")
  )

  job <- gdal_call("gdal_raster_convert",
    list(input = "in.tif", output = "out.tif"),
    modifiers = modifiers
  )

  expect_length(job$arguments$`creation-option`, 2)
  expect_true("COMPRESS=DEFLATE" %in% job$arguments$`creation-option`)
  expect_true("TILED=YES" %in% job$arguments$`creation-option`)
})

test_that("gdal_call applies config modifiers", {
  modifiers <- list(
    function(x) gdal_with_config(x, "GDAL_CACHEMAX=512"),
    function(x) gdal_with_config(x, "CPL_DEBUG=ON")
  )

  job <- gdal_call("gdal_raster_info",
    list(input = "test.tif"),
    modifiers = modifiers
  )

  expect_length(job$config_options, 2)
  expect_equal(unname(job$config_options["GDAL_CACHEMAX"]), "512")
  expect_equal(unname(job$config_options["CPL_DEBUG"]), "ON")
})

test_that("gdal_call errors on non-list modifiers", {
  expect_error(
    gdal_call("gdal_raster_info",
      list(input = "test.tif"),
      modifiers = "not_a_list"
    ),
    "modifiers must be a list of functions or NULL"
  )
})

test_that("gdal_call errors on non-function modifier element", {
  expect_error(
    gdal_call("gdal_raster_info",
      list(input = "test.tif"),
      modifiers = list("not_a_function")
    ),
    "is not a function"
  )
})

test_that("gdal_call works with empty args list", {
  job <- gdal_call("gdal_raster_info", list())
  expect_s3_class(job, "gdal_job")
  expect_equal(length(job$arguments), 0)
})

test_that("gdal_call works with NULL modifiers (default)", {
  job <- gdal_call("gdal_raster_info", list(input = "test.tif"))
  expect_s3_class(job, "gdal_job")
})

# ===== Tests =====

test_that("gdal_call invokes function by character name", {
  # Build args based on GDAL version
  args <- list(levels = c(2, 4, 8))
  if (gdal_check_version("3.13", op = ">=")) {
    args$input <- "test.tif"
  } else {
    args$dataset <- "test.tif"
  }
  
  job <- gdal_call("gdal_raster_overview_add", args)
  expect_s3_class(job, "gdal_job")
  expect_identical(job$arguments$levels, c(2, 4, 8))
})

test_that("gdal_list_callable_commands returns character vector by default", {
  cmds <- gdal_list_callable_commands()
  expect_type(cmds, "character")
  expect_true(length(cmds) > 0)
  expect_true(all(startsWith(cmds, "gdal_")))
})

test_that("gdal_list_callable_commands filters by type", {
  raster_cmds <- gdal_list_callable_commands(type = "raster")
  vector_cmds <- gdal_list_callable_commands(type = "vector")

  expect_true(all(grepl("^gdal_raster_", raster_cmds)))
  expect_true(all(grepl("^gdal_vector_", vector_cmds)))
  expect_true(length(raster_cmds) > 0)
  expect_true(length(vector_cmds) > 0)
})

test_that("gdal_list_callable_commands returns data frame when simplify=FALSE", {
  df <- gdal_list_callable_commands(simplify = FALSE)
  expect_s3_class(df, "data.frame")
  expect_named(df, c("command", "type", "func"))
  expect_true(nrow(df) > 0)
})

test_that("gdal_list_callable_commands data frame contains valid functions", {
  df <- gdal_list_callable_commands(simplify = FALSE)
  
  # Pick a few and verify they are callable
  for (i in seq_len(min(3, nrow(df)))) {
    fn <- df$func[[i]]
    expect_true(is.function(fn))
  }
})

test_that("gdal_list_callable_commands errors on invalid type", {
  expect_error(
    gdal_list_callable_commands(type = "invalid_type"),
    "not recognized"
  )
})

test_that("gdal_list_callable_commands excludes utility functions", {
  cmds <- gdal_list_callable_commands()
  
  # Should not contain these
  expect_false(any(grepl("gdal_with_", cmds)))
  expect_false(any(grepl("gdal_job_run", cmds)))
  expect_false(any(grepl("gdal_check_", cmds)))
})

test_that("gdal_call and gdal_list_callable_commands work together", {
  cmds <- gdal_list_callable_commands(type = "raster", simplify = FALSE)
  
  # Try calling the first one (should be gdal_raster_aspect or similar)
  first_cmd <- cmds$command[[1]]
  fn <- cmds$func[[1]]
  
  # Calling with empty args should succeed
  job <- gdal_call(first_cmd, list())
  expect_s3_class(job, "gdal_job")
})
