test_that("checkpoint directory is created on demand", {
  checkpoint_dir <- tempfile(pattern = "checkpoint_")
  on.exit(unlink(checkpoint_dir, recursive = TRUE))

  expect_false(dir.exists(checkpoint_dir))

  # Simulate creating checkpoint
  dir.create(checkpoint_dir, recursive = TRUE)
  expect_true(dir.exists(checkpoint_dir))
})


test_that("checkpoint metadata can be saved and loaded", {
  checkpoint_dir <- tempfile(pattern = "checkpoint_")
  on.exit(unlink(checkpoint_dir, recursive = TRUE))

  # Create a mock pipeline
  job1 <- gdal_raster_info(input = "test.tif")
  pipeline <- new_gdal_pipeline(list(job1))

  # Compute hash
  hash <- .compute_pipeline_hash(pipeline)
  expect_true(is.character(hash))
  expect_true(nchar(hash) > 0)

  # Save checkpoint
  metadata <- .save_checkpoint(pipeline, checkpoint_dir, 1, NULL)

  expect_true(is.list(metadata))
  expect_true(!is.null(metadata$pipeline_id))
  expect_equal(metadata$completed_steps, 1)
  expect_equal(metadata$total_steps, 1)

  # Verify metadata file was created
  expect_true(file.exists(file.path(checkpoint_dir, "metadata.json")))

  # Load checkpoint
  loaded <- .load_checkpoint(checkpoint_dir)
  expect_equal(loaded$pipeline_id, metadata$pipeline_id)
  expect_equal(loaded$completed_steps, 1)
})


test_that("pipeline hash is consistent for same pipeline", {
  job1 <- gdal_raster_info(input = "test.tif")
  pipeline1 <- new_gdal_pipeline(list(job1))

  job2 <- gdal_raster_info(input = "test.tif")
  pipeline2 <- new_gdal_pipeline(list(job2))

  hash1 <- .compute_pipeline_hash(pipeline1)
  hash2 <- .compute_pipeline_hash(pipeline2)

  expect_equal(hash1, hash2)
})


test_that("pipeline hash differs for different pipelines", {
  job1 <- gdal_raster_info(input = "test1.tif")
  pipeline1 <- new_gdal_pipeline(list(job1))

  job2 <- gdal_raster_info(input = "test2.tif")
  pipeline2 <- new_gdal_pipeline(list(job2))

  hash1 <- .compute_pipeline_hash(pipeline1)
  hash2 <- .compute_pipeline_hash(pipeline2)

  expect_false(identical(hash1, hash2))
})


test_that("checkpoint detects pipeline changes", {
  checkpoint_dir <- tempfile(pattern = "checkpoint_")
  on.exit(unlink(checkpoint_dir, recursive = TRUE))

  # Create and save checkpoint for one pipeline
  job1 <- gdal_raster_info(input = "test.tif")
  pipeline1 <- new_gdal_pipeline(list(job1))
  checkpoint_state <- .save_checkpoint(pipeline1, checkpoint_dir, 1, NULL)

  # Try to resume with a different pipeline
  job2 <- gdal_raster_reproject(input = "test.tif", dst_crs = "EPSG:4326")
  pipeline2 <- new_gdal_pipeline(list(job2))

  # Should detect mismatch
  hash1 <- checkpoint_state$pipeline_id
  hash2 <- .compute_pipeline_hash(pipeline2)
  expect_false(identical(hash1, hash2))
})


test_that("checkpoint respects global option for directory", {
  # Save old option
  old_option <- getOption("gdalcli.checkpoint_dir")
  on.exit(options(gdalcli.checkpoint_dir = old_option))

  # Set custom option
  custom_dir <- "/custom/checkpoint/path"
  options(gdalcli.checkpoint_dir = custom_dir)

  # Verify it would be used as default
  expect_equal(
    getOption("gdalcli.checkpoint_dir", ".gdalcli.checkpoint"),
    custom_dir
  )
})


test_that("checkpoint metadata includes version and timestamps", {
  checkpoint_dir <- tempfile(pattern = "checkpoint_")
  on.exit(unlink(checkpoint_dir, recursive = TRUE))

  job1 <- gdal_raster_info(input = "test.tif")
  pipeline <- new_gdal_pipeline(list(job1))

  metadata <- .save_checkpoint(pipeline, checkpoint_dir, 1, NULL)

  # Check required fields
  expect_true(!is.null(metadata$gdalcli_version))
  expect_true(!is.null(metadata$created_at))
  expect_true(!is.null(metadata$pipeline_id))
  expect_true(!is.null(metadata$total_steps))
  expect_true(!is.null(metadata$completed_steps))
  expect_true(!is.null(metadata$step_outputs))

  # Verify types
  expect_true(is.character(metadata$gdalcli_version))
  expect_true(is.character(metadata$created_at))
  expect_true(is.list(metadata$step_outputs))
})


test_that("checkpoint can save and load step outputs", {
  checkpoint_dir <- tempfile(pattern = "checkpoint_")
  on.exit(unlink(checkpoint_dir, recursive = TRUE))

  # Create a temporary output file
  temp_output <- tempfile(fileext = ".tif")
  writeLines("dummy output", temp_output)
  on.exit(unlink(temp_output), add = TRUE)

  job1 <- gdal_raster_info(input = "test.tif")
  pipeline <- new_gdal_pipeline(list(job1))

  # Save checkpoint with output file
  metadata <- .save_checkpoint(pipeline, checkpoint_dir, 1, temp_output)

  # Verify output was copied
  checkpoint_file <- metadata$step_outputs[["1"]]
  expect_true(!is.null(checkpoint_file))
  expect_true(file.exists(checkpoint_file))
})


test_that("multiple checkpoints can be saved sequentially", {
  checkpoint_dir <- tempfile(pattern = "checkpoint_")
  on.exit(unlink(checkpoint_dir, recursive = TRUE))

  job1 <- gdal_raster_info(input = "test.tif")
  pipeline <- new_gdal_pipeline(list(job1))

  # Save first checkpoint
  metadata1 <- .save_checkpoint(pipeline, checkpoint_dir, 1, NULL)
  expect_equal(metadata1$completed_steps, 1)

  # Save second checkpoint (simulating step 2)
  metadata2 <- .save_checkpoint(pipeline, checkpoint_dir, 2, NULL)
  expect_equal(metadata2$completed_steps, 2)

  # Load and verify latest state
  loaded <- .load_checkpoint(checkpoint_dir)
  expect_equal(loaded$completed_steps, 2)
})


test_that("pipeline with checkpoint parameter can be created", {
  job1 <- gdal_raster_info(input = "test.tif")
  job2 <- gdal_raster_reproject(input = "test.tif", dst_crs = "EPSG:4326")
  pipeline <- new_gdal_pipeline(list(job1, job2))

  expect_true(inherits(pipeline, "gdal_pipeline"))
  expect_equal(length(pipeline$jobs), 2)
})


test_that("checkpoint functions handle missing files gracefully", {
  checkpoint_dir <- tempfile(pattern = "checkpoint_")
  on.exit(unlink(checkpoint_dir, recursive = TRUE))

  # Load from non-existent checkpoint
  loaded <- .load_checkpoint(checkpoint_dir)
  expect_true(is.null(loaded))

  # Save checkpoint with non-existent output file
  job1 <- gdal_raster_info(input = "test.tif")
  pipeline <- new_gdal_pipeline(list(job1))

  # Should not fail even though output file doesn't exist
  metadata <- .save_checkpoint(pipeline, checkpoint_dir, 1, "/nonexistent/file.tif")
  expect_equal(metadata$completed_steps, 1)
})


test_that("checkpoint directory is cleaned up on pipeline success", {
  checkpoint_dir <- tempfile(pattern = "checkpoint_")

  # Create checkpoint directory
  dir.create(checkpoint_dir, recursive = TRUE)
  expect_true(dir.exists(checkpoint_dir))

  # Simulate cleanup
  unlink(checkpoint_dir, recursive = TRUE)
  expect_false(dir.exists(checkpoint_dir))
})


test_that("checkpoint preserves all metadata fields", {
  checkpoint_dir <- tempfile(pattern = "checkpoint_")
  on.exit(unlink(checkpoint_dir, recursive = TRUE))

  job1 <- gdal_raster_info(input = "input.tif")
  job2 <- gdal_raster_reproject(input = "input.tif", dst_crs = "EPSG:4326")
  pipeline <- new_gdal_pipeline(list(job1, job2))

  # Save checkpoint
  metadata <- .save_checkpoint(pipeline, checkpoint_dir, 1, NULL)

  # Verify all expected fields are present
  expected_fields <- c(
    "pipeline_id",
    "created_at",
    "total_steps",
    "completed_steps",
    "step_outputs",
    "gdalcli_version"
  )

  for (field in expected_fields) {
    expect_true(field %in% names(metadata),
                info = sprintf("Missing field: %s", field))
  }
})


test_that("checkpoint supports pipeline with multiple operations", {
  checkpoint_dir <- tempfile(pattern = "checkpoint_")
  on.exit(unlink(checkpoint_dir, recursive = TRUE))

  # Create a multi-step pipeline
  job1 <- gdal_raster_reproject(
    input = "input.tif",
    dst_crs = "EPSG:4326"
  )
  job2 <- gdal_raster_clip(
    input = "input.tif",
    bbox = c(0, 0, 10, 10)
  )
  pipeline <- new_gdal_pipeline(list(job1, job2))

  # Save checkpoint for first step
  metadata1 <- .save_checkpoint(pipeline, checkpoint_dir, 1, NULL)
  expect_equal(metadata1$total_steps, 2)
  expect_equal(metadata1$completed_steps, 1)

  # Save checkpoint for second step
  metadata2 <- .save_checkpoint(pipeline, checkpoint_dir, 2, NULL)
  expect_equal(metadata2$completed_steps, 2)

  # Verify progress
  loaded <- .load_checkpoint(checkpoint_dir)
  expect_equal(loaded$completed_steps, 2)
  expect_equal(loaded$total_steps, 2)
})


test_that("checkpoints are disabled by default", {
  # Verify checkpoints are off by default
  expect_false(getOption("gdalcli.checkpoint", FALSE))
})


test_that("gdalcli_options can enable checkpoints", {
  # Save old options
  old_checkpoint <- getOption("gdalcli.checkpoint", FALSE)
  on.exit(options(gdalcli.checkpoint = old_checkpoint))

  # Enable checkpoints
  gdalcli_options(checkpoint = TRUE)

  # Verify enabled
  expect_true(getOption("gdalcli.checkpoint", FALSE))
})


test_that("gdalcli_options sets checkpoint directory", {
  # Save old options
  old_dir <- getOption("gdalcli.checkpoint_dir", NULL)
  on.exit(options(gdalcli.checkpoint_dir = old_dir))

  custom_dir <- "/custom/checkpoint/path"

  # Set via gdalcli_options
  gdalcli_options(checkpoint_dir = custom_dir)

  # Verify set
  expect_equal(
    getOption("gdalcli.checkpoint_dir", NULL),
    custom_dir
  )
})


test_that("gdalcli_options defaults checkpoint_dir to current directory", {
  # Save old options
  old_checkpoint <- getOption("gdalcli.checkpoint", FALSE)
  old_dir <- getOption("gdalcli.checkpoint_dir", NULL)
  on.exit({
    options(gdalcli.checkpoint = old_checkpoint)
    options(gdalcli.checkpoint_dir = old_dir)
  })

  # Enable checkpoints without specifying directory
  gdalcli_options(checkpoint = TRUE)

  # Verify defaults to current working directory
  expect_equal(
    getOption("gdalcli.checkpoint_dir", NULL),
    getwd()
  )
})


test_that("gdalcli_options returns previous options", {
  # Save old options
  old_checkpoint <- getOption("gdalcli.checkpoint", FALSE)
  old_dir <- getOption("gdalcli.checkpoint_dir", NULL)
  on.exit({
    options(gdalcli.checkpoint = old_checkpoint)
    options(gdalcli.checkpoint_dir = old_dir)
  })

  # Ensure clean state
  options(gdalcli.checkpoint = FALSE)
  options(gdalcli.checkpoint_dir = NULL)

  # Call gdalcli_options
  result <- gdalcli_options(checkpoint = TRUE, checkpoint_dir = "/tmp")

  # Verify it returns previous values
  expect_false(result$checkpoint)
  expect_null(result$checkpoint_dir)
})


test_that("gdalcli_options validates input parameters", {
  # Save old options for cleanup
  old_checkpoint <- getOption("gdalcli.checkpoint", FALSE)
  on.exit(options(gdalcli.checkpoint = old_checkpoint))

  # Invalid checkpoint value
  expect_error(gdalcli_options(checkpoint = "yes"))

  # Invalid checkpoint_dir value
  expect_error(gdalcli_options(checkpoint_dir = 123))

  # Invalid backend value
  expect_error(gdalcli_options(backend = "invalid_backend"))
})
