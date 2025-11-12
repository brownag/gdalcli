test_that("set_gdal_auth.s3 sets AWS environment variables", {
  # Save original env vars
  original_key <- Sys.getenv("AWS_ACCESS_KEY_ID")
  original_secret <- Sys.getenv("AWS_SECRET_ACCESS_KEY")
  on.exit({
    if (original_key != "") Sys.setenv(AWS_ACCESS_KEY_ID = original_key)
    if (original_secret != "") Sys.setenv(AWS_SECRET_ACCESS_KEY = original_secret)
  })

  # Test with credentials
  result <- set_gdal_auth("s3",
    access_key_id = "test_key",
    secret_access_key = "test_secret"
  )
  expect_true(result)
  expect_equal(Sys.getenv("AWS_ACCESS_KEY_ID"), "test_key")
  expect_equal(Sys.getenv("AWS_SECRET_ACCESS_KEY"), "test_secret")

  # Test with region
  result <- set_gdal_auth("s3",
    access_key_id = "test_key",
    secret_access_key = "test_secret",
    region = "us-west-2"
  )
  expect_equal(Sys.getenv("AWS_REGION"), "us-west-2")

  # Test with session token
  result <- set_gdal_auth("s3",
    access_key_id = "test_key",
    secret_access_key = "test_secret",
    session_token = "test_token"
  )
  expect_equal(Sys.getenv("AWS_SESSION_TOKEN"), "test_token")

  # Test no_sign_request
  result <- set_gdal_auth("s3", no_sign_request = TRUE)
  expect_equal(Sys.getenv("AWS_NO_SIGN_REQUEST"), "YES")
})

test_that("set_gdal_auth.s3 requires credentials", {
  expect_error(
    set_gdal_auth("s3"),
    class = NULL  # Will have validation error
  )
})

test_that("set_gdal_auth.azure validates exactly one method", {
  # Save original env vars
  original_conn <- Sys.getenv("AZURE_STORAGE_CONNECTION_STRING")
  on.exit({
    if (original_conn != "") Sys.setenv(AZURE_STORAGE_CONNECTION_STRING = original_conn)
  })

  # Test connection string
  result <- set_gdal_auth("azure", connection_string = "DefaultEndpointsProtocol=https;...")
  expect_true(result)
  expect_equal(Sys.getenv("AZURE_STORAGE_CONNECTION_STRING"), "DefaultEndpointsProtocol=https;...")

  # Test that multiple methods raise error
  expect_error(
    set_gdal_auth("azure",
      connection_string = "...",
      account = "account",
      access_key = "key"
    ),
    "exactly ONE method"
  )

  # Test no methods provided
  expect_error(
    set_gdal_auth("azure"),
    "requires exactly one of"
  )
})

test_that("set_gdal_auth.azure sanitizes SAS tokens", {
  original_account <- Sys.getenv("AZURE_STORAGE_ACCOUNT")
  original_token <- Sys.getenv("AZURE_STORAGE_SAS_TOKEN")
  on.exit({
    if (original_account != "") Sys.setenv(AZURE_STORAGE_ACCOUNT = original_account)
    if (original_token != "") Sys.setenv(AZURE_STORAGE_SAS_TOKEN = original_token)
  })

  # Token with leading ? (common from Azure portal)
  result <- set_gdal_auth("azure",
    account = "myaccount",
    sas_token = "?st=2023-01-01&se=2024-12-31&sig=..."
  )
  expect_true(result)

  # Check that leading ? was removed
  set_token <- Sys.getenv("AZURE_STORAGE_SAS_TOKEN")
  expect_false(grepl("^\\?", set_token))
})

test_that("set_gdal_auth.gs handles credentials file", {
  original_creds <- Sys.getenv("GOOGLE_APPLICATION_CREDENTIALS")
  on.exit({
    if (original_creds != "") Sys.setenv(GOOGLE_APPLICATION_CREDENTIALS = original_creds)
  })

  # Create a temporary credentials file
  temp_file <- tempfile(fileext = ".json")
  writeLines('{"type": "service_account"}', temp_file)
  on.exit(file.remove(temp_file), add = TRUE)

  # Test with valid file
  result <- set_gdal_auth("gs", credentials_file = temp_file)
  expect_true(result)
  expect_equal(Sys.getenv("GOOGLE_APPLICATION_CREDENTIALS"), temp_file)

  # Test with non-existent file
  expect_error(
    set_gdal_auth("gs", credentials_file = "/nonexistent/path/creds.json"),
    "not found"
  )
})

test_that("set_gdal_auth.gs handles no_sign_request", {
  original_no_sign <- Sys.getenv("GS_NO_SIGN_REQUEST")
  on.exit({
    if (original_no_sign != "") Sys.setenv(GS_NO_SIGN_REQUEST = original_no_sign)
  })

  result <- set_gdal_auth("gs", no_sign_request = TRUE)
  expect_true(result)
  expect_equal(Sys.getenv("GS_NO_SIGN_REQUEST"), "YES")
})

test_that("set_gdal_auth.oss sets OSS environment variables", {
  original_endpoint <- Sys.getenv("OSS_ENDPOINT")
  original_key <- Sys.getenv("OSS_ACCESS_KEY_ID")
  original_secret <- Sys.getenv("OSS_SECRET_ACCESS_KEY")
  on.exit({
    if (original_endpoint != "") Sys.setenv(OSS_ENDPOINT = original_endpoint)
    if (original_key != "") Sys.setenv(OSS_ACCESS_KEY_ID = original_key)
    if (original_secret != "") Sys.setenv(OSS_SECRET_ACCESS_KEY = original_secret)
  })

  result <- set_gdal_auth("oss",
    endpoint = "http://oss-us-east-1.aliyuncs.com",
    access_key_id = "test_key",
    secret_access_key = "test_secret"
  )
  expect_true(result)
  expect_equal(Sys.getenv("OSS_ENDPOINT"), "http://oss-us-east-1.aliyuncs.com")
  expect_equal(Sys.getenv("OSS_ACCESS_KEY_ID"), "test_key")
})

test_that("set_gdal_auth.swift_v3 sets OpenStack Keystone v3 variables", {
  original_version <- Sys.getenv("OS_IDENTITY_API_VERSION")
  on.exit({
    if (original_version != "") Sys.setenv(OS_IDENTITY_API_VERSION = original_version)
  })

  result <- set_gdal_auth("swift_v3",
    auth_url = "http://keystone.example.com:5000/v3",
    username = "user",
    password = "pass",
    project_name = "admin",
    project_domain_name = "Default"
  )
  expect_true(result)
  expect_equal(Sys.getenv("OS_IDENTITY_API_VERSION"), "3")
  expect_equal(Sys.getenv("OS_USERNAME"), "user")
  expect_equal(Sys.getenv("OS_PROJECT_NAME"), "admin")
})

test_that("set_gdal_auth.swift_v1 sets OpenStack Auth v1 variables", {
  original_url <- Sys.getenv("SWIFT_AUTH_V1_URL")
  on.exit({
    if (original_url != "") Sys.setenv(SWIFT_AUTH_V1_URL = original_url)
  })

  result <- set_gdal_auth("swift_v1",
    auth_v1_url = "http://swift.example.com/auth/v1.0",
    user = "testuser",
    key = "testkey"
  )
  expect_true(result)
  expect_equal(Sys.getenv("SWIFT_AUTH_V1_URL"), "http://swift.example.com/auth/v1.0")
  expect_equal(Sys.getenv("SWIFT_USER"), "testuser")
})

test_that("set_gdal_auth.default raises informative error", {
  expect_error(
    set_gdal_auth("invalid_handler"),
    class = "gdalcli_unsupported_auth_handler"
  )
})
