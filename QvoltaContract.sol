pragma solidity ^0.4.8;

/**
 * Overflow aware uint math functions.
 */
contract SafeMath {
    function safeMul(uint a, uint b) internal returns (uint) {
        uint c = a * b;
        assert(a == 0 || c / a == b);
        return c;
    }

    function safeSub(uint a, uint b) internal returns (uint) {
        assert(b <= a);
        return a - b;
    }

    function safeAdd(uint a, uint b) internal returns (uint) {
        uint c = a + b;
        assert(c >= a && c >= b);
        return c;
    }

    function assert(bool assertion) internal {
        if (!assertion) throw;
    }
}

/**
 * ERC 20 token
 *
 * https://github.com/ethereum/EIPs/issues/20
 */
contract Token {

    /// @return total amount of tokens
    function totalSupply() constant returns (uint256 supply) {}

    /// @param _owner The address from which the balance will be retrieved
    /// @return The balance
    function balanceOf(address _owner) constant returns (uint256 balance) {}

    /// @notice send `_value` token to `_to` from `msg.sender`
    /// @param _to The address of the recipient
    /// @param _value The amount of token to be transferred
    /// @return Whether the transfer was successful or not
    function transfer(address _to, uint256 _value) returns (bool success) {}

    /// @notice send `_value` token to `_to` from `_from` on the condition it is approved by `_from`
    /// @param _from The address of the sender
    /// @param _to The address of the recipient
    /// @param _value The amount of token to be transferred
    /// @return Whether the transfer was successful or not
    function transferFrom(address _from, address _to, uint256 _value) returns (bool success) {}

    /// @notice `msg.sender` approves `_addr` to spend `_value` tokens
    /// @param _spender The address of the account able to transfer the tokens
    /// @param _value The amount of wei to be approved for transfer
    /// @return Whether the approval was successful or not
    function approve(address _spender, uint256 _value) returns (bool success) {}

    /// @param _owner The address of the account owning tokens
    /// @param _spender The address of the account able to transfer the tokens
    /// @return Amount of remaining tokens allowed to spent
    function allowance(address _owner, address _spender) constant returns (uint256 remaining) {}

    event Transfer(address indexed _from, address indexed _to, uint256 _value);

    event Approval(address indexed _owner, address indexed _spender, uint256 _value);

}

/**
 * ERC 20 token
 *
 * https://github.com/ethereum/EIPs/issues/20
 */
contract StandardToken is Token {

    /**
     * Reviewed:
     * - Interger overflow = OK, checked
     */
    function transfer(address _to, uint256 _value) returns (bool success) {
        //Default assumes totalSupply can't be over max (2^256 - 1).
        //If your token leaves out totalSupply and can issue more tokens as time goes on, you need to check if it doesn't wrap.
        //Replace the if with this one instead.
        if (balances[msg.sender] >= _value && balances[_to] + _value > balances[_to]) {
            //if (balances[msg.sender] >= _value && _value > 0) {
            balances[msg.sender] -= _value;
            balances[_to] += _value;
            Transfer(msg.sender, _to, _value);
            return true;
        }
        else {return false;}
    }

    function transferFrom(address _from, address _to, uint256 _value) returns (bool success) {
        //same as above. Replace this line with the following if you want to protect against wrapping uints.
        if (balances[_from] >= _value && allowed[_from][msg.sender] >= _value && balances[_to] + _value > balances[_to]) {
            //if (balances[_from] >= _value && allowed[_from][msg.sender] >= _value && _value > 0) {
            balances[_to] += _value;
            balances[_from] -= _value;
            allowed[_from][msg.sender] -= _value;
            Transfer(_from, _to, _value);
            return true;
        }
        else {return false;}
    }

    function balanceOf(address _owner) constant returns (uint256 balance) {
        return balances[_owner];
    }

    function approve(address _spender, uint256 _value) returns (bool success) {
        allowed[msg.sender][_spender] = _value;
        Approval(msg.sender, _spender, _value);
        return true;
    }

    function allowance(address _owner, address _spender) constant returns (uint256 remaining) {
        return allowed[_owner][_spender];
    }

    mapping (address => uint256) balances;

    mapping (address => mapping (address => uint256)) allowed;

    uint256 public totalSupply;

}

contract BurnableToken is StandardToken, SafeMath {

    address public constant BURN_ADDRESS = 0;

    /** How many tokens we burned */
    event Burned(address burner, uint burnedAmount);

    /**
     * Burn extra tokens from a balance.
     */
    function burn(uint burnAmount) {
        address burner = msg.sender;
        balances[burner] = safeSub(balances[burner], burnAmount);
        totalSupply = safeSub(totalSupply, burnAmount);
        Burned(burner, burnAmount);
    }
}

contract QvoltaToken is BurnableToken {

    string public name = "Qvolta Token";

    string public symbol = "QVT";

    uint public decimals = 18;

    uint public totalSupply = 218750000;

    uint public startBlock; // pre-ico start block (set in constructor)
    uint public preIcoEndBlock; // pre-ico end - start block + 5 days
    uint public endBlock; // ico end block (set in constructor)

    // Initial founder address (set in constructor)
    // All deposited ETH will be instantly forwarded to this address.
    // Address is a multisig wallet.
    address public founder = 0x0;

    uint public preIcoEtherCap = 17500; //max amount raised during pre ico 17500 ether (10%)
    uint public etherCap = 175000; //max amount raised during crowdsale 175000 ether

    uint public presaleTokenSupply = 0; //this will keep track of the token supply created during the ico
    uint public presaleEtherRaised = 0; //this will keep track of the Ether raised during the crowdsale
    uint public preIcoTokenSupply = 0; //this will keep track of the token supply sold during the pre-ico

    bool public halted = false; //the founder address can set this to true to halt the crowdsale due to emergency
    bool public freeze = true; //Freeze state
    event Buy(address indexed sender, uint eth, uint fbt);

    event Withdraw(address indexed sender, address to, uint eth);

    function QvoltaToken(address founderInput, uint startBlockInput, uint endBlockInput) {
        founder = founderInput;
        startBlock = startBlockInput;
        endBlock = endBlockInput;
        // Time in start block bonus is 5 days
        preIcoEndBlock = startBlock + 5 days;
    }

    function price() constant returns (uint) {
        //pre-ico price
        if (block.number >= startBlock && block.number < preIcoEndBlock) return 2000;
        //default price
        return 1000;
    }

    // Buy entry point
    function buy(uint8 v, bytes32 r, bytes32 s) {
        buyRecipient(msg.sender, v, r, s);
    }

    /**
     * Main token buy function.
     *
     * Buy for the sender itself or buy on the behalf of somebody else (third party address).
     */
    function buyRecipient(address recipient, uint8 v, bytes32 r, bytes32 s) {
        bytes32 hash = sha256(msg.sender);

        if (block.number > startBlock && block.number < preIcoEndBlock && safeAdd(presaleEtherRaised, msg.value) > preIcoEtherCap) throw;
        if (block.number < startBlock || block.number > endBlock || safeAdd(presaleEtherRaised, msg.value) > (etherCap - safeMul(preIcoTokenSupply, price())) || halted) throw;

        uint tokens = safeMul(msg.value, price());
        totalSupply = totalSupply - tokens;

        balances[recipient] = safeAdd(balances[recipient], tokens);
        presaleTokenSupply = safeAdd(presaleTokenSupply, tokens);
        presaleEtherRaised = safeAdd(presaleEtherRaised, msg.value);

        if (block.number >= startBlock && block.number < preIcoEndBlock) {
            preIcoTokenSupply = safeAdd(preIcoTokenSupply, tokens);
        }

        if (!founder.call.value(msg.value)()) throw;

        //immediately send Ether to founder address
        Buy(recipient, msg.value, tokens);
    }

    /**
     * Emergency Stop ICO.
     */
    function halt() {
        if (msg.sender != founder) throw;
        halted = true;
    }

    function unhalt() {
        if (msg.sender != founder) throw;
        halted = false;
    }

    /**
     * Freeze and unfreeze ICO.
     */
    function setFreeze() {
        if (msg.sender != founder) throw;
        freeze = true;
    }

    function unfreeze() {
        if (msg.sender != founder) throw;
        freeze = false;
    }

    /**
     * ERC 20 Standard Token interface transfer function
     *
     * Prevent transfers until freeze period is over.
     */
    function transfer(address _to, uint256 _value) returns (bool success) {
        if (freeze && msg.sender != founder) throw;
        return super.transfer(_to, _value);
    }
    /**
     * ERC 20 Standard Token interface transfer function
     *
     * Prevent transfers until freeze period is over.
     */
    function transferFrom(address _from, address _to, uint256 _value) returns (bool success) {
        if (freeze && msg.sender != founder) throw;
        return super.transferFrom(_from, _to, _value);
    }

    /**
     * Burn all tokens from a balance.
     *
     */
    function burn(uint burnAmount) {
        address burner = msg.sender;
        balances[burner] = safeSub(balances[burner], burnAmount);
        totalSupply = safeSub(totalSupply, burnAmount);
        Burned(burner, burnAmount);
    }

    /**
     * Do not allow direct deposits.
     */
    function() {
        throw;
    }
}
