---
assignees:
- claude-code
position_column: doing
position_ordinal: '80'
title: 'Obey the org test contract: move the integration tests to a nested package'
---
## Goal

Make this package obey the org test contract. The contract is in the README of swissarmyhammer/workflows (origin/main 5f7e9a5, contract commit f7b504f).

## The contract

1. `swift test` at the root runs all the unit tests, and only the unit tests. A green run means that all the tests ran.
2. The integration tests run as a separate, explicit target. The command names that target.
3. Do not select tests with an environment variable. Remove the `METADATA_REGISTRY_INTEGRATION_TESTS` gate from the test suite. The `integration-gate-env` input of the shared workflow is LEGACY.
4. CI runs the unit job before the integration job. Set a `needs:` edge.

## Selected shape

Shape 2, the nested package. FoundationModelsMultitool commits 32d82b2 and 0ceda07 are the model.

## Steps

1. Make a new package `IntegrationTests/Package.swift`. This package depends on the root package by a path.
2. Move `Tests/FoundationModelsMetadataRegistryTests/Integration/RouterIntegrationTests.swift` into the new package. Remove the `.enabled(if:)` environment gate from the suite.
3. Add a `SemanticSearchCore` library product to the root manifest. The integration suite imports it.
4. Remove the integration product dependencies from the root test target.
5. Keep the examples' opt-in environment variable. The contract applies to tests, not to example programs. Update the applicable comments.
6. Replace `.github/workflows/ci.yml`: a `unit` job that calls the shared `swift-ci.yaml` with no legacy inputs, and an `integration` job with `needs: unit` that builds and runs the nested package on each run. Keep the metallib colocation step.
7. Add a unit test that pins the `needs: unit` edge in ci.yml.
8. Make sure the root `swift test` is green, and the integration package builds.

#test-contract