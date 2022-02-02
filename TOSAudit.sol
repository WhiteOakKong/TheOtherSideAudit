// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/****************************************
 * @author: tos_nft                 *
 * @team:   TheOtherSide                *
 ****************************************
 *   TOS-ERC721 provides low-gas    *
 *           mints + transfers          *
 ****************************************/

import './Delegated.sol';
import './ERC721EnumerableT.sol';
import "@openzeppelin/contracts/utils/Strings.sol";
import './SafeMath.sol';

interface IERC20Proxy{
  function burnFromAccount( address account, uint leaves ) external payable;
  function mintToAccount( address[] calldata accounts, uint[] calldata leaves ) external payable;
}

interface IERC1155Proxy{
  function burnFrom( address account, uint[] calldata ids, uint[] calldata quantities ) external payable;
}

contract TheOtherSideV13 is ERC721EnumerableT, Delegated {
  using Strings for uint;
  using SafeMath for uint256;

  enum MoonType {
      Genesis,
      Normal
  }

  struct Moon {
    address owner;
    MoonType moonType;
  }

  bool public revealed = false;
  string public notRevealedUri = "ipfs://QmPrzMdTq8WjSPRDHdBPfXeTRA8coSYoYmPwJhWdHLvcpE/hidden_metadata.json";

  uint public MAX_SUPPLY   = 500;
  uint public PRICE        = 0.065 ether;
  uint public MAX_QTY = 2;
  
  Moon[] public moons;

  bool public isWhitelistActive = false;
  bool public isMintActive = true;

  mapping(address => uint) public accessList;

  bool public isStakeActive   = true;

  mapping(address => uint) private _balances;
  string private _tokenURIPrefix = "ipfs://QmRCeq3V3h9jujsoZRnAidEhAhRnPUEXeSWV9wAbLeN4U5/";
  string private _tokenURISuffix =  ".json";

  struct Staker {
    uint256[] tokenIds;
    mapping (uint256 => uint256) tokenIndex;
  }

    // @notice mapping of a staker to its current properties
    mapping (address => Staker) private stakers;

    // Mapping from token ID to owner address
    mapping (uint256 => address) public originalStakeOwner;

     // @notice event emitted when a user has staked a token
    event Staked(address owner, uint256 amount);

    // @notice event emitted when a user has unstaked a token
    event Unstaked(address owner, uint256 amount);

  constructor()
    ERC721T("The Other Side v.13", "TOSV13"){
  }

  //external
  fallback() external payable {}


  function balanceOf(address account) public view override returns (uint) {
    require(account != address(0), "MOON: balance query for the zero address");
    return _balances[account];
  }

  function isOwnerOf( address account, uint[] calldata tokenIds ) external view override returns( bool ){
    for(uint i; i < tokenIds.length; ++i ){
      if( moons[ tokenIds[i] ].owner != account )
        return false;
    }

    return true;
  }

  function ownerOf( uint tokenId ) public override view returns( address owner_ ){
    address owner = moons[tokenId].owner;
    require(owner != address(0), "MOON: query for nonexistent token");
    return owner;
  }

  function tokenByIndex(uint index) external view override returns (uint) {
    require(index < totalSupply(), "MOON: global index out of bounds");
    return index;
  }

  function tokenOfOwnerByIndex(address owner, uint index) public view override returns (uint tokenId) {
    uint count;
    for( uint i; i < moons.length; ++i ){
      if( owner == moons[i].owner ){
        if( count == index )
          return i;
        else
          ++count;
      }
    }

    revert("ERC721Enumerable: owner index out of bounds");
  }

  function tokenURI(uint tokenId) external view override returns (string memory) {
    require(_exists(tokenId), "MOON: URI query for nonexistent token");

    if(revealed == false) {
        return notRevealedUri;
    }
    return string(abi.encodePacked(_tokenURIPrefix, tokenId.toString(), _tokenURISuffix));
  }

  function totalSupply() public view override returns( uint totalSupply_ ){
    return moons.length;
  }

  function walletOfOwner( address account ) external view override returns( uint[] memory ){
    uint quantity = balanceOf( account );
    uint[] memory wallet = new uint[]( quantity );
    for( uint i; i < quantity; ++i ){
        wallet[i] = tokenOfOwnerByIndex( account, i );
    }
    return wallet;
  }

  //only owner
  function setRevealState(bool reveal_) external onlyDelegates {
      revealed = reveal_;
  }

  //payable
  function mint( uint quantity ) external payable {
    require(isMintActive == true,"MOON: Minting needs to be enabled.");
    require(quantity <= MAX_QTY, "MOON:Quantity must be less than or equal to 2 only");
    require( msg.value >= PRICE * quantity, "MOON: Ether sent is not correct" );

    //flag to check whitelist address
    if( isWhitelistActive ){
      require( accessList[ msg.sender ] >= quantity, "MOON: Account is not on the access list" );
      accessList[ msg.sender ] -= quantity;
    }

    uint supply = totalSupply();
    require( supply + quantity <= MAX_SUPPLY, "MOON: Mint/order exceeds supply" );
    for(uint i; i < quantity; ++i){
      _mint( msg.sender, supply++, MoonType.Genesis );
    }
  }

  function getBalanceofContract() public view returns (uint256) {
    return address(this).balance;
  }

  function getContractAddress() public view returns (address) {
    return address(this);
  }

  function withdraw(uint256 amount_) public onlyOwner {
    require(address(this).balance >= amount_, "Address: insufficient balance");

    // This will payout the owner 100% of the contract balance.
    // Do not remove this otherwise you will not be able to withdraw the funds.
    // =============================================================================
    (bool os, ) = payable(owner()).call{value: amount_}("");
    require(os);
    // =============================================================================
  }


  //onlyDelegates
  function mint_(uint[] calldata quantity, address[] calldata recipient, MoonType[] calldata types_ ) external payable onlyDelegates{
    require(isMintActive == true,"MOON: Minting needs to be enabled.");
    
    require(quantity.length == recipient.length, "MOON: Must provide equal quantities and recipients" );
    require(recipient.length == types_.length,   "MOON: Must provide equal recipients and types" );

    uint totalQuantity;
    uint supply = totalSupply();
    for(uint i; i < quantity.length; ++i){
      require(quantity[i] <= MAX_QTY, "MOON:Quantity must be less than or equal to 2 only");
      totalQuantity += quantity[i];
    }
    require( supply + totalQuantity < MAX_SUPPLY, "MOON: Mint/order exceeds supply" );

    for(uint i; i < recipient.length; ++i){
      for(uint j; j < quantity[i]; ++j){
        uint tokenId = supply++;
        _mint( recipient[i], tokenId, types_[i] );
      }
    }
  }

  function setWhitelistAddress(address[] calldata accounts, uint allowed) external onlyDelegates{
    for(uint i; i < accounts.length; ++i){
      accessList[ accounts[i] ] = allowed;
    }
  }

  function setMintingActive(bool mintActive_) external onlyDelegates {
    isMintActive = mintActive_;
  }

  function setWhitelistActive(bool isWhitelistActive_) external onlyDelegates{
    require( isWhitelistActive != isWhitelistActive_ , "MOON: New value matches old" );
    isWhitelistActive = isWhitelistActive_;
  }

  function setBaseURI(string calldata prefix, string calldata suffix) external onlyDelegates{
    _tokenURIPrefix = prefix;
    _tokenURISuffix = suffix;
  }

  function setMaxSupply(uint maxSupply) external onlyDelegates{
    require( MAX_SUPPLY != maxSupply, "MOON: New value matches old" );
    require( maxSupply >= totalSupply(), "MOON: Specified supply is lower than current balance" );
    MAX_SUPPLY = maxSupply;
  }

  function setPrice(uint price) external onlyDelegates{
    require( PRICE != price, "MOON: New value matches old" );
    PRICE = price;
  }

  //internal
  function _beforeTokenTransfer(address from, address to) internal {
    if( from != address(0) )
      --_balances[ from ];

    if( to != address(0) )
      ++_balances[ to ];
  }

  function _exists(uint tokenId) internal view override returns (bool) {
    return tokenId < moons.length && moons[tokenId].owner != address(0);
  }

  function _mint(address to, uint tokenId, MoonType type_ ) internal {
    _beforeTokenTransfer(address(0), to);
    moons.push(Moon( to, type_));
    emit Transfer(address(0), to, tokenId);
  }

  function _transfer(address from, address to, uint tokenId) internal override {
    require(moons[tokenId].owner == from, "MOON: transfer of token that is not owned");

    // Clear approvals from the previous owner
    _approve(address(0), tokenId);
    _beforeTokenTransfer(from, to);

    moons[tokenId].owner = to;
    emit Transfer(from, to, tokenId);
  }

  /**
     * @dev All the staking goes through this function
     * @dev Rewards to be given out is calculated
     * @dev Balance of stakers are updated as they stake the nfts based on ether price
    */
    function _stake( address _user, uint256 _tokenId ) internal {

        Staker storage staker = stakers[_user];
        staker.tokenIds.push(_tokenId);
        staker.tokenIndex[staker.tokenIds.length - 1];
        originalStakeOwner[_tokenId] = _user;

        _transfer(_user,address(this), _tokenId);
      
        emit Staked(_user, _tokenId);
    }


    /**
     * @dev All the unstaking goes through this function
     * @dev Rewards to be given out is calculated
     * @dev Balance of stakers are updated as they unstake the nfts based on ether price
    */
    function _unstake( address _user, uint256 _tokenId) internal {

        Staker storage staker = stakers[_user];
        uint256 lastIndex = staker.tokenIds.length - 1;
        uint256 lastIndexKey = staker.tokenIds[lastIndex];
        uint256 tokenIdIndex = staker.tokenIndex[_tokenId];
        
        staker.tokenIds[tokenIdIndex] = lastIndexKey;
        staker.tokenIndex[lastIndexKey] = tokenIdIndex;
        if (staker.tokenIds.length > 0) {
            staker.tokenIds.pop();
            delete staker.tokenIndex[_tokenId];
        }
        if (staker.tokenIds.length == 0) {
            delete stakers[_user];
        }
        delete originalStakeOwner[_tokenId];

        _transfer(address(this),_user, _tokenId);
        
        emit Unstaked(_user, _tokenId);

    }

    /// @dev Getter functions for Staking contract
    /// @dev Get the tokens staked by a user
    function getStakedTokens(address _user) public view returns (uint256[] memory tokenIds) {
        return stakers[_user].tokenIds;
    }

    function stake( uint[] calldata tokenIds ) external {
        require( isStakeActive, "MOON: Staking is not active" );

        Moon storage moon;
        //Check if TokenIds exist and the moon owner is the msge sender
        for( uint i; i < tokenIds.length; ++i ){
            require( _exists(tokenIds[i]), "MOON: Query for nonexistent token" );
            moon = moons[ tokenIds[i] ];
            require(moon.owner == msg.sender, "MOON: Staking token that is not owned");

            _stake(msg.sender,tokenIds[i]);

        }
    }

    function unStake( uint[] calldata tokenIds ) external {
        require( isStakeActive, "MOON: Staking is not active" );

        //Check if TokenIds exist
        for( uint i; i < tokenIds.length; ++i ){
            require( originalStakeOwner[tokenIds[i]] == msg.sender, 
            "MOON._unstake: Sender must have staked tokenID");

            _unstake(msg.sender,tokenIds[i]);
            
        }
    }

    function setStakeActive( bool isActive_ ) external onlyDelegates {
      isStakeActive = isActive_;
    }
}
