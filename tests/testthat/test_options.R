test_that("gdalcli_options() returns default values when called without arguments", {
  # Reset to defaults
  options(
    gdalcli.backend = "auto",
    gdalcli.stream_out_format = NULL,
    gdalcli.verbose = FALSE,
    gdalcli.audit_logging = FALSE
  )

  result <- gdalcli_options()

  expect_is(result, "list")
  expect_named(result, c("backend", "stream_out_format", "verbose", "audit_logging"))
  expect_equal(result$backend, "auto")
  expect_null(result$stream_out_format)
  expect_false(result$verbose)
  expect_false(result$audit_logging)
})

test_that("gdalcli_options() can set single option", {
  # Reset to defaults
  options(gdalcli.backend = "auto")

  old <- gdalcli_options(backend = "processx")

  expect_equal(old$backend, "auto")
  expect_equal(getOption("gdalcli.backend"), "processx")
  expect_equal(gdalcli_options()$backend, "processx")
})

test_that("gdalcli_options() can set multiple options at once", {
  # Reset to defaults
  options(
    gdalcli.backend = "auto",
    gdalcli.verbose = FALSE,
    gdalcli.audit_logging = FALSE
  )

  old <- gdalcli_options(
    backend = "gdalraster",
    verbose = TRUE,
    audit_logging = TRUE
  )

  expect_equal(old$backend, "auto")
  expect_false(old$verbose)
  expect_false(old$audit_logging)

  current <- gdalcli_options()
  expect_equal(current$backend, "gdalraster")
  expect_true(current$verbose)
  expect_true(current$audit_logging)
})

test_that("gdalcli_options() tolerates NULL values", {
  old <- gdalcli_options(stream_out_format = NULL)

  expect_equal(getOption("gdalcli.stream_out_format"), NULL)
  current <- gdalcli_options()
  expect_null(current$stream_out_format)
})

test_that("gdalcli_options() rejects invalid option names", {
  expect_error(
    gdalcli_options(invalid_option = "value"),
    "Unknown option.*invalid_option.*Valid options are"
  )

  expect_error(
    gdalcli_options(backend = "processx", nonexistent = TRUE),
    "Unknown option.*nonexistent.*Valid options are"
  )
})

test_that("gdalcli_options() returns previous values invisibly", {
  # Reset to defaults
  options(gdalcli.backend = "auto")

  old <- gdalcli_options(backend = "processx")

  expect_invisible(gdalcli_options(backend = "auto"))
  expect_equal(old$backend, "auto")
})

test_that("gdalcli_options() accepts all valid backend options", {
  valid_backends <- c("auto", "gdalraster", "processx", "reticulate")

  for (backend in valid_backends) {
    gdalcli_options(backend = backend)
    expect_equal(gdalcli_options()$backend, backend)
  }
})

test_that("gdalcli_options() rejects invalid backend values", {
  expect_error(
    gdalcli_options(backend = "invalid_backend"),
    "Invalid backend.*invalid_backend.*Valid backends are"
  )

  expect_error(
    gdalcli_options(backend = "gdal"),
    "Invalid backend.*gdal.*Valid backends are"
  )
})
