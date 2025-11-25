# Tests for gdal_vector_from_object and related functions

test_that("gdal_vector_from_object validates input", {
  expect_error(
    gdal_vector_from_object("not_sf"),
    "x must be an sf object"
  )

  expect_error(
    gdal_vector_from_object(data.frame(x = 1, y = 2)),
    "x must be an sf object"
  )
})

test_that("gdal_vector_from_object accepts valid operation types", {
  skip_if_not_installed("sf")

  # Create minimal sf object for testing
  geom <- sf::st_sfc(
    sf::st_point(c(0, 0)),
    sf::st_point(c(1, 1))
  )
  sf_data <- sf::st_sf(
    id = 1:2,
    geometry = geom
  )

  # Test each operation type
  for (op in c("translate", "filter", "sql", "info")) {
    result <- expect_no_error(
      suppressWarnings(
        gdal_vector_from_object(
          sf_data,
          operation = op
        )
      )
    )

    if (op != "info") {
      expect_true(inherits(result, "sf") || inherits(result, "data.frame"))
    } else {
      expect_type(result, "list")
    }
  }
})

test_that("gdal_vector_from_object rejects invalid operation", {
  skip_if_not_installed("sf")

  geom <- sf::st_sfc(sf::st_point(c(0, 0)))
  sf_data <- sf::st_sf(id = 1, geometry = geom)

  expect_error(
    gdal_vector_from_object(sf_data, operation = "invalid"),
    "invalid"
  )
})

test_that("gdal_vector_from_object info operation returns list", {
  skip_if_not_installed("sf")

  geom <- sf::st_sfc(
    sf::st_point(c(0, 0)),
    sf::st_point(c(1, 1))
  )
  sf_data <- sf::st_sf(
    id = 1:2,
    name = c("a", "b"),
    geometry = geom
  )

  result <- suppressWarnings(
    gdal_vector_from_object(sf_data, operation = "info")
  )

  expect_type(result, "list")
  expect_true("n_features" %in% names(result))
})

test_that(".gdal_vector_translate_tempfile works", {
  skip_if_not_installed("sf")

  # Create temporary files
  temp_in <- tempfile(fileext = ".geojson")
  temp_out <- tempfile(fileext = ".geojson")
  on.exit(unlink(c(temp_in, temp_out)))

  # Create test data
  geom <- sf::st_sfc(sf::st_point(c(0, 0)))
  sf_data <- sf::st_sf(id = 1, geometry = geom)

  # Write to file
  sf::st_write(sf_data, temp_in, quiet = TRUE)

  # Test translation function
  result <- expect_no_error(
    suppressWarnings(
      gdalcli:::.gdal_vector_translate_tempfile(temp_in, temp_out)
    )
  )

  if (!is.null(result)) {
    expect_true(inherits(result, "sf") || inherits(result, "data.frame"))
  }
})

test_that(".gdal_vector_filter_tempfile works", {
  skip_if_not_installed("sf")

  temp_in <- tempfile(fileext = ".geojson")
  temp_out <- tempfile(fileext = ".geojson")
  on.exit(unlink(c(temp_in, temp_out)))

  geom <- sf::st_sfc(
    sf::st_point(c(0, 0)),
    sf::st_point(c(1, 1))
  )
  sf_data <- sf::st_sf(
    id = 1:2,
    value = c(10, 20),
    geometry = geom
  )

  sf::st_write(sf_data, temp_in, quiet = TRUE)

  # Test without filter (copy)
  result <- expect_no_error(
    suppressWarnings(
      gdalcli:::.gdal_vector_filter_tempfile(temp_in, temp_out)
    )
  )

  expect_true(inherits(result, "sf") || inherits(result, "data.frame"))
})

test_that(".gdal_vector_info_tempfile returns list", {
  skip_if_not_installed("sf")

  temp_file <- tempfile(fileext = ".geojson")
  on.exit(unlink(temp_file))

  geom <- sf::st_sfc(sf::st_point(c(0, 0)))
  sf_data <- sf::st_sf(id = 1, geometry = geom)
  sf::st_write(sf_data, temp_file, quiet = TRUE)

  result <- expect_no_error(
    suppressWarnings(
      gdalcli:::.gdal_vector_info_tempfile(temp_file)
    )
  )

  expect_type(result, "list")
})

test_that(".gdal_has_sql_dialect checks dialect availability", {
  # Should recognize standard dialects
  expect_true(gdalcli:::.gdal_has_sql_dialect("default"))
  expect_true(gdalcli:::.gdal_has_sql_dialect("ogrsql"))

  # SQLite dialect availability depends on GDAL build
  sqlite_result <- gdalcli:::.gdal_has_sql_dialect("sqlite")
  expect_type(sqlite_result, "logical")
})

test_that(".gdal_vector_translate_arrow returns sf", {
  skip_if_not_installed("arrow")
  skip_if_not_installed("sf")

  geom <- sf::st_sfc(
    sf::st_point(c(0, 0)),
    sf::st_point(c(1, 1))
  )
  sf_data <- sf::st_sf(
    id = 1:2,
    geometry = geom
  )

  arrow_table <- arrow::as_arrow_table(sf_data)

  result <- expect_no_error(
    suppressWarnings(
      gdalcli:::.gdal_vector_translate_arrow(arrow_table, NULL, NULL, NULL)
    )
  )

  expect_true(inherits(result, "sf") || inherits(result, "data.frame"))
})

test_that(".gdal_vector_filter_arrow filters data", {
  skip_if_not_installed("arrow")
  skip_if_not_installed("sf")

  geom <- sf::st_sfc(
    sf::st_point(c(0, 0)),
    sf::st_point(c(1, 1))
  )
  sf_data <- sf::st_sf(
    id = 1:2,
    value = c(10, 20),
    geometry = geom
  )

  arrow_table <- arrow::as_arrow_table(sf_data)

  result <- expect_no_error(
    suppressWarnings(
      gdalcli:::.gdal_vector_filter_arrow(arrow_table, NULL, NULL)
    )
  )

  expect_true(inherits(result, "sf") || inherits(result, "data.frame"))
})

test_that(".gdal_vector_info_arrow returns info list", {
  skip_if_not_installed("arrow")
  skip_if_not_installed("sf")

  geom <- sf::st_sfc(
    sf::st_point(c(0, 0)),
    sf::st_point(c(1, 1))
  )
  sf_data <- sf::st_sf(
    id = 1:2,
    name = c("a", "b"),
    geometry = geom
  )

  arrow_table <- arrow::as_arrow_table(sf_data)

  result <- expect_no_error(
    gdalcli:::.gdal_vector_info_arrow(arrow_table)
  )

  expect_type(result, "list")
  expect_named(result, c("n_features", "n_fields", "fields", "arrow_schema"))
})

test_that("gdal_vector_from_object handles Arrow availability", {
  skip_if_not_installed("sf")

  geom <- sf::st_sfc(sf::st_point(c(0, 0)))
  sf_data <- sf::st_sf(id = 1, geometry = geom)

  # Test with any available path (Arrow or tempfile)
  result <- expect_no_error(
    suppressWarnings(
      gdal_vector_from_object(sf_data, operation = "info")
    )
  )

  expect_type(result, "list")
})

test_that("gdal_vector_from_object respects output_crs parameter", {
  skip_if_not_installed("sf")

  geom <- sf::st_sfc(
    sf::st_point(c(0, 0)),
    crs = "EPSG:4326"
  )
  sf_data <- sf::st_sf(id = 1, geometry = geom)

  result <- expect_no_error(
    suppressWarnings(
      gdal_vector_from_object(
        sf_data,
        operation = "translate",
        output_crs = "EPSG:3857"
      )
    )
  )

  # Result should be sf object if operation successful
  if (!is.null(result)) {
    expect_true(inherits(result, "sf") || inherits(result, "data.frame"))
  }
})
