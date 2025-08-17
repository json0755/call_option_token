// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script, console} from "forge-std/Script.sol";
import {CallOptionToken} from "../src/CallOptionToken.sol";

/**
 * @title 期权演示脚本
 * @notice 演示期权发行、转让和行权的完整流程
 */
contract DemoScript is Script {
    CallOptionToken public optionToken;
    
    // 演示用户地址
    address public issuer = address(0x1111);
    address public buyer1 = address(0x2222);
    address public buyer2 = address(0x3333);
    
    function run() public {
        console.log(unicode"\n=== 期权合约演示开始 ===");
        
        // 部署合约
        deployContract();
        
        // 演示发行期权
        demonstrateIssueOptions();
        
        // 演示期权转让
        demonstrateTransferOptions();
        
        // 演示行权过程
        demonstrateExerciseOptions();
        
        // 演示期权到期
        demonstrateExpiration();
        
        console.log(unicode"\n=== 期权合约演示结束 ===");
    }
    
    function deployContract() internal {
        console.log(unicode"\n--- 1. 部署期权合约 ---");
        
        vm.startPrank(issuer);
        optionToken = new CallOptionToken(
            "Call Option Token",
            "COT",
            2 ether, // 行权价格: 2 ETH
            block.timestamp + 30 days, // 30天后到期
            address(0) // ETH作为标的资产
        );
        vm.stopPrank();
        
        console.log(unicode"合约地址:", address(optionToken));
        console.log(unicode"期权名称:", optionToken.name());
        console.log(unicode"期权符号:", optionToken.symbol());
        console.log(unicode"行权价格:", optionToken.strikePrice() / 1e18, "ETH");
        console.log(unicode"到期时间:", optionToken.expirationDate());
    }
    
    function demonstrateIssueOptions() internal {
        console.log(unicode"\n--- 2. 发行期权 ---");
        
        vm.deal(issuer, 100 ether);
        vm.startPrank(issuer);
        
        uint256 underlyingAmount = 10 ether;
        console.log(unicode"发行人地址:", issuer);
        console.log(unicode"发行人ETH余额:", issuer.balance / 1e18, "ETH");
        console.log(unicode"准备发行期权数量:", underlyingAmount / 1e18, unicode"个");
        
        // 发行期权
        optionToken.issueOptions{value: underlyingAmount}(underlyingAmount);
        
        console.log(unicode"\n发行后状态:");
        console.log(unicode"发行人期权余额:", optionToken.balanceOf(issuer) / 1e18, unicode"个");
        console.log(unicode"合约ETH余额:", address(optionToken).balance / 1e18, "ETH");
        console.log(unicode"总期权供应量:", optionToken.totalSupply() / 1e18, unicode"个");
        console.log(unicode"总标的资产存款:", optionToken.totalUnderlyingDeposited() / 1e18, "ETH");
        
        vm.stopPrank();
    }
    
    function demonstrateTransferOptions() internal {
        console.log(unicode"\n--- 3. 期权转让 ---");
        
        vm.startPrank(issuer);
        
        // 转让给买家1
        uint256 transferAmount1 = 3 ether;
        optionToken.transfer(buyer1, transferAmount1);
        console.log(unicode"转让给买家1:", transferAmount1 / 1e18, unicode"个期权");
        
        // 转让给买家2
        uint256 transferAmount2 = 2 ether;
        optionToken.transfer(buyer2, transferAmount2);
        console.log(unicode"转让给买家2:", transferAmount2 / 1e18, unicode"个期权");
        
        console.log(unicode"\n转让后余额分布:");
        console.log(unicode"发行人余额:", optionToken.balanceOf(issuer) / 1e18, unicode"个");
        console.log(unicode"买家1余额:", optionToken.balanceOf(buyer1) / 1e18, unicode"个");
        console.log(unicode"买家2余额:", optionToken.balanceOf(buyer2) / 1e18, unicode"个");
        
        vm.stopPrank();
    }
    
    function demonstrateExerciseOptions() internal {
        console.log(unicode"\n--- 4. 行权过程 ---");
        
        // 设置时间到行权期（到期前24小时内）
        uint256 exerciseStartTime = optionToken.expirationDate() - 1 days;
        vm.warp(exerciseStartTime + 1 hours); // 到期前23小时
        console.log(unicode"当前时间已进入行权期");
        console.log(unicode"是否在行权期:", optionToken.isExercisePeriod());
        
        // 买家1行权
        vm.deal(buyer1, 10 ether);
        vm.startPrank(buyer1);
        
        uint256 exerciseAmount = 2 ether;
        uint256 requiredPayment = optionToken.calculateExerciseCost(exerciseAmount);
        
        console.log(unicode"\n买家1行权:");
        console.log(unicode"行权期权数量:", exerciseAmount / 1e18, unicode"个");
        console.log(unicode"需要支付:", requiredPayment / 1e18, "ETH");
        console.log(unicode"买家1行权前ETH余额:", buyer1.balance / 1e18, "ETH");
        
        // 执行行权
        optionToken.exercise{value: requiredPayment + 1 ether}(exerciseAmount);
        
        console.log(unicode"\n行权后状态:");
        console.log(unicode"买家1期权余额:", optionToken.balanceOf(buyer1) / 1e18, unicode"个");
        console.log(unicode"买家1ETH余额:", buyer1.balance / 1e18, "ETH");
        console.log(unicode"合约ETH余额:", address(optionToken).balance / 1e18, "ETH");
        console.log(unicode"剩余期权供应量:", optionToken.totalSupply() / 1e18, unicode"个");
        console.log(unicode"剩余标的资产:", optionToken.totalUnderlyingDeposited() / 1e18, "ETH");
        
        vm.stopPrank();
        
        // 买家2也行权
        vm.deal(buyer2, 10 ether);
        vm.startPrank(buyer2);
        
        uint256 exerciseAmount2 = 1 ether;
        uint256 requiredPayment2 = optionToken.calculateExerciseCost(exerciseAmount2);
        
        console.log(unicode"\n买家2行权:");
        console.log(unicode"行权期权数量:", exerciseAmount2 / 1e18, unicode"个");
        console.log(unicode"需要支付:", requiredPayment2 / 1e18, "ETH");
        
        optionToken.exercise{value: requiredPayment2}(exerciseAmount2);
        
        console.log(unicode"\n买家2行权后:");
        console.log(unicode"买家2期权余额:", optionToken.balanceOf(buyer2) / 1e18, unicode"个");
        console.log(unicode"买家2ETH余额:", buyer2.balance / 1e18, "ETH");
        
        vm.stopPrank();
    }
    
    function demonstrateExpiration() internal {
        console.log(unicode"\n--- 5. 期权到期处理 ---");
        
        // 设置时间到期权到期后
        vm.warp(optionToken.expirationDate() + 1 days);
        console.log(unicode"期权已到期");
        console.log(unicode"是否在行权期:", optionToken.isExercisePeriod());
        
        // 发行人处理到期期权
        vm.startPrank(issuer);
        
        console.log(unicode"\n到期前状态:");
        console.log(unicode"合约是否已到期:", optionToken.expired());
        console.log(unicode"剩余期权供应量:", optionToken.totalSupply() / 1e18, unicode"个");
        console.log(unicode"剩余标的资产:", optionToken.totalUnderlyingDeposited() / 1e18, "ETH");
        console.log(unicode"发行人ETH余额:", issuer.balance / 1e18, "ETH");
        
        // 执行到期处理
        optionToken.expireOptions();
        
        console.log(unicode"\n到期后状态:");
        console.log(unicode"合约是否已到期:", optionToken.expired());
        console.log(unicode"发行人ETH余额:", issuer.balance / 1e18, "ETH");
        console.log(unicode"合约ETH余额:", address(optionToken).balance / 1e18, "ETH");
        
        vm.stopPrank();
    }
}