pragma solidity ^0.4.13;

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
        require(assertion);
    }
}

/**
 * ERC 20 token
 *
 * https://github.com/ethereum/EIPs/issues/20
 */
contract Token {

    /// @return total amount of tokens
    function totalSupply() constant returns (uint256 supply);

    /// @param _owner The address from which the balance will be retrieved
    /// @return The balance
    function balanceOf(address _owner) constant returns (uint256 balance);

    /// @notice send `_value` token to `_to` from `msg.sender`
    /// @param _to The address of the recipient
    /// @param _value The amount of token to be transferred
    /// @return Whether the transfer was successful or not
    function transfer(address _to, uint256 _value) returns (bool success);

    /// @notice send `_value` token to `_to` from `_from` on the condition it is approved by `_from`
    /// @param _from The address of the sender
    /// @param _to The address of the recipient
    /// @param _value The amount of token to be transferred
    /// @return Whether the transfer was successful or not
    function transferFrom(address _from, address _to, uint256 _value) returns (bool success);

    /// @notice `msg.sender` approves `_addr` to spend `_value` tokens
    /// @param _spender The address of the account able to transfer the tokens
    /// @param _value The amount of wei to be approved for transfer
    /// @return Whether the approval was successful or not
    function approve(address _spender, uint256 _value) returns (bool success);

    /// @param _owner The address of the account owning tokens
    /// @param _spender The address of the account able to transfer the tokens
    /// @return Amount of remaining tokens allowed to spent
    function allowance(address _owner, address _spender) constant returns (uint256 remaining);

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

contract QvoltaToken is StandardToken, SafeMath {

    string public name = "Qvolta Token";

    string public symbol = "QVT";

    uint public decimals = 18;

    bool public halted = false; //the founder address can set this to true to halt the crowdsale due to emergency
    bool public freeze = true; //Freeze state
    bool public preIco = false; //Pre-ico state

    // Initial founder address (set in constructor)
    // All deposited ETH will be forwarded to this address.
    // Address is a multisig wallet.
    address public founder = 0x0;
    address public owner = 0x0;

    uint public bounty = 2187500; //Bounty count

    uint public preIcoCap = 17500000; //max amount raised during pre ico 17500 ether (10%)
    uint public icoCap = 175000000; //max amount raised during crowdsale 175000 ether

    uint public presaleTokenSupply = 0; //this will keep track of the token supply created during the crowdsale
    uint public presaleEtherRaised = 0; //this will keep track of the Ether raised during the crowdsale
    uint public preIcoTokenSupply = 0;//this will keep track of the token supply created during the pre-ico

    event Buy(address indexed sender, uint eth, uint fbt);

    function QvoltaToken(address _founder) {
        owner = msg.sender;
        founder = _founder;

        uint totalTokens = 218750000;
        uint team = 41562500;

        balances[founder] = team;
        totalSupply = safeSub(totalTokens, team);
        totalSupply = safeSub(totalTokens, bounty);
    }

    /**
     * Pre-ico price is 2000 Qvolta for 1 ETH
     * Regular price is 1000 Qvolta for 1 ETH
     */
    function price() constant returns (uint) {
        //pre-ico price
        if (preIco) return 2000*10^18;
        //default price
        return 1000*10^18;
    }

    /**
      * The basic entry point to participate the crowdsale process.
      *
      * Pay for funding, get invested tokens back in the sender address.
      */
    function buy() public payable {
        buyRecipient(msg.sender);
    }

    /**
     * Main token buy function.
     *
     * Buy for the sender itself or buy on the behalf of somebody else (third party address).
     */
    function buyRecipient(address recipient) payable {
        require(!halted);
        require(msg.value>0);

        // Count expected tokens price
        uint tokens = safeMul(msg.value, price());

        // Check how much tokens already sold
        if (preIco) {
            require(safeAdd(presaleTokenSupply, tokens) < preIcoCap);
        } else {
            require(safeAdd(presaleTokenSupply, tokens) < safeSub(icoCap, preIcoTokenSupply));
        }

        // Send Ether to founder address
        if (!founder.call.value(msg.value)()) {
            revert();
        }

        // Add tokens to user balance and remove from totalSupply
        balances[recipient] = safeAdd(balances[recipient], tokens);
        totalSupply = safeSub(totalSupply, tokens);

        // Update stats
        if (preIco) {
            preIcoTokenSupply  = safeAdd(preIcoTokenSupply, tokens);
        }
        presaleTokenSupply = safeAdd(presaleTokenSupply, tokens);
        presaleEtherRaised = safeAdd(presaleEtherRaised, msg.value);

        // Send buy Qvolta token action
        Buy(recipient, msg.value, tokens);
    }

    /**
     * Pre-ico state.
     */
    function setPreIco() onlyOwner() {
        preIco = true;
    }

    function unPreIco() onlyOwner() {
        preIco = false;
    }

    /**
     * Emergency Stop ICO.
     */
    function halt() onlyOwner() {
        halted = true;
    }

    function unhalt() onlyOwner() {
        halted = false;
    }

    /**
     * Freeze and unfreeze ICO.
     */
    function freeze() onlyOwner() {
        freeze = true;
    }

    function unfreeze() onlyOwner() {
        freeze = false;
    }

    /**
     * Transfer bounty
     */
    function sendBounty(address _to, uint256 _value) onlyOwner() {
        bounty = safeSub(bounty, _value);
        balances[_to] = safeAdd(balances[_to], _value);
    }

    /**
     * ERC 20 Standard Token interface transfer function
     *
     * Prevent transfers until freeze period is over.
     */
    function transfer(address _to, uint256 _value) isAvailable() returns (bool success) {
        return super.transfer(_to, _value);
    }
    /**
     * ERC 20 Standard Token interface transfer function
     *
     * Prevent transfers until freeze period is over.
     */
    function transferFrom(address _from, address _to, uint256 _value) isAvailable() returns (bool success) {
        return super.transferFrom(_from, _to, _value);
    }

    /**
     * Burn all tokens from a balance.
     */
    function burnRemainingTokens() isAvailable() onlyOwner() {
        totalSupply = 0;
    }

    modifier onlyOwner() {
        require(msg.sender == owner);
        _;
    }

    modifier isAvailable() {
        require(!halted && !freeze);
        _;
    }

    /**
     * just being sent some cash?
     */
    function() payable {

    }

    // Replaces an owner
    function changeOwner(address _to) onlyOwner() {
        owner = _to;
    }

    // Replaces an founder
    function changeFounder(address _to) onlyOwner() {
        founder = _to;
    }
}
