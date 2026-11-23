# Build and verify PUSH

Developer: Sebastian Santos · PUSH 1.16.7 / Admin 1.16.11

Use a Mac with Xcode and its command-line tools. Deployment targets are macOS 14 or later for Apple Silicon and Intel. The recorded local build uses the installed Xcode macOS toolchain; these packages are test artifacts with ad-hoc code signatures and unsigned installer packages.

From the repository root:

```bash
bash Packaging/build-test-release.sh
```

An optional first argument selects an output folder. The default is `artifacts/`. The helper derives versions from the source, builds both architectures, builds the engine/client packages, embeds that exact client into Admin and writes package checksums. It does not install or activate either app, fetch macOS, access user credentials or restart a Mac.

The build includes Mist CLI 2.3 from `PUSH-Admin/Resources/mist-cli.2.3.pkg`. Its checksum is enforced by the build. Its upstream MIT license and provenance are beside it. The hardware-readiness package is regenerated from `PUSH-Admin/HardwareReporter`; generated reporter packages are not required in Git.

## Safe tests

```bash
bash Tests/run-safe-tests.sh
bash PUSH-Admin/Tests/run-safe-tests.sh
bash verify-push-attribution.sh .
```

For Admin’s actual exported-package checks, point the suite at the just-built client and an empty output folder:

```bash
PUSH_SELF_SERVICE_CLIENT="$PWD/artifacts/PUSH-Client-1.16.7.pkg" \
PUSH_SELF_SERVICE_FOLDER="$PWD/artifacts/test-self-service-export" \
bash PUSH-Admin/Tests/run-safe-tests.sh
```

Tests use fixtures and in-memory request/signature backends. They do not install macOS or access a real user Keychain. The client suite also compares its Security.framework result with the system codesign result for a local tool and fails closed when host trust is unavailable.

Some restricted build hosts require the optional `PUSH_MACRO_SANDBOX_WORKAROUND=1` compiler setting used by the local build workflow. It changes compiler invocation only; it is not a client security setting.

## Before distributing

- Expand the final package and verify installed CLI/UI versions, code signatures and the embedded client bytes.
- Review generated manifests, payload paths, scripts, images and activation settings.
- Keep API secrets and runtime records outside packages and Git.
- Complete Developer ID signing/notarization and applicable MDM approvals for your deployment.
- Test the actual authorization, download, preparation and reboot journey on a compatible managed pilot. Automated tests and a successful Jamf publish do not prove OS upgrade completion.

Legacy deployment wrappers remain for historical compatibility. The build helper above and Admin’s reviewed workflow are the current paths. Do not substitute a stale client package from an older checkout or release.
