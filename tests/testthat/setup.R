# Test setup file
# Run before any tests to ensure clean environment

# Clear any existing auth environment variables
test_env_vars <- c(
  "AWS_ACCESS_KEY_ID", "AWS_SECRET_ACCESS_KEY", "AWS_SESSION_TOKEN",
  "AWS_REGION", "AWS_NO_SIGN_REQUEST",
  "AZURE_STORAGE_CONNECTION_STRING", "AZURE_STORAGE_ACCOUNT",
  "AZURE_STORAGE_ACCESS_KEY", "AZURE_STORAGE_SAS_TOKEN",
  "GOOGLE_APPLICATION_CREDENTIALS", "GS_NO_SIGN_REQUEST",
  "OSS_ENDPOINT", "OSS_ACCESS_KEY_ID", "OSS_SECRET_ACCESS_KEY",
  "OS_IDENTITY_API_VERSION", "SWIFT_AUTH_V1_URL", "SWIFT_USER"
)

for (var in test_env_vars) {
  if (nzchar(Sys.getenv(var))) {
    Sys.unsetenv(var)
  }
}
