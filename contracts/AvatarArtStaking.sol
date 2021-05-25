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
        bool isAllowWithdrawal;
    }
    
    struct TransactionHistory{
        uint time;
        uint amount;
    }
    
    address internal _bnuTokenAddress;
    uint internal _stopTime;
    
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
    mapping(address => TransactionHistory[]) internal _stakingHistories;
    
    //Store user's withdrawal histories
    //Mapping user account => withdrawal history
    mapping(address => TransactionHistory[]) internal _withdrawHistories;
    
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
        require(startTime < endTime, "Start time should be less than end time");
        _nftStages.push(NftStage(startTime, endTime, true, false));
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
    
    function getStopTime() external view returns(uint){
        return _stopTime;
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
            earnedAmount += _calculatePendingEarned(userStakedAmount, _getUserRewardPendingTime(account));
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
    function getStakingHistories(address account) external view returns(TransactionHistory[] memory){
        return _stakingHistories[account];
    }
    
    function getUserLastStakingTime(address account) external view returns(uint){
        return _getUserLastStakingTime(account);
    }
    
    function getUserRewardPendingTime(address account) external view returns(uint){
        return _getUserRewardPendingTime(account);
    }
    
    /**
     * @dev Get total BNU token amount staked by `account`
     */ 
    function getUserStakedAmount(address account) external override view returns(uint){
        return _userStakeds[account];
    }
    
    /**
     * @dev Get withdrawal histories of `account`
     */ 
    function getWithdrawalHistories(address account) external view returns(TransactionHistory[] memory){
        return _withdrawHistories[account];
    }
    
    /**
     * @dev Remove NFT stage from data
     */ 
    function setNftStage(uint index, bool isActive, bool isAllowWithdrawal) external onlyOwner returns(bool){
        uint nftStageLength = _nftStages.length;
        require(index < nftStageLength, "Index is invalid");
        
        _nftStages[index].isActive = isActive;
        _nftStages[index].isAllowWithdrawal = isAllowWithdrawal;
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
        TransactionHistory[] storage stakingHistories = _stakingHistories[_msgSender()];
        stakingHistories.push(TransactionHistory(_now(), amount));
        
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
     * @dev Stop staking program
     */ 
    function stop() external onlyOwner{
        _isRunning = false;
        _stopTime = _now();

        IERC20 bnuTokenContract = IERC20(_bnuTokenAddress);
        if(bnuTokenContract.balanceOf(address(this)) > _totalStakedAmount)
            bnuTokenContract.transfer(_owner, bnuTokenContract.balanceOf(address(this)) - _totalStakedAmount);
        
        emit Stopped(_now());
    }
    
    /**
     * @dev See IAvatarArtStaking
     */ 
    function withdraw(uint amount) external override returns(bool){
        //Calculate interest and store with extra interest
        _calculateInterest(_msgSender());
        
        (bool hasNftStage, NftStage memory nftStage) = _getCurrentNftStage();
        
        IERC20 bnuTokenContract = IERC20(_bnuTokenAddress);
        
        //Calculate to withdraw staked amount
        if((!hasNftStage || nftStage.isAllowWithdrawal) && amount > 0){
            _userStakeds[_msgSender()] -= amount;
            _totalStakedAmount -= amount;
            
            require(bnuTokenContract.transfer(_msgSender(), amount), "Can not pay staked amount for user");
        }
        
        uint eanedAmount = _userEarneds[_msgSender()];
        
        //Pay all interest
        if(eanedAmount > 0){
            //Make sure that user can withdraw all their staked amount
            if(bnuTokenContract.balanceOf(address(this)) - _totalStakedAmount >= eanedAmount){
                require(bnuTokenContract.transfer(_msgSender(), eanedAmount), "Can not pay interest for user");
                _userEarneds[_msgSender()] = 0;
            }
        }
        
        if(amount > 0)
            _withdrawHistories[_msgSender()].push(TransactionHistory(_now(), amount));
        
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
            uint earnedAmount = _calculatePendingEarned(userStakedAmount, _getUserRewardPendingTime(account));
            _userEarneds[account] += earnedAmount;
        }
        _userLastStakingTimes[account] = _now();
    }
    
    /**
     * @dev Calculate interest for user from `lastStakingTime` to  `now`
     * based on user staked amount and apr
     */ 
    function _calculatePendingEarned(uint userStakedAmount, uint pendingTime) internal view returns(uint){
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
    
    /**
     * @dev Get current NFT stage
     */ 
    function _getCurrentNftStage() internal view returns(bool, NftStage memory nftStage){
        for(uint index = 0; index < _nftStages.length; index++){
            nftStage = _nftStages[index];
            if(nftStage.isActive && nftStage.startTime <= _now() && nftStage.endTime >= _now())
                return (true, nftStage);
        }
        
        return (false, nftStage);
    }
    
    function _getUserLastStakingTime(address account) internal view returns(uint){
        return _userLastStakingTimes[account];
    }
    
    function _getUserRewardPendingTime(address account) internal view returns(uint){
        if(!_isRunning && _stopTime > 0)
            return _stopTime - _getUserLastStakingTime(account);
        return _now() - _getUserLastStakingTime(account);
    }
    
    event Staked(address account, uint amount);
    event Withdrawn(address account, uint amount);
    event Stopped(uint time);
}