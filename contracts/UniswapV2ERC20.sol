pragma solidity =0.5.16;

import './interfaces/IUniswapV2ERC20.sol';
import './libraries/SafeMath.sol';

contract UniswapV2ERC20 is IUniswapV2ERC20 {

    // 使用SafeMath库来防止uint类型的溢出
    using SafeMath for uint;

    // ERC20代币的基础属性
    string public constant name = 'Uniswap V2';// 代币名称
    string public constant symbol = 'UNI-V2'; // 代币符号
    uint8 public constant decimals = 18; // 代币精度
    uint  public totalSupply; // 代币总量
    mapping(address => uint) public balanceOf; // 每个地址对应的代币余额
    mapping(address => mapping(address => uint)) public allowance; // 每个地址对其他地址的代币授权余额

    // 是用于不同DApp之间区分相同结构和内容的签名消息，该值有助于用户辨识哪些为信任的DApp
    // 当用户想要授权一个操作（比如在不发送交易的情况下允许代币的花费）时，他们会在他们的钱包软件中对一条消息进行签名。
    // 这条消息包含了他们想要授权的信息，以及DOMAIN_SEPARATOR。当他们的签名被提交到合约时，
    // 合约会使用DOMAIN_SEPARATOR来确认签名的有效性，并确保它是为该合约实例和当前链上的行动创建的。
    bytes32 public DOMAIN_SEPARATOR;

    // 用于keccak256方法的参数
    // keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");
    bytes32 public constant PERMIT_TYPEHASH = 0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9;

    // 用于记录合约中每个地址使用链下签名消息的交易数量，防止重放攻击
    mapping(address => uint) public nonces;

    // Approval和Transfer两个事件，用于在交易和授权发生时触发
    event Approval(address indexed owner, address indexed spender, uint value);
    event Transfer(address indexed from, address indexed to, uint value);

    constructor() public {
        uint chainId;
        assembly {
            // 内联汇编获取当前链的ID
            chainId := chainid
        }
        
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256('EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)'),
                keccak256(bytes(name)),
                keccak256(bytes('1')),
                chainId,// 当前链的ID，确保签名是对特定链有效，防止在多条链上重放攻击
                address(this) // 合约本身的地址，用于验证签名是为这个特定合约创建的
            )
        );
    }

    // 内部函数_mint，增加代币供应量并调整指定地址的代币余额
    // 增发新的流动性给接收者
    // 用于用户提供流动性时(提供一定比例的两种ERC-20代币)增加流动性代币给流动性提供者
    function _mint(address to, uint value) internal {
        totalSupply = totalSupply.add(value);
        balanceOf[to] = balanceOf[to].add(value);
        emit Transfer(address(0), to, value);
    }

    // 内部函数_burn，减少代币供应量并调整指定地址的余额
    // 用于燃烧流动性代币来提取相应的两种资产，并减少交易对的流动性
    function _burn(address from, uint value) internal {
        balanceOf[from] = balanceOf[from].sub(value);
        totalSupply = totalSupply.sub(value);
        emit Transfer(from, address(0), value);
    }

    // 私有函数_approve，设置指定地址的授权余额
    function _approve(address owner, address spender, uint value) private {
        allowance[owner][spender] = value;
        emit Approval(owner, spender, value);
    }

    // 私有函数_transfer，实现代币的转移
    function _transfer(address from, address to, uint value) private {
        balanceOf[from] = balanceOf[from].sub(value);
        balanceOf[to] = balanceOf[to].add(value);
        emit Transfer(from, to, value);
    }

    // 公共函数approve，允许外部调用来设置授权余额
    function approve(address spender, uint value) external returns (bool) {
        _approve(msg.sender, spender, value);
        return true;
    }

    // 公共函数transfer，允许外部调用来转移代币
    function transfer(address to, uint value) external returns (bool) {
        _transfer(msg.sender, to, value);
        return true;
    }

    // 公共函数transferFrom，允许外部调用来从一个地址转移到另一个地址，前提是有足够的授权余额
    function transferFrom(address from, address to, uint value) external returns (bool) {
        if (allowance[from][msg.sender] != uint(-1)) {// 如果授权余额不是无限的
            allowance[from][msg.sender] = allowance[from][msg.sender].sub(value); // 减少授权余额
        }
        _transfer(from, to, value);// 调用内部函数_transfer
        return true;
    }

    // permit 方法实现的就是白皮书 2.5 节中介绍的“Meta transactions for pool shares 元交易”功能。
    // EIP-712 定义了离线签名的规范，即 digest 的格式定义：
    // 用户签名的内容是其（owner）授权（approve）某个合约（spender）可以在截止时间（deadline）之前花掉一定数量（value）的代币（Pair 流动性代币），
    // 应用（periphery 合约）拿着签名的原始信息和签名后生成的 v, r, s，
    // 可以调用 Pair 合约的 permit 方法获得授权，permit 方法使用 ecrecover 还原出签名地址为代币所有人，验证通过则批准授权。
    // 每个具体实现逻辑在 UniswapV2Pair 中。Pair 合约主要实现了三个方法：mint（添加流动性）、burn（移除流动性）、swap（兑换）。

    
    // 公共函数permit，允许通过签名来进行授权，而不需要实际发送交易，增加用户体验
    // abi.encodePacked 将输入的参数根据其所需最低空间编码，类似abi.encode，但是会把其中填充的很多0给省略。
    // 当我们想要省略空间，且不与合约进行交互，可以使用abi.encodePacked、。例如：算一些数据的hash可以使用。
    // keccak256 算法是在以太坊中计算公钥的256位哈希，再截取这256位哈希的后160位哈希作为地址值。是哈希函数其中一种
    function permit(address owner, address spender, uint value, uint deadline, uint8 v, bytes32 r, bytes32 s) external {
        require(deadline >= block.timestamp, 'UniswapV2: EXPIRED');// 确保签名没有过期
        // 通过keccak256方法来计算签名消息的哈希值
        bytes32 digest = keccak256(
            abi.encodePacked(
                '\x19\x01', // 用于区分链下签名消息的前缀
                DOMAIN_SEPARATOR,
                // 通过abi.encode方法来计算签名消息的哈希值
                keccak256(abi.encode(PERMIT_TYPEHASH, owner, spender, value, nonces[owner]++, deadline))
            )
        );

        // 使用ecrecover恢复签名者地址
        address recoveredAddress = ecrecover(digest, v, r, s);
        // 验证签名消息的发送者是否为owner
        require(recoveredAddress != address(0) && recoveredAddress == owner, 'UniswapV2: INVALID_SIGNATURE');

        // 如果签名验证通过，则调用_approve方法来设置授权余额
        _approve(owner, spender, value);
    }
    
    // permit函数主要实现了用户验证与授权，Uniswap V2的core函数虽然功能完善，
    // 但是对于用户来说却极不友好，用户需要借助它的周边合约才能和核心合约进行交互，
    // 但是在设计到流动性供给是，比如减少用户流动性，此时用户需要将自己的流动性代币燃烧掉，
    // 而由于用户调用的是周边合约，所以在未经授权的情况下是无法进行燃烧操作的，此时如果安装常规操作，
    // 那么用户需要先调用交易对合约对周边合约进行授权，之后再调用周边合约进行燃烧操作，
    // 而这个过程形成了两个不同合约的两个交易(无法合并到一个交易中)。
    // --- 
    // 如果我们通过线下消息签名，则可以减少其中一个交易，将所有操作放在一个交易里执行，确保了交易的原子性，
    // 在周边合约里，减小流动性来提取资产时，周边合约在一个函数内先调用交易对的permit函数进行授权，
    // 接着再进行转移流动性代币到交易对合约，提取代币等操作，所有操作都在周边合约的同一个函数中进行，
    // 达成了交易的原子性和对用户的友好性。
}
