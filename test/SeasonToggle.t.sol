// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { Test, console2 } from "forge-std/Test.sol";
import { SeasonToggle } from "src/SeasonToggle.sol";
import { SeasonToggleFactory } from "src/SeasonToggleFactory.sol";
import { SeasonToggleFactoryTest } from "test/SeasonToggleFactory.t.sol";
import { IHats } from "hats-protocol/Interfaces/IHats.sol";
import { LibClone } from "solady/utils/LibClone.sol";

contract SeasonToggleTest is SeasonToggleFactoryTest {
  uint256 public hat1_1_1 = 0x0000000100010001000000000000000000000000000000000000000000000000;
  uint256 public seasonStart;

  address public dao; // wears topHat1
  address public subdao; // wears hat1_1
  address public contributor; // wears hat1_1_1
  address public other; // wears no hat
  address public eligibility;

  uint256 public farBeforeThreshold;
  uint256 public justBeforeThreshold;
  uint256 public atThreshold;
  uint256 public justAfterThreshold;
  uint256 public farAfterThreshold;
  uint256 public seasonEnd;
  uint256 public justAfterSeason;
  uint256 public farAfterSeason;

  /// @notice Thrown when a non-admin attempts to extend a branch to a new season
  error SeasonToggle_NotBranchAdmin();
  /// @notice Thrown when attempting to extend a branch to a new season before its extendable
  error SeasonToggle_NotExtendable();
  /// @notice Valid extendability delays are <= 10,000
  error SeasonToggle_InvalidExtendabilityDelay();
  /// @notice Season durations must be at least `MIN_SEASON_DURATION` long
  error SeasonToggle_SeasonDurationTooShort();
  /// @notice Emitted when a non-factory address attempts to call an onlyFactory function
  error SeasonToggle_NotFactory();

  function setUp() public virtual override {
    super.setUp();

    // set up addresses
    dao = makeAddr("dao");
    subdao = makeAddr("subdao");
    contributor = makeAddr("contributor");
    other = makeAddr("other");
    eligibility = makeAddr("eligibility");

    // deploy an instance of the SeasonToggle contract for hat1_1
    instance = factory.createSeasonToggle(hat1_1, seasonDuration, extendabilityDelay);
    seasonStart = block.timestamp;

    // calculate threshold relative timestamps for warping
    farBeforeThreshold =
      seasonStart + seasonDuration - (((10_000 - extendabilityDelay) * seasonDuration) / 10_000) - 1000;
    justBeforeThreshold = seasonStart + seasonDuration - (((10_000 - extendabilityDelay) * seasonDuration) / 10_000) - 1;
    atThreshold = seasonStart + seasonDuration - (((10_000 - extendabilityDelay) * seasonDuration) / 10_000);
    justAfterThreshold = seasonStart + seasonDuration - (((10_000 - extendabilityDelay) * seasonDuration) / 10_000) + 1;
    farAfterThreshold =
      seasonStart + seasonDuration - (((10_000 - extendabilityDelay) * seasonDuration) / 10_000) + 1000;
    seasonEnd = seasonStart + seasonDuration;
    justAfterSeason = seasonStart + seasonDuration + 1;
    farAfterSeason = seasonStart + seasonDuration + 1000;

    // set up hats
    vm.startPrank(dao);
    // mint top hat to the dao
    topHat1 = hats.mintTopHat(dao, "Top hat", "");
    // create hat1_1
    hat1_1 = hats.createHat(topHat1, "hat1_1", 2, address(1), address(instance), true, "");
    vm.stopPrank();
  }

  /// @notice Mocks a call to the eligibility contract for `wearer` and `hat` that returns `eligible` and `standing`
  function mockEligibityCall(address wearer, uint256 hat, bool eligible, bool standing) public {
    bytes memory data = abi.encodeWithSignature("getWearerStatus(address,uint256)", wearer, hat);
    vm.mockCall(eligibility, data, abi.encode(eligible, standing));
  }
}

contract SeasonToggleHarness is SeasonToggle {
  constructor() SeasonToggle("this is a test harness") { }

  function checkOnlyFactory() public view onlyFactory returns (bool) {
    return true;
  }

  function extendabilityThreshold_(uint256 seasonEnd, uint256 extendabilityDelay, uint256 seasonDuration)
    public
    pure
    returns (uint256)
  {
    return _extendabilityThreshold(seasonEnd, extendabilityDelay, seasonDuration);
  }
}

contract InternalTest is SeasonToggleTest {
  SeasonToggleHarness harnessImplementation;
  SeasonToggleHarness harness;

  function setUp() public virtual override {
    super.setUp();
    // deploy harness implementation
    harnessImplementation = new SeasonToggleHarness();
    // deploy harness proxy, for hat1_1
    harness = SeasonToggleHarness(
      LibClone.cloneDeterministic(
        address(harnessImplementation), abi.encodePacked(address(this), hats, hat1_1, uint32(1)), bytes32("salt")
      )
    );
    // mint hat1_1 to harness contract
    vm.prank(dao);
    hats.mintHat(hat1_1, address(harness));
  }
}

contract _onlyFactoryTest is InternalTest {
  function test_succeeds_FromFactory() public {
    vm.prank(address(this)); // this contract served as the factory for the harness
    assertTrue(harness.checkOnlyFactory());
  }

  function test_reverts_FromNonFactory() public {
    vm.prank(other);
    vm.expectRevert(SeasonToggle_NotFactory.selector);
    harness.checkOnlyFactory();
  }
}

contract _extendabilityThreshold is InternalTest {
  function test_fuzz_threshold(uint256 _seasonEnd, uint256 _extendabilityDelay, uint256 _seasonDuration) public {
    _extendabilityDelay = bound(_extendabilityDelay, 0, 10_000);
    _seasonDuration = bound(_seasonDuration, 1 days, 100_000 days);
    _seasonEnd = bound(_seasonEnd, _seasonDuration, seasonStart + 100_000 days);

    uint256 result = harness.extendabilityThreshold_(_seasonEnd, _extendabilityDelay, _seasonDuration);
    uint256 expected = _seasonEnd - (((10_000 - _extendabilityDelay) * _seasonDuration) / 10_000);

    assertEq(result, expected, "Threshold");
  }

  function test_threshold_halfDelay() public {
    uint256 end = block.timestamp + 1000 days;
    uint256 actual = harness.extendabilityThreshold_(end, 5000, 500 days);
    uint256 expected = end - 250 days; // 500 / (5000 / 10000) = 500 / 2
    assertEq(actual, expected);
  }

  function test_threshold_noDelay() public {
    uint256 end = block.timestamp + 1000 days;
    uint256 actual = harness.extendabilityThreshold_(end, 0, 500 days);
    uint256 expected = end - 500 days; // 500 / (10000 / 10000) = 500 / 1
    assertEq(actual, expected);
  }

  function test_threshold_fullDelay() public {
    uint256 end = block.timestamp + 1000 days;
    uint256 actual = harness.extendabilityThreshold_(end, 10_000, 500 days);
    uint256 expected = end - 0 days; // 500 / (0 / 10000) = 500 / 2
    assertEq(actual, expected);
  }
}

contract SetUp is InternalTest {
  // use the internal test to be able to set up an un-initialized instance
  function test_succeeds_whenUninitialized() public {
    vm.prank(address(this)); // this contract served as the factory for the harness
    harness.setUp(seasonDuration, extendabilityDelay);
    assertEq(harness.seasonDuration(), seasonDuration, "seasonDuration");
    assertEq(harness.extendabilityDelay(), extendabilityDelay, "extendabilityDelay");
  }

  // attempt to set up the implementation again
  function test_reverts_forImplementation() public {
    vm.prank(address(this)); // this contract served as the factory for the harness, but not the implementation
    vm.expectRevert(SeasonToggle_NotFactory.selector);
    implementation.setUp(seasonDuration, extendabilityDelay);
  }

  function test_reverts_forNonFactoryCaller() public {
    vm.prank(other);
    vm.expectRevert(SeasonToggle_NotFactory.selector);
    harness.setUp(seasonDuration, extendabilityDelay);
  }

  function test_reverts_forInvalidSeasonDuration() public {
    vm.prank(address(this)); // this contract served as the factory for the harness
    vm.expectRevert(SeasonToggle_SeasonDurationTooShort.selector);
    // try a just-too-short duration
    harness.setUp(1 days - 1, extendabilityDelay);
  }

  function test_reverts_forInvalidExtendabilityDelay() public {
    vm.prank(address(this)); // this contract served as the factory for the harness
    vm.expectRevert(SeasonToggle_InvalidExtendabilityDelay.selector);
    harness.setUp(seasonDuration, 10_001);
  }
}

contract DeployInstance is SeasonToggleTest {
  function test_CorrectInitialVariables() public {
    assertEq(address(instance.FACTORY()), address(factory), "factory");
    assertEq(address(instance.HATS()), address(hats), "hats");
    assertEq(instance.branchRoot(), hat1_1, "branchRoot");
    assertEq(instance.branchRootLevel(), 1, "branchRootLevel");
    assertEq(instance.seasonDuration(), seasonDuration, "seasonDuration");
    assertEq(instance.extendabilityDelay(), extendabilityDelay, "extendabilityDelay");
    assertEq(instance.seasonEnd(), seasonStart + instance.seasonDuration(), "seasonEnd");
    assertEq(instance.version(), VERSION, "version");
  }
}

contract GetHatStatus is SeasonToggleTest {
  uint256 testHat;

  function setUp() public override {
    super.setUp();
    // create hat1_1_1
    vm.prank(dao);
    hat1_1_1 = hats.createHat(hat1_1, "hat1_1_1", 2, address(1), address(instance), true, "");
  }

  function inSeason(uint256 _testHat) public {
    vm.warp(seasonStart + 1);
    assertTrue(instance.getHatStatus(_testHat), "seasonStart + 1");

    vm.warp(seasonStart + seasonDuration - 1);
    assertTrue(instance.getHatStatus(_testHat), "seasonStart + seasonDuration - 1");

    vm.warp(seasonStart + seasonDuration);
    assertTrue(instance.getHatStatus(_testHat), "seasonStart + seasonDuration");
  }

  function outOfSeason(uint256 _testHat) public {
    vm.warp(seasonStart + seasonDuration + 1);
    assertFalse(instance.getHatStatus(_testHat), "seasonStart + seasonDuration + 1");

    vm.warp(seasonStart + seasonDuration + 365 days);
    assertFalse(instance.getHatStatus(_testHat), "seasonStart + seasonDuration + 100");
  }

  function test_true_forHatOutOfBranch() public {
    testHat = 1;
    assertTrue(instance.getHatStatus(testHat));
  }

  function test_true_forHatInBranch_inSeason() public {
    inSeason(hat1_1_1);
  }

  function test_true_forBranchRoot_inSeason() public {
    inSeason(hat1_1);
  }

  function test_false_forHatInBranch_outOfSeason() public {
    outOfSeason(hat1_1_1);
  }

  function test_false_forBranchRoot_outOfSeason() public {
    outOfSeason(hat1_1);
  }
}

contract Extend is SeasonToggleTest {
  function test_reverts_forNonBranchAdmin() public {
    vm.prank(other);
    vm.expectRevert(SeasonToggle_NotBranchAdmin.selector);
    instance.extend(0, 0);
  }

  function test_reverts_ifNotExtendable() public {
    vm.prank(dao);
    vm.warp(justBeforeThreshold);
    vm.expectRevert(SeasonToggle_NotExtendable.selector);
    instance.extend(0, 0);
  }

  function test_reverts_forInvalidDelayValue(uint256 delay) public {
    vm.assume(delay > 10_000);
    // ensure its extendable
    vm.warp(justAfterThreshold);
    // try to extend with an invalid delay value
    vm.prank(dao);
    vm.expectRevert(SeasonToggle_InvalidExtendabilityDelay.selector);
    instance.extend(0, delay);
  }

  function test_reverts_forInvalidSeasonDuration(uint256 duration) public {
    duration = bound(duration, 1, 1 days - 1);
    // ensure its extendable
    vm.warp(justAfterThreshold);
    // try to extend with an invalid season duration
    vm.prank(dao);
    vm.expectRevert(SeasonToggle_SeasonDurationTooShort.selector);
    instance.extend(duration, 0);
  }

  function test_extend_withNoChanges() public {
    // ensure its extendable
    vm.warp(justAfterThreshold);
    // extend
    vm.prank(dao);
    instance.extend(0, 0);
    // check that the season duration and extendability delay are unchanged
    assertEq(instance.seasonDuration(), seasonDuration, "seasonDuration");
    assertEq(instance.extendabilityDelay(), extendabilityDelay, "extendabilityDelay");
    assertEq(instance.seasonEnd(), seasonStart + (2 * seasonDuration), "seasonEnd");
  }

  function test_extend_withDurationChange() public {
    // ensure its extendable
    vm.warp(justAfterThreshold);
    // extend
    vm.prank(dao);
    instance.extend(seasonDuration + 1, 0);
    // check that the season duration and extendability delay are correct
    assertEq(instance.seasonDuration(), seasonDuration + 1, "seasonDuration");
    assertEq(instance.extendabilityDelay(), extendabilityDelay, "extendabilityDelay");
    assertEq(instance.seasonEnd(), seasonStart + seasonDuration + (seasonDuration + 1), "seasonEnd");
  }

  function test_extend_withDelayChange() public {
    // ensure its extendable
    vm.warp(justAfterThreshold);
    // extend
    vm.prank(dao);
    instance.extend(0, 5000);
    // check that the season duration and extendability delay are correct
    assertEq(instance.seasonDuration(), seasonDuration, "seasonDuration");
    assertEq(instance.extendabilityDelay(), 5000, "extendabilityDelay");
    assertEq(instance.seasonEnd(), seasonStart + (2 * seasonDuration), "seasonEnd");
  }

  function test_extend_withBothChanges() public {
    // ensure its extendable
    vm.warp(justAfterThreshold);
    // extend
    vm.prank(dao);
    instance.extend(seasonDuration + 1, 5000);
    // check that the season duration and extendability delay are correct
    assertEq(instance.seasonDuration(), seasonDuration + 1, "seasonDuration");
    assertEq(instance.extendabilityDelay(), 5000, "extendabilityDelay");
    assertEq(instance.seasonEnd(), seasonStart + seasonDuration + (seasonDuration + 1), "seasonEnd");
  }

  function test_extend_again_withNoChanges() public {
    // ensure its extendable
    vm.warp(justAfterThreshold);
    // extend
    vm.prank(dao);
    instance.extend(0, 0);
    // extend again
    vm.warp(seasonStart + (2 * seasonDuration) - (((10_000 - extendabilityDelay) * seasonDuration) / 10_000) + 1);
    vm.prank(dao);
    instance.extend(0, 0);
    // check that the season duration and extendability delay are unchanged
    assertEq(instance.seasonDuration(), seasonDuration, "seasonDuration");
    assertEq(instance.extendabilityDelay(), extendabilityDelay, "extendabilityDelay");
    // and the seasonEnd is correct
    assertEq(instance.seasonEnd(), seasonStart + (3 * seasonDuration), "seasonEnd");

  }
}

contract ExtendabilityThreshold is SeasonToggleTest {
  function test_threshold() public {
    uint256 actual = instance.extendabilityThreshold();
    uint256 expected = seasonStart + seasonDuration - (((10_000 - extendabilityDelay) * seasonDuration) / 10_000);
    assertEq(actual, expected, "Threshold");
  }

  function test_afterExtension() public {
    // warp to just after the threshold
    vm.warp(justAfterThreshold);
    // extend another season
    vm.prank(dao);
    instance.extend(0, 0);

    uint256 actual = instance.extendabilityThreshold();
    uint256 expected = seasonStart + seasonDuration + (((10_000 - extendabilityDelay) * seasonDuration) / 10_000);
    assertEq(actual, expected, "Threshold");
  }
}

contract Extendable is SeasonToggleTest {
  function test_true_forAtSeasonEnd() public {
    vm.warp(seasonEnd);
    assertTrue(instance.extendable());
  }

  function test_true_forAfterSeasonEnd() public {
    vm.warp(justAfterSeason);
    assertTrue(instance.extendable());

    vm.warp(farAfterSeason);
    assertTrue(instance.extendable());
  }

  function test_true_forAtThreshold() public {
    vm.warp(atThreshold);
    assertTrue(instance.extendable());
  }

  function test_false_forBeforeThreshold() public {
    vm.warp(farBeforeThreshold);
    assertFalse(instance.extendable());

    vm.warp(justBeforeThreshold);
    assertFalse(instance.extendable());
  }
}

contract InBranch is SeasonToggleTest {
  function test_true_forHatInBranch() public {
    assertTrue(instance.inBranch(hat1_1_1));
  }

  function test_true_forBranchRoot() public {
    assertTrue(instance.inBranch(hat1_1));
  }

  function test_false_forHatOutOfBranch() public {
    assertFalse(instance.inBranch(topHat1));
  }
}
