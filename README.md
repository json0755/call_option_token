# Call Option Token (看涨期权Token)

一个基于以太坊的看涨期权Token实现，用于理解期权的基本原理和实现机制。

## 项目概述

本项目实现了一个简洁优雅的看涨期权Token合约，支持期权的完整生命周期：发行、交易、行权和过期处理。

## 核心功能

### 1. 期权创建
- 部署时确定标的资产(ETH)、行权价格和到期日期
- 支持灵活的参数配置

### 2. 期权发行 (项目方角色)
- `issueOptions()`: 存入ETH，按1:1比例铸造期权Token
- 支持批量发行，灵活控制供应量

### 3. 期权交易
- 标准ERC20接口，可与USDT等稳定币创建交易对
- 支持在DEX上以较低价格交易期权Token

### 4. 期权行权 (用户角色)
- `exercise()`: 支付行权价格，获得标的ETH，销毁期权Token
- 仅在到期日前24小时内可行权
- 自动处理多余支付的退还

### 5. 过期处理 (项目方角色)
- `expireOptions()`: 过期后销毁所有未行权Token
- 项目方赎回剩余标的资产

## 技术特性

- **安全性**: 基于OpenZeppelin库，包含重入攻击防护
- **Gas优化**: 高效的存储和计算设计
- **权限控制**: 明确的角色权限分离
- **事件日志**: 完整的操作记录

## 快速开始

### 环境要求

- [Foundry](https://getfoundry.sh/)
- Node.js >= 16

### 安装依赖

```bash
# 克隆项目
git clone <repository-url>
cd call_option_token

# 安装Foundry依赖
forge install
```

### 编译合约

```bash
forge build
```

### 运行测试

```bash
# 运行所有测试
forge test

# 运行详细测试
forge test -vv

# 运行特定测试
forge test --match-test testExerciseOptions
```

### 部署合约

1. 复制环境配置文件：
```bash
cp .env.example .env
```

2. 编辑 `.env` 文件，填入您的私钥和RPC URL

3. 部署到本地网络：
```bash
# 启动本地节点
anvil

# 部署合约
forge script script/Deploy.s.sol --rpc-url $LOCAL_RPC_URL --broadcast
```

4. 部署到测试网：
```bash
forge script script/Deploy.s.sol --rpc-url $SEPOLIA_RPC_URL --broadcast --verify
```

## 合约接口

### 主要函数

```solidity
// 发行期权 (仅所有者)
function issueOptions(uint256 _underlyingAmount) external payable onlyOwner

// 行权
function exercise(uint256 _optionAmount) external payable

// 过期处理 (仅所有者)
function expireOptions() external onlyOwner

// 查询期权信息
function getOptionInfo() external view returns (
    uint256 _strikePrice,
    uint256 _expirationDate,
    uint256 _totalSupply,
    uint256 _totalUnderlying,
    bool _expired,
    bool _canExercise
)

// 计算行权成本
function calculateExerciseCost(uint256 _optionAmount) external view returns (uint256)
```

### 事件

```solidity
event OptionsIssued(address indexed issuer, uint256 underlyingAmount, uint256 optionTokens);
event OptionsExercised(address indexed exerciser, uint256 optionTokens, uint256 underlyingReceived, uint256 paymentMade);
event OptionsExpired(address indexed owner, uint256 underlyingRedeemed);
```

## 使用示例

### 1. 项目方发行期权

```solidity
// 存入10 ETH，发行10个期权Token
optionToken.issueOptions{value: 10 ether}(10 ether);
```

### 2. 用户购买期权

```solidity
// 通过DEX或直接转账获得期权Token
optionToken.transfer(user, 1 ether);
```

### 3. 用户行权

```solidity
// 在行权期内，支付行权价格行权
uint256 cost = optionToken.calculateExerciseCost(1 ether);
optionToken.exercise{value: cost}(1 ether);
```

### 4. 项目方处理过期期权

```solidity
// 过期后赎回剩余资产
optionToken.expireOptions();
```

## 测试覆盖

项目包含全面的测试用例，覆盖：

- ✅ 合约部署和初始化
- ✅ 期权发行功能
- ✅ 期权转账和交易
- ✅ 期权行权机制
- ✅ 过期处理逻辑
- ✅ 权限控制
- ✅ 边界条件和错误处理
- ✅ 完整的期权生命周期

## 安全考虑

- **重入攻击防护**: 使用OpenZeppelin的ReentrancyGuard
- **权限控制**: 明确的所有者权限管理
- **时间锁定**: 严格的行权时间窗口控制
- **溢出保护**: Solidity 0.8+内置溢出检查
- **紧急提取**: 提供紧急情况下的资产提取功能

## 项目结构

```
├── src/
│   └── CallOptionToken.sol      # 主合约
├── test/
│   └── CallOptionToken.t.sol    # 测试文件
├── script/
│   └── Deploy.s.sol             # 部署脚本
├── lib/                         # 依赖库
├── foundry.toml                 # Foundry配置
└── README.md                    # 项目文档
```

## 许可证

MIT License

## 贡献

欢迎提交Issue和Pull Request来改进项目。

## 免责声明

本项目仅用于学习和理解期权机制，不构成投资建议。在生产环境中使用前，请进行充分的安全审计。
