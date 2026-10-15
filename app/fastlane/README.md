fastlane documentation
----

# Installation

Make sure you have the latest version of the Xcode command line tools installed:

```sh
xcode-select --install
```

For _fastlane_ installation instructions, see [Installing _fastlane_](https://docs.fastlane.tools/#installing-fastlane)

# Available Actions

### next_build_number

```sh
[bundle exec] fastlane next_build_number
```

Print the next sequential TestFlight build number (latest on ASC + 1)

----


## iOS

### ios retry_upload

```sh
[bundle exec] fastlane ios retry_upload
```

Retry uploading an already-built .ipa (no rebuild) after network failure

### ios beta

```sh
[bundle exec] fastlane ios beta
```

Build and upload to TestFlight (com.hurated.interview)

### ios distribute_external

```sh
[bundle exec] fastlane ios distribute_external
```

Give an uploaded build to external testers: wait for processing, submit for Beta App Review, add to the group, notify testers

Usage: fastlane distribute_external build:1 [group:"External Testers"] [app_version:1.0]

### ios prune_external_groups

```sh
[bundle exec] fastlane ios prune_external_groups
```

Keep each external TestFlight group lean: the newest approved build, plus the newest build still awaiting review when it is newer; remove the rest from the group

Usage: fastlane prune_external_groups [group:"External Testers"] [dry_run:true]

### ios expire_old_builds

```sh
[bundle exec] fastlane ios expire_old_builds
```

Expire previous TestFlight builds except latest and externally approved

### ios set_testflight_notes

```sh
[bundle exec] fastlane ios set_testflight_notes
```

Update the TestFlight 'What to Test' notes on an already-uploaded build, without re-uploading a binary

Usage: fastlane set_testflight_notes build:1 (defaults to app_version 1.0; reads fastlane/changelog.txt)

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
