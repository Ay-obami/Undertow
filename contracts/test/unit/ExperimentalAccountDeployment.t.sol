// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {DeployAccountLayer} from "../../scripts/DeployAccountLayer.s.sol";

contract ExperimentalAccountDeploymentTest is Test {
    function test_DisabledDeploymentRevertsBeforeConfigurationOrBroadcast() public {
        DeployAccountLayer deployment = new DeployAccountLayer();
        vm.setEnv("ENABLE_EXPERIMENTAL_ACCOUNT_LAYER", "false");
        vm.setEnv("FTSO_ORACLE", "deliberately-invalid-address");
        vm.expectRevert("DeployAccountLayer: experimental account layer disabled");
        deployment.run();
    }
}
