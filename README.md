## Uniswap 系列汇总

[uniswap-v1](https://github.com/Louis-XWB/Uniswap-v1/)

[uniswap-v2-core](https://github.com/Louis-XWB/uniswap-v2-core)

[uniswap-v2-periphery](https://github.com/Louis-XWB/uniswap-v2-periphery)

[uniswap-v3-core](https://github.com/Louis-XWB/uniswap-v3-core)

[uniswap-v3-periphery](https://github.com/Louis-XWB/uniswap-v3-periphery)


# Uniswap-v2 源码学习

## Intro

Uniswap V1 是这个协议在 2018 年推出的第一个主要版本，而 V2 则是其后续在 2020 推出的升级版本。这个版本引入了一系列重大改进和新特性，包括 ERC-20 到 ERC-20 的直接交换、价格预言机、闪电贷等，以及其他优化升级。


1) **ERC-20 之间的直接交换**

    Uniswap V1 的每一对 ERC-20 代币都需要 ETH 作为中介。如果你想直接进行两种 ERC-20 代币的交换，你必须先将一种代币换成 ETH，然后再用 ETH 去换另一种代币。

    Uniswap V2 允许直接交换任何两种 ERC-20 代币，不再需要 ETH 作为中介。

2) **价格预言机**

    Uniswap V2 引入了价格预言机功能。每当一个新的交易被确认，合约就会为那个特定时间点的代币对价格做一个累积记录。这种方法允许其他用户或者智能合约在需要获取一个资产的平均价格时，可以根据这些价格记录来计算平均价格，从而防止了代币价格被轻易操控。
   
    具体实现：[价格预言机的实现原理](#FAQ)

4) **闪电贷 (Flash Swaps)**

    Uniswap V2 引入了闪电贷款，用户可以几乎不付费地借出任何数量的 ERC-20 代币，只要在同一笔交易中能还清。这允许用户进行复杂的交易，比如套利、抵押物清算和自动市场制造等。

5) **费用灵活性**

    在 V1 中，交易费用是固定的0.3%，在 V2 中，这个费率依然存在，但协议为将来可能的费用变更留出了空间，如为开发团队提供费用分成的可能性。

6) **资金池的创建**

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


2) 关于 [EIP-2612](https://eips.ethereum.org/EIPS/eip-2612) 的 permit 方法

    简单说就是，过去我们要调用一个合约的方法，需要先调用 `approve` 方法，然后再调用合约的方法。这样做的目的是为了防止合约在用户不知情的情况下，转移用户的代币。而 `permit` 方法的出现，就是为了简化这个过程，让用户可以在一次调用中完成授权，得到授权后，合约就可以直接转走用户的代币了。
    
    好处是，用户不需要再调用两次方法，而且用户可以在一次调用中完成授权，而不是两次调用。用户可以一次性签名一个授权交易，然后这个签名可以被用来在智能合约中执行多个转账操作，而无需每次都发送一个包含ETH的交易。这种方法非常适合那些需要 **批量处理** 或者想要 **节约交易费用** 的场景。

    举例一些应用场景：
    * **批量转账** ：DApps可以收集多个用户的 `permit` 签名，然后集中处理这些授权，从而为用户节省gas成本。这对于聚合器或批处理服务尤其有用。
    * **Gasless Transactions** ：用户可以在不持有ETH的情况下，通过 `permit` 签名来授权转账，这样就可以避免用户需要先购买ETH，然后再进行转账的情况。

             这里说的“使用permit进行无gas授权”，是指用户不必发送一个典型的ERC-20 approve调用来授权代币使用权，这通常需要支付两次gas（一次用于approve调用，一次用于将来的转账调用）。相反，permit函数允许用户用他们的签名一次性地进行授权，然后这个签名可以被其他人提交到区块链上，可能是在执行后续交易的同时。这意味着最终用户可以在不直接支付gas费的情况下，通过别人提交的交易，来授权他们的代币。

             这里的“无gas”是指用户不必支付gas费，而不是说这个交易不需要gas费。这个交易仍然需要gas费，但是这个gas费是由提交这个交易的人支付的，而不是由用户直接支付的。提交这个交易的可以是智能合约、DApp、或者其他代理。比如通过智能合约提交，智能合约可以使用用户提供的permit签名来获取代币使用权，然后立即执行用户指定的操作，例如交换代币或存入流动性池，智能合约会从我们的代币里扣除gas费用，而不是我们的钱包直接支付gas，达到“无gas交易”的效果。
    * **更好的交互流程**：当用户与新的DeFi平台交互时，通常需要进行多个交易（如授权、存款等）。使用 `permit` ，用户可以一次性完成多个授权，然后只需要另外一个交易就能参与交易或服务。

    * **投票委托**：用户可以通过permit签名授权其他地址代表他们行使投票权，这在去中心化自治组织（DAOs）中尤其有用。

    * **订阅模式**：用户可以签署一个长期有效的permit，允许服务商定期从他们的账户中扣款，创建一种订阅服务的模式。


3) 如何取消 `permit` 授权？

    在Uniswap V2及类似实现的ERC-20代币中， `permit` 签名授权是具有时间限制的，因为它包括一个截止日期（deadline），过了这个日期，签名就无效了。

    一旦一个 `permit` 签名被生成并使用，就不能直接“作废”或“撤销”，因为它已经被链上记录下来。然而，你可以通过以下几种方式来间接作废或覆盖 `permit` 授权：

    * **时间过期**: `permit` 函数要求包含一个deadline参数，过了这个时间戳后，签名就不再有效。

    * **使用授权的代币**: 如果授权的代币已经被花费，那么这个特定的 `permit` 签名自然就没有剩余的授权额度，从而变得无效。

    * **更改授权**: 通过调用approve函数并设置授权额度为0，你可以作废先前通过permit给出的授权。这是因为approve会更新持有人和花费者之间的授权额度，覆盖permit创建的授权状态。
        ``` solidity
        // 假设
        // token是合约的接口，
        // spender是你之前通过permit授权的地址
        token.approve(spender, 0);
        ```

    * **nonce变更**: `permit` 函数使用nonce来确保每个签名的唯一性，一旦使用了某个nonce，就不能再次使用。因此，如果你创建了一个新的 `permit` 签名（无论是否使用），只要它具有一个递增的nonce，就能确保先前的签名不能再次被用于permit。

    * **转移部分或全部代币**: 如果你转移了授权给其他人的全部或部分代币，那么根据ERC-20标准，授权额度不会自动调整。这意味着，如果转移后余额低于授权额度，那么授权实际上是部分无效的。










## Resources

Uniswap-v2 doc: [v2/overview](https://docs.uniswap.org/contracts/v2/overview)

Uniswap-v2 Whitepaper: [uniswap.org/whitepaper.pdf](https://docs.uniswap.org/whitepaper.pdf)
