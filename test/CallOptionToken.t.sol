// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../src/CallOptionToken.sol";

contract CallOptionTokenTest is Test {
    CallOptionToken public optionToken;
    
    address public owner = address(0x1);
    address public user1 = address(0x2);
    address public user2 = address(0x3);
    
    uint256 public constant STRIKE_PRICE = 2e18; // 2 ETH per option token
    uint256 public constant EXPIRATION_DATE = 1735689600; // 2025-01-01 00:00:00 UTC
    uint256 public constant UNDERLYING_AMOUNT = 10 ether;
    
    event OptionsIssued(address indexed issuer, uint256 underlyingAmount, uint256 optionTokens);
    event OptionsExercised(address indexed exerciser, uint256 optionTokens, uint256 underlyingReceived, uint256 paymentMade);
    event OptionsExpired(address indexed owner, uint256 underlyingRedeemed);
    
    function setUp() public {
        vm.startPrank(owner);
        vm.deal(owner, 100 ether);
        vm.deal(user1, 100 ether);
        vm.deal(user2, 100 ether);
        
        optionToken = new CallOptionToken(
            "ETH Call Option",
            "ETHCALL",
            STRIKE_PRICE,
            EXPIRATION_DATE,
            address(0) // ETH as underlying
        );
        vm.stopPrank();
    }
    
    function testConstructor() public {
        assertEq(optionToken.name(), "ETH Call Option");
        assertEq(optionToken.symbol(), "ETHCALL");
        assertEq(optionToken.strikePrice(), STRIKE_PRICE);
        assertEq(optionToken.expirationDate(), EXPIRATION_DATE);
        assertEq(optionToken.underlyingAsset(), address(0));
        assertEq(optionToken.owner(), owner);
        assertFalse(optionToken.expired());
    }
    
    function testConstructorInvalidStrikePrice() public {
        vm.expectRevert("Strike price must be greater than 0");
        vm.prank(owner);
        new CallOptionToken(
            "ETH Call Option",
            "ETHCALL",
            0, // Invalid strike price
            EXPIRATION_DATE,
            address(0)
        );
    }
    
    function testConstructorInvalidExpirationDate() public {
        vm.expectRevert("Expiration date must be in the future");
        vm.prank(owner);
        new CallOptionToken(
            "ETH Call Option",
            "ETHCALL",
            STRIKE_PRICE,
            block.timestamp - 1, // Past date
            address(0)
        );
    }
    
    function testIssueOptions() public {
        vm.startPrank(owner);
        
        vm.expectEmit(true, false, false, true);
        emit OptionsIssued(owner, UNDERLYING_AMOUNT, UNDERLYING_AMOUNT);
        
        optionToken.issueOptions{value: UNDERLYING_AMOUNT}(UNDERLYING_AMOUNT);
        
        assertEq(optionToken.totalSupply(), UNDERLYING_AMOUNT);
        assertEq(optionToken.balanceOf(owner), UNDERLYING_AMOUNT);
        assertEq(optionToken.totalUnderlyingDeposited(), UNDERLYING_AMOUNT);
        assertEq(address(optionToken).balance, UNDERLYING_AMOUNT);
        
        vm.stopPrank();
    }
    
    function testIssueOptionsOnlyOwner() public {
        vm.prank(user1);
        vm.expectRevert();
        optionToken.issueOptions{value: UNDERLYING_AMOUNT}(UNDERLYING_AMOUNT);
    }
    
    function testIssueOptionsETHAmountMismatch() public {
        vm.prank(owner);
        vm.expectRevert("ETH amount mismatch");
        optionToken.issueOptions{value: 5 ether}(UNDERLYING_AMOUNT);
    }
    
    function testIssueOptionsZeroAmount() public {
        vm.prank(owner);
        vm.expectRevert("Must deposit underlying assets");
        optionToken.issueOptions{value: 0}(0);
    }
    
    function testTransferOptions() public {
        // Issue options first
        vm.prank(owner);
        optionToken.issueOptions{value: UNDERLYING_AMOUNT}(UNDERLYING_AMOUNT);
        
        // Transfer some options to user1
        uint256 transferAmount = 3 ether;
        vm.prank(owner);
        optionToken.transfer(user1, transferAmount);
        
        assertEq(optionToken.balanceOf(owner), UNDERLYING_AMOUNT - transferAmount);
        assertEq(optionToken.balanceOf(user1), transferAmount);
    }
    
    function testExerciseOptions() public {
        // Issue options
        vm.prank(owner);
        optionToken.issueOptions{value: UNDERLYING_AMOUNT}(UNDERLYING_AMOUNT);
        
        // Transfer some options to user1
        uint256 exerciseAmount = 2 ether;
        vm.prank(owner);
        optionToken.transfer(user1, exerciseAmount);
        
        // Move to exercise period (1 day before expiration)
        vm.warp(EXPIRATION_DATE - 12 hours);
        
        // Calculate required payment
        uint256 requiredPayment = optionToken.calculateExerciseCost(exerciseAmount);
        
        uint256 user1BalanceBefore = user1.balance;
        uint256 contractBalanceBefore = address(optionToken).balance;
        
        vm.startPrank(user1);
        
        vm.expectEmit(true, false, false, true);
        emit OptionsExercised(user1, exerciseAmount, exerciseAmount, requiredPayment);
        
        optionToken.exercise{value: requiredPayment}(exerciseAmount);
        
        vm.stopPrank();
        
        // Check balances
        assertEq(optionToken.balanceOf(user1), 0);
        assertEq(optionToken.totalSupply(), UNDERLYING_AMOUNT - exerciseAmount);
        assertEq(optionToken.totalUnderlyingDeposited(), UNDERLYING_AMOUNT - exerciseAmount);
        
        // User should receive the underlying ETH
        assertEq(user1.balance, user1BalanceBefore - requiredPayment + exerciseAmount);
        
        // Contract should have less underlying ETH but more payment ETH
        assertEq(address(optionToken).balance, contractBalanceBefore - exerciseAmount + requiredPayment);
    }
    
    function testExerciseOptionsWithExcess() public {
        // Issue options
        vm.prank(owner);
        optionToken.issueOptions{value: UNDERLYING_AMOUNT}(UNDERLYING_AMOUNT);
        
        // Transfer some options to user1
        uint256 exerciseAmount = 1 ether;
        vm.prank(owner);
        optionToken.transfer(user1, exerciseAmount);
        
        // Move to exercise period
        vm.warp(EXPIRATION_DATE - 12 hours);
        
        uint256 requiredPayment = optionToken.calculateExerciseCost(exerciseAmount);
        uint256 excessPayment = 1 ether;
        uint256 totalPayment = requiredPayment + excessPayment;
        
        uint256 user1BalanceBefore = user1.balance;
        
        vm.prank(user1);
        optionToken.exercise{value: totalPayment}(exerciseAmount);
        
        // User should get back the excess payment
        assertEq(user1.balance, user1BalanceBefore - requiredPayment + exerciseAmount);
    }
    
    function testExerciseOptionsInsufficientPayment() public {
        // Issue options
        vm.prank(owner);
        optionToken.issueOptions{value: UNDERLYING_AMOUNT}(UNDERLYING_AMOUNT);
        
        // Transfer some options to user1
        uint256 exerciseAmount = 1 ether;
        vm.prank(owner);
        optionToken.transfer(user1, exerciseAmount);
        
        // Move to exercise period
        vm.warp(EXPIRATION_DATE - 12 hours);
        
        uint256 requiredPayment = optionToken.calculateExerciseCost(exerciseAmount);
        
        vm.prank(user1);
        vm.expectRevert(CallOptionToken.InsufficientPayment.selector);
        optionToken.exercise{value: requiredPayment - 1}(exerciseAmount);
    }
    
    function testExerciseOptionsInsufficientBalance() public {
        // Issue options
        vm.prank(owner);
        optionToken.issueOptions{value: UNDERLYING_AMOUNT}(UNDERLYING_AMOUNT);
        
        // Move to exercise period
        vm.warp(EXPIRATION_DATE - 12 hours);
        
        uint256 exerciseAmount = 1 ether;
        uint256 requiredPayment = optionToken.calculateExerciseCost(exerciseAmount);
        
        vm.prank(user1); // user1 has no option tokens
        vm.expectRevert(CallOptionToken.InsufficientBalance.selector);
        optionToken.exercise{value: requiredPayment}(exerciseAmount);
    }
    
    function testExerciseOptionsNotInExercisePeriod() public {
        // Issue options
        vm.prank(owner);
        optionToken.issueOptions{value: UNDERLYING_AMOUNT}(UNDERLYING_AMOUNT);
        
        // Transfer some options to user1
        uint256 exerciseAmount = 1 ether;
        vm.prank(owner);
        optionToken.transfer(user1, exerciseAmount);
        
        // Try to exercise before exercise period
        uint256 requiredPayment = optionToken.calculateExerciseCost(exerciseAmount);
        
        vm.prank(user1);
        vm.expectRevert(CallOptionToken.NotExercisePeriod.selector);
        optionToken.exercise{value: requiredPayment}(exerciseAmount);
    }
    
    function testExerciseOptionsAfterExpiration() public {
        // Issue options
        vm.prank(owner);
        optionToken.issueOptions{value: UNDERLYING_AMOUNT}(UNDERLYING_AMOUNT);
        
        // Transfer some options to user1
        uint256 exerciseAmount = 1 ether;
        vm.prank(owner);
        optionToken.transfer(user1, exerciseAmount);
        
        // Move past expiration
        vm.warp(EXPIRATION_DATE + 1);
        
        uint256 requiredPayment = optionToken.calculateExerciseCost(exerciseAmount);
        
        vm.prank(user1);
        vm.expectRevert(CallOptionToken.NotExercisePeriod.selector);
        optionToken.exercise{value: requiredPayment}(exerciseAmount);
    }
    
    function testExpireOptions() public {
        // Issue options
        vm.prank(owner);
        optionToken.issueOptions{value: UNDERLYING_AMOUNT}(UNDERLYING_AMOUNT);
        
        // Move past expiration
        vm.warp(EXPIRATION_DATE + 1);
        
        uint256 ownerBalanceBefore = owner.balance;
        
        vm.startPrank(owner);
        
        vm.expectEmit(true, false, false, true);
        emit OptionsExpired(owner, UNDERLYING_AMOUNT);
        
        optionToken.expireOptions();
        
        vm.stopPrank();
        
        assertTrue(optionToken.expired());
        assertEq(optionToken.totalUnderlyingDeposited(), 0);
        assertEq(address(optionToken).balance, 0);
        assertEq(owner.balance, ownerBalanceBefore + UNDERLYING_AMOUNT);
    }
    
    function testExpireOptionsOnlyOwner() public {
        vm.warp(EXPIRATION_DATE + 1);
        
        vm.prank(user1);
        vm.expectRevert();
        optionToken.expireOptions();
    }
    
    function testExpireOptionsNotExpired() public {
        vm.prank(owner);
        vm.expectRevert(CallOptionToken.OptionNotExpired.selector);
        optionToken.expireOptions();
    }
    
    function testExpireOptionsAlreadyExpired() public {
        // Issue options
        vm.prank(owner);
        optionToken.issueOptions{value: UNDERLYING_AMOUNT}(UNDERLYING_AMOUNT);
        
        // Move past expiration and expire
        vm.warp(EXPIRATION_DATE + 1);
        vm.prank(owner);
        optionToken.expireOptions();
        
        // Try to expire again
        vm.prank(owner);
        vm.expectRevert(CallOptionToken.OptionExpired.selector);
        optionToken.expireOptions();
    }
    
    function testIsExercisePeriod() public {
        // Before exercise period
        assertFalse(optionToken.isExercisePeriod());
        
        // During exercise period (1 day before expiration)
        vm.warp(EXPIRATION_DATE - 12 hours);
        assertTrue(optionToken.isExercisePeriod());
        
        // At expiration
        vm.warp(EXPIRATION_DATE);
        assertTrue(optionToken.isExercisePeriod());
        
        // After expiration
        vm.warp(EXPIRATION_DATE + 1);
        assertFalse(optionToken.isExercisePeriod());
    }
    
    function testGetOptionInfo() public {
        // Issue options
        vm.prank(owner);
        optionToken.issueOptions{value: UNDERLYING_AMOUNT}(UNDERLYING_AMOUNT);
        
        (
            uint256 _strikePrice,
            uint256 _expirationDate,
            uint256 _totalSupply,
            uint256 _totalUnderlying,
            bool _expired,
            bool _canExercise
        ) = optionToken.getOptionInfo();
        
        assertEq(_strikePrice, STRIKE_PRICE);
        assertEq(_expirationDate, EXPIRATION_DATE);
        assertEq(_totalSupply, UNDERLYING_AMOUNT);
        assertEq(_totalUnderlying, UNDERLYING_AMOUNT);
        assertFalse(_expired);
        assertFalse(_canExercise); // Not in exercise period yet
        
        // Move to exercise period
        vm.warp(EXPIRATION_DATE - 12 hours);
        
        (, , , , , _canExercise) = optionToken.getOptionInfo();
        assertTrue(_canExercise);
    }
    
    function testCalculateExerciseCost() public {
        uint256 optionAmount = 1 ether;
        uint256 expectedCost = (optionAmount * STRIKE_PRICE) / 1e18;
        
        assertEq(optionToken.calculateExerciseCost(optionAmount), expectedCost);
    }
    
    function testGetContractBalance() public {
        assertEq(optionToken.getContractBalance(), 0);
        
        vm.prank(owner);
        optionToken.issueOptions{value: UNDERLYING_AMOUNT}(UNDERLYING_AMOUNT);
        
        assertEq(optionToken.getContractBalance(), UNDERLYING_AMOUNT);
    }
    
    function testEmergencyWithdraw() public {
        // Issue options
        vm.prank(owner);
        optionToken.issueOptions{value: UNDERLYING_AMOUNT}(UNDERLYING_AMOUNT);
        
        uint256 ownerBalanceBefore = owner.balance;
        
        vm.prank(owner);
        optionToken.emergencyWithdraw();
        
        assertEq(address(optionToken).balance, 0);
        assertEq(owner.balance, ownerBalanceBefore + UNDERLYING_AMOUNT);
    }
    
    function testEmergencyWithdrawOnlyOwner() public {
        vm.prank(user1);
        vm.expectRevert();
        optionToken.emergencyWithdraw();
    }
    
    function testReceiveETH() public {
        uint256 sendAmount = 1 ether;
        
        vm.prank(user1);
        (bool success, ) = address(optionToken).call{value: sendAmount}("");
        
        assertTrue(success);
        assertEq(address(optionToken).balance, sendAmount);
    }
    
    function testCompleteOptionLifecycle() public {
        // 1. Issue options
        vm.prank(owner);
        optionToken.issueOptions{value: UNDERLYING_AMOUNT}(UNDERLYING_AMOUNT);
        
        // 2. Transfer options to users
        vm.startPrank(owner);
        optionToken.transfer(user1, 3 ether);
        optionToken.transfer(user2, 2 ether);
        vm.stopPrank();
        
        // 3. Move to exercise period
        vm.warp(EXPIRATION_DATE - 12 hours);
        
        // 4. User1 exercises some options
        uint256 user1ExerciseAmount = 1 ether;
        uint256 user1Payment = optionToken.calculateExerciseCost(user1ExerciseAmount);
        
        vm.prank(user1);
        optionToken.exercise{value: user1Payment}(user1ExerciseAmount);
        
        // 5. Move past expiration
        vm.warp(EXPIRATION_DATE + 1);
        
        // 6. Owner expires remaining options
        vm.prank(owner);
        optionToken.expireOptions();
        
        // Verify final state
        assertTrue(optionToken.expired());
        assertEq(optionToken.totalUnderlyingDeposited(), 0);
        assertEq(optionToken.balanceOf(user1), 2 ether); // Still has unexercised options
        assertEq(optionToken.balanceOf(user2), 2 ether); // Still has unexercised options
    }
}