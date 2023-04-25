// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { Script, console2 } from "forge-std/Script.sol";
import { SeasonToggle } from "src/SeasonToggle.sol";
import { SeasonToggleFactory } from "src/SeasonToggleFactory.sol";
import { IHats } from "hats-protocol/Interfaces/IHats.sol";

contract DeployFactory is Script {
  SeasonToggleFactory public factory;
  SeasonToggle public implementation;
  IHats public constant hats = IHats(0x9D2dfd6066d5935267291718E8AA16C8Ab729E9d); // v1.hatsprotocol.eth
  string public version = "0.1.0"; // increment with each deploy
  bytes32 internal constant SALT = bytes32(abi.encode(0x4a75)); // ~ H(4) A(a) T(7) S(5)

  /// @notice Call this function from tests or other scripts if default values are not desired
  function prepare(string memory _version) public {
    version = _version;
  }

  function run() public {
    uint256 privKey = vm.envUint("PRIVATE_KEY");
    address deployer = vm.rememberKey(privKey);

    vm.startBroadcast(deployer);
    // deploy the implementation
    implementation = new SeasonToggle{ salt: SALT }(version);
    // deploy the contract
    factory = new SeasonToggleFactory{ salt: SALT }(implementation, hats, version);
    vm.stopBroadcast();

    console2.log("implementation", address(implementation));
    console2.log("factory", address(factory));
  }
  // forge script script/SeasonToggle.s.sol:DeployFactory -f mainnet --broadcast --verify

  // forge verify-contract --chain-id 5 --num-of-optimizations 1000000 --watch --constructor-args $(cast abi-encode "constructor(string)" "0.1.0") --compiler-version v0.8.18 0xbD881534a2cD11eB7F3BC70ceDc65d435F9181a1 src/SeasonToggle.sol:SeasonToggle --etherscan-api-key $ETHERSCAN_KEY
  
  // forge verify-contract --chain-id 5 --num-of-optimizations 1000000 --watch --constructor-args $(cast abi-encode "constructor(address,address,string)" 0xbD881534a2cD11eB7F3BC70ceDc65d435F9181a1 0x9D2dfd6066d5935267291718E8AA16C8Ab729E9d "0.1.0") --compiler-version v0.8.18 0xa2003399a08a3638af97405cd5f6a6d958cbfb51 src/SeasonToggleFactory.sol:SeasonToggleFactory --etherscan-api-key $ETHERSCAN_KEY
}
