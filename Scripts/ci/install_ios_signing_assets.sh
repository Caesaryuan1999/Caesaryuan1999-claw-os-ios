#!/usr/bin/env bash
set -euo pipefail

require_env() {
  local name="$1"
  if [ -z "${!name:-}" ]; then
    echo "::error::Missing required GitHub secret or environment variable: ${name}"
    exit 1
  fi
}

require_env APPLE_TEAM_ID
require_env IOS_CERTIFICATE_P12_BASE64
require_env IOS_CERTIFICATE_PASSWORD
require_env IOS_APP_PROFILE_BASE64
require_env IOS_EXTENSION_PROFILE_BASE64
require_env IOS_KEYCHAIN_PASSWORD

WORK_DIR="${RUNNER_TEMP}/ios-signing"
KEYCHAIN_PATH="${RUNNER_TEMP}/claw-os-signing.keychain-db"
PROFILE_DIR="${HOME}/Library/MobileDevice/Provisioning Profiles"

rm -rf "${WORK_DIR}"
mkdir -p "${WORK_DIR}" "${PROFILE_DIR}"

CERT_PATH="${WORK_DIR}/certificate.p12"
APP_PROFILE_PATH="${WORK_DIR}/app.mobileprovision"
EXT_PROFILE_PATH="${WORK_DIR}/extension.mobileprovision"

decode_base64_to_file() {
  local value="$1"
  local output="$2"
  if printf '%s' "${value}" | base64 --decode > "${output}" 2>/dev/null; then
    return
  fi
  printf '%s' "${value}" | base64 -D > "${output}"
}

decode_base64_to_file "${IOS_CERTIFICATE_P12_BASE64}" "${CERT_PATH}"
decode_base64_to_file "${IOS_APP_PROFILE_BASE64}" "${APP_PROFILE_PATH}"
decode_base64_to_file "${IOS_EXTENSION_PROFILE_BASE64}" "${EXT_PROFILE_PATH}"

security create-keychain -p "${IOS_KEYCHAIN_PASSWORD}" "${KEYCHAIN_PATH}"
security set-keychain-settings -lut 21600 "${KEYCHAIN_PATH}"
security unlock-keychain -p "${IOS_KEYCHAIN_PASSWORD}" "${KEYCHAIN_PATH}"
security import "${CERT_PATH}" \
  -P "${IOS_CERTIFICATE_PASSWORD}" \
  -A \
  -t cert \
  -f pkcs12 \
  -k "${KEYCHAIN_PATH}"
security list-keychains -d user -s "${KEYCHAIN_PATH}" $(security list-keychains -d user | sed 's/[ "]//g')
security set-key-partition-list -S apple-tool:,apple: -s -k "${IOS_KEYCHAIN_PASSWORD}" "${KEYCHAIN_PATH}"

read_profile_value() {
  local profile_path="$1"
  local key="$2"
  local plist_path="${profile_path}.plist"
  security cms -D -i "${profile_path}" > "${plist_path}"
  /usr/libexec/PlistBuddy -c "Print :${key}" "${plist_path}"
}

validate_profile_bundle_id() {
  local profile_path="$1"
  local expected_bundle_id="$2"
  local label="$3"
  local plist_path="${profile_path}.plist"
  local application_id
  local actual_bundle_id

  security cms -D -i "${profile_path}" > "${plist_path}"
  application_id="$(/usr/libexec/PlistBuddy -c 'Print :Entitlements:application-identifier' "${plist_path}")"
  actual_bundle_id="${application_id#${APPLE_TEAM_ID}.}"

  if [ "${actual_bundle_id}" != "${expected_bundle_id}" ]; then
    echo "::error::${label} provisioning profile bundle id mismatch. Expected '${expected_bundle_id}', got '${actual_bundle_id}'."
    exit 1
  fi
}

install_profile() {
  local profile_path="$1"
  local env_name="$2"
  local uuid
  local profile_name
  uuid="$(read_profile_value "${profile_path}" UUID)"
  profile_name="$(read_profile_value "${profile_path}" Name)"
  cp "${profile_path}" "${PROFILE_DIR}/${uuid}.mobileprovision"
  echo "${env_name}=${profile_name}" >> "${GITHUB_ENV}"
  echo "Installed provisioning profile '${profile_name}' (${uuid})."
}

validate_profile_bundle_id "${APP_PROFILE_PATH}" "${APP_BUNDLE_ID}" "Main app"
validate_profile_bundle_id "${EXT_PROFILE_PATH}" "${EXTENSION_BUNDLE_ID}" "Notification extension"

install_profile "${APP_PROFILE_PATH}" APP_PROFILE_NAME
install_profile "${EXT_PROFILE_PATH}" EXTENSION_PROFILE_NAME

security find-identity -v -p codesigning "${KEYCHAIN_PATH}"
