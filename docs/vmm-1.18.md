# Firecracker v1.18.0 compatibility

The `firecracker-v1.18.0` branch targets the unmodified upstream Firecracker
**v1.18.0** release, source commit
`eaf83bb718a559d324613d566eaf776b31a62340`. It is based on
`vhive-serverless/firecracker-go-sdk` main at `ef254567cf5dfd40e096e6e8a7a32c25937463e0`.

`client/swagger.yaml` is copied byte-for-byte from
[`src/firecracker/swagger/firecracker.yaml`](https://github.com/firecracker-microvm/firecracker/blob/eaf83bb718a559d324613d566eaf776b31a62340/src/firecracker/swagger/firecracker.yaml).
Its SHA-256 is
`3693a55005be2b9c81bf14e9908bd894e361adedff4abcf8c1ac24a8c40adb0c`.
Models, operations and mocks are generated with Go Swagger **v0.33.1**:

```sh
go generate ./
make unit-tests
FC_TEST_RELEASE_API=1 DISABLE_ROOT_TESTS=1 go test -short -timeout 90s ./...
```

The SDK keeps the upstream APIs and helpers for pmem, serial, memory hotplug,
balloon hinting, and PCI. Balloon hinting start/stop return HTTP 204 and the
memory-hotplug update size is a required pointer. The VMM `--module` log filter
is supported in direct and jailed process builders. `--snapshot-version` is an
upstream query that prints a version and exits; it is not a VM configuration
option.

Snapshot restore accepts upstream `network_overrides` and `vsock_override` through
`SnapshotConfig`. Restoring skips device creation handlers, including vsock
creation, before loading state. The load wrapper normalizes a nil network override
list to an empty JSON sequence without mutating the caller's model, because the
release VMM rejects JSON null for that field. Snapshot load errors retain their
underlying error chain. Drive paths in a snapshot must be available at the paths
recorded by the upstream VMM.

`tools/prepare-testdata.sh` pins guest kernel/rootfs artifacts and the official
v1.18.0 Firecracker/jailer release archive with SHA-256 checks. An external
`FC_TEST_DATA_PATH` is supported, including the small checked-in inputs.
`make all-tests` also prepares an Ubuntu 24.04 ext4 SSH fixture with locally
generated test credentials, CNI **v1.9.1** and `tc-redirect-tap`
**v0.0.0-20250516183331-34bf829e9a5c**. Fixture generation currently covers
x86_64 only. Generated credentials and large disk fixtures are ignored by Git.

This branch was checked with Go **1.26.11** on x86_64 Linux: root-disabled short
tests and the mocked restore regressions pass, the schema matches upstream, and
regenerating the client produces identical tracked files. `TestReleaseAPI`
checks the actual release version, machine configuration, balloon reporting and
hinting configuration, typed errors, and nil network override normalization.
It starts the release VMM without booting a guest; it does not require KVM.

Full privileged guest lifecycle, jailer, networking, SSH, and snapshot tests
require a separate KVM worker run. The runtime repository records those runner
commands and results. SDK API validation does not establish runtime-level
snapshot storage consistency or guest reclamation behavior. ARM validation
has not been performed.
