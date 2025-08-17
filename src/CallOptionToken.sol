// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// 导入OpenZeppelin标准库
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";           // ERC20标准实现
import "@openzeppelin/contracts/access/Ownable.sol";              // 所有权管理
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";       // 重入攻击防护

/**
 * @title CallOptionToken - 看涨期权Token合约
 * @dev 这是一个完整的看涨期权实现，支持期权的发行、交易、行权和过期处理
 * 
 * 核心功能：
 * 1. 期权发行：项目方存入ETH，按1:1比例铸造期权Token
 * 2. 期权交易：基于ERC20标准，可在DEX上自由交易
 * 3. 期权行权：用户在行权期内支付行权价格获得标的ETH
 * 4. 过期处理：过期后项目方可赎回未行权的标的资产
 * 
 * 安全特性：
 * - 使用OpenZeppelin安全库
 * - 重入攻击防护
 * - 严格的权限控制
 * - 时间锁定机制
 * 
 * @author Denglian
 */
contract CallOptionToken is ERC20, Ownable, ReentrancyGuard {
    // ============ 期权核心参数 ============
    // 这些参数在合约部署时确定，之后不可更改
    
    uint256 public immutable strikePrice;      // 行权价格：用户行权时需要支付的价格 (以wei为单位)
                                                // 例如：2e18 表示 2 ETH
    
    uint256 public immutable expirationDate;   // 到期日期：期权的最后有效时间 (Unix时间戳)
                                                // 过期后期权失效，无法再行权
    
    address public immutable underlyingAsset;  // 标的资产地址：期权对应的底层资产
                                                // address(0) 表示ETH，其他地址表示ERC20代币
    
    // ============ 合约运行状态 ============
    
    bool public expired;                        // 过期标志：标记期权是否已被手动过期
                                                // true表示已过期，false表示仍有效
    
    uint256 public totalUnderlyingDeposited;   // 标的资产总量：合约中存储的标的资产总数
                                                // 用于跟踪可供行权的资产数量
    
    // ============ 事件定义 ============
    // 用于记录合约中的重要操作，便于前端监听和数据分析
    
    /**
     * @dev 期权发行事件
     * @param issuer 发行者地址（项目方）
     * @param underlyingAmount 存入的标的资产数量
     * @param optionTokens 铸造的期权Token数量
     */
    event OptionsIssued(address indexed issuer, uint256 underlyingAmount, uint256 optionTokens);
    
    /**
     * @dev 期权行权事件
     * @param exerciser 行权者地址（用户）
     * @param optionTokens 行权的期权Token数量
     * @param underlyingReceived 获得的标的资产数量
     * @param paymentMade 支付的行权费用
     */
    event OptionsExercised(address indexed exerciser, uint256 optionTokens, uint256 underlyingReceived, uint256 paymentMade);
    
    /**
     * @dev 期权过期事件
     * @param owner 合约所有者地址
     * @param underlyingRedeemed 赎回的标的资产数量
     */
    event OptionsExpired(address indexed owner, uint256 underlyingRedeemed);
    
    // ============ 自定义错误定义 ============
    // 使用自定义错误可以节省gas费用，并提供更清晰的错误信息
    
    error OptionExpired();              // 期权已过期：当尝试在过期后进行操作时抛出
    error OptionNotExpired();           // 期权未过期：当尝试在未过期时执行过期操作时抛出
    error NotExercisePeriod();          // 非行权期：当在行权期外尝试行权时抛出
    error InsufficientPayment();        // 支付不足：当行权支付金额不够时抛出
    error InsufficientBalance();        // 余额不足：当用户期权Token余额不足时抛出
    error NoUnderlyingToRedeem();       // 无资产可赎回：当没有标的资产可赎回时抛出
    error TransferFailed();             // 转账失败：当ETH转账失败时抛出
    
    /**
     * @dev 构造函数 - 初始化期权合约
     * 
     * 部署时需要确定期权的所有核心参数，这些参数一旦设定就无法更改
     * 
     * @param _name 期权Token名称，例如："Call Option ETH 2024-12"
     * @param _symbol 期权Token符号，例如："CALL-ETH-1224"
     * @param _strikePrice 行权价格，以wei为单位，例如：2e18 表示 2 ETH
     * @param _expirationDate 到期日期，Unix时间戳格式
     * @param _underlyingAsset 标的资产地址，ETH使用address(0)
     * 
     * 注意事项：
     * - 行权价格必须大于0
     * - 到期日期必须在未来
     * - 当前版本仅支持ETH作为标的资产
     */
    constructor(
        string memory _name,
        string memory _symbol,
        uint256 _strikePrice,
        uint256 _expirationDate,
        address _underlyingAsset
    ) ERC20(_name, _symbol) Ownable(msg.sender) {
        // 参数验证：确保输入参数的有效性
        require(_strikePrice > 0, "Strike price must be greater than 0");
        require(_expirationDate > block.timestamp, "Expiration date must be in the future");
        
        // 设置不可变参数
        strikePrice = _strikePrice;
        expirationDate = _expirationDate;
        underlyingAsset = _underlyingAsset;
    }
    
    /**
     * @dev 发行期权Token - 项目方专用功能
     * 
     * 这是期权生命周期的第一步，只有合约所有者（项目方）可以调用
     * 项目方需要存入标的资产（ETH），合约会按1:1比例铸造期权Token
     * 
     * 工作流程：
     * 1. 验证期权未过期
     * 2. 接收标的资产（ETH）
     * 3. 按1:1比例铸造期权Token给项目方
     * 4. 更新合约状态
     * 5. 发出事件通知
     * 
     * @param _underlyingAmount 要存入的标的资产数量（必须与msg.value相等）
     * 
     * 使用示例：
     * ```solidity
     * // 存入10 ETH，发行10个期权Token
     * optionContract.issueOptions{value: 10 ether}(10 ether);
     * ```
     * 
     * 注意事项：
     * - 仅限合约所有者调用
     * - 期权未过期时才能发行
     * - 对于ETH，必须通过msg.value传入资金
     * - 发行后项目方可以将期权Token转给用户或在DEX上出售
     */
    function issueOptions(uint256 _underlyingAmount) external payable onlyOwner nonReentrant {
        // 步骤1：验证期权状态
        if (expired) revert OptionExpired();
        
        uint256 actualAmount;
        
        // 步骤2：处理标的资产存入
        if (underlyingAsset == address(0)) {
            // ETH作为标的资产的情况
            actualAmount = msg.value;
            require(actualAmount == _underlyingAmount, "ETH amount mismatch");
        } else {
            // ERC20代币作为标的资产 (预留功能，暂未实现)
            // 未来版本可以支持USDC、USDT等稳定币作为标的资产
            revert("ERC20 underlying assets not implemented yet");
        }
        
        // 步骤3：验证存入金额
        require(actualAmount > 0, "Must deposit underlying assets");
        
        // 步骤4：更新合约状态并铸造期权Token
        // 按1:1比例铸造：存入1 ETH = 铸造1个期权Token
        totalUnderlyingDeposited += actualAmount;  // 更新总存入量
        _mint(msg.sender, actualAmount);           // 铸造期权Token给项目方
        
        // 步骤5：发出事件通知
        emit OptionsIssued(msg.sender, actualAmount, actualAmount);
    }
    
    /**
     * @dev 行权功能 - 用户专用功能
     * 
     * 这是期权的核心功能，允许用户在行权期内行使期权权利
     * 用户需要支付行权价格来获得标的资产（ETH）
     * 
     * 行权条件：
     * 1. 期权未过期
     * 2. 当前时间在行权期内（到期前24小时）
     * 3. 用户拥有足够的期权Token
     * 4. 用户支付足够的行权费用
     * 
     * 工作流程：
     * 1. 验证行权条件
     * 2. 计算所需支付金额
     * 3. 销毁用户的期权Token
     * 4. 转移标的资产给用户
     * 5. 退还多余支付（如有）
     * 6. 发出事件通知
     * 
     * @param _optionAmount 要行权的期权Token数量
     * 
     * 计算公式：
     * 所需支付 = _optionAmount * strikePrice / 1e18
     * 
     * 使用示例：
     * ```solidity
     * // 行权1个期权Token，假设行权价格为2 ETH
     * uint256 cost = optionContract.calculateExerciseCost(1 ether);
     * optionContract.exercise{value: cost}(1 ether);
     * ```
     * 
     * 注意事项：
     * - 只能在行权期内调用（到期前24小时）
     * - 需要支付对应的行权费用
     * - 行权后期权Token会被销毁
     * - 多余的支付会自动退还
     */
    function exercise(uint256 _optionAmount) external payable nonReentrant {
        // 步骤1：验证行权条件
        if (expired) revert OptionExpired();                           // 检查期权是否已过期
        if (!isExercisePeriod()) revert NotExercisePeriod();          // 检查是否在行权期内
        if (balanceOf(msg.sender) < _optionAmount) revert InsufficientBalance(); // 检查用户期权Token余额
        
        // 步骤2：计算并验证支付金额
        uint256 requiredPayment = _optionAmount * strikePrice / 1e18;  // 计算所需支付的行权费用
        if (msg.value < requiredPayment) revert InsufficientPayment(); // 验证用户支付是否足够
        
        // 步骤3：销毁期权Token
        // 行权后期权Token失效，需要从用户账户中销毁
        _burn(msg.sender, _optionAmount);
        
        // 步骤4：更新合约状态
        // 减少合约中的标的资产总量
        totalUnderlyingDeposited -= _optionAmount;
        
        // 步骤5：处理支付退还
        // 如果用户支付超过所需金额，退还多余部分
        uint256 excess = msg.value - requiredPayment;
        if (excess > 0) {
            (bool refundSuccess, ) = payable(msg.sender).call{value: excess}("");
            if (!refundSuccess) revert TransferFailed();
        }
        
        // 步骤6：转移标的资产给用户
        // 将对应数量的ETH转给行权用户
        (bool transferSuccess, ) = payable(msg.sender).call{value: _optionAmount}("");
        if (!transferSuccess) revert TransferFailed();
        
        // 步骤7：发出事件通知
        emit OptionsExercised(msg.sender, _optionAmount, _optionAmount, requiredPayment);
    }
    
    /**
     * @dev 期权过期处理 - 项目方专用功能
     * 
     * 当期权到期后，项目方可以调用此函数来处理过期期权
     * 这会将所有未行权的标的资产返还给项目方
     * 
     * 过期处理的意义：
     * - 对于项目方：可以收回未被行权的标的资产
     * - 对于用户：未行权的期权Token变为无价值
     * - 对于合约：清理状态，标记为已过期
     * 
     * 执行条件：
     * 1. 当前时间已超过到期日期
     * 2. 期权尚未被标记为过期
     * 3. 仅限合约所有者调用
     * 
     * 工作流程：
     * 1. 验证过期条件
     * 2. 标记期权为已过期
     * 3. 计算剩余标的资产
     * 4. 将剩余资产转给项目方
     * 5. 发出事件通知
     * 
     * 注意事项：
     * - 只能在到期后调用
     * - 执行后期权永久失效
     * - 未行权的期权Token失去价值
     */
    function expireOptions() external onlyOwner nonReentrant {
        // 步骤1：验证过期条件
        if (block.timestamp < expirationDate) revert OptionNotExpired(); // 检查是否已到期
        if (expired) revert OptionExpired();                             // 检查是否已处理过期
        
        // 步骤2：标记期权为已过期
        expired = true;
        
        // 步骤3：处理剩余标的资产
        uint256 remainingUnderlying = totalUnderlyingDeposited;
        if (remainingUnderlying > 0) {
            // 清零标的资产记录
            totalUnderlyingDeposited = 0;
            
            // 步骤4：将剩余资产转给项目方
            (bool success, ) = payable(owner()).call{value: remainingUnderlying}("");
            if (!success) revert TransferFailed();
        }
        
        // 步骤5：发出事件通知
        emit OptionsExpired(owner(), remainingUnderlying);
    }
    
    /**
     * @dev 检查当前是否在行权期内
     * 
     * 行权期规则：
     * - 开始时间：到期日前24小时
     * - 结束时间：到期日
     * - 只有在此期间内用户才能行权
     * 
     * 设计理念：
     * 限制行权期可以防止用户在期权价值不明确时盲目行权
     * 同时给用户足够的时间来决定是否行权
     * 
     * @return bool 如果当前时间在行权期内返回true，否则返回false
     */
    function isExercisePeriod() public view returns (bool) {
        uint256 currentTime = block.timestamp;
        uint256 exerciseStart = expirationDate - 1 days; // 到期前1天开始可以行权
        return currentTime >= exerciseStart && currentTime <= expirationDate;
    }
    
    /**
     * @dev 获取期权的完整信息 - 查询函数
     * 
     * 这是一个便民函数，一次性返回期权的所有关键信息
     * 前端可以调用此函数来显示期权的当前状态
     * 
     * @return _strikePrice 行权价格（wei单位）
     * @return _expirationDate 到期日期（Unix时间戳）
     * @return _totalSupply 当前期权Token总供应量
     * @return _totalUnderlying 合约中标的资产总量
     * @return _expired 期权是否已被手动标记为过期
     * @return _canExercise 当前是否可以行权（综合考虑时间和过期状态）
     */
    function getOptionInfo() external view returns (
        uint256 _strikePrice,
        uint256 _expirationDate,
        uint256 _totalSupply,
        uint256 _totalUnderlying,
        bool _expired,
        bool _canExercise
    ) {
        return (
            strikePrice,                    // 行权价格
            expirationDate,                 // 到期日期
            totalSupply(),                  // 当前期权Token总量
            totalUnderlyingDeposited,       // 标的资产总量
            expired,                        // 是否已过期
            isExercisePeriod() && !expired  // 是否可行权
        );
    }
    
    /**
     * @dev 计算行权所需的支付金额 - 辅助查询函数
     * 
     * 这个函数帮助用户在行权前计算需要支付多少ETH
     * 用户可以先调用此函数，然后准备相应的ETH进行行权
     * 
     * 计算公式：
     * 所需支付 = 期权Token数量 × 行权价格 ÷ 1e18
     * 
     * @param _optionAmount 要行权的期权Token数量（wei单位）
     * @return uint256 需要支付的ETH数量（wei单位）
     * 
     * 使用示例：
     * ```solidity
     * // 计算行权1个期权Token需要多少ETH
     * uint256 cost = optionContract.calculateExerciseCost(1 ether);
     * ```
     */
    function calculateExerciseCost(uint256 _optionAmount) external view returns (uint256) {
        return _optionAmount * strikePrice / 1e18;
    }
    
    /**
     * @dev 获取合约当前ETH余额 - 状态查询函数
     * 
     * 这个函数返回合约中当前存储的ETH总量
     * 主要用于调试和监控合约状态
     * 
     * @return uint256 合约中的ETH数量（wei单位）
     */
    function getContractBalance() external view returns (uint256) {
        return address(this).balance;
    }
    
    /**
     * @dev 紧急提取函数 - 安全措施
     * 
     * 这是一个安全后门，仅在合约出现严重问题时使用
     * 只有合约所有者可以调用，用于在紧急情况下提取所有ETH
     * 
     * 使用场景：
     * - 发现合约漏洞需要紧急修复
     * - 合约逻辑出现问题导致资金锁定
     * - 其他不可预见的紧急情况
     * 
     * 注意事项：
     * - 仅限合约所有者调用
     * - 会提取合约中的所有ETH
     * - 使用前应充分考虑对用户的影响
     */
    function emergencyWithdraw() external onlyOwner {
        uint256 balance = address(this).balance;
        if (balance > 0) {
            (bool success, ) = payable(owner()).call{value: balance}("");
            if (!success) revert TransferFailed();
        }
    }
    
    /**
     * @dev 接收ETH的回调函数
     * 
     * 这个函数允许合约接收直接发送的ETH
     * 主要用于支持期权发行和行权过程中的ETH转账
     * 
     * 注意：直接向合约发送ETH不会触发任何期权相关逻辑
     * 用户应该通过 issueOptions() 或 exercise() 函数来操作
     */
    receive() external payable {
        // 允许接收ETH，但不执行任何特殊逻辑
        // 用户应该使用专门的函数来进行期权操作
    }
}