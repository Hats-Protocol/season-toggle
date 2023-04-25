// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { Test, console2 } from "forge-std/Test.sol";
import { DeployFactory } from "script/SeasonToggle.s.sol";
import { SeasonToggle } from "src/SeasonToggle.sol";
import { SeasonToggleFactory } from "src/SeasonToggleFactory.sol";
import { LibClone } from "solady/utils/LibClone.sol";
import { IHats } from "hats-protocol/Interfaces/IHats.sol";

contract SeasonToggleFactoryTest is Test, DeployFactory {
  // variables inhereted from DeployFactory script
  // address public implementation;
  // address public factory;
  // address public hats;

  // other variables for testing
  uint256 public fork;
  uint256 public topHat1 = 0x0000000100000000000000000000000000000000000000000000000000000000;
  uint256 public hat1_1 = 0x0000000100010000000000000000000000000000000000000000000000000000;
  bytes32 maxBytes32 = bytes32(type(uint256).max);
  bytes largeBytes = abi.encodePacked("this is a fairly large bytes object");
  string public constant VERSION = "this is a test";
  uint256 public seasonDuration = 2 days;
  uint256 public extendabilityDelay = 5000; // 50%
  SeasonToggle public instance;
  uint32 branchRootLevel;

  event SeasonToggleDeployed(uint256 branchRoot, address instance, uint256 seasonDuration, uint256 extendabilityDelay);

  error SeasonToggleFactory_AlreadyDeployed(uint256 hatId);

  function setUp() public virtual {
    // create and activate a mainnet fork, at the block number where v1.hatsprotocol.eth was deployed
    fork = vm.createSelectFork(vm.rpcUrl("mainnet"), 16_947_805);

    // deploy the clone factory and the implementation contract
    DeployFactory.prepare(VERSION);
    DeployFactory.run();
  }
}

contract Deploy is SeasonToggleFactoryTest {
  function test_deploy() public {
    assertEq(address(factory.HATS()), address(hats), "hats");
    assertEq(address(factory.IMPLEMENTATION()), address(implementation), "implementation");
    assertEq(implementation.version(), VERSION, "version");
    assertEq(factory.version(), VERSION, "factory version");
  }
}

/// @notice Harness contract to test SeasonToggleFactory's internal functions
contract FactoryHarness is SeasonToggleFactory {
  constructor(SeasonToggle _implementation, IHats _hats, string memory _version)
    SeasonToggleFactory(_implementation, _hats, _version)
  { }

  function encodeArgs(uint256 _hatId) public view returns (bytes memory) {
    return _encodeArgs(_hatId);
  }

  function calculateSalt(bytes memory args) public view returns (bytes32) {
    return _calculateSalt(args);
  }

  function getSeasonToggleAddress(bytes memory _arg, bytes32 _salt) public view returns (address) {
    return _getSeasonToggleAddress(_arg, _salt);
  }

  function createToggle(uint256 _hatId) public returns (SeasonToggle) {
    return _createSeasonToggle(_hatId);
  }
}

contract InternalTest is SeasonToggleFactoryTest {
  FactoryHarness harness;

  function setUp() public virtual override {
    super.setUp();
    // deploy harness
    harness = new FactoryHarness(implementation, hats, "this is a test harness");
  }
}

contract Internal_encodeArgs is InternalTest {
  function test_fuzz_encodeArgs(uint256 _hatId) public {
    branchRootLevel = hats.getLocalHatLevel(_hatId);
    assertEq(
      harness.encodeArgs(_hatId), abi.encodePacked(address(harness), hats, _hatId, branchRootLevel), "encodeArgs"
    );
  }

  function test_encodeArgs_0() public {
    test_fuzz_encodeArgs(0);
  }

  function test_encodeArgs_max() public {
    test_fuzz_encodeArgs(type(uint256).max);
  }

  function test_encodeArgs_validbranchRoot() public {
    test_fuzz_encodeArgs(hat1_1);
  }
}

contract Internal_calculateSalt is InternalTest {
  function test_fuzz_calculateSalt(bytes memory _args) public {
    assertEq(harness.calculateSalt(_args), keccak256(abi.encodePacked(_args, block.chainid)), "calculateSalt");
  }

  function test_calculateSalt_0() public {
    test_fuzz_calculateSalt(hex"00");
  }

  function test_calculateSalt_large() public {
    test_fuzz_calculateSalt(largeBytes);
  }

  function test_calculateSalt_validbranchRoot() public {
    test_fuzz_calculateSalt(harness.encodeArgs(hat1_1));
  }
}

contract Internal_getSeasonToggleAddress is InternalTest {
  function test_fuzz_getSeasonToggleAddress(bytes memory _arg, bytes32 _salt) public {
    assertEq(
      harness.getSeasonToggleAddress(_arg, _salt),
      LibClone.predictDeterministicAddress(address(implementation), _arg, _salt, address(harness))
    );
  }

  function test_getSeasonToggleAddress_0() public {
    test_fuzz_getSeasonToggleAddress(hex"00", hex"00");
  }

  function test_getSeasonToggleAddress_large() public {
    test_fuzz_getSeasonToggleAddress(largeBytes, maxBytes32);
  }

  function test_getSeasonToggleAddress_validbranchRoot() public {
    bytes memory args = harness.encodeArgs(hat1_1);
    test_fuzz_getSeasonToggleAddress(args, harness.calculateSalt(args));
  }
}

contract Internal_createToggle is InternalTest {
  function test_createToggle_1() public {
    bytes memory args = harness.encodeArgs(1);
    instance = harness.createToggle(1);
    assertEq(address(instance), harness.getSeasonToggleAddress(args, harness.calculateSalt(args)));
  }

  function test_createToggle_0() public {
    bytes memory args = harness.encodeArgs(0);
    instance = harness.createToggle(0);
    assertEq(address(instance), harness.getSeasonToggleAddress(args, harness.calculateSalt(args)));
  }

  function test_createToggle_max() public {
    bytes memory args = harness.encodeArgs(type(uint256).max);
    instance = harness.createToggle(type(uint256).max);
    assertEq(address(instance), harness.getSeasonToggleAddress(args, harness.calculateSalt(args)));
  }

  function test_createToggle_validBranchRoot() public {
    bytes memory args = harness.encodeArgs(hat1_1);
    instance = harness.createToggle(hat1_1);
    assertEq(address(instance), harness.getSeasonToggleAddress(args, harness.calculateSalt(args)));
  }
}

contract CreateSeasonToggle is SeasonToggleFactoryTest {
  function test_createSeasonToggle() public {
    uint256 branchRootLevel = hats.getLocalHatLevel(hat1_1);

    vm.expectEmit(true, true, true, true);
    emit SeasonToggleDeployed(hat1_1, factory.getSeasonToggleAddress(hat1_1), seasonDuration, extendabilityDelay);
    instance = factory.createSeasonToggle(hat1_1, seasonDuration, extendabilityDelay);

    assertEq(instance.branchRoot(), hat1_1, "hat");
    assertEq(address(instance.FACTORY()), address(factory), "FACTORY");
    assertEq(address(instance.HATS()), address(hats), "HATS");
    assertEq(instance.branchRoot(), hat1_1, "branchRoot");
    assertEq(instance.branchRootLevel(), branchRootLevel, "branchRootLevel");
    assertEq(instance.seasonDuration(), seasonDuration, "seasonDuration");
    assertEq(instance.extendabilityDelay(), extendabilityDelay, "extendabilityDelay");
  }

  // function test_createSeasonToggle_validbranchRoot() public {
  //   test_fuzz_createSeasonToggle(hat1_1);
  // }

  function test_createSeasonToggle_alreadyDeployed_reverts() public {
    factory.createSeasonToggle(hat1_1, seasonDuration, extendabilityDelay);
    vm.expectRevert(abi.encodeWithSelector(SeasonToggleFactory_AlreadyDeployed.selector, hat1_1));
    factory.createSeasonToggle(hat1_1, seasonDuration, extendabilityDelay);
  }
}

contract GetSeasonToggleAddress is SeasonToggleFactoryTest {
  function test_getSeasonToggleAddress_validBranchRoot() public {
    branchRootLevel = hats.getLocalHatLevel(hat1_1);
    bytes memory args = abi.encodePacked(address(factory), hats, hat1_1, branchRootLevel);
    address expected = LibClone.predictDeterministicAddress(
      address(implementation), args, keccak256(abi.encodePacked(args, block.chainid)), address(factory)
    );
    assertEq(factory.getSeasonToggleAddress(hat1_1), expected);
  }

  // function test_getSeasonToggleAddress_validbranchRoot() public {
  //   test_fuzz_getSeasonToggleAddress(hat1_1);
  // }
}

contract Deployed is InternalTest {
  // uses the FactoryHarness version for easy access to the internal _createSeasonToggle function
  function test_deployed_true() public {
    harness.createToggle(hat1_1);
    assertTrue(harness.deployed(hat1_1));
  }

  function test_deployed_false() public {
    assertFalse(harness.deployed(hat1_1));
  }
}
