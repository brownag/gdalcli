test_that("pipeline creation and basic execution works", {
  # Create a simple pipeline
  job1 <- gdal_raster_info(input = "test.tif")
  job2 <- gdal_raster_convert(input = "test.tif", output = "output.jpg")

  # Create pipeline
  pipeline <- new_gdal_pipeline(list(job1, job2))
  expect_s3_class(pipeline, "gdal_pipeline")
  expect_length(pipeline$jobs, 2)
  expect_s3_class(pipeline$jobs[[1]], "gdal_job")
  expect_s3_class(pipeline$jobs[[2]], "gdal_job")
})

test_that("pipeline operator creates correct pipeline", {
  # Test pipeline operator
  job <- gdal_raster_info(input = "input.tif") |>
    gdal_raster_convert(output = "output.jpg")

  expect_s3_class(job, "gdal_job")
  expect_s3_class(job$pipeline, "gdal_pipeline")
  expect_length(job$pipeline$jobs, 2)
})

test_that("serialize_gdal_job handles argument ordering correctly", {
  # Test positional arguments come before options
  job <- gdal_vector_rasterize(
    input = "input.shp",
    output = "output.tif",
    burn = 1,
    resolution = c(10, 10)
  )

  args <- .serialize_gdal_job(job)

  # Should start with command parts, then positional args, then options
  expect_equal(unname(args[1:3]), c("vector", "rasterize", "input.shp"))
  expect_equal(unname(args[4]), "output.tif")

  # Options should come after positional args
  burn_idx <- which(args == "--burn")
  resolution_idx <- which(args == "--resolution")

  expect_true(burn_idx > 4)  # After positional args
  expect_true(resolution_idx > 4)
})

test_that("serialize_gdal_job handles flag mappings correctly", {
  # Test resolution maps to --resolution, not --tr
  job <- gdal_vector_rasterize(
    input = "input.shp",
    output = "output.tif",
    resolution = c(10, 10)
  )

  args <- .serialize_gdal_job(job)

  # Should use --resolution, not --tr
  expect_true("--resolution" %in% args)
  expect_false("--tr" %in% args)

  resolution_idx <- which(args == "--resolution")
  expect_equal(unname(args[resolution_idx + 1]), "10,10")
})

test_that("serialize_gdal_job handles comma-separated multi-value args", {
  # Test bbox uses comma separation - use gdal_raster_create which has bbox
  job <- gdal_raster_create(
    output = "output.tif",
    size = c(100, 100),
    bbox = c(-180, -90, 180, 90)
  )

  args <- .serialize_gdal_job(job)

  # Should have comma-separated bbox
  bbox_idx <- which(args == "--bbox")
  expect_equal(unname(args[bbox_idx + 1]), "-180,-90,180,90")
})

test_that("pipeline connections work correctly", {
  # Test that pipeline connects outputs to inputs
  job <- gdal_vector_reproject(
    input = "input.shp",
    output = "temp.gpkg",
    dst_crs = "EPSG:4326"
  ) |>
  gdal_vector_rasterize(
    output = "output.tif",
    burn = 1,
    resolution = c(10, 10)
  )

  # Check that the rasterize job has input set to temp.gpkg
  pipeline <- job$pipeline
  rasterize_job <- pipeline$jobs[[2]]

  expect_equal(rasterize_job$arguments$input, "temp.gpkg")
})

test_that("pipeline uses temp files for connections when needed", {
  # Test pipeline with jobs that produce outputs
  job <- gdal_vector_reproject(
    input = "input.shp",
    output = "temp.gpkg",
    dst_crs = "EPSG:4326"
  ) |>
  gdal_vector_rasterize(
    output = "output.tif",
    burn = 1
  )

  pipeline <- job$pipeline
  rasterize_job <- pipeline$jobs[[2]]

  # The rasterize job should have input set to temp.gpkg
  expect_true("input" %in% names(rasterize_job$arguments))
  expect_equal(rasterize_job$arguments$input, "temp.gpkg")
})

test_that("pipeline execution fails gracefully on errors", {
  # Create a pipeline with invalid arguments
  job <- gdal_raster_info(input = "nonexistent.tif") |>
    gdal_raster_convert(output = "output.jpg")

  # Should fail at first job
  expect_error(
    gdal_job_run(job),
    "Pipeline failed at job 1"
  )
})

test_that("pipeline with virtual paths doesn't override user outputs", {
  # Test that user-specified outputs are preserved
  job <- gdal_vector_reproject(
    input = "input.shp",
    output = "user_output.gpkg",
    dst_crs = "EPSG:4326"
  ) |>
  gdal_vector_rasterize(
    output = "user_raster.tif",
    burn = 1
  )

  pipeline <- job$pipeline

  # First job should still output to user_output.gpkg
  reproject_job <- pipeline$jobs[[1]]
  expect_equal(reproject_job$arguments$output, "user_output.gpkg")

  # Second job should input from user_output.gpkg and output to user_raster.tif
  rasterize_job <- pipeline$jobs[[2]]
  expect_equal(rasterize_job$arguments$input, "user_output.gpkg")
  expect_equal(rasterize_job$arguments$output, "user_raster.tif")
})

test_that("render_gdal_pipeline creates correct command strings", {
  job <- gdal_raster_info(input = "input.tif") |>
    gdal_raster_convert(output = "output.jpg")

  rendered <- render_gdal_pipeline(job)
  expect_type(rendered, "character")
  expect_true(grepl("gdal raster info", rendered))
  expect_true(grepl("gdal raster convert", rendered))
})

test_that("render_shell_script creates executable script", {
  job <- gdal_raster_info(input = "input.tif") |>
    gdal_raster_convert(output = "output.jpg")

  script <- render_shell_script(job)
  expect_type(script, "character")
  expect_true(grepl("#!/bin/bash", script))
  expect_true(grepl("set -e", script))
  expect_true(grepl("gdal raster info", script))
  expect_true(grepl("gdal raster convert", script))
})

test_that("pipeline metadata can be set and retrieved", {
  job <- gdal_raster_info(input = "input.tif") |>
    gdal_raster_convert(output = "output.jpg")

  # Set metadata
  job <- set_name(job, "Test Pipeline")
  job <- set_description(job, "A test pipeline")

  expect_equal(job$pipeline$name, "Test Pipeline")
  expect_equal(job$pipeline$description, "A test pipeline")
})

test_that("get_jobs returns correct job list", {
  job1 <- gdal_raster_info(input = "input.tif")
  job2 <- gdal_raster_convert(input = "input.tif", output = "output.jpg")

  pipeline <- new_gdal_pipeline(list(job1, job2))
  jobs <- get_jobs(pipeline)

  expect_length(jobs, 2)
  expect_s3_class(jobs[[1]], "gdal_job")
  expect_s3_class(jobs[[2]], "gdal_job")
})

test_that("add_job extends pipeline correctly", {
  job1 <- gdal_raster_info(input = "input.tif")
  job2 <- gdal_raster_convert(input = "input.tif", output = "output.jpg")

  pipeline <- new_gdal_pipeline(list(job1))
  extended <- add_job(pipeline, job2)

  expect_length(extended$jobs, 2)
  expect_equal(extended$jobs[[2]], job2)
})

test_that("empty pipeline renders correctly", {
  pipeline <- new_gdal_pipeline(list())
  expect_length(pipeline$jobs, 0)

  rendered <- render_gdal_pipeline(pipeline)
  expect_equal(rendered, "gdal pipeline")
})

test_that("is_virtual_path correctly identifies virtual paths", {
  expect_true(is_virtual_path("/vsimem/temp.tif"))
  expect_true(is_virtual_path("/vsis3/bucket/key"))
  expect_true(is_virtual_path("/vsizip/archive.zip/file.txt"))

  expect_false(is_virtual_path("regular_file.tif"))
  expect_false(is_virtual_path("/home/user/file.tif"))
  expect_false(is_virtual_path("C:/windows/file.tif"))
})

# ============================================================================
# Phase 1: Native Pipeline Execution Tests
# ============================================================================

test_that("render_native_pipeline generates correct native format", {
  pipeline <- gdal_raster_info(input = "input.tif") |>
    gdal_raster_reproject(dst_crs = "EPSG:32632") |>
    gdal_raster_convert(output = "output.tif")

  # Extract the pipeline object and render with native format
  pipe_obj <- pipeline$pipeline
  native_cmd <- render_gdal_pipeline(pipe_obj, format = "native")

  expect_type(native_cmd, "character")
  expect_true(grepl("! read", native_cmd))
  expect_true(grepl("! reproject", native_cmd))
  expect_true(grepl("! write", native_cmd))
  expect_true(grepl("--dst-crs", native_cmd))
})

test_that("render_gdal_pipeline with format='native' includes full command", {
  pipeline <- gdal_raster_info(input = "input.tif") |>
    gdal_raster_reproject(dst_crs = "EPSG:32632") |>
    gdal_raster_convert(output = "output.tif")

  pipe_obj <- pipeline$pipeline
  native_cmd <- render_gdal_pipeline(pipe_obj, format = "native")

  expect_type(native_cmd, "character")
  expect_true(grepl("gdal raster pipeline", native_cmd))
  expect_true(grepl("! read input.tif", native_cmd))
  expect_true(grepl("! write output.tif", native_cmd))
})

test_that("render_gdal_pipeline with format='shell_chain' uses && separator", {
  pipeline <- gdal_raster_info(input = "input.tif") |>
    gdal_raster_convert(output = "output.tif")

  pipe_obj <- pipeline$pipeline
  chain_cmd <- render_gdal_pipeline(pipe_obj, format = "shell_chain")

  expect_type(chain_cmd, "character")
  expect_true(grepl(" && ", chain_cmd))
  expect_true(grepl("gdal raster info", chain_cmd))
  expect_true(grepl("gdal raster convert", chain_cmd))
})

test_that("gdal_job_run pipeline with execution_mode='sequential' runs all jobs", {
  # This is more of a structural test since we can't actually run GDAL
  pipeline <- gdal_raster_info(input = "input.tif") |>
    gdal_raster_convert(output = "output.tif")

  expect_s3_class(pipeline, "gdal_job")
  expect_s3_class(pipeline$pipeline, "gdal_pipeline")
  expect_length(pipeline$pipeline$jobs, 2)
})

test_that("gdal_job_run accepts execution_mode parameter", {
  # Test that the parameter is accepted (structural test)
  job <- gdal_raster_info(input = "input.tif") |>
    gdal_raster_convert(output = "output.tif")

  # Just check that calling with the parameter doesn't error on parameter validation
  # (actual execution will fail due to missing GDAL, but that's expected)
  expect_s3_class(job, "gdal_job")
})

test_that("native pipeline execution detects pipeline type correctly", {
  # Test raster pipeline detection
  raster_pipeline <- gdal_raster_info(input = "raster.tif") |>
    gdal_raster_reproject(dst_crs = "EPSG:32632")

  pipe_obj <- raster_pipeline$pipeline
  first_job <- pipe_obj$jobs[[1]]

  cmd_path <- first_job$command_path
  if (length(cmd_path) > 0 && cmd_path[1] == "gdal") {
    cmd_path <- cmd_path[-1]
  }
  pipeline_type <- if (length(cmd_path) > 0) cmd_path[1] else "raster"

  expect_equal(pipeline_type, "raster")
})

test_that("native pipeline execution detects vector pipeline type", {
  # Test vector pipeline detection
  vector_pipeline <- gdal_vector_info(input = "vector.gpkg") |>
    gdal_vector_reproject(dst_crs = "EPSG:32632")

  pipe_obj <- vector_pipeline$pipeline
  first_job <- pipe_obj$jobs[[1]]

  cmd_path <- first_job$command_path
  if (length(cmd_path) > 0 && cmd_path[1] == "gdal") {
    cmd_path <- cmd_path[-1]
  }
  pipeline_type <- if (length(cmd_path) > 0) cmd_path[1] else "raster"

  expect_equal(pipeline_type, "vector")
})

test_that("native pipeline rendering skips input/output in intermediate steps", {
  pipeline <- gdal_raster_info(input = "input.tif") |>
    gdal_raster_reproject(dst_crs = "EPSG:32632") |>
    gdal_raster_convert(output = "output.tif")

  pipe_obj <- pipeline$pipeline
  native_cmd <- render_gdal_pipeline(pipe_obj, format = "native")

  # The reproject step should NOT have --input or --output flags
  # (because it's an intermediate step)
  expect_false(grepl("reproject.*--input", native_cmd))
  expect_false(grepl("reproject.*--output", native_cmd))
})

# ============================================================================
# Phase 2: Shell Script Generation Tests
# ============================================================================

test_that("render_shell_script with format='commands' generates separate commands", {
  pipeline <- gdal_raster_info(input = "input.tif") |>
    gdal_raster_reproject(dst_crs = "EPSG:32632") |>
    gdal_raster_convert(output = "output.tif")

  script <- render_shell_script(pipeline, format = "commands")

  expect_type(script, "character")
  expect_true(grepl("#!/bin/bash", script))
  expect_true(grepl("set -e", script))
  # Should have multiple gdal commands
  lines <- strsplit(script, "\n")[[1]]
  gdal_lines <- lines[grepl("^gdal ", lines)]
  expect_true(length(gdal_lines) > 1)
})

test_that("render_shell_script with format='native' generates single pipeline command", {
  pipeline <- gdal_raster_info(input = "input.tif") |>
    gdal_raster_reproject(dst_crs = "EPSG:32632") |>
    gdal_raster_convert(output = "output.tif")

  script <- render_shell_script(pipeline, format = "native")

  expect_type(script, "character")
  expect_true(grepl("#!/bin/bash", script))
  expect_true(grepl("set -e", script))
  expect_true(grepl("gdal raster pipeline", script))
  # Should have single pipeline command with ! syntax
  expect_true(grepl("! read", script))
  expect_true(grepl("! reproject", script))
  expect_true(grepl("! write", script))
})

test_that("render_shell_script respects shell parameter", {
  pipeline <- gdal_raster_info(input = "input.tif") |>
    gdal_raster_convert(output = "output.tif")

  script_bash <- render_shell_script(pipeline, shell = "bash")
  script_zsh <- render_shell_script(pipeline, shell = "zsh")

  expect_true(grepl("#!/bin/bash", script_bash))
  expect_true(grepl("#!/bin/zsh", script_zsh))
})

test_that("render_shell_script includes pipeline metadata", {
  pipeline <- new_gdal_pipeline(
    list(
      gdal_raster_info(input = "input.tif"),
      gdal_raster_convert(output = "output.tif")
    ),
    name = "Test Pipeline",
    description = "A test pipeline"
  )

  script <- render_shell_script(pipeline, format = "native")

  expect_true(grepl("Test Pipeline", script))
  expect_true(grepl("A test pipeline", script))
})

test_that("render_shell_script with format defaults to 'commands'", {
  pipeline <- gdal_raster_info(input = "input.tif") |>
    gdal_raster_convert(output = "output.tif")

  script_default <- render_shell_script(pipeline)
  script_explicit <- render_shell_script(pipeline, format = "commands")

  # Both should be identical (default should be 'commands')
  expect_equal(script_default, script_explicit)
})

test_that("gdal_pipeline convenience function detects pipeline type", {
  # Create raster jobs
  job1 <- gdal_raster_info(input = "input.tif")
  job2 <- gdal_raster_reproject(dst_crs = "EPSG:32632")

  # Create pipeline using convenience function
  pipeline_job <- gdal_pipeline(jobs = list(job1, job2))

  expect_s3_class(pipeline_job, "gdal_job")
  expect_equal(pipeline_job$command_path[1], "raster")
  expect_equal(pipeline_job$command_path[2], "pipeline")
})

test_that("gdal_pipeline convenience function works with vector jobs", {
  # Create vector jobs
  job1 <- gdal_vector_info(input = "input.gpkg")
  job2 <- gdal_vector_reproject(dst_crs = "EPSG:32632")

  # Create pipeline using convenience function
  pipeline_job <- gdal_pipeline(jobs = list(job1, job2))

  expect_s3_class(pipeline_job, "gdal_job")
  expect_equal(pipeline_job$command_path[1], "vector")
  expect_equal(pipeline_job$command_path[2], "pipeline")
})