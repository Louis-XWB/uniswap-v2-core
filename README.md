## Uniswap 系列汇总

[uniswap-v1](https://github.com/Louis-XWB/Uniswap-v1/)

[uniswap-v2-core](https://github.com/Louis-XWB/uniswap-v2-core)

[uniswap-v2-periphery](https://github.com/Louis-XWB/uniswap-v2-periphery)


# Uniswap-v2 源码学习

## Intro

Uniswap V1 是这个协议在 2018 年推出的第一个主要版本，而 V2 则是其后续在 2020 推出的升级版本。这个版本引入了一系列重大改进和新特性，包括 ERC-20 到 ERC-20 的直接交换、价格预言机、闪电贷等，以及其他优化升级。


1) **ERC-20 之间的直接交换**

    Uniswap V1 的每一对 ERC-20 代币都需要 ETH 作为中介。如果你想直接进行两种 ERC-20 代币的交换，你必须先将一种代币换成 ETH，然后再用 ETH 去换另一种代币。

    Uniswap V2 允许直接交换任何两种 ERC-20 代币，不再需要 ETH 作为中介。

2) **价格预言机**

    Uniswap V2 引入了价格预言机功能。每当一个新的交易被确认，合约就会为那个特定时间点的代币对价格做一个累积记录。这种方法允许其他智能合约在需要获取一个资产的平均价格时，根据这些价格记录来计算平均价格，这可以用来防止价格操控。
    
    --- 
    具体实现：[价格预言机的实现原理](#FAQ)

3) **闪电贷 (Flash Swaps)**

    Uniswap V2 引入了闪电贷款，用户可以几乎不付费地借出任何数量的 ERC-20 代币，只要在同一笔交易中能还清。这允许用户进行复杂的交易，比如套利、抵押物清算和自动市场制造等。

4) **费用灵活性**

    在 V1 中，交易费用是固定的0.3%，在 V2 中，这个费率依然存在，但协议为将来可能的费用变更留出了空间，如为开发团队提供费用分成的可能性。

5) **资金池的创建**

    在 V1 中，创建新资金池需要调用工厂合约并部署一个新的交易对合约。V2 通过使用一个单一的智能合约来处理所有资金池，使得资金池的创建更为高效。

## Code Learning

V2 的代码分为两个仓库，一个是 [uniswap-v2-core](https://github.com/Louis-XWB/uniswap-v2-core)，另一个是 [uniswap-v2-periphery](https://github.com/Louis-XWB/uniswap-v2-periphery)。

* `uniswap-v2-core` : Uniswap V2 的核心代码，包括 Uniswap V2 的核心合约、工厂合约、路由合约等。
* `uniswap-v2-periphery` : Uniswap V2 的外围代码，包括 Uniswap V2 的接口、帮助函数、测试代码等。

### uniswap-v2-core

专注于处理 LP(Liquidity Provider) 的创建和管理，手续费设定，以及代币的铸造(`mint`)、销毁(`burn`)和交换(`swap`)等核心功能，不涉及数据转换等额外操作。

* [UniswapV2ERC20.sol](https://github.com/Louis-XWB/uniswap-v2-core/blob/master/contracts/UniswapV2ERC20.sol) - ERC20 合约，实现 ERC20 标准方法

* [UniswapV2Factory.sol](https://github.com/Louis-XWB/uniswap-v2-core/blob/master/contracts/UniswapV2Factory.sol) - 工厂合约，用于创建新的 Pair 合约（以及设置协议手续费接收地址）

* [UniswapV2Pair.sol](https://github.com/Louis-XWB/uniswap-v2-core/blob/master/contracts/UniswapV2Pair.sol) - Pair（交易对）合约，定义和交易有关的几个最基础方法，如 swap/mint/burn，价格预言机等功能，其本身是一个 ERC20 合约，继承 `UniswapV2ERC20`

## FAQ
1) 价格预言机的实现原理

    在 Uniswap V2 中，价格预言机的工作原理与其他类型的价格预言机有所不同。Uniswap V2 通过一种叫做“时间加权平均价格”（TWAP）的机制来实现其预言机功能：

    * 每次交易发生时，Uniswap V2 的智能合约会记录下当前累积价格，以及这个价格变化的时间戳。
    * 这个累积价格是基于流动性池中资产的当前比例，通过一个数学公式计算得出的价格。
    * 累积价格会随着每次交易而变化，这样就可以创建一个价格随时间变化的历史记录。
    * 任何人都可以通过 Uniswap V2 的智能合约来查询这些价格记录。
    * 当需要获取一个资产的平均价格时，智能合约会查看这个累积价格在过去一段时间内的变化，然后计算出一个平均值。
    * 这个平均值就是这段时间内的平均价格，也就是 TWAP。
    * 通过这种方法，Uniswap V2 的智能合约可以计算出任何两种 ERC-20 代币的 TWAP。
  
    这种方法的好处是，它提供了一种防止价格操纵的机制。因为要操纵 TWAP，攻击者需要在较长的时间段内维持不真实的价格，这通常会涉及高昂的成本和风险。

    价格预言机在 DeFi 中的应用非常广泛，比如：
    * **借贷平台** ：确定抵押品的当前价值，以及是否需要进行清算。
    * **合成资产** ：实时追踪底层资产的价格，确保合成资产的准确定价。
    * **稳定币** ：维持与锚定资产（如美元）的价值稳定。


## Resources

Uniswap-v2 doc: [v2/overview](https://docs.uniswap.org/contracts/v2/overview)

Uniswap-v2 Whitepaper: [uniswap.org/whitepaper.pdf](https://docs.uniswap.org/whitepaper.pdf)
