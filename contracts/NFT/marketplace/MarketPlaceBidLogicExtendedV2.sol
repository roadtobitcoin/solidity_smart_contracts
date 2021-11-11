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
    uint256 listingPrice = 1 ether; // minimum price, change for what you want
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
        uint256 bidID;
        address nftContract;
        address payable bidder;
        uint256 price;
    }

mapping (address => mapping(uint256 =>BidDetails)) public bidtoTokenID;

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
  ) public  nonReentrant whenNotPaused {
      /* Check if listingPrice is provided, this revenue will go to Marketplace Owner*/
    require(price > listingPrice, "Price must be above the listing fees");
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
  event Bidsubmitted (address indexed nftContract, uint256 tokenId, uint256 itemId, address indexed Bidder, uint256 bidAmount);
  
  function placebid (address nftContract, uint256 tokenId, uint256 itemId) 
    public payable whenNotPaused ValidCombinationOfOrder( nftContract,  tokenId,  itemId){
      require(idToMarketItem[itemId].seller != msg.sender, "Sorry! seller can't place the bid on his own order");
      require(msg.value >= listingPrice && msg.value > bidtoTokenID[nftContract][tokenId].price, "Keep Bid price greater than last bid on this token");

    if
    (_bidderHasABid(nftContract, tokenId, msg.sender ) == false ) {
        revert("your Bid is already in place for this token");
    } else  {
      
     _cancelBid( nftContract, tokenId,  itemId);
       
      bidtoTokenID[nftContract][tokenId] =  BidDetails(
      itemId,
      nftContract,
      payable(msg.sender),
      msg.value
      );
    }
    emit Bidsubmitted(nftContract, tokenId, itemId, msg.sender, msg.value);
    }
    
    function _getValidOrder(address _nftAddress, uint256 itemId)
            internal view returns (MarketItem memory marketItem) {
        marketItem = idToMarketItem[itemId];
        require (idToMarketItem[itemId].nftContract == _nftAddress, "Invalid contract address to bid" );
        require(idToMarketItem[itemId].sold == true && idToMarketItem[itemId].removedFromMarketplace == false, "Invalid itemdId to bid token");
    }
    
    event cancelledBidSucess(uint256 tokenId, uint256 itemId, address indexed cancelledbidderaddress,uint256 cancelledBidprice, address indexed cancelledBy );
     
    function _cancelBid(address nftContract, uint256 tokenId,  uint256 itemId) internal {
          uint256 cancelledBidprice = bidtoTokenID[nftContract][tokenId].price;
          address payable cancelledbidder = bidtoTokenID[nftContract][tokenId].bidder;
    
         require(cancelledBidprice <= address(this).balance);
        (bool success, ) = payable(cancelledbidder).call{value: cancelledBidprice}("");
        require(success, "Could not send value!");
        delete bidtoTokenID[nftContract][tokenId];

        emit cancelledBidSucess (tokenId, itemId,  cancelledbidder, cancelledBidprice, msg.sender);
    }
  
  
    function cancelBid(address nftContract, uint256 tokenId,  uint256 itemId) public whenNotPaused 
         ValidCombinationOfOrder( nftContract,  tokenId,  itemId) {
        
        BidDetails memory bid = bidtoTokenID[nftContract][tokenId];
        require(bid.bidder == msg.sender || msg.sender == owner,"Marketplace: Unauthorized sender to cancel the Bid!");
        _cancelBid( nftContract, tokenId,  itemId);
        }
         
    function _bidderHasABid(address nftContract, uint256 tokenId, address bidder) internal view returns (bool)    {
         
         BidDetails  memory bidDetails  = bidtoTokenID[nftContract][tokenId];
         if ( bidDetails.bidder == bidder) {
         return false;
         }
          else {
          return true;
               }
             
    }
    
   event BidAccepted (address indexed nftContract, uint256 tokenId, uint256 itemId, address indexed seller, 
   address indexed Bidder, uint256 NFTSoldPrice, uint256 sellerReceviedAmount );
  
   function acceptBid (address nftContract, uint256 tokenId, uint256 itemId) public nonReentrant whenNotPaused
        ValidCombinationOfOrder( nftContract,  tokenId,  itemId) {
        require(idToMarketItem[itemId].seller == msg.sender, "Only Seller can accept Bid for the token");
        uint256 price = bidtoTokenID[nftContract][tokenId].price;
        address payable tokenPurchaser = bidtoTokenID[nftContract][tokenId].bidder;

        idToMarketItem[itemId].sold = true;

         uint saleAmount = price - listingPrice;
        /* Transfer sold value to seller */
        idToMarketItem[itemId].seller.transfer(saleAmount);
        //payable(contractaddress).transfer(listingPrice);
        /* Transfer token to new owner/bidder */
        IERC721(nftContract).transferFrom(address(this), tokenPurchaser, tokenId);
        idToMarketItem[itemId].owner = payable(tokenPurchaser);
        idToMarketItem[itemId].sold = false;
        idToMarketItem[itemId].removedFromMarketplace = false;
        
         _itemsSold.increment();
        totalSaleitems++; 
        delete bidtoTokenID[nftContract][tokenId];
        emit BidAccepted(nftContract, tokenId, itemId, msg.sender, tokenPurchaser, price, saleAmount);
    }
      
      event removedNFTfromSale(address indexed nftContract, uint256 tokenId, uint256 itemId, address indexed cancelledUser);
      
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
         // delete bidtoTokenID[tokenId];
         emit removedNFTfromSale(nftContract, tokenId, itemId, msg.sender );
      }
  event soldNFT(address indexed nftContract, uint256 tokenId, uint256 itemId, address indexed buyer, address indexed previousOwner,
   uint256 NFTsoldAmount, uint256 buyerReceviedAmount);
    /* sellContract　createMarketSale */
      function createMarketSale(address nftContract, uint256 tokenId,  uint256 itemId) public payable nonReentrant whenNotPaused 
        ValidCombinationOfOrder( nftContract,  tokenId,  itemId)
               {
    require (msg.sender != idToMarketItem[itemId].seller, "Try removeMarketItem option instead of purchasing your own placed token");
            /* check if buyer has provided paied enough balance */
        uint price = idToMarketItem[itemId].price;
        //uint tokenId = idToMarketItem[itemId].tokenId;
        require(msg.value >= price, "Please submit the asking price in order to complete the purchase");
         idToMarketItem[itemId].sold = true;
    
        uint saleAmount = msg.value - listingPrice;
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
       // delete bidtoTokenID[tokenId];
    emit soldNFT (nftContract, tokenId, itemId, msg.sender, previousOwner, price, saleAmount);    
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
  
        function setPaused(bool _setPaused) public  {
        require(msg.sender == owner , "Only Owner can Puase the contract");
        return (_setPaused) ? _pause() : _unpause();
    }
}
