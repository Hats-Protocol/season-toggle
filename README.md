# SeasonToggle

Testt

A mechanistic [Hats Protocol](https://github.com/Hats-Protocol/hats-protocol) Toggle module — i.e. a contract that implements the [`IHatsToggle` interface](https://github.com/Hats-Protocol/hats-protocol/src/Interfaces/IHatsToggle.sol) — that allows an organization to configure certain hats to be automatically toggled off after a given interval, i.e. a "season".

Organizational structure should not be permanent. By automatically turning off hats by default, SeasonToggle helps ensure that organizations continuously and explicitly revisit their own structure.

## Overview & Usage

In Hats Protocol, hats can be configured with Toggle modules that programmatically control whether and when the hat is active or inactive. SeasonToggle adds an automatic expiry for a group of hats within a given branch of an organization's hat tree, unless an admin of that branch explicitly extends it to a new season.

Usage of SeasonToggle involves the following phases:

1. **Setup**: create a new instance of SeasonToggle for the relevant branch of the hat tree
2. **Extension**: renew the branch of hats for a new season

Once in operation, Hats Protocol will retrieve hat status (active or inactive) from an instance of SeasonToggle by calling the `SeasonToggle.getHatStatus()` function.

### Phase 1: Setup

A given branch of hats is defined by its `branchRoot`, which is the id of the hat that is the root of the branch. Any hat that is a descendant of the `branchRoot` is considered to be part of the branch. All hats are `branchRoot`s of their own branch.

#### Deploy a new SeasonToggle instance

For each `branchRoot`, there is a corresponding SeasonToggle contract instance. These contracts are created via the [SeasonToggleFactory](./src/SeasonToggleFactory.sol) contract. For cheap deployment, each instance is a clone of an implementation contract. To create a new instance, call the `SeasonToggleFactory.createSeasonToggle()` function, passing in the `branchRoot` — and two other parameters; see below — as an argument. If a SeasonToggle instance already exists for `branchRoot`, the call will fail; otherwise, the new instance will be deployed.

The `SeasonToggleFactory.createSeasonToggle()` function takes two parameters in addition to the `branchRoot`:

- `seasonDuration`: the length of the first season, in seconds. This value must not be less than 1 hour, or 3600 seconds.
- `extensionDelay`: the proportion of the season that must elapse before the branch can be extended to a new season. This value is input as the numerator of the expression `extensionDelay / 10,000`, so a value of 0 corresponds to a delay of 0% and a value of 10,000 corresponds to a delay of 100% of the season. This value must be less than 10,000. See the [Extension phase](#phase-2-extension) below for more on the extension delay.

#### Set the SeasonToggle as the toggle for the hats in the branch

To enable SeasonToggle for the hats in the branch, the SeasonToggle instance must be set as the toggle module for each hat. For existing (mutable) hats in the branch, an admin can do so by calling `Hats.changeToggleModule()`, passing in the SeasonToggle instance as the new toggle module. For new hats in the branch, the SeasonToggle instance can be set as the toggle module when the hat is created.

Since SeasonToggle instance contract addresses are deterministic, the address can be set as the toggle module on hats even before the SeasonToggle instance is deployed. However, the SeasonToggle instance must be deployed before it can be used to toggle hats.

> **Warning**
> There is no explicit restriction on setting the SeasonToggle instance as the toggle module for hats outside of the branch. Such hats will be subject to the SeasonToggle's expiry logic, but their admins will not have the ability to control the season extension, which may result in unexpected behavior. **It is recommended that the SeasonToggle instance be set as the toggle module only for hats in the branch.**

### Phase 2: Extension

An admin of a given `branchRoot` can extend it to a new season by calling the `SeasonToggle.extend()` function on its corresponding instance.

Extension is only allowed after `extensionDelay` has elapsed since the start of the current season. The intent here is to ensure that the organization can only extend to a new season once it has sufficent information about how the next season should proceed. The longer the `extensionDelay`, the more likely the organization will be able to make an informed decision about its structure for the next season.

The exact time at which the `extensionDelay` will elapse can be read from the `SeasonToggle.extensionThreshold()` function, and whether the branch can be extended at the present time can be read from the `SeasonToggle.extendable()` function.

The `SeasonToggle.extend()` function takes two optional arguments, `seasonDuration` and `extensionDelay`. If these values are non-zero, they will be set as the new `seasonDuration` and `extensionDelay` for the next season. If they are zero, the values from the present season will be used again.

## Development

This repo uses Foundry for development and testing. To get started:

1. Fork the project
2. Install [Foundry](https://book.getfoundry.sh/getting-started/installation)
3. To compile the contracts, run `forge build`
4. To test, run `forge test`
