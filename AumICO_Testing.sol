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


contract ERC223 {
  uint public totalSupply;
  function balanceOf(address who) public view returns (uint);
  
  function name() public view returns (string _name);
  function symbol() public view returns (string _symbol);
  function decimals() public view returns (uint8 _decimals);
  function totalSupply() public view returns (uint256 _supply);

  function transfer(address to, uint value) public returns (bool ok);
  function transfer(address to, uint value, bytes data) public returns (bool ok);
  function transfer(address to, uint value, bytes data, string custom_fallback) public returns (bool ok);
  function transferFrom(address from, address to, uint value) public returns(bool);
  
  event Transfer(address indexed from, address indexed to, uint value, bytes indexed data);
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
		bool userLiquidated;
		uint depositedLEX;
	}
	
	uint[3] public tokenPrice;
	uint[3] public availableTokens;
	uint public tokenCurrentStage;
	bool public hasICOFinished;
	
	uint public etherPrice; //Price x100 (with no cents: $800.55 => 80055)
	uint public etherInContract;
	uint public LEXInContract;
	uint public usdEstimateInContract; //With no cents and x10**8 (1usd => 10000000000)
	uint public softCap = 35437500000000000; //15% of goal $3,543,750 With no cents and x10**8 (1usd => 10000000000)
	uint currentSoftCapContact;
	
	//uint public startEpochTimestamp = 1518487231; // Test, Testing
	uint public startEpochTimestamp = 1518807600; // Friday February 16th 2018 at 12pm GMT-06:00, you can verify the epoch at https://www.epochconverter.com/
	uint public endEpochTimestamp = 1521093600; // Thursday March 15th 2018 at 12am GMT-06:00, you can verify the epoch at https://www.epochconverter.com/
	
	uint public lastPriceCheck = 0;
	
	uint preICOAvailableTokens = 11250000; // 11,250,000 AUM's for the pre ICO, with 8 decimals
	uint ICOAvailableTokens = 20625000; // 20,625,000 AUM's for the pre ICO, with 8 decimals
	
	uint minAmmountToInvest = 100000000000000000; // 0.1 Ether, or 100,000,000,000,000,000 wei
	uint maxAmmountToInvest = 500000000000000000000; // 500 Ether, or 500,000,000,000,000,000,000 wei
	
	address LEXTokenAddress; //Limited Exchange Token address, For future processing via Koinvex
	address tokenContractAddress;
	address tokenVaultAddress;
	address admin;
	address etherVault;
	address etherGasProvider;
	mapping(address => Contact) public allContacts;
	address[] public contactsAddresses;
	
	bool tokenContractAddressReady;
	bool LEXtokenContractAddressReady;
	
	ERC223 public tokenReward;
	ERC223 public LEXToken;
	
	OperationInQueue[] public operationsInQueue;
	uint public currentOperation;
	
	modifier onlyAdmin()
	{
	    require(msg.sender == admin);
	    _;
	}
	
	event Transfer(address indexed _from, address indexed _to, uint256 _value);

	function AumICO() public {
		OAR = OraclizeAddrResolverI(0x6f485C8BF6fc43eA212E93BBF8ce046C7f1cb475); //Testing
	    admin = msg.sender;
		etherPrice = 100055; // testing
		etherInContract = 0;
		LEXInContract = 0;
		usdEstimateInContract = 19687500000000000; //$1,968,750 in pre-sale
		tokenPrice[0] = 35;//uint public tokenPricePreSale = 35; //Price x100 (with no cents: $0.35 => 35)
		tokenPrice[1] = 55;//uint public tokenPricePreICO = 55; //Price x100 (with no cents: $0.55 => 55)
		tokenPrice[2] = 75;//uint public tokenPriceICO = 75; //Price x100 (with no cents: $0.75 => 75)
		availableTokens[0] = 0;
		availableTokens[1] = preICOAvailableTokens * 10**8;
		availableTokens[2] = ICOAvailableTokens * 10**8;
		tokenCurrentStage = 0;
		tokenContractAddressReady = false;
		LEXtokenContractAddressReady = true;
		LEXTokenAddress = 0x8f0483125fcb9aaaefa9209d8e9d7b9c8b9fb90f;//Test, Token address on Ganache
		//tokenContractAddress = 0xf25186b5081ff5ce73482ad761db0eb0d25abfbf;//Test, Token address on Ganache
		//tokenVaultAddress = 0x821aEa9a577a9b44299B9c15c88cf3087F3b5544;//Test, Token address on Ganache
		//tokenVaultAddress = 0x627306090abaB3A6e1400e9345bC60c78a8BEf57;//Test, Token address on Ganache
		etherVault = 0xC5fdf4076b8F3A5357c5E395ab970B5B54098Fef;////Test, address on Ganache
		etherGasProvider = 0xC5fdf4076b8F3A5357c5E395ab970B5B54098Fef;////Test, address on Ganache
		//etherVault = 0x1FE5e535C3BB002EE0ba499a41f66677fC383424;// all deposited ether will go to this address
		//etherGasProvider = 0x1FE5e535C3BB002EE0ba499a41f66677fC383424;// this address is whitelisted for sending ether to this contract without sending back tokens
		tokenVaultAddress = msg.sender;
		//tokenReward = ERC223(tokenContractAddress); // Test
		currentOperation = 0;
		hasICOFinished = false;
		lastPriceCheck = 0;
		currentSoftCapContact = 0;
	}
	
	function () payable {
		if(msg.sender == etherGasProvider)
		{
			return;
		}
		if(!allContacts[msg.sender].isOnWhitelist || (now < startEpochTimestamp && msg.sender != admin) || now >= endEpochTimestamp || hasICOFinished || !tokenContractAddressReady)
		{
			revert();
		}
        uint depositedEther = msg.value;
        uint currentVaultBalance = tokenReward.balanceOf(tokenVaultAddress);
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
			receiver.transfer(depositedEther);
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
					etherInContract += usedEther;
					allContacts[receiver].obtainedTokens += tokensAvailableForTransfer;
			        allContacts[receiver].depositedEther += usedEther;
			        usdEstimateInContract += safeMul(tokensAvailableForTransfer, tokenPrice[tokenCurrentStage] );
					etherVault.transfer(depositedEther);
					tokenReward.transferFrom(tokenVaultAddress, receiver, tokensAvailableForTransfer);
				}
				tokenCurrentStage++;
				sendTokens(receiver, leftoverEther);
			}else
			{
			    usdEstimateInContract += safeMul(obtainedTokens, tokenPrice[tokenCurrentStage] );
				availableTokens[tokenCurrentStage] = safeSub(availableTokens[tokenCurrentStage], obtainedTokens);
				etherInContract += depositedEther;
				allContacts[receiver].obtainedTokens += obtainedTokens;
			    allContacts[receiver].depositedEther += depositedEther;
				etherVault.transfer(depositedEther);
				tokenReward.transferFrom(tokenVaultAddress, receiver, obtainedTokens);
			}
		}
	}
	
	
	function tokenFallback(address _from, uint _value, bytes _data) public
	{
		if(msg.sender != LEXTokenAddress || !LEXtokenContractAddressReady)
		{
			revert();
		}
		if(!allContacts[_from].isOnWhitelist || now < startEpochTimestamp || now >= endEpochTimestamp || hasICOFinished || !tokenContractAddressReady)
		{
			revert();
		}
		uint currentVaultBalance = tokenReward.balanceOf(tokenVaultAddress);
		if(currentVaultBalance > 0)
		{
			sendTokensForLEX(_from, _value);
		}else
		{
			revert();
		}
	}
	
	function sendTokensForLEX(address receiver, uint depositedLEX) private 
	{
		if(tokenCurrentStage >= 3)
		{
			hasICOFinished = true;
			LEXToken.transfer(receiver, depositedLEX);
		}else
		{
			uint depositedBalance = safeMul(depositedLEX, 100000000);
			uint obtainedTokens = safeDiv(depositedBalance, tokenPrice[tokenCurrentStage]);
			if(obtainedTokens > availableTokens[tokenCurrentStage])
			{
			    uint leftoverLEX = depositedLEX;
				if(availableTokens[tokenCurrentStage] > 0)
				{
				    uint tokensAvailableForTransfer = availableTokens[tokenCurrentStage];
				    uint leftoverTokens = safeSub(obtainedTokens, availableTokens[tokenCurrentStage]);
    				availableTokens[tokenCurrentStage] = 0;
    				uint leftoverLEXFactor = safeMul(leftoverTokens, tokenPrice[tokenCurrentStage] );
    				leftoverLEX = safeDiv(leftoverLEXFactor, 100000000);
    				
				    uint usedLEX = safeSub(depositedLEX, leftoverLEX);
					LEXInContract += usedLEX;
					allContacts[receiver].obtainedTokens += tokensAvailableForTransfer;
			        allContacts[receiver].depositedLEX += usedLEX;
			        usdEstimateInContract += safeMul(tokensAvailableForTransfer, tokenPrice[tokenCurrentStage] );
					tokenReward.transferFrom(tokenVaultAddress, receiver, tokensAvailableForTransfer);
				}
				tokenCurrentStage++;
				sendTokensForLEX(receiver, leftoverLEX);
			}else
			{
			    usdEstimateInContract += depositedLEX;
				availableTokens[tokenCurrentStage] = safeSub(availableTokens[tokenCurrentStage], obtainedTokens);
				LEXInContract += depositedLEX;
				allContacts[receiver].obtainedTokens += obtainedTokens;
			    allContacts[receiver].depositedLEX += depositedLEX;
				tokenReward.transferFrom(tokenVaultAddress, receiver, obtainedTokens);
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
    			if(safeSub(now, lastPriceCheck) > 300)
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
		return tokenReward.balanceOf(tokenVaultAddress);
	}
	
	
	function getEtherInContract() public constant returns (uint) {
		return etherInContract;
	}
	
	function GetQueueLength() public onlyAdmin constant returns (uint) {
		return safeSub(operationsInQueue.length, currentOperation);
	}
	
	function changeTokenAddress (address newTokenAddress) public onlyAdmin
	{
		tokenContractAddress = newTokenAddress;
		tokenReward = ERC223(tokenContractAddress);
		tokenContractAddressReady = true;
	}
	
	function ChangeLEXTokenAddress (address newLEXTokenAddress) public onlyAdmin
	{
		LEXTokenAddress = newLEXTokenAddress;
		LEXToken = ERC223(LEXTokenAddress);
		LEXtokenContractAddressReady = true;
	}
	
	function ChangeEtherVault(address newEtherVault) onlyAdmin public
	{
		etherVault = newEtherVault;
	}
	
	function ExtractEtherLeftOnContract(address newEtherGasProvider) onlyAdmin public
	{
		if(now > endEpochTimestamp)
	    {
			etherVault.transfer(this.balance);
		}
	}
	
	function ChangeEtherGasProvider(address newEtherGasProvider) onlyAdmin public
	{
		etherGasProvider = newEtherGasProvider;
	}
	
	function ChangeTokenVaultAddress(address newTokenVaultAddress) onlyAdmin public
	{
		tokenVaultAddress = newTokenVaultAddress;
	}
	
	function AdvanceQueue() onlyAdmin public
	{
		CheckQueue();
	}
	
	function UpdateEtherPriceNow() onlyAdmin public
	{
		updatePrice();
	}
	
	function CheckSoftCap() onlyAdmin public
	{
	    if(usdEstimateInContract < softCap && now > endEpochTimestamp && currentSoftCapContact < contactsAddresses.length)
	    {
	        for(uint i = currentSoftCapContact; i < 4;i++)
	        {
				if(i < contactsAddresses.length)
				{
					if(!allContacts[contactsAddresses[i]].userLiquidated)
					{
						allContacts[contactsAddresses[i]].userLiquidated = true;
						allContacts[contactsAddresses[i]].depositedEther = 0;
						contactsAddresses[i].transfer(allContacts[contactsAddresses[i]].depositedEther);
					}
					currentSoftCapContact++;
				}
	        }
	    }
	}
	
	function AddToWhitelist(address addressToAdd) onlyAdmin public
	{
	    if(!allContacts[addressToAdd].userExists)
		{
    		contactsAddresses.push(addressToAdd);
    		allContacts[addressToAdd].userExists = true;
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
	
	function GetAdminAddress() public returns (address)
	{
		return admin;
	}
	
	function IsOnWhitelist(address addressToCheck) public view returns(bool isOnWhitelist)
	{
		return allContacts[addressToCheck].isOnWhitelist;
	}
	
	function getPrice() public constant returns (uint) {
		return etherPrice;
	}
	
	function updatePrice() private
	{
		if (oraclize_getPrice("URL") > this.balance) {
            //LogNewOraclizeQuery("Oraclize query was NOT sent, please add some ETH to cover for the query fee");
        } else {
            //LogNewOraclizeQuery("Oraclize query was sent, standing by for the answer..");
            oraclize_query("URL", "json(https://min-api.cryptocompare.com/data/price?fsym=ETH&tsyms=USD).USD", 300000);
        }
	}
	
	function __callback(bytes32 _myid, string _result) {
		require (msg.sender == oraclize_cbAddress());
		etherPrice = parseInt(_result, 2);
		lastPriceCheck = now;
		CheckQueue();
	}
}
