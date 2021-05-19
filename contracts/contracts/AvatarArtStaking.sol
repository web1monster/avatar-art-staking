// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./interfaces/IAvatarArtStaking.sol";
import "./interfaces/IERC20.sol";
import "./core/Runnable.sol";

contract AvatarArtStaking is IAvatarArtStaking, Runnable{
    struct NftStage{
        uint startTime;
        uint endTime;
        bool isActive;
    }
    
    struct StakingHistory{
        uint time;
        uint amount;
    }
    
    address internal _bnuTokenAddress;
    
    //Store all BNU token amount that is staked in contract
    uint internal _totalStakedAmount;
    uint internal _apr;
    uint public constant APR_MULTIPLIER = 1000;
    uint public constant ONE_YEAR = 365 days;
    uint public constant ONE_DAY = 1 days;
    
    //Store all BNU token amount that is staked by user
    //Mapping user account => token amount
    mapping(address => uint) internal _userStakeds;
    
    //Store all earned BNU token amount that will be reward for user when he stakes
    //Mapping user account => token amount
    mapping(address => uint) internal _userEarneds;
    
    //Store the last time user stakes
    //Mapping user account => time
    mapping(address => uint) internal _userLastStakingTimes;
    
    //Store user's staking histories
    //Mapping user account => Staking history
    mapping(address => StakingHistory[]) internal _userStakingHistories;
    
    //List of staking users 
    address[] internal _stakingUsers;
    
    //NFT
    //Store to check whether NFT is running or not
    NftStage[] internal _nftStages;
    
    constructor(address bnuTokenAddress, uint apr){
        _bnuTokenAddress = bnuTokenAddress;
        _apr = apr;
    }
    
    /**
     * @dev Create new NFT stage
    */ 
    function createNftStage(uint startTime, uint endTime) external onlyOwner{
        _nftStages.push(NftStage(startTime, endTime, true));
    }
    
    /**
     * @dev Get APR
    */
    function getApr() external override view returns(uint){
        return _apr;
    }
    
    /**
     * @dev Get BNU token address
    */
    function getBnuTokenAddress() external view returns(address){
        return _bnuTokenAddress;
    }
    
    function getNftStages() external view returns(NftStage[] memory){
        return _nftStages;
    }
    
    /**
     * @dev Get total BNU token amount staked in contract
     */ 
    function getTotalStaked() external override view returns(uint){
        return _totalStakedAmount;
    }
    
    /**
     * @dev Get user's BNU earned
     * It includes stored interest and pending interest
     */ 
    function getUserEarnedAmount(address account) external override view returns(uint){
        uint earnedAmount = _userEarneds[account];
        
        //Calculate pending amount
        uint userStakedAmount = _userStakeds[account];
        if(userStakedAmount > 0){
            earnedAmount += _calculatePendingEarned(userStakedAmount, _userLastStakingTimes[account]);
        }
        
        return earnedAmount;
    }
    
    /**
     * @dev Get list of users who are staking
     */ 
    function getStakingUsers() external override view returns(address[] memory){
        return _stakingUsers;
    }
    
    /**
     * @dev Get staking histories of `account`
     */ 
    function getStakingHistories(address account) external view returns(StakingHistory[] memory){
        return _userStakingHistories[account];
    }
    
    /**
     * @dev Get user ticket slot for receiving NFT
     */ 
    function getUserNftTicket(address account, uint nftStageIndex) external override view returns(uint){
        require(nftStageIndex < _nftStages.length, "NFT stage index is invalid");
        StakingHistory[] memory stakingHistories = _userStakingHistories[account];
        if(stakingHistories.length == 0)
            return 0;
            
        NftStage memory nftStage = _nftStages[nftStageIndex];
        if(!nftStage.isActive)
            return 0;
            
        uint result = 0;
        uint index = 0;
        uint stakedAmount = 0;
        while(nftStage.startTime <= nftStage.endTime){
            uint nextDay = nftStage.startTime + ONE_DAY;
            for(index; index < stakingHistories.length; index++){
                StakingHistory memory stakingHistory = stakingHistories[index];
                if(stakingHistory.time >= nftStage.startTime && stakingHistory.time < nextDay){
                    stakedAmount += stakingHistory.amount;
                }
            }
            
            result += stakedAmount;
            
            nftStage.startTime = nextDay;
        }
        
        return result;
    }
    
    /**
     * @dev Get total BNU token amount staked by `account`
     */ 
    function getUserStakedAmount(address account) external override view returns(uint){
        return _userStakeds[account];
    }
    
    /**
     * @dev Remove NFT stage from data
     */ 
    function removeNftStage(uint index) external onlyOwner returns(bool){
        uint nftStageLength = _nftStages.length;
        require(index < nftStageLength, "Index is invalid");
        
        _nftStages[index].isActive = false;
        
        //NftStage[] memory nftStages = new NftStage[](nftStageLength -1);
        //uint newIndex = 0;
        //for(uint itemIndex = 0; itemIndex < nftStageLength; itemIndex++){
            //if(itemIndex != index){
                //nftStages[newIndex] = _nftStages[itemIndex];
                //++;
            //}
        //}
        
        //_nftStages = nftStages;
        return true;
    }
    
    /**
     * @dev Set BNU token address
    */
    function setBnuTokenAddress(address tokenAddress) external onlyOwner{
        require(tokenAddress != address(0), "Zero address");
        _bnuTokenAddress = tokenAddress;
    }
    
    /**
     * @dev Set APR
     * Before set APR with new value, contract should process to calculate all current users' profit 
     * to reset interest
    */
    function setApr(uint apr) external onlyOwner{
        for(uint userIndex = 0; userIndex < _stakingUsers.length; userIndex++){
            _calculateInterest(_stakingUsers[userIndex]);
        }
        _apr = apr;
    }
    
    /**
     * @dev See IAvatarArtStaking
     */ 
    function stake(uint amount) external override isRunning returns(bool){
        //CHECK REQUIREMENTS
        require(amount > 0, "Amount should be greater than zero");
        
        //Transfer token from user address to contract
        require(IERC20(_bnuTokenAddress).transferFrom(_msgSender(), address(this), amount), "Can not transfer token to contract");
        
        //Calculate interest and store with extra interest
        _calculateInterest(_msgSender());
        
        //Create staking history
        StakingHistory[] storage stakingHistories = _userStakingHistories[_msgSender()];
        stakingHistories.push(StakingHistory(_now(), amount));
        
        //Update user staked amount and contract staked amount
        _userStakeds[_msgSender()] += amount;
        _totalStakedAmount += amount;
        
        if(!_isUserStaked(_msgSender()))
            _stakingUsers.push(_msgSender());
        
        //Emit events
        emit Staked(_msgSender(), amount);
        
        return true;
    }
    
    /**
     * @dev See IAvatarArtStaking
     */ 
    function withdraw(uint amount) external override returns(bool){
        //Calculate interest and store with extra interest
        _calculateInterest(_msgSender());
        
        //Calculate to withdraw staked amount
        if(amount > 0){
            _userStakeds[_msgSender()] -= amount;
            _totalStakedAmount -= amount;
            
            require(IERC20(_bnuTokenAddress).transfer(_msgSender(), amount), "Can not pay staked amount for user");
        }
        
        uint eanedAmount =  _userEarneds[_msgSender()];
        
        //Pay all interest
        if(eanedAmount > 0){
            require(IERC20(_bnuTokenAddress).transfer(_msgSender(), eanedAmount), "Can not pay interest for user");
            _userEarneds[_msgSender()] = 0;
        }
        
        //Emit events 
        emit Withdrawn(_msgSender(), amount);
        
        return true;
    }
    
    /**
     * @dev Calculate and update user pending interest
     */ 
    function _calculateInterest(address account) internal{
        uint userStakedAmount = _userStakeds[account];
        if(userStakedAmount > 0){
            uint earnedAmount = _calculatePendingEarned(userStakedAmount, _userLastStakingTimes[account]);
            
            _userLastStakingTimes[account] = _now();
            _userEarneds[account] += earnedAmount;
        }
    }
    
    /**
     * @dev Calculate interest for user from `lastStakingTime` to  `now`
     * based on user staked amount and apr
     */ 
    function _calculatePendingEarned(uint userStakedAmount, uint lastStakingTime) internal view returns(uint){
        uint pendingTime = _now() - lastStakingTime;
        return userStakedAmount * pendingTime * _apr / APR_MULTIPLIER / ONE_YEAR / 100;
    }
    
    /**
     * @dev Check user has staked or not
     */
    function _isUserStaked(address account) internal view returns(bool){
        for(uint index = 0; index < _stakingUsers.length; index++){
            if(_stakingUsers[index] == account)
                return true;
        }
        
        return false;
    }
    
    event Staked(address account, uint amount);
    event Withdrawn(address account, uint amount);
}