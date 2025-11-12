test_that("vsi_url.vsis3 composes correct paths", {
  # Simple S3 path
  url <- vsi_url("vsis3", bucket = "my-bucket", key = "path/to/file.tif")
  expect_equal(url, "/vsis3/my-bucket/path/to/file.tif")

  # With streaming
  url_stream <- vsi_url("vsis3",
    bucket = "my-bucket",
    key = "file.tif",
    streaming = TRUE
  )
  expect_equal(url_stream, "/vsis3_streaming/my-bucket/file.tif")
})

test_that("vsi_url.vsizip detects VSI paths and applies chaining syntax", {
  # Local archive
  url_local <- vsi_url("vsizip",
    archive_path = "archive.zip",
    file_in_archive = "layer.shp"
  )
  expect_equal(url_local, "/vsizip/archive.zip/layer.shp")

  # VSI archive (should use chaining syntax)
  vsi_archive <- "/vsis3/bucket/archive.zip"
  url_chained <- vsi_url("vsizip",
    archive_path = vsi_archive,
    file_in_archive = "layer.shp"
  )
  expect_equal(url_chained, "/vsizip/{/vsis3/bucket/archive.zip}//layer.shp")
})

test_that("is_vsi_path correctly identifies VSI paths", {
  expect_true(is_vsi_path("/vsis3/bucket/key"))
  expect_true(is_vsi_path("/vsizip/{/vsis3/bucket/archive.zip}//file.txt"))
  expect_true(is_vsi_path("/vsimem/temp.tif"))

  expect_false(is_vsi_path("C:/local/file.zip"))
  expect_false(is_vsi_path("s3://bucket/key"))
  expect_false(is_vsi_path("/home/user/file.tif"))
})

test_that("validate_path_component rejects invalid inputs", {
  expect_error(validate_path_component(NULL, "test"))
  expect_error(validate_path_component("", "test", allow_empty = FALSE))
  expect_error(validate_path_component(123, "test"))
  expect_error(validate_path_component(c("a", "b"), "test"))

  # Should pass
  expect_equal(validate_path_component("valid", "test"), "valid")
  expect_equal(validate_path_component(NA, "test", allow_na = TRUE), NA)
})

test_that("sanitize_sas_token removes leading and trailing delimiters", {
  # Test leading ?
  token1 <- "?st=2023-01-01&se=2024-12-31&sig=..."
  sanitized1 <- sanitize_sas_token(token1)
  expect_equal(sanitized1, "st=2023-01-01&se=2024-12-31&sig=...")
  expect_false(grepl("^[?&]", sanitized1))

  # Test leading &
  token2 <- "&st=2023&sig=..."
  sanitized2 <- sanitize_sas_token(token2)
  expect_false(grepl("^[?&]", sanitized2))

  # Test already clean
  token3 <- "st=2023&sig=..."
  sanitized3 <- sanitize_sas_token(token3)
  expect_equal(sanitized3, "st=2023&sig=...")
})

test_that("compose_wrapper_vsi_path handles nested VSI correctly", {
  # Local path, no inner file
  url1 <- compose_wrapper_vsi_path("vsizip", "archive.zip", NULL, FALSE)
  expect_equal(url1, "/vsizip/archive.zip")

  # VSI path, with inner file
  url2 <- compose_wrapper_vsi_path("vsizip", "/vsis3/bucket/archive.zip", "file.txt", FALSE)
  expect_equal(url2, "/vsizip/{/vsis3/bucket/archive.zip}//file.txt")

  # Streaming variant
  url3 <- compose_wrapper_vsi_path("vsizip", "archive.zip", "file.txt", TRUE)
  expect_equal(url3, "/vsizip_streaming/archive.zip/file.txt")
})

test_that("vsi_url.default raises informative error", {
  expect_error(
    vsi_url("invalid_handler", path = "test"),
    class = "gdalcli_unsupported_handler"
  )
})

test_that("Multi-level nesting composes correctly", {
  # ZIP on S3
  s3_zip <- vsi_url("vsis3", "bucket", "archive.zip")
  expect_equal(s3_zip, "/vsis3/bucket/archive.zip")

  # TAR inside ZIP on S3
  tar_in_zip <- vsi_url("vsitar", s3_zip, "data.tar.gz")
  expect_equal(tar_in_zip, "/vsitar/{/vsis3/bucket/archive.zip}//data.tar.gz")

  # GZip the TAR
  final <- vsi_url("vsigzip", tar_in_zip)
  expect_equal(final, "/vsigzip//vsitar/{/vsis3/bucket/archive.zip}//data.tar.gz")
})

test_that("vsisubfile composes correctly with offset and size", {
  url <- vsi_url("vsisubfile", offset = 1024, size = 512000, filename = "largefile.dat")
  expect_equal(url, "/vsisubfile/1024_512000,largefile.dat")

  # With VSI chaining
  s3_file <- vsi_url("vsis3", "bucket", "largefile")
  url_chained <- vsi_url("vsisubfile", offset = 0, size = 10000, filename = s3_file)
  expect_equal(url_chained, "/vsisubfile/0_10000,{/vsis3/bucket/largefile}")
})

test_that("vsicrypt handles key parameters correctly", {
  url <- vsi_url("vsicrypt", key = "secret", filename = "encrypted.bin")
  expect_equal(url, "/vsicrypt/key=secret,file=encrypted.bin")

  # With base64 key
  url_b64 <- vsi_url("vsicrypt",
    key = "c2VjcmV0",
    filename = "encrypted.bin",
    key_format = "base64"
  )
  expect_equal(url_b64, "/vsicrypt/key_b64=c2VjcmV0,file=encrypted.bin")

  # VSI chaining
  s3_file <- vsi_url("vsis3", "bucket", "encrypted.zip")
  url_chained <- vsi_url("vsicrypt", key = "secret", filename = s3_file)
  expect_equal(url_chained, "/vsicrypt/key=secret,file={/vsis3/bucket/encrypted.zip}")
})

test_that("Path-based handlers work with all handler types", {
  # S3
  expect_equal(
    vsi_url("vsis3", "bucket", "key"),
    "/vsis3/bucket/key"
  )

  # GCS
  expect_equal(
    vsi_url("vsigs", "bucket", "key"),
    "/vsigs/bucket/key"
  )

  # Azure
  expect_equal(
    vsi_url("vsiaz", "container", "key"),
    "/vsiaz/container/key"
  )

  # Azure ADLS
  expect_equal(
    vsi_url("vsiadls", "filesystem", "path"),
    "/vsiadls/filesystem/path"
  )

  # HTTP
  expect_equal(
    vsi_url("vsicurl", "https://example.com/data.tif"),
    "/vsicurl/https://example.com/data.tif"
  )

  # Memory
  expect_equal(
    vsi_url("vsimem", "temp.tif"),
    "/vsimem/temp.tif"
  )
})
