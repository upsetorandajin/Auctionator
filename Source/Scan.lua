-- TODO is all this shit needed?
local addonName, addonTable = ...
local ZT = addonTable.ztt.ZT
local zc = addonTable.zc
local zz = zc.md
local _

Auctionator.Scan = {
  IDstring = '',
  itemName = nil,
  itemLinkd = nil,
  scanData = {},
  sortedData = {},
  whenScanned = 0,
  lowprice = Auctionator.Constants.BigNum,
  absoluteBest = nil,
  itemClass = 0,
  itemSubclass = 0,
  itemLevel = 0,
  yourBestPrice = nil,
  yourWorstPrice = nil,
  itemTextColor = { 1.0, 1.0, 1.0 },
  searchText = nil,
  bidIndex = {}
}

function Auctionator.Scan:new( options )
  options = options or {}
  setmetatable( options, self )
  self.__index = self

  return options
end

function Auctionator.Scan:UpdateItemLink( itemLink )
  -- Auctionator.Debug.Message( itemLink )

  if itemLink and self.itemLink == nil then

    self.itemLink = itemLink

    local _, quality, iLevel, sType, sSubType

    if zc.IsBattlePetLink( itemLink ) then

      local speciesID, level, breedQuality = zc.ParseBattlePetLink (itemLink)

      iLevel  = level
      quality = breedQuality

      self.itemClass    = LE_ITEM_CLASS_BATTLEPET
      self.itemSubclass = 0

    else
      Auctionator.Util.Print( { GetItemInfo( itemLink ) }, 'GET ITEM INFO' .. itemLink )

      _, _, quality, iLevel, _, sType, sSubType, _, _, _, _, itemClass, itemSubClass = GetItemInfo(itemLink)

      self.itemClass    = itemClass
      self.itemSubclass = itemSubClass
    end

    self.itemQuality  = quality
    self.itemLevel    = iLevel

    self.itemTextColor = { 0.75, 0.75, 0.75 }

    -- TODO jesus this should be a lookup table
    if quality == 0 then self.itemTextColor = { 0.6, 0.6, 0.6 } end
    if quality == 1 then self.itemTextColor = { 1.0, 1.0, 1.0 } end
    if quality == 2 then self.itemTextColor = { 0.2, 1.0, 0.0 } end
    if quality == 3 then self.itemTextColor = { 0.0, 0.5, 1.0 } end
    if quality == 4 then self.itemTextColor = { 0.7, 0.3, 1.0 } end
  end

end

-- TODO I *think* I only want to do this when curpage and indexonpage are passed
-- Not terribly certain that I'll always get these, and not certain that they
-- correspond to what I think they do. Yay code spikes
function Auctionator.Scan:AddToBidIndex( buyoutPrice, stackSize, page, index )
  if page == nil or index == nil then
    return
  end

  local key = buyoutPrice .. '-' .. stackSize

  if self.bidIndex[ key ] == nil then
    self.bidIndex[ key ] = { count = 0, entries = {} }
  end

  self.bidIndex[ key ].count = self.bidIndex[ key ].count + 1
  table.insert( self.bidIndex[ key ].entries, {
    page = page,
    index = index
  })
end

function Auctionator.Scan:AddScanItem( stackSize, buyoutPrice, owner, numAuctions, curpage, indexOnPage )
  Auctionator.Debug.Message( 'Auctionator.Scan:AddScanItem', stackSize, buyoutPrice, owner, numAuctions, curpage, indexOnPage )

  local sd = {}
  local i

  if numAuctions == nil then
    numAuctions = 1
  end

  self:AddToBidIndex( buyoutPrice, stackSize, curpage, indexOnPage )

  for i = 1, numAuctions do
    sd["stackSize"] = stackSize
    sd["buyoutPrice"] = buyoutPrice
    sd["owner"] = owner
    sd["pagenum"] = curpage

    tinsert( self.scanData, sd )

    if buyoutPrice and buyoutPrice > 0 then
      local itemPrice = math.floor( buyoutPrice / stackSize )

      self.lowprice = math.min( self.lowprice, itemPrice )
    end
  end

end

function Auctionator.Scan:SubtractScanItem( stackSize, buyoutPrice )
  local sd
  local i

  for i, sd in ipairs( self.scanData ) do
    if sd.stackSize == stackSize and sd.buyoutPrice == buyoutPrice then
      tremove (self.scanData, i)
      return
    end
  end
end

function Auctionator.Scan:CondenseAndSort()
  -- Condense the scan data into a table that has only a single entry per
  -- stacksize/price combo
  self.sortedData = {}

  local i,sd
  local conddata = {}

  for i, sd in ipairs( self.scanData ) do

    local ownerCode = "x"
    local dataType  = "n"    -- normal

    if (sd.owner == UnitName("player")) then
      ownerCode = "y"
    end

    local key = "_" .. sd.stackSize .. "_" .. sd.buyoutPrice .. "_" .. ownerCode .. dataType

    if conddata[ key ] then
      conddata[ key ].count = conddata[ key ].count + 1
    else
      local data = {}

      data.stackSize = sd.stackSize
      data.buyoutPrice = sd.buyoutPrice
      data.itemPrice = sd.buyoutPrice / sd.stackSize
      data.count = 1
      data.type = dataType
      data.yours = ownerCode == "y"

      if ownerCode ~= "x" and ownerCode ~= "y" then
        data.altname = ownerCode
      end

      if sd.volume then
        data.volume = sd.volume
      end

      conddata[ key ] = data
    end
  end

  ----- create a table of these entries
  local n = 1
  local i, v

  for i, v in pairs( conddata ) do
    self.sortedData[ n ] = v
    n = n + 1
  end

  -- sort the table by itemPrice
  table.sort( self.sortedData, function( a, b ) return a.itemPrice < b.itemPrice end )

  -- analyze and store some info about the data
  self:AnalyzeSortData()
end

function Auctionator.Scan:AnalyzeSortData()
  self.absoluteBest = nil
  -- a table with one entry per stacksize that is the cheapest auction for that
  -- particular stacksize
  self.bestPrices = {}
  self.numMatches = 0
  self.numMatchesWithBuyout = 0
  self.hasStack = false
  self.yourBestPrice = nil
  self.yourWorstPrice = nil

  local j, sd

  ----- find the best price per stacksize and overall -----
  for j, sd in ipairs( self.sortedData ) do

    if sd.type == "n" then
      self.numMatches = self.numMatches + 1

      if sd.itemPrice > 0 then
        self.numMatchesWithBuyout = self.numMatchesWithBuyout + 1

        if self.bestPrices[ sd.stackSize ] == nil or self.bestPrices[ sd.stackSize ].itemPrice >= sd.itemPrice then
          self.bestPrices[ sd.stackSize ] = sd
        end

        if self.absoluteBest == nil or self.absoluteBest.itemPrice > sd.itemPrice then
          self.absoluteBest = sd
        end

        if sd.your then
          if self.yourBestPrice == nil or self.yourBestPrice > sd.itemPrice then
            self.yourBestPrice = sd.itemPrice
          end

          if self.yourWorstPrice == nil or self.yourWorstPrice < sd.itemPrice then
            self.yourWorstPrice = sd.itemPrice
          end

        end
      end

      if sd.stackSize > 1 then
        self.hasStack = true
      end
    end
  end
end

function Auctionator.Scan:FindInSortedData( stackSize, buyoutPrice )
  local j = 1
  for j = 1, #self.sortedData do
    sd = self.sortedData[ j ]
    if sd.stackSize == stackSize and sd.buyoutPrice == buyoutPrice and sd.yours then
      return j
    end
  end

  return 0
end

function Auctionator.Scan:FindMatchByStackSize( stackSize )
  local index = nil
  local basedata = self.absoluteBest

  if self.bestPrices[ stackSize ] then
    basedata = self.bestPrices[ stackSize ]
  end

  local numrows = #self.sortedData
  local n

  for n = 1, numrows do
    local data = self.sortedData[n]

    if basedata and data.itemPrice == basedata.itemPrice and data.stackSize == basedata.stackSize and data.yours == basedata.yours then
      index = n
      break
    end
  end

  return index
end

function Auctionator.Scan:FindMatchByYours()
  Auctionator.Debug.Message( 'Auctionator.Scan:FindMatchByYours' )

  local index = nil
  local j

  for j = 1, #self.sortedData do
    sd = self.sortedData[ j ]

    if sd.yours then
      index = j
      break
    end
  end

  return index
end


function Auctionator.Scan:FindCheapest()
  Auctionator.Debug.Message( 'Auctionator.Scan:FindCheapest' )

  local index = nil
  local j

  for j = 1, #self.sortedData do
    sd = self.sortedData[ j ]

    if sd.itemPrice > 0 then
      index = j
      break
    end
  end

  return index
end


-----------------------------------------

function Auctionator.Scan:GetNumAvailable()
  local num = 0

  local j, data
  for j = 1, #self.sortedData do

    data = self.sortedData[ j ]
    num = num + ( data.count * data.stackSize )
  end

  return num
end

-----------------------------------------

function Auctionator.Scan:IsNil()
  return self.itemName == nil or self.itemName == "" or self.itemName == "nil"
end