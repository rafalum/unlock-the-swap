import {TestERC20} from "@uniswap/v4-core/contracts/test/TestERC20.sol";

contract ERC20 is TestERC20 {

    uint256 _totalSupply;

    constructor(uint256 amountToMint) TestERC20(amountToMint) {
        _totalSupply = amountToMint;
    }

    function totalSupply() external view returns (uint256) {
        return _totalSupply;
    }
}