test_that("Shell-style quoting handles safe characters without quoting", {
  expect_equal(.quote_argument("simple_file.tif"), "simple_file.tif")
  expect_equal(.quote_argument("path/to/file.txt"), "path/to/file.txt")
  expect_equal(.quote_argument("EPSG:4326"), "EPSG:4326")
  expect_equal(.quote_argument("123"), "123")
})

test_that("Shell-style quoting adds quotes for special characters", {
  # Spaces
  expect_equal(.quote_argument("my file.tif"), "'my file.tif'")

  # Special shell characters
  expect_equal(.quote_argument("test$var"), "'test$var'")
  expect_equal(.quote_argument("test&file"), "'test&file'")

  # Semicolon (command separator)
  expect_equal(.quote_argument("test;file"), "'test;file'")
})

test_that("Shell-style quoting escapes embedded single quotes", {
  # Single quote in string
  input <- "it's_a_file"
  result <- .quote_argument(input)
  expect_true(grepl("'", result))  # Should contain quotes
  expect_true(grepl("\"", result))  # Should use '"'"' technique
})

test_that("Empty string is properly quoted", {
  result <- .quote_argument("")
  expect_equal(result, "''")
})

test_that("RFC 104 argument formatting handles boolean flags", {
  arg_mapping <- list()

  # Logical TRUE
  result <- .format_rfc104_argument(TRUE, "overwrite", arg_mapping)
  expect_equal(result, "--overwrite")

  # Logical FALSE
  result <- .format_rfc104_argument(FALSE, "overwrite", arg_mapping)
  expect_equal(result, character(0))
})

test_that("RFC 104 argument formatting handles single values", {
  arg_mapping <- list()

  result <- .format_rfc104_argument("EPSG:4326", "dst_crs", arg_mapping)
  expect_equal(result, c("--dst-crs", "EPSG:4326"))

  # Numeric value
  result <- .format_rfc104_argument(100, "resolution", arg_mapping)
  expect_equal(result, c("--resolution", "100"))
})

test_that("RFC 104 argument formatting handles repeatable arguments", {
  # Repeatable argument (max_count > 1 but min != max)
  arg_mapping <- list(
    creation_option = list(min_count = 0, max_count = 999)
  )

  result <- .format_rfc104_argument(
    c("COMPRESS=LZW", "TILED=YES"),
    "creation_option",
    arg_mapping
  )

  expect_equal(result, c("--creation-option", "COMPRESS=LZW", "--creation-option", "TILED=YES"))
})

test_that("RFC 104 argument formatting handles composite (packed) arguments", {
  # Composite argument (e.g., bbox with fixed 4 values)
  arg_mapping <- list(
    bbox = list(min_count = 4, max_count = 4)
  )

  result <- .format_rfc104_argument(
    c(-120, 30, -110, 40),
    "bbox",
    arg_mapping
  )

  expect_equal(result, c("--bbox", "-120,30,-110,40"))
})

test_that("RFC 104 argument formatting applies special flag mappings", {
  arg_mapping <- list()

  # resolution flag
  result <- .format_rfc104_argument(10, "resolution", arg_mapping)
  expect_equal(result[1], "--resolution")

  # size flag (maps to --ts)
  result <- .format_rfc104_argument(c(512, 512), "size", arg_mapping)
  expect_equal(result[1], "--ts")

  # extent flag (maps to --te)
  result <- .format_rfc104_argument(c(0, 0, 100, 100), "extent", arg_mapping)
  expect_equal(result[1], "--te")
})

test_that("job_to_rfc104_step formats a simple read operation", {
  job <- new_gdal_job(
    command_path = c("gdal", "vector", "read"),
    arguments = list(input = "input.gpkg"),
    arg_mapping = list()
  )

  result <- .job_to_rfc104_step(job)
  expect_true(grepl("^read", result))
  expect_true(grepl("input\\.gpkg", result))
})

test_that("job_to_rfc104_step formats operations with options", {
  job <- new_gdal_job(
    command_path = c("gdal", "vector", "reproject"),
    arguments = list(
      input = "in.gpkg",
      output = "out.gpkg",
      dst_crs = "EPSG:32632"
    ),
    arg_mapping = list()
  )

  result <- .job_to_rfc104_step(job)
  expect_true(grepl("^reproject", result))
  expect_true(grepl("--dst-crs", result))
  expect_true(grepl("EPSG:32632", result))
})

test_that("pipeline_to_rfc104_command constructs valid RFC 104 string", {
  jobs <- list(
    new_gdal_job(
      command_path = c("gdal", "raster", "read"),
      arguments = list(input = "input.tif"),
      arg_mapping = list()
    ),
    new_gdal_job(
      command_path = c("gdal", "raster", "reproject"),
      arguments = list(dst_crs = "EPSG:3857"),
      arg_mapping = list()
    )
  )

  pipeline <- new_gdal_pipeline(jobs = jobs, name = NA_character_)

  result <- .pipeline_to_rfc104_command(pipeline)

  expect_true(grepl("^gdal raster pipeline !", result))
  expect_true(grepl("! read", result))
  expect_true(grepl("! reproject", result))
  expect_true(grepl("--dst-crs", result))
})

test_that("pipeline_to_gdalg_spec generates valid GDALG JSON structure", {
  jobs <- list(
    new_gdal_job(
      command_path = c("gdal", "vector", "read"),
      arguments = list(input = "input.gpkg"),
      arg_mapping = list()
    ),
    new_gdal_job(
      command_path = c("gdal", "vector", "write"),
      arguments = list(output = "output.gpkg"),
      arg_mapping = list()
    )
  )

  pipeline <- new_gdal_pipeline(jobs = jobs, name = NA_character_)
  spec <- .pipeline_to_gdalg_spec(pipeline)

  expect_equal(spec$type, "gdal_streamed_alg")
  expect_true(is.character(spec$command_line))
  expect_true(length(spec$command_line) > 0)
  expect_true(spec$relative_paths_relative_to_this_file)
})

test_that("parse_rfc104_command_string correctly splits pipeline steps", {
  command_line <- "gdal vector pipeline ! read input.gpkg ! reproject --dst-crs EPSG:32632 ! write output.gpkg"

  steps <- .parse_rfc104_command_string(command_line)

  expect_length(steps, 3)
  expect_equal(steps[[1]][1], "read")
  expect_equal(steps[[2]][1], "reproject")
  expect_equal(steps[[3]][1], "write")
})

test_that("parse_rfc104_command_string handles quoted arguments", {
  # Quoted argument with spaces
  command_line <- "gdal vector pipeline ! filter --where 'name = \"test\"' ! write out.gpkg"

  steps <- .parse_rfc104_command_string(command_line)

  # Should have extracted the quoted argument
  expect_length(steps, 2)
  expect_equal(steps[[1]][1], "filter")
})

test_that("rfc104_step_to_job reconstructs job from tokens", {
  tokens <- c("reproject", "--dst-crs", "EPSG:32632")

  job <- .rfc104_step_to_job(tokens, "vector", 2)

  expect_true(inherits(job, "gdal_job"))
  expect_equal(job$command_path, c("gdal", "vector", "reproject"))
  expect_equal(job$arguments$dst_crs, "EPSG:32632")
})

test_that("rfc104_step_to_job handles repeatable arguments", {
  tokens <- c("write", "--co", "COMPRESS=LZW", "--co", "TILED=YES", "output.tif")

  job <- .rfc104_step_to_job(tokens, "raster", 3)

  expect_equal(job$arguments$co, c("COMPRESS=LZW", "TILED=YES"))
  expect_equal(job$arguments$output, "output.tif")
})

test_that("rfc104_step_to_job handles composite arguments", {
  tokens <- c("filter", "--bbox", "-120,30,-110,40")

  job <- .rfc104_step_to_job(tokens, "vector", 1)

  expect_equal(job$arguments$bbox, c("-120", "30", "-110", "40"))
})

test_that("gdalg_to_pipeline reconstructs pipeline from command string", {
  command_line <- "gdal vector pipeline ! read input.gpkg ! reproject --dst-crs EPSG:32632 ! write output.gpkg"

  pipeline <- .gdalg_to_pipeline(command_line)

  expect_true(inherits(pipeline, "gdal_pipeline"))
  expect_length(pipeline$jobs, 3)
  expect_equal(pipeline$jobs[[1]]$command_path[3], "read")
  expect_equal(pipeline$jobs[[2]]$command_path[3], "reproject")
  expect_equal(pipeline$jobs[[3]]$command_path[3], "write")
})

test_that("Round-trip: pipeline -> GDALG JSON -> pipeline preserves structure", {
  jobs <- list(
    new_gdal_job(
      command_path = c("gdal", "raster", "read"),
      arguments = list(input = "input.tif"),
      arg_mapping = list()
    ),
    new_gdal_job(
      command_path = c("gdal", "raster", "reproject"),
      arguments = list(dst_crs = "EPSG:3857"),
      arg_mapping = list()
    ),
    new_gdal_job(
      command_path = c("gdal", "raster", "write"),
      arguments = list(output = "output.tif"),
      arg_mapping = list()
    )
  )

  pipeline1 <- new_gdal_pipeline(jobs = jobs, name = NA_character_)

  # Serialize to command string
  command_line <- .pipeline_to_rfc104_command(pipeline1)

  # Deserialize back
  pipeline2 <- .gdalg_to_pipeline(command_line)

  # Check basic structure is preserved
  expect_equal(length(pipeline1$jobs), length(pipeline2$jobs))
  expect_equal(pipeline1$jobs[[1]]$command_path[3], pipeline2$jobs[[1]]$command_path[3])
  expect_equal(pipeline1$jobs[[2]]$command_path[3], pipeline2$jobs[[2]]$command_path[3])
})

test_that("Complex argument quoting works correctly in full pipeline", {
  jobs <- list(
    new_gdal_job(
      command_path = c("gdal", "vector", "read"),
      arguments = list(input = "my input file.gpkg"),
      arg_mapping = list()
    ),
    new_gdal_job(
      command_path = c("gdal", "vector", "filter"),
      arguments = list(where = "name = 'test'"),
      arg_mapping = list()
    ),
    new_gdal_job(
      command_path = c("gdal", "vector", "write"),
      arguments = list(output = "my output.gpkg"),
      arg_mapping = list()
    )
  )

  pipeline <- new_gdal_pipeline(jobs = jobs, name = NA_character_)
  command_line <- .pipeline_to_rfc104_command(pipeline)

  # Should contain quoted filenames
  expect_true(grepl("'my input file\\.gpkg'", command_line) || grepl("'my input file.gpkg'", command_line))
  expect_true(grepl("'my output\\.gpkg'", command_line) || grepl("'my output.gpkg'", command_line))
})

test_that("gdal_save_pipeline saves GDALG JSON format to disk", {
  skip_if_not(requireNamespace("jsonlite", quietly = TRUE))

  tmpfile <- tempfile(fileext = ".gdalg.json")
  on.exit(unlink(tmpfile))

  jobs <- list(
    new_gdal_job(
      command_path = c("gdal", "vector", "read"),
      arguments = list(input = "input.gpkg"),
      arg_mapping = list()
    ),
    new_gdal_job(
      command_path = c("gdal", "vector", "write"),
      arguments = list(output = "output.gpkg"),
      arg_mapping = list()
    )
  )

  pipeline <- new_gdal_pipeline(jobs = jobs, name = NA_character_)

  # Save
  result <- gdal_save_pipeline(pipeline, tmpfile)

  # Check file was created
  expect_true(file.exists(tmpfile))

  # Check file contains valid JSON
  json_content <- jsonlite::fromJSON(tmpfile)
  expect_equal(json_content$type, "gdal_streamed_alg")
  expect_true(is.character(json_content$command_line))
  expect_true(json_content$relative_paths_relative_to_this_file)
})

test_that("gdal_load_pipeline loads GDALG JSON and reconstructs pipeline", {
  skip_if_not(requireNamespace("jsonlite", quietly = TRUE))

  tmpfile <- tempfile(fileext = ".gdalg.json")
  on.exit(unlink(tmpfile))

  # Create and save a pipeline
  jobs <- list(
    new_gdal_job(
      command_path = c("gdal", "raster", "read"),
      arguments = list(input = "input.tif"),
      arg_mapping = list()
    ),
    new_gdal_job(
      command_path = c("gdal", "raster", "reproject"),
      arguments = list(dst_crs = "EPSG:3857"),
      arg_mapping = list()
    )
  )

  pipeline1 <- new_gdal_pipeline(jobs = jobs, name = NA_character_)
  gdal_save_pipeline(pipeline1, tmpfile)

  # Load it back
  pipeline2 <- gdal_load_pipeline(tmpfile)

  # Verify structure
  expect_true(inherits(pipeline2, "gdal_pipeline"))
  expect_length(pipeline2$jobs, 2)
  expect_equal(pipeline2$jobs[[1]]$command_path[3], "read")
  expect_equal(pipeline2$jobs[[2]]$command_path[3], "reproject")
})

test_that("gdal_save_pipeline errors on non-existent path and requires overwrite", {
  tmpfile <- tempfile(fileext = ".gdalg.json")

  jobs <- list(
    new_gdal_job(
      command_path = c("gdal", "vector", "read"),
      arguments = list(input = "input.gpkg"),
      arg_mapping = list()
    )
  )

  pipeline <- new_gdal_pipeline(jobs = jobs, name = NA_character_)

  # First save should work
  gdal_save_pipeline(pipeline, tmpfile)
  expect_true(file.exists(tmpfile))

  # Second save without overwrite should error
  expect_error(
    gdal_save_pipeline(pipeline, tmpfile, overwrite = FALSE),
    "already exists"
  )

  # With overwrite should work
  expect_no_error(gdal_save_pipeline(pipeline, tmpfile, overwrite = TRUE))

  on.exit(unlink(tmpfile))
})

test_that("gdal_load_pipeline validates GDALG spec structure", {
  skip_if_not(requireNamespace("jsonlite", quietly = TRUE))

  tmpfile <- tempfile(fileext = ".json")
  on.exit(unlink(tmpfile))

  # Invalid: missing type
  invalid_spec <- list(command_line = "...")
  writeLines(jsonlite::toJSON(invalid_spec), tmpfile)
  expect_error(gdal_load_pipeline(tmpfile), "type")

  # Invalid: wrong type value
  invalid_spec <- list(type = "wrong", command_line = "...")
  writeLines(jsonlite::toJSON(invalid_spec), tmpfile)
  expect_error(gdal_load_pipeline(tmpfile), 'gdal_streamed_alg')

  # Invalid: missing command_line
  invalid_spec <- list(type = "gdal_streamed_alg")
  writeLines(jsonlite::toJSON(invalid_spec), tmpfile)
  expect_error(gdal_load_pipeline(tmpfile), "command_line")
})

test_that("Complex vector pipeline with multiple operations round-trips", {
  jobs <- list(
    new_gdal_job(
      command_path = c("gdal", "vector", "read"),
      arguments = list(input = "data.gpkg", layer = c("layer1", "layer2")),
      arg_mapping = list(layer = list(min_count = 0, max_count = 999))
    ),
    new_gdal_job(
      command_path = c("gdal", "vector", "filter"),
      arguments = list(bbox = c(-120, 30, -110, 40)),
      arg_mapping = list(bbox = list(min_count = 4, max_count = 4))
    ),
    new_gdal_job(
      command_path = c("gdal", "vector", "reproject"),
      arguments = list(dst_crs = "EPSG:32632"),
      arg_mapping = list()
    ),
    new_gdal_job(
      command_path = c("gdal", "vector", "write"),
      arguments = list(output = "output.gpkg"),
      arg_mapping = list()
    )
  )

  pipeline1 <- new_gdal_pipeline(jobs = jobs, name = NA_character_)

  # Serialize
  command_line <- .pipeline_to_rfc104_command(pipeline1)

  # Should have 4 steps
  steps <- strsplit(command_line, " ! ")[[1]]
  expect_length(steps[steps != ""], 5)  # gdal vector pipeline ! + 4 steps

  # Deserialize
  pipeline2 <- .gdalg_to_pipeline(command_line)

  # Check structure
  expect_equal(length(pipeline1$jobs), length(pipeline2$jobs))
})

# Hybrid Format Tests (.gdalcli.json v0.5.0+)

test_that("Hybrid format generation includes all three components", {
  # Create test pipeline
  pipeline <- structure(
    list(
      jobs = list(
        structure(
          list(
            command_path = c("gdal", "raster", "clip"),
            arguments = list(input = "input.tif", output = "output.tif"),
            arg_mapping = list(input = "source", output = "destination"),
            config_options = c("GDAL_CACHEMAX=512"),
            env_vars = c(AWS_ACCESS_KEY_ID = "test-key"),
            stream_in = NULL,
            stream_out_format = NULL
          ),
          class = "gdal_job"
        )
      ),
      name = NULL,
      description = NULL
    ),
    class = "gdal_pipeline"
  )

  spec <- .pipeline_to_gdalcli_spec(pipeline)

  # Verify three components
  expect_true(!is.null(spec$gdalg))
  expect_true(!is.null(spec$metadata))
  expect_true(!is.null(spec$r_job_specs))

  # Verify gdalg structure
  expect_equal(spec$gdalg$type, "gdal_streamed_alg")
  expect_true(!is.null(spec$gdalg$command_line))
  expect_true(is.logical(spec$gdalg$relative_paths_relative_to_this_file))

  # Verify metadata structure
  expect_true(!is.null(spec$metadata$gdalcli_version))
  expect_true(!is.null(spec$metadata$gdal_version_required))
  expect_true(!is.null(spec$metadata$created_at))
  expect_true(!is.null(spec$metadata$created_by_r_version))

  # Verify r_job_specs
  expect_equal(length(spec$r_job_specs), 1)
  expect_true(!is.null(spec$r_job_specs[[1]]$command_path))
  expect_true(!is.null(spec$r_job_specs[[1]]$arguments))
})

test_that("Hybrid format preserves metadata fields", {
  pipeline <- structure(
    list(
      jobs = list(
        structure(
          list(
            command_path = c("gdal", "raster", "convert"),
            arguments = list(),
            arg_mapping = list(),
            config_options = character(),
            env_vars = character(),
            stream_in = NULL,
            stream_out_format = NULL
          ),
          class = "gdal_job"
        )
      ),
      name = NULL,
      description = NULL
    ),
    class = "gdal_pipeline"
  )

  spec <- .pipeline_to_gdalcli_spec(
    pipeline,
    name = "Test Pipeline",
    description = "A test pipeline",
    custom_tags = list(version = "1.0", author = "test")
  )

  # Check metadata preservation
  expect_equal(spec$metadata$pipeline_name, "Test Pipeline")
  expect_equal(spec$metadata$pipeline_description, "A test pipeline")
  expect_equal(spec$metadata$custom_tags$version, "1.0")
  expect_equal(spec$metadata$custom_tags$author, "test")
})

test_that("Hybrid format preserves full job specifications", {
  pipeline <- structure(
    list(
      jobs = list(
        structure(
          list(
            command_path = c("gdal", "raster", "clip"),
            arguments = list(input = "input.tif", output = "output.tif", projwin = "1,2,3,4"),
            arg_mapping = list(input = "source", output = "dest", projwin = "bbox"),
            config_options = c("GDAL_CACHEMAX=512", "MAX_TEMP_FILE_SIZE=100MB"),
            env_vars = c(AWS_ACCESS_KEY_ID = "key123", AWS_SECRET = "secret"),
            stream_in = "stdin",
            stream_out_format = "COG"
          ),
          class = "gdal_job"
        )
      ),
      name = NULL,
      description = NULL
    ),
    class = "gdal_pipeline"
  )

  spec <- .pipeline_to_gdalcli_spec(pipeline)

  # Verify job spec preservation
  job_spec <- spec$r_job_specs[[1]]
  expect_equal(job_spec$command_path, c("gdal", "raster", "clip"))
  expect_equal(job_spec$arguments$output, "output.tif")
  expect_equal(job_spec$arg_mapping$input, "source")
  expect_true(any(grepl("GDAL_CACHEMAX=512", job_spec$config_options)))
  expect_true("AWS_ACCESS_KEY_ID" %in% names(job_spec$env_vars))
  expect_equal(job_spec$stream_in, "stdin")
  expect_equal(job_spec$stream_out_format, "COG")
})

test_that("Hybrid format round-trip: save and load preserves metadata", {
  pipeline <- structure(
    list(
      jobs = list(
        structure(
          list(
            command_path = c("gdal", "raster", "scale"),
            arguments = list(src_min = 0, src_max = 255),
            arg_mapping = list(),
            config_options = character(),
            env_vars = character(),
            stream_in = NULL,
            stream_out_format = NULL
          ),
          class = "gdal_job"
        )
      ),
      name = NULL,
      description = NULL
    ),
    class = "gdal_pipeline"
  )

  # Convert to spec
  spec1 <- .pipeline_to_gdalcli_spec(
    pipeline,
    name = "Round-trip Test",
    description = "Testing metadata preservation",
    custom_tags = list(test = TRUE)
  )

  # Serialize to JSON
  json_str <- jsonlite::toJSON(spec1, pretty = TRUE, auto_unbox = TRUE)

  # Deserialize from JSON
  spec2 <- jsonlite::fromJSON(json_str, simplifyVector = FALSE)

  # Verify metadata preserved through JSON round-trip
  expect_equal(spec2$metadata$pipeline_name, "Round-trip Test")
  expect_equal(spec2$metadata$pipeline_description, "Testing metadata preservation")
  expect_equal(spec2$metadata$custom_tags$test, TRUE)
})

test_that("Hybrid format auto-detection recognizes gdalg component", {
  spec <- list(
    gdalg = list(
      type = "gdal_streamed_alg",
      command_line = "gdal raster pipeline ! clip input.tif output.tif",
      relative_paths_relative_to_this_file = TRUE
    ),
    metadata = list(),
    r_job_specs = list()
  )

  # Should recognize hybrid format and load successfully
  expect_no_error({
    pipeline <- .gdalcli_spec_to_pipeline(spec)
  })

  # Result should be a gdal_pipeline
  expect_true(inherits(pipeline, "gdal_pipeline"))
})

test_that("Hybrid format prefers r_job_specs for lossless reconstruction", {
  spec <- list(
    gdalg = list(
      type = "gdal_streamed_alg",
      command_line = "gdal raster pipeline ! clip input.tif output.tif",
      relative_paths_relative_to_this_file = TRUE
    ),
    metadata = list(),
    r_job_specs = list(
      list(
        command_path = c("gdal", "raster", "clip"),
        arguments = list(input = "input.tif", output = "output.tif"),
        arg_mapping = list(input = "source", output = "dest"),
        config_options = "GDAL_CACHEMAX=512",
        env_vars = "KEY=value",
        stream_in = NULL,
        stream_out_format = NULL
      )
    )
  )

  pipeline <- .gdalcli_spec_to_pipeline(spec)

  # Verify that arg_mapping from r_job_specs is used (not reconstructed from command_line)
  expect_equal(
    pipeline$jobs[[1]]$arg_mapping,
    list(input = "source", output = "dest")
  )
})

test_that("Legacy format error handling - rejects pre-v0.5.0 .gdalcli.json", {
  legacy_spec <- list(
    steps = list(
      list(operation = "clip", input = "input.tif")
    ),
    name = "Old Format"
  )

  # Should error with helpful message
  expect_error(
    .gdalcli_spec_to_pipeline(legacy_spec),
    "legacy|pre-v0.5.0|no longer supported"
  )
})
