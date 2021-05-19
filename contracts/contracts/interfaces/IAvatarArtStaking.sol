// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IAvatarArtStaking{
    /**
     * @dev Get APR
    */
    function getApr() external view returns(uint);
    
    /**
     * @dev Get total BNU token amount staked in contract
     */ 
    function getTotalStaked() external view returns(uint);
    
    /**
     * @dev Get user's BNU earned
     */ 
    function getUserEarnedAmount(address account) external view returns(uint);
    
    /**
     * @dev Get list of staking users
     */ 
    function getStakingUsers() external view returns(address[] memory);
    
    /**
     * @dev Get user ticket slot for receiving NFT
     */ 
    function getUserNftTicket(address account, uint nftStageIndex) external view returns(uint);
    
    /**
     * @dev Get total BNU token amount staked by `account`
     */ 
    function getUserStakedAmount(address account) external view returns(uint);
    
    /**
     * @dev User join to stake BNU and have a chance to receive an NFT from AvatarArt
     * 
     * An NFT will be available within 30 days from contract created or date will be configured
     * After that, this contract be only used to stake
     */ 
    function stake(uint amount) external returns(bool);
    
    /**
     * @dev User withdraw staked BNU from contract
     * User will receive all staked BNU and reward BNU based on APY configuration
     */ 
    function withdraw(uint amount) external returns(bool);
}