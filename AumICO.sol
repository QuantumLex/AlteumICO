pragma solidity ^0.4.18;

/**************************************************************
*
* Alteum ICO
* Author: Lex Garza 
* by ALTEUM / Copanga
*
**************************************************************/

import "./usingOraclize.sol"; // For testing on a local node
//import "github.com/oraclize/ethereum-api/oraclizeAPI.sol";

interface token
{
	function sendCoin(address receiver, uint amount) public returns(bool sufficient);
	function getBalance(address addr) public view returns(uint);
}

/*
* Safe Math Library from Zeppelin Solidity
* https://github.com/OpenZeppelin/zeppelin-solidity/blob/master/contracts/math/SafeMath.sol
*/
contract SafeMath
{
    function safeAdd(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        assert(c >= a);
        return c;
      }
    
	function safeSub(uint256 a, uint256 b) internal pure returns (uint256) {
		assert(b <= a);
		return a - b;
	}
	
	function safeDiv(uint256 a, uint256 b) internal pure returns (uint256) {
		uint256 c = a / b;
		return c;
	}
	
	function safeMul(uint256 a, uint256 b) internal pure returns (uint256) {
		if (a == 0) {
			return 0;
		}
		uint256 c = a * b;
		assert(c / a == b);
		return c;
	}
}

contract AumICO is usingOraclize, SafeMath {
	//uint public tokenPricePreSale = 35; //Price x100 (with no cents: $0.35 => 35)
	//uint public tokenPricePreICO = 55; //Price x100 (with no cents: $0.55 => 55)
	//uint public tokenPriceICO = 75; //Price x100 (with no cents: $0.75 => 75)
	//uint totalAvailableTokens = 31875000; // 37,500,000 AUM's available for sale, minus 5,625,000 sold in presale 
	
	struct OperationInQueue
	{
		uint operationStartTime;
		uint depositedEther;
		address receiver;
		bool closed;
	}
	
	struct Contact
	{
		uint obtainedTokens;
		uint depositedEther;
		bool isOnWhitelist;
		bool userExists;
	}
	
	uint[3] public tokenPrice;
	uint[3] public availableTokens;
	uint public tokenCurrentStage;
	bool public hasICOFinished;
	
	uint public etherPrice; //Price x100 (with no cents: $800.55 => 80055)
	uint public etherInContract;
	
	uint public startEpochTimestamp = 1518487231; // Testing
	//uint public startEpochTimestamp = 1518807600; // Friday February 16th 2018 at 12pm GMT-06:00, you can verify the epoch at https://www.epochconverter.com/
	uint public endEpochTimestamp = 1521093600; // Thursday March 15th 2018 at 12am GMT-06:00, you can verify the epoch at https://www.epochconverter.com/
	
	uint public lastPriceCheck = 0;
	
	uint preICOAvailableTokens = 11250000; // 11,250,000 AUM's for the pre ICO, with 8 decimals
	uint ICOAvailableTokens = 20625000; // 20,625,000 AUM's for the pre ICO, with 8 decimals
	
	uint minAmmountToInvest = 100000000000000000; // 0.1 Ether, or 100,000,000,000,000,000 wei
	uint maxAmmountToInvest = 500000000000000000000; // 500 Ether, or 500,000,000,000,000,000,000 wei
	
	address tokenContractAddress;
	address admin;
	mapping(address => Contact) public allContacts;
	address[] public contactsAddresses;
	
	token public tokenReward;
	
	OperationInQueue[] public operationsInQueue;
	uint public currentOperation;
	
	modifier onlyAdmin()
	{
	    require(msg.sender == admin);
	    _;
	}
	
	event Transfer(address indexed _from, address indexed _to, uint256 _value);

	function AumICO() public {
	    admin = msg.sender;
		etherPrice = 80055; // testing
		etherInContract = 0;
		tokenPrice[0] = 35;//uint public tokenPricePreSale = 35; //Price x100 (with no cents: $0.35 => 35)
		tokenPrice[1] = 55;//uint public tokenPricePreICO = 55; //Price x100 (with no cents: $0.55 => 55)
		tokenPrice[2] = 75;//uint public tokenPriceICO = 75; //Price x100 (with no cents: $0.75 => 75)
		availableTokens[0] = 0;
		availableTokens[1] = preICOAvailableTokens * 10**8;
		availableTokens[2] = ICOAvailableTokens * 10**8;
		tokenCurrentStage = 0;
		//tokenContractAddress = this;
		tokenContractAddress = 0x8f0483125FCb9aaAEFA9209D8E9d7b9C8B9Fb90F;//Test, Token address on Ganache
		tokenReward = token(tokenContractAddress);
		currentOperation = 0;
		hasICOFinished = false;
		//lastPriceCheck = 0;
		lastPriceCheck = now; // testing
	}
	
	function changeTokenAddress (address newTokenAddress) public onlyAdmin
	{
		tokenContractAddress = newTokenAddress;
		tokenReward = token(tokenContractAddress);
	}
	
	function () payable {
		if(!allContacts[msg.sender].isOnWhitelist || now < startEpochTimestamp || now >= endEpochTimestamp || hasICOFinished)
		{
			revert();
		}
        uint depositedEther = msg.value;
        uint currentVaultBalance = tokenReward.getBalance(this);
        uint totalAddressDeposit = safeAdd(allContacts[msg.sender].depositedEther, depositedEther);
        uint leftoverEther = 0;
		if(depositedEther < minAmmountToInvest || totalAddressDeposit > maxAmmountToInvest)
		{
			bool canEtherPassthrough = false;
		    if(totalAddressDeposit > maxAmmountToInvest)
		    {
		        uint passthroughEther = safeSub(maxAmmountToInvest, allContacts[msg.sender].depositedEther);   
		        if(passthroughEther > 0)
		        {
		            depositedEther = safeSub(depositedEther, 100000);   //Gas for the extra transactions
		            if(depositedEther > passthroughEther)
		            {
		                leftoverEther = safeSub(depositedEther, passthroughEther);   
		            }
		            depositedEther = passthroughEther;
		            canEtherPassthrough = true;
		        }
		    }
		    if(!canEtherPassthrough)
		    {
		        revert();    
		    }
		}
		if (currentVaultBalance > 0)
		{
			if(safeSub(now, lastPriceCheck) > 300)
			{
				operationsInQueue.push(OperationInQueue(now, depositedEther, msg.sender, false));
				updatePrice();
			}else
			{
				sendTokens(msg.sender, depositedEther);
			}
		}else 
		{
			revert();
		}
		if(leftoverEther > 0)
		{
		    msg.sender.transfer(leftoverEther);
		}
    }
    
	function sendTokens(address receiver, uint depositedEther) private 
	{
		if(tokenCurrentStage >= 3)
		{
			hasICOFinished = true;
			//receiver.transfer(depositedEther);
		}else
		{
		    
			uint obtainedTokensDividend = safeMul(etherPrice, depositedEther );
			uint obtainedTokensDivisor = safeMul(tokenPrice[tokenCurrentStage], 10**10 );
			uint obtainedTokens = safeDiv(obtainedTokensDividend, obtainedTokensDivisor);
			
			if(obtainedTokens > availableTokens[tokenCurrentStage])
			{
			    uint leftoverEther = depositedEther;
				if(availableTokens[tokenCurrentStage] > 0)
				{
				    uint tokensAvailableForTransfer = availableTokens[tokenCurrentStage];
				    uint leftoverTokens = safeSub(obtainedTokens, availableTokens[tokenCurrentStage]);
    				availableTokens[tokenCurrentStage] = 0;
    				uint leftoverEtherDividend = safeMul(leftoverTokens, tokenPrice[tokenCurrentStage] );
    				leftoverEtherDividend = safeMul(leftoverEtherDividend, 10**10 );
    				leftoverEther = safeDiv(leftoverEtherDividend, etherPrice);
    				
				    uint usedEther = safeSub(depositedEther, leftoverEther);
					etherInContract += depositedEther;
					allContacts[receiver].obtainedTokens += tokensAvailableForTransfer;
			        allContacts[receiver].depositedEther += usedEther;
					//tokenReward.sendCoin(receiver, tokensAvailableForTransfer);
				}
				tokenCurrentStage++;
				sendTokens(receiver, leftoverEther);
			}else
			{
				availableTokens[tokenCurrentStage] = safeSub(availableTokens[tokenCurrentStage], obtainedTokens);
				etherInContract += depositedEther;
				allContacts[receiver].obtainedTokens += obtainedTokens;
			    allContacts[receiver].depositedEther += depositedEther;
				//tokenReward.sendCoin(receiver, obtainedTokens);
			}
		}
	}
	
	function CheckQueue() private
	{
	    if(operationsInQueue.length > currentOperation)
	    {
    		if(!operationsInQueue[currentOperation].closed)
    		{
    		    operationsInQueue[currentOperation].closed = true;
    			if(safeSub(now, operationsInQueue[currentOperation].operationStartTime) > 300)
    			{
    				operationsInQueue.push(OperationInQueue(now, operationsInQueue[currentOperation].depositedEther, operationsInQueue[currentOperation].receiver, false));
    				updatePrice();
    				currentOperation++;
    				return;
    			}else
    			{
    				sendTokens(operationsInQueue[currentOperation].receiver, operationsInQueue[currentOperation].depositedEther);
    			}
    		}
    		currentOperation++;
	    }
	}
	
	function getTokenAddress() public constant returns (address) {
		return tokenContractAddress;
	}
	
	function getTokenBalance() public constant returns (uint) {
		return tokenReward.getBalance(this);
	}
	
	
	function getEtherInContract() public constant returns (uint) {
		return etherInContract;
	}
	
	function GetQueueLength() public constant returns (uint) {
		return safeSub(operationsInQueue.length, currentOperation);
	}
	
	function AdvanceQueue() onlyAdmin public
	{
		CheckQueue();
	}
	
	function AddToWhitelist(address addressToAdd) onlyAdmin public
	{
		if(!allContacts[addressToAdd].userExists)
		{
			contactsAddresses.push(addressToAdd);
			allContacts[addressToAdd].userExists = true;
			allContacts[addressToAdd].obtainedTokens = 0;
			allContacts[addressToAdd].depositedEther = 0;
		}
		allContacts[addressToAdd].isOnWhitelist = true;
	}
	
	function RemoveFromWhitelist(address addressToRemove) onlyAdmin public
	{
	    if(allContacts[addressToRemove].userExists)
		{
			allContacts[addressToRemove].isOnWhitelist = false;
		}
	}
	
	function IsOnWhitelist(address addressToCheck) public view returns(bool isOnWhitelist)
	{
		return allContacts[addressToCheck].isOnWhitelist;
	}
	
	
	function getPrice() public constant returns (uint) {
		return etherPrice;
	}
	
	function updatePrice() public 
	{
		if (oraclize_getPrice("URL") > this.balance) {
            //LogNewOraclizeQuery("Oraclize query was NOT sent, please add some ETH to cover for the query fee");
        } else {
            //LogNewOraclizeQuery("Oraclize query was sent, standing by for the answer..");
            oraclize_query("URL", "json(https://min-api.cryptocompare.com/data/price?fsym=ETH&tsyms=USD).USD");
        }
	}
	
	function __callback(bytes32 _myid, string _result) {
		require (msg.sender == oraclize_cbAddress());
		etherPrice = parseInt(_result, 2);
		lastPriceCheck = now;
		CheckQueue();
	}
}
