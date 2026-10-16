#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h:h}"

if [[ -z "${BUNDLE_IDENTIFIER:-}" ]]; then
    echo "Set BUNDLE_IDENTIFIER to the permanent reverse-DNS identifier for this app." >&2
    exit 1
fi
if [[ -z "${MARKETING_VERSION:-}" ]]; then
    echo "Set MARKETING_VERSION, for example 1.2.0." >&2
    exit 1
fi
if [[ -z "${BUILD_NUMBER:-}" ]]; then
    echo "Set BUILD_NUMBER to a monotonically increasing integer." >&2
    exit 1
fi

RELEASE_BUILD=1 \
UNIVERSAL_BUILD="${UNIVERSAL_BUILD:-1}" \
"$project_dir/scripts/build-app.sh" release

REQUIRE_UNIVERSAL="${UNIVERSAL_BUILD:-1}" \
REQUIRE_SECURE_TIMESTAMP=1 \
"$project_dir/scripts/check-release.sh"

if [[ -n "${NOTARY_PROFILE:-}" ]]; then
    "$project_dir/scripts/notarize-app.sh"
else
    echo "Release bundle is signed and validated but not notarized."
    echo "Set NOTARY_PROFILE and run scripts/notarize-app.sh before distribution."
fi
