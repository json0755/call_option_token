// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "../src/CallOptionToken.sol";

contract DeployScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        vm.startBroadcast(deployerPrivateKey);
        
        // 部署参数
        string memory name = "ETH Call Option Token";
        string memory symbol = "ETHCALL";
        uint256 strikePrice = 2e18; // 2 ETH per option token
        uint256 expirationDate = block.timestamp + 30 days; // 30天后到期
        address underlyingAsset = address(0); // ETH作为标的资产
        
        // 部署合约
        CallOptionToken optionToken = new CallOptionToken(
            name,
            symbol,
            strikePrice,
            expirationDate,
            underlyingAsset
        );
        
        vm.stopBroadcast();
        
        // 输出部署信息
        console.log("CallOptionToken deployed at:", address(optionToken));
        console.log("Name:", name);
        console.log("Symbol:", symbol);
        console.log("Strike Price:", strikePrice);
        console.log("Expiration Date:", expirationDate);
        console.log("Underlying Asset:", underlyingAsset);
        console.log("Owner:", optionToken.owner());
    }
}