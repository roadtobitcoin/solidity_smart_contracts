pragma solidity ^0.8.0;
//SPDX-License-Identifier: MIT

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/utils/Context.sol";
//import "@openzeppelin/contracts/access/Ownable.sol";

contract NFTMarket is ReentrancyGuard,Pausable {
  using Counters for Counters.Counter;
  Counters.Counter private _itemIds;
  Counters.Counter private _itemsSold;

    address payable owner;
    uint256 marketplaceShare = 1 ether; // minimum price, change for what you want
    uint256 public totalSaleitems = 0;
    address  public  contractaddress = address(this);

    constructor() Pausable(){
    owner = payable(msg.sender);
    }
    
    modifier ValidCombinationOfOrder(address nftContract, uint256 tokenId, uint256 itemId) {
    require(nftContract == idToMarketItem[itemId].nftContract && tokenId == idToMarketItem[itemId].tokenId && itemId == idToMarketItem[itemId].itemId, 
        "Sorry! tokenID & itemID combination you are trying is not valid.");
    require(idToMarketItem[itemId].sold == true &&  idToMarketItem[itemId].removedFromMarketplace == false, 
        "Sorry! this itemId & tokenId combination is not anymore for sale on this marketplace");
        _;
    }
    
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

    struct BidDetails {
        uint256 itemId;
        uint256 tokenId;
        address nftContract;
        address payable bidder;
        uint256 price;
    }

  mapping (address => mapping(uint256 =>BidDetails)) public bidToItemID;

  
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

    function getMarketplaceShare() public view returns (uint256) {
        return marketplaceShare;
    }
          /* Function to update the marketplace fees */
    function updateMarketplaceShare(uint _marketplaceShare) public  {
        require (msg.sender == owner, "Only Owner can call this");
         marketplaceShare = _marketplaceShare;
    }

    /* Listing NFT to the Marketplace */
  function createMarketItem(address nftContract, uint256 tokenId,    uint256 price
  ) public  nonReentrant whenNotPaused {
      /* Check if marketplaceShare is provided, this revenue will go to Marketplace Owner*/
    require(price > marketplaceShare, "Price must be above the listing fees");
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
    /* change the NFT ownership from owner to MarketAddress */
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
  event Bidsubmitted (address indexed nftContract, uint256 tokenId, uint256 itemId, address indexed Bidder, uint256 bidAmount);
  
    /* Function to place the bid on any token on marketplace */
  function placebid (address nftContract, uint256 tokenId, uint256 itemId) 
    public payable whenNotPaused ValidCombinationOfOrder( nftContract,  tokenId,  itemId){
      require(idToMarketItem[itemId].seller != msg.sender, "Sorry! seller can't place the bid on his own order");
      require(msg.value >= marketplaceShare && msg.value > bidToItemID[nftContract][tokenId].price, "Keep Bid price greater than last bid on this token");

    if
    (_bidderHasABid(nftContract, itemId, msg.sender ) == false ) {
        revert("your Bid is already in place for this token");
    } else  {
      
     _cancelBid( nftContract, tokenId,  itemId);
       
      bidToItemID[nftContract][itemId] =  BidDetails(
      itemId,
      tokenId,
      nftContract,
      payable(msg.sender),
      msg.value
      );
    }
    emit Bidsubmitted(nftContract, tokenId, itemId, msg.sender, msg.value);
    }
    
    event cancelledBidSucess(uint256 tokenId, uint256 itemId, address indexed cancelledbidderaddress,uint256 cancelledBidprice, address indexed cancelledBy );
     
    function _cancelBid(address nftContract, uint256 tokenId,  uint256 itemId) internal {
          uint256 cancelledBidprice = bidToItemID[nftContract][itemId].price;
          address payable cancelledbidder = bidToItemID[nftContract][itemId].bidder;
    
         require(cancelledBidprice <= address(this).balance);
        (bool success, ) = payable(cancelledbidder).call{value: cancelledBidprice}("");
        require(success, "Could not send value!");
        delete bidToItemID[nftContract][itemId];

        emit cancelledBidSucess (tokenId, itemId,  cancelledbidder, cancelledBidprice, msg.sender);
    }
  
    /* Function to cancel any placed bid by bidder */
    function cancelBid(address nftContract, uint256 tokenId,  uint256 itemId) public whenNotPaused 
         ValidCombinationOfOrder( nftContract,  tokenId,  itemId) {
        
        BidDetails memory bid = bidToItemID[nftContract][itemId];
        require(bid.bidder == msg.sender || msg.sender == owner,"Marketplace: Unauthorized sender to cancel the Bid!");
        _cancelBid( nftContract, tokenId,  itemId);
        }
         
           /* Internal function to check wheather bidder placed the bid or not for any given token */
    function _bidderHasABid(address nftContract, uint256 itemId, address bidder) internal view returns (bool)    {
         
         BidDetails  memory bidDetails  = bidToItemID[nftContract][itemId];
         if ( bidDetails.bidder == bidder) {
         return false;
         }
          else {
          return true;
               }
             
    }
    
   event BidAccepted (address indexed nftContract, uint256 tokenId, uint256 itemId, address indexed seller, 
   address indexed Bidder, uint256 NFTSoldPrice, uint256 sellerReceviedAmount );
  
      /* Function to accept  any bid placed on marketplace */
   function acceptBid (address nftContract, uint256 tokenId, uint256 itemId) public nonReentrant whenNotPaused
        ValidCombinationOfOrder( nftContract,  tokenId,  itemId) {
        require(idToMarketItem[itemId].seller == msg.sender, "Only Seller can accept Bid for the token");
        uint256 price = bidToItemID[nftContract][itemId].price;
        address payable tokenPurchaser = bidToItemID[nftContract][itemId].bidder;

        idToMarketItem[itemId].sold = true;

         uint saleAmount = price - marketplaceShare;
        /* Transfer sold value to seller */
        idToMarketItem[itemId].seller.transfer(saleAmount);
        //payable(contractaddress).transfer(marketplaceShare);
        /* Transfer token to new owner/bidder */
        IERC721(nftContract).transferFrom(address(this), tokenPurchaser, tokenId);
        idToMarketItem[itemId].owner = payable(tokenPurchaser);
        idToMarketItem[itemId].sold = false;
        idToMarketItem[itemId].removedFromMarketplace = false;
        
         _itemsSold.increment();
        totalSaleitems++; 
        delete bidToItemID[nftContract][itemId];
        emit BidAccepted(nftContract, tokenId, itemId, msg.sender, tokenPurchaser, price, saleAmount);
    }
      
      event removedNFTfromSale(address indexed nftContract, uint256 tokenId, uint256 itemId, address indexed cancelledUser);
      
        /* To remove an item from marketplace */
      function removeMarketItem(address nftContract, uint256 tokenId,  uint256 itemId) public nonReentrant whenNotPaused 
        ValidCombinationOfOrder( nftContract,  tokenId,  itemId) {
        require(idToMarketItem[itemId].seller == msg.sender, "you are not owner of this token");
         
       // uint tokenId = idToMarketItem[itemId].tokenId;
         idToMarketItem[itemId].sold = true;
    
          /* Transfer token to new owner */
        IERC721(nftContract).transferFrom(address(this), msg.sender, tokenId);
        idToMarketItem[itemId].owner = payable(msg.sender);
        idToMarketItem[itemId].sold = false;
        idToMarketItem[itemId].removedFromMarketplace = true;
         _itemsSold.increment();
         _cancelBid(nftContract,  tokenId,  itemId);
         // delete bidToItemID[tokenId];
         emit removedNFTfromSale(nftContract, tokenId, itemId, msg.sender );
      }
  
  event soldNFT(address indexed nftContract, uint256 tokenId, uint256 itemId, address indexed buyer, address indexed previousOwner,
   uint256 NFTsoldAmount, uint256 buyerReceviedAmount);
    
    /* sellContract　createMarketSale - to sell any item*/
      function createMarketSale(address nftContract, uint256 tokenId,  uint256 itemId) public payable nonReentrant whenNotPaused 
        ValidCombinationOfOrder( nftContract,  tokenId,  itemId)
               {
    require (msg.sender != idToMarketItem[itemId].seller, "Try removeMarketItem option instead of purchasing your own placed token");
            /* check if buyer has provided paied enough balance */
        uint price = idToMarketItem[itemId].price;
        //uint tokenId = idToMarketItem[itemId].tokenId;
        require(msg.value >= price, "Please submit the asking price in order to complete the purchase");
         idToMarketItem[itemId].sold = true;
    
        uint saleAmount = msg.value - marketplaceShare;
        address payable previousOwner = idToMarketItem[itemId].seller;
    /* Transfer sold value to seller */
        previousOwner.transfer(saleAmount);
        
        /* Transfer token to new owner */
        IERC721(nftContract).transferFrom(address(this), msg.sender, tokenId);
        idToMarketItem[itemId].owner = payable(msg.sender);
        idToMarketItem[itemId].sold = false;
        idToMarketItem[itemId].removedFromMarketplace = false;
        
         _itemsSold.increment();
       totalSaleitems++;
       _cancelBid( nftContract, tokenId,  itemId);
       // delete bidToItemID[tokenId];
    emit soldNFT (nftContract, tokenId, itemId, msg.sender, previousOwner, price, saleAmount);    
      }
  
        function getMarketItem(uint256 marketItemId) public view returns (MarketItem memory) {
        return idToMarketItem[marketItemId];
      }
    
      function fetchMarketItem(uint256 itemId) public view returns (MarketItem memory) {
        MarketItem memory item = idToMarketItem[itemId];
        return item;
      }
              /* Returns only items that are sold within marketsale */
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
          /* Returns only items that placed on marketsale  for Sale */
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
      
        /* Returns only items that placed on marketsale  for Sale by nftContract */
      function fetchMarketItemsbyNftAddress(address nftContract) public view returns (MarketItem[] memory) {
        uint itemCount = _itemIds.current();
        uint unsoldItemCount = _itemIds.current() - _itemsSold.current();
        uint currentIndex = 0;
    
        MarketItem[] memory items = new MarketItem[](unsoldItemCount);
        for (uint i = 0; i < itemCount; i++) {
          if (idToMarketItem[i + 1].owner == address(this) && idToMarketItem[i + 1].nftContract == nftContract) {
            uint currentId = idToMarketItem[i + 1].itemId;
            MarketItem storage currentItem = idToMarketItem[currentId];
            items[currentIndex] = currentItem;
            currentIndex += 1;
          }
        }
       
        return items;
      }

          /* Returns only items that a user has purchased */
      function fetchMyNFTsSoldbyThis() public view returns (MarketItem[] memory) {
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
  
    /* Returns only items that a user has purchased  --shown by nftContract*/
      function fetchMyNFTsSoldbyThisMarketplace(address nftContract) public view returns (MarketItem[] memory) {
        uint totalItemCount = _itemIds.current();
        uint itemCount = 0;
        uint currentIndex = 0;
    
        for (uint i = 0; i < totalItemCount; i++) {
          if (idToMarketItem[i + 1].seller == msg.sender && idToMarketItem[i + 1].owner == address(this) && idToMarketItem[i + 1].sold == true && idToMarketItem[i + 1].nftContract == nftContract) {
            itemCount += 1;
          }
        }
        
        MarketItem[] memory items = new MarketItem[](itemCount);
        for (uint i = 0; i < totalItemCount; i++) {
          if (idToMarketItem[i + 1].seller == msg.sender && idToMarketItem[i + 1].owner == address(this) && idToMarketItem[i + 1].sold == true && idToMarketItem[i + 1].nftContract == nftContract) {
            uint currentId = idToMarketItem[i + 1].itemId;
            MarketItem storage currentItem = idToMarketItem[currentId];
            items[currentIndex] = currentItem;
            currentIndex += 1;
          }
        }
       
        return items;
      }
      
       /* Returns only items a user has created */
      function fetchItemsCreated() public view returns (MarketItem[] memory) {
        uint totalItemCount = _itemIds.current();
        uint itemCount = 0;
        uint currentIndex = 0;
    
        for (uint i = 0; i < totalItemCount; i++) {
          if (idToMarketItem[i + 1].seller == msg.sender && idToMarketItem[i + 1].sold == true && idToMarketItem[i + 1].removedFromMarketplace == false ) {
            itemCount += 1;
          }
        }
    
        MarketItem[] memory items = new MarketItem[](itemCount);
        for (uint i = 0; i < totalItemCount; i++) {
          if (idToMarketItem[i + 1].seller == msg.sender && idToMarketItem[i + 1].sold == true && idToMarketItem[i + 1].removedFromMarketplace == false) {
            uint currentId = i + 1;
            MarketItem storage currentItem = idToMarketItem[currentId];
            items[currentIndex] = currentItem;
            currentIndex += 1;
          }
        }
        return items;
      }
  

      /* Returns bid placed by any given address for any token ID*/
      function tokenIDonSale() public view returns (uint256[] memory) {
        uint itemCount = _itemIds.current();
        uint unsoldItemCount = _itemIds.current() - _itemsSold.current();
        uint currentIndex = 0;
    
        uint256[] memory items = new uint256[](unsoldItemCount);
        for (uint i = 0; i < itemCount; i++) {
          if (idToMarketItem[i + 1].owner == address(this)) {
            items[i] = idToMarketItem[i + 1].tokenId;
            

            currentIndex += 1;
          }
        }
       return items;
      }


  
        function contractBalance () public view returns (uint256) {
        uint256  balancecontract = address(this).balance;
        return balancecontract;
  }
  
        function setPaused(bool _setPaused) public  {
        require(msg.sender == owner , "Only Owner can Puase the contract");
        return (_setPaused) ? _pause() : _unpause();
    }
    
       function withdraw() public payable  {
     require(msg.sender == owner , "Only Owner can Puase the contract");
    require(payable(msg.sender).send(address(this).balance));
  }

                 /* Returns only items that placed on marketsale  for Sale */
      function bidderbid(address nftContract) public view returns (BidDetails[] memory) {
    uint totalItemCount = _itemIds.current();
    uint itemCount = 0;
    uint currentIndex = 0;

        for (uint i = 0; i < totalItemCount; i++) {
      if (bidToItemID[nftContract][i + 1].bidder == msg.sender && bidToItemID[nftContract][i + 1].nftContract == nftContract
          && bidToItemID[nftContract][i + 1].bidder != address(0)) {
        itemCount += 1;
      }
    }
    
        BidDetails[] memory items = new BidDetails[](itemCount);
        for (uint i = 0; i < totalItemCount; i++) {
          if (bidToItemID[nftContract][i + 1].bidder == msg.sender && bidToItemID[nftContract][i + 1].nftContract == nftContract
          && bidToItemID[nftContract][i + 1].bidder != address(0))
          //&& idToMarketItem[i + 1].sold == true && idToMarketItem[i + 1].removedFromMarketplace == false 
           {
            uint currentId = bidToItemID[nftContract][i + 1].itemId;
            BidDetails storage currentItem = bidToItemID[nftContract][currentId];
            items[currentIndex] = currentItem;
            currentIndex += 1;
          }
        }
       
        return items;
      } 

}

