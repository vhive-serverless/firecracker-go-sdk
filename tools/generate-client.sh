#!/usr/bin/env bash
# Generate models, HTTP client and mocks with a versioned Go Swagger toolchain.
set -euo pipefail
cd "$(dirname "$0")/.."
generator_version=v0.33.1
tool_dir=$(mktemp -d)
trap 'rm -rf "$tool_dir"' EXIT
GOBIN="$tool_dir" go install "github.com/go-swagger/go-swagger/cmd/swagger@$generator_version"

# Skip network-dependent contact email validation, as in the previous generator.
find client -type f ! -name swagger.yaml -delete
"$tool_dir/swagger" generate model -f client/swagger.yaml -T templates \
    --model-package=client/models --copyright-file=COPYRIGHT_HEADER --skip-validation
"$tool_dir/swagger" generate client -f client/swagger.yaml -T templates \
    --model-package=client/models -c client --copyright-file=COPYRIGHT_HEADER \
    --skip-validation -A Firecracker
"$tool_dir/swagger" generate client -f client/swagger.yaml -C go_swagger_layout.yaml \
    -T templates --model-package=client/models -c fctesting \
    --copyright-file=COPYRIGHT_HEADER --skip-validation -A Firecracker
