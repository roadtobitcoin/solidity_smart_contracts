pragma solidity ^0.8.0;
//SPDX-License-Identifier: MIT

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";



contract NFTMarket is ReentrancyGuard {
  using Counters for Counters.Counter;
  Counters.Counter private _itemIds;
  Counters.Counter private _itemsSold;

address payable owner;
 uint256 listingPrice = 1 ether; // minimum price, change for what you want
 uint256 public totalSaleitems = 0;
 address  public  contractaddress = address(this);

  constructor() {
        owner = payable(msg.sender);
    }

    /*  
    Definitions MarketItem
    @param: itemId 
    @param: ntfContract NFT ERC721 URI Storage deployed on ERC721URIStorage
    @param: seller  Address of Seller
    @param: owner Address of Owner
    @param: price Price of the item
    @param: sold  Sold or not, boolean
    */
    
  struct MarketItem {
    uint itemId;
    address nftContract;
    uint256 tokenId;
    address payable seller;
    address payable owner;
    uint256 price;
    bool sold ;
    bool removedFromMarketplace;
  }

  mapping(uint256 => MarketItem) public idToMarketItem;

  event MarketItemCreated (
    uint indexed itemId,
    address indexed nftContract,
    uint256 indexed tokenId,
    address seller,
    address owner,
    uint256 price,
    bool sold,
    bool removedFromMarketplace
  );

    function getListingPrice() public view returns (uint256) {
        return listingPrice;
    }
    
    function updateListingPrice(uint _newlistingprice) public  {
        require (msg.sender == owner, "Only Owner can call this");
         listingPrice = _newlistingprice;
    }

    /* Listing NFT to the Marketplace */
  function createMarketItem(address nftContract, uint256 tokenId,    uint256 price
  ) public  nonReentrant {
      /* Check if listingPrice is provided, this revenue will go to Marketplace Owner*/
    require(price > listingPrice, "Price must be above the listing fees");
    //require(
      //      msg.value == listingPrice,
        //    "Price must be equal to listing price"
    //    );
    /* create new itermId，tokenId */
    _itemIds.increment();
    uint256 itemId = _itemIds.current();
  /* fill in MarkItem information, and set the NFT URI, seller address, price */
    idToMarketItem[itemId] =  MarketItem(
      itemId,
      nftContract,
      tokenId,
      payable(msg.sender),
      payable(address(this)),
      price,
      true,
      false
    );
    /* change the NFT ownership from owner to MarketAddress */
    IERC721(nftContract).transferFrom(msg.sender, address(this), tokenId);

    emit MarketItemCreated(
      itemId,
      nftContract,
      tokenId,
      msg.sender,
      address(this),
      price,
      true,
      false
    );
  }
  
  function removeMarketItem(address nftContract,   uint256 itemId) public nonReentrant {
    require(idToMarketItem[itemId].seller == msg.sender, "you are not owner of this token");
     //  uint256 itemId = _itemIds.current();
    //      uint256 price = idToMarketItem[itemId].price;
        /* check if buyer has provided paied enough balance */
  //  uint price = idToMarketItem[itemId].price;
    uint tokenId = idToMarketItem[itemId].tokenId;
     idToMarketItem[itemId].sold = true;

      /* Transfer token to new owner */
    IERC721(nftContract).transferFrom(address(this), msg.sender, tokenId);
    idToMarketItem[itemId].owner = payable(msg.sender);
    idToMarketItem[itemId].sold = false;
    idToMarketItem[itemId].removedFromMarketplace = true;
     _itemsSold.increment();
   
  }
  
  /* sellContract　createMarketSale */
  function createMarketSale(
    address nftContract,
    uint256 itemId
    ) public payable nonReentrant {
        /* check if buyer has provided paied enough balance */
    uint price = idToMarketItem[itemId].price;
    uint tokenId = idToMarketItem[itemId].tokenId;
    require(msg.value >= price, "Please submit the asking price in order to complete the purchase");
     idToMarketItem[itemId].sold = true;

  uint saleAmount = msg.value - listingPrice;
/* Transfer sold value to seller */
    idToMarketItem[itemId].seller.transfer(saleAmount);
    //payable(contractaddress).transfer(listingPrice);
    /* Transfer token to new owner */
    IERC721(nftContract).transferFrom(address(this), msg.sender, tokenId);
    idToMarketItem[itemId].owner = payable(msg.sender);
    idToMarketItem[itemId].sold = false;
    idToMarketItem[itemId].removedFromMarketplace = false;
    
     _itemsSold.increment();
   totalSaleitems++;
   
    
  }
  
  
  
    function getMarketItem(uint256 marketItemId) public view returns (MarketItem memory) {
    return idToMarketItem[marketItemId];
  }

  function fetchMarketItem(uint256 itemId) public view returns (MarketItem memory) {
    MarketItem memory item = idToMarketItem[itemId];
    return item;
  }
  
      function itemsSOldbyMarketplace( ) public view returns (MarketItem[] memory) {
       uint totalItemCount = _itemIds.current();
    uint itemCount = 0;
    uint currentIndex = 0;

    for (uint i = 0; i < totalItemCount; i++) {
      if (idToMarketItem[i + 1].owner != address(this) && idToMarketItem[i + 1].sold == false && idToMarketItem[i + 1].removedFromMarketplace == false) {
        itemCount += 1;
      }
    }

    MarketItem[] memory items = new MarketItem[](itemCount);
    for (uint i = 0; i < totalItemCount; i++) {
      if (idToMarketItem[i + 1].owner != address(this) && idToMarketItem[i + 1].sold == false && idToMarketItem[i + 1].removedFromMarketplace == false) {
        uint currentId = idToMarketItem[i + 1].itemId;
        MarketItem storage currentItem = idToMarketItem[currentId];
        items[currentIndex] = currentItem;
        currentIndex += 1;
      }
    }
   
    return items;
  }

  function fetchMarketItems() public view returns (MarketItem[] memory) {
    uint itemCount = _itemIds.current();
    uint unsoldItemCount = _itemIds.current() - _itemsSold.current();
    uint currentIndex = 0;

    MarketItem[] memory items = new MarketItem[](unsoldItemCount);
    for (uint i = 0; i < itemCount; i++) {
      if (idToMarketItem[i + 1].owner == address(this)) {
        uint currentId = idToMarketItem[i + 1].itemId;
        MarketItem storage currentItem = idToMarketItem[currentId];
        items[currentIndex] = currentItem;
        currentIndex += 1;
      }
    }
   
    return items;
  }

  function fetchMyNFTs() public view returns (MarketItem[] memory) {
    uint totalItemCount = _itemIds.current();
    uint itemCount = 0;
    uint currentIndex = 0;

    for (uint i = 0; i < totalItemCount; i++) {
      if (idToMarketItem[i + 1].seller == msg.sender && idToMarketItem[i + 1].owner == address(this) && idToMarketItem[i + 1].sold == true) {
        itemCount += 1;
      }
    }

    MarketItem[] memory items = new MarketItem[](itemCount);
    for (uint i = 0; i < totalItemCount; i++) {
      if (idToMarketItem[i + 1].seller == msg.sender && idToMarketItem[i + 1].owner == address(this) && idToMarketItem[i + 1].sold == true) {
        uint currentId = idToMarketItem[i + 1].itemId;
        MarketItem storage currentItem = idToMarketItem[currentId];
        items[currentIndex] = currentItem;
        currentIndex += 1;
      }
    }
   
    return items;
  }
  
      function withdraw() public payable  {
          require(msg.sender ==owner, "Only ownercan withdraw the Money");
    require(payable(msg.sender).send(address(this).balance));
  }
  
    function contractBalance () public view returns (uint256) {
   uint256  balancecontract = address(this).balance;
      return balancecontract;
  }
}
