// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script, console} from "forge-std/Script.sol";
import {CallOptionToken} from "../src/CallOptionToken.sol";

/**
 * @title 简化期权演示脚本
 * @notice 专门演示期权发行和行权的核心流程
 */
contract SimpleDemoScript is Script {
    CallOptionToken public optionToken;
    
    address public issuer = address(0x1111);
    address public buyer = address(0x2222);
    
    function run() public {
        console.log(unicode"\n========== 期权合约核心流程演示 ==========");
        
        // 1. 部署合约
        deployContract();
        
        // 2. 发行期权
        issueOptions();
        
        // 3. 转让期权
        transferOptions();
        
        // 4. 行权演示
        exerciseOptions();
        
        console.log(unicode"\n========== 演示完成 ==========");
    }
    
    function deployContract() internal {
        console.log(unicode"\n步骤1: 部署期权合约");
        
        vm.startPrank(issuer);
        optionToken = new CallOptionToken(
            "Demo Call Option",
            "DCO",
            2 ether, // 行权价格: 2 ETH
            block.timestamp + 30 days,
            address(0) // ETH作为标的资产
        );
        vm.stopPrank();
        
        console.log(unicode"✓ 合约部署成功");
        console.log(unicode"  合约地址:", address(optionToken));
        console.log(unicode"  行权价格:", optionToken.strikePrice() / 1e18, "ETH");
    }
    
    function issueOptions() internal {
        console.log(unicode"\n步骤2: 发行期权");
        
        vm.deal(issuer, 100 ether);
        vm.startPrank(issuer);
        
        uint256 underlyingAmount = 5 ether;
        console.log(unicode"  发行人准备存入:", underlyingAmount / 1e18, "ETH");
        console.log(unicode"  发行人ETH余额(发行前):", issuer.balance / 1e18, "ETH");
        
        // 发行期权
        optionToken.issueOptions{value: underlyingAmount}(underlyingAmount);
        
        console.log(unicode"✓ 期权发行成功");
        console.log(unicode"  发行的期权数量:", optionToken.balanceOf(issuer) / 1e18, unicode"个");
        console.log(unicode"  合约ETH余额:", address(optionToken).balance / 1e18, "ETH");
        console.log(unicode"  发行人ETH余额(发行后):", issuer.balance / 1e18, "ETH");
        
        vm.stopPrank();
    }
    
    function transferOptions() internal {
        console.log(unicode"\n步骤3: 转让期权");
        
        vm.startPrank(issuer);
        
        uint256 transferAmount = 2 ether;
        optionToken.transfer(buyer, transferAmount);
        
        console.log(unicode"✓ 期权转让成功");
        console.log(unicode"  转让数量:", transferAmount / 1e18, unicode"个");
        console.log(unicode"  买家期权余额:", optionToken.balanceOf(buyer) / 1e18, unicode"个");
        console.log(unicode"  发行人剩余期权:", optionToken.balanceOf(issuer) / 1e18, unicode"个");
        
        vm.stopPrank();
    }
    
    function exerciseOptions() internal {
        console.log(unicode"\n步骤4: 行权过程");
        
        // 设置时间到行权期
        uint256 exerciseStartTime = optionToken.expirationDate() - 1 days;
        vm.warp(exerciseStartTime + 1 hours);
        
        console.log(unicode"  当前是否在行权期:", optionToken.isExercisePeriod());
        
        vm.deal(buyer, 10 ether);
        vm.startPrank(buyer);
        
        uint256 exerciseAmount = 1 ether;
        uint256 requiredPayment = optionToken.calculateExerciseCost(exerciseAmount);
        
        console.log(unicode"\n行权前状态:");
        console.log(unicode"  买家期权余额:", optionToken.balanceOf(buyer) / 1e18, unicode"个");
        console.log(unicode"  买家ETH余额:", buyer.balance / 1e18, "ETH");
        console.log(unicode"  合约ETH余额:", address(optionToken).balance / 1e18, "ETH");
        console.log(unicode"  准备行权数量:", exerciseAmount / 1e18, unicode"个");
        console.log(unicode"  需要支付:", requiredPayment / 1e18, "ETH");
        
        // 执行行权
        optionToken.exercise{value: requiredPayment}(exerciseAmount);
        
        console.log(unicode"\n✓ 行权成功！");
        console.log(unicode"\n行权后状态:");
        console.log(unicode"  买家期权余额:", optionToken.balanceOf(buyer) / 1e18, unicode"个");
        console.log(unicode"  买家ETH余额:", buyer.balance / 1e18, "ETH");
        console.log(unicode"  合约ETH余额:", address(optionToken).balance / 1e18, "ETH");
        console.log(unicode"  剩余期权供应量:", optionToken.totalSupply() / 1e18, unicode"个");
        console.log(unicode"  剩余标的资产:", optionToken.totalUnderlyingDeposited() / 1e18, "ETH");
        
        vm.stopPrank();
    }
}