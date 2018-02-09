pragma solidity ^0.4.18;

/**
 * @title SafeMath
 * @dev Math operations with safety checks that throw on error
 */
library SafeMath {
  function mul(uint256 a, uint256 b) internal pure returns (uint256) {
    if (a == 0) {
      return 0;
    }
    uint256 c = a * b;
    assert(c / a == b);
    return c;
  }

  function div(uint256 a, uint256 b) internal pure returns (uint256) {
    // assert(b > 0); // Solidity automatically throws when dividing by 0
    uint256 c = a / b;
    // assert(a == b * c + a % b); // There is no case in which this doesn't hold
    return c;
  }

  function sub(uint256 a, uint256 b) internal pure returns (uint256) {
    assert(b <= a);
    return a - b;
  }

  function add(uint256 a, uint256 b) internal pure returns (uint256) {
    uint256 c = a + b;
    assert(c >= a);
    return c;
  }
}



/**
 * @title Ownable
 * @dev The Ownable contract has an owner address, and provides basic authorization control
 * functions, this simplifies the implementation of "user permissions".
 */
contract Ownable {
  address public owner;


  event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);


  /**
   * @dev The Ownable constructor sets the original `owner` of the contract to the sender
   * account.
   */
  function Ownable() public {
    owner = msg.sender;
  }


  /**
   * @dev Throws if called by any account other than the owner.
   */
  modifier onlyOwner() {
    require(msg.sender == owner);
    _;
  }


  /**
   * @dev Allows the current owner to transfer control of the contract to a newOwner.
   * @param newOwner The address to transfer ownership to.
   */
  function transferOwnership(address newOwner) public onlyOwner {
    require(newOwner != address(0));
    OwnershipTransferred(owner, newOwner);
    owner = newOwner;
  }

}

interface Token {
    
    function transfer(address _to, uint256 _amount) public returns (bool success);
    function balanceOf(address _owner) public view returns (uint256 balance);
    function decimals()public view returns (uint8);
}

/**
 * @title Crowdsale
 * @dev Crowdsale is a base contract for managing a token crowdsale.
 * Crowdsales have a end timestamps, where investors can make
 * token purchases and the crowdsale will assign them tokens based
 * on a token per ETH rate. Funds collected are forwarded to a wallet
 * as they arrive.
 */
contract Crowdsale {
  using SafeMath for uint256;

  // The token being sold
  Token public token;

  // end timestamps where investments are allowed (both inclusive)
  uint256 public endTime;


   // Number of tokens per ether
  uint256 public rate = 10000;
  
  //Duration of ICO in minutes.Set to 30 days
  uint256 durationInMinutes = 43200;
  
  // amount of raised money in wei
  uint256 public weiRaised;
 
  //To check whether the contract has been powered up
  bool contractPoweredUp = false;
  
  /**
   * event for token purchase logging
   * @param purchaser who paid for the tokens
   * @param beneficiary who got the tokens
   * @param value weis paid for purchase
   * @param amount amount of tokens purchased
   */
  event TokenPurchase(address indexed purchaser, address indexed beneficiary, uint256 value, uint256 amount);


//modifiers    
   
  
     modifier nonZeroAddress(address _to) {
        require(_to != 0x0);
        _;
    }
    
    modifier nonZeroEth() {
        require(msg.value > 0);
        _;
    }

  function Crowdsale(address _tokenToBeUsed) public nonZeroAddress(_tokenToBeUsed) {
    token = Token(_tokenToBeUsed);
  }

  // fallback function can be used to buy tokens
  function () external payable {
    buyTokens(msg.sender);
  }

  // low level token purchase function
  function buyTokens(address beneficiary) public payable nonZeroAddress(beneficiary) {
    require(validPurchase());

    uint256 weiAmount = msg.value;
    

    // calculate token amount to be created
    uint256 tokenUnits = weiAmount.mul(rate);

    // update state
    weiRaised = weiRaised.add(weiAmount);

    forwardFunds();
    require(token.transfer(beneficiary, tokenUnits));
    TokenPurchase(msg.sender, beneficiary, weiAmount, tokenUnits);

  }

  // send ether to the fund collection wallet
  // override to create custom fund forwarding mechanisms
  function forwardFunds() internal ;


  
  // @return true if crowdsale event has ended
  function hasEnded() public view returns (bool) {
      
    //Sale must have started before it has ended
    require(contractPoweredUp);  
    
    return now > endTime;
  }

 function validPurchase() internal view returns (bool);

}

/**
 * @title RefundVault
 * @dev This contract is used for storing funds while a crowdsale
 * is in progress. Supports refunding the money if crowdsale fails,
 * and forwarding it if crowdsale is successful.
 */
contract RefundVault is Ownable {
  using SafeMath for uint256;

  enum State { Active, Refunding, Closed }

  mapping (address => uint256) public deposited;
  address public wallet;
  State public state;

  event Closed();
  event RefundsEnabled();
  event Refunded(address indexed beneficiary, uint256 weiAmount);

  function RefundVault(address _wallet) public {
    require(_wallet != address(0));
    wallet = _wallet;
    state = State.Active;
  }

  function deposit(address investor) onlyOwner public payable {
    require(state == State.Active);
    deposited[investor] = deposited[investor].add(msg.value);
  }

  function close() onlyOwner public {
    require(state == State.Active);
    state = State.Closed;
    Closed();
  }
  function withdrawToWallet() onlyOwner public{
    require(state == State.Closed);
    wallet.transfer(this.balance);
  }

  function enableRefunds() onlyOwner public {
    require(state == State.Active);
    state = State.Refunding;
    RefundsEnabled();
  }

  function refund(address investor) public {
    require(state == State.Refunding);
    uint256 depositedValue = deposited[investor];
    deposited[investor] = 0;
    investor.transfer(depositedValue);
    Refunded(investor, depositedValue);
  }
}


/**
 * @title FinalizableCrowdsale
 * @dev Extension of Crowdsale where an owner can do extra work
 * after finishing.
 */
contract FinalizableCrowdsale is Crowdsale, Ownable {
  using SafeMath for uint256;

  bool public isFinalized = false;
  
  

  event Finalized();
  
  function FinalizableCrowdsale(address _tokenToBeUsed) Crowdsale( _tokenToBeUsed) public{
      
  }

  /**
   * @dev Must be called after crowdsale ends, to do some extra finalization
   * work. Calls the contract's finalization function.
   */
  function finalize() onlyOwner public {
    require(!isFinalized);
    require(hasEnded());

    finalization();
    Finalized();

    isFinalized = true;
  }

  /**
   * @dev Can be overridden to add finalization logic. The overriding function
   * should call super.finalization() to ensure the chain of finalization is
   * executed entirely.
   */
  function finalization() internal ;
}


/**
 * @title RefundableCrowdsale
 * @dev Extension of Crowdsale contract that adds a funding goal, and
 * the possibility of users getting a refund if goal is not met.
 * Uses a RefundVault as the crowdsale's vault.
 */
contract CROCCrowdsale is FinalizableCrowdsale {
  using SafeMath for uint256;

  //tokens available for ICO
  uint256 public tokensAvailableToIco = 84000000000000000000000000;
  

  // refund vault used to hold funds while crowdsale is running
  RefundVault public vault;
  

  
  
  // minimum amount of funds to be raised in weis
  uint256 public softCap = 2000 ether;
  
  //hard cap for the ICO
  uint256 public hardCap = 8400 ether;
  
    
  //Max contribution each whitelisted address can make. Defaults to 5 ether
  uint256 public maxContributionPerAddress = 5 ether;
  
  //Whiteslisted address- Only these addresses will be able to buy tokens
  mapping(address=>bool) public whiteListedAddresses;

  //event to notify about the change in rate
  event RateChanged(uint256 _rate);
      
  //max contribution change event
  event MaxContributionChanged(uint256 _mxContri);
  
  function CROCCrowdsale( address _wallet, address _tokenToBeUsed) FinalizableCrowdsale( _tokenToBeUsed) public nonZeroAddress(_wallet){
   
    vault = new RefundVault(_wallet);
    
  }
  
   modifier _isFinalized() {
       
    require(isFinalized);
        _;
  }
    
  /**
  *@dev To power up the contract
  * This will start the sale
  * This will set the end time of the sale
  * It will also check whether the contract has required number of tokens assigned to it or not
  */
  function powerUpContract()public onlyOwner{
     require(!contractPoweredUp);
      
    // Contract should have enough CROC credits
    require(token.balanceOf(this) >= hardCap);
    
    endTime = now + durationInMinutes * 1 minutes;
    
    contractPoweredUp = true;
  }
  
   /**
  *@dev Since the sale contract will own some tokens. This method will allows contract owner to transfer all
  * of the tokens assigned to this contract to other address, in case it is required. Can only be done once sale has ended
  * @param _to The receiver address
  * @param amount Amount of tokens to send
  */
  function transferToken(address _to, uint256 amount)public onlyOwner nonZeroAddress(_to) {
      
    require(hasEnded());
    token.transfer(_to, amount);  
  }

 //Convinience method to set rate
  function setRate(uint256 _rate)public onlyOwner{
      require(_rate>0);
      rate = _rate;
      RateChanged(rate);
  }
  /**
  *@dev To allow owner to add address in the whitelist
  *@param address Address to be added in the white list
  */
  function addToWhiteList(address _receiver)public onlyOwner nonZeroAddress(_receiver){
      require(whiteListedAddresses[_receiver]==false);
      whiteListedAddresses[_receiver] = true;
  }
  
  /**
  *@dev To allow owner to remove address from the whitelist
  *@param address Address to be removed in the white list
  */
  function removeFromWhiteList(address _receiver)public onlyOwner nonZeroAddress(_receiver) {
      require(whiteListedAddresses[_receiver]==true);
      whiteListedAddresses[_receiver] = false;
  }
  
  /**
  *@dev To change maximum contribution allowed per address
  *@param _maxContri the maximum contribution each address can do
  */
  function setMaxContribution(uint256 _maxContri)public onlyOwner{
      require(_maxContri>0);
      maxContributionPerAddress = _maxContri * 1 ether;
      MaxContributionChanged(maxContributionPerAddress);
      
  }
  
  // We're overriding the fund forwarding from Crowdsale.
  // In addition to sending the funds, we want to call
  // the RefundVault deposit function
  function forwardFunds() internal {
    vault.deposit.value(msg.value)(msg.sender);
  }

  // if crowdsale is unsuccessful, investors can claim refunds here
  function claimRefund() public {
    require(isFinalized);
    require(!goalReached());

    vault.refund(msg.sender);
  }
  
  //if crowdsales is successful, the money rasied should be transferred to the wallet address
  function withdrawFunds() public onlyOwner{
      require(isFinalized);
      require(goalReached());
      
      vault.withdrawToWallet();
  }

  // vault finalization task, called when owner calls finalize()
  function finalization() internal {
    if (goalReached()) {
      vault.close();
    } else {
      vault.enableRefunds();
    }

  }
 
 // @return true if the transaction can buy tokens
  function validPurchase() internal view returns (bool) {
      
    //To check whether sale has ended or not  
    require(!hasEnded());
    
    //Minimum contribution allowed is 0.1 ether
    require(msg.value>= 0.1 ether);
    
    //To check the address is whitelisted
    require(whiteListedAddresses[msg.sender]==true);
    
    //To check address has not made the max contribution
    require(vault.deposited(msg.sender).add(msg.value) <= maxContributionPerAddress);
    

    //Hard cap should not be breached after this sale
    require(weiRaised.add(msg.value)<=hardCap);
    
    return true;
  }

  function goalReached() public view returns (bool) {
    return weiRaised >= softCap;
  }

}
