# Changelog

## 2.3.0

- Add optional Sintezza Perf developer measurements for loot review.
- Dim excluded items in the loot review.
- Allow non-equipment items when equipment-set membership is unavailable, and explain blocked selections in the review. Tint items the vendor will not buy red.
- Save merchant IDs in new journal entries and look up their names in the client when available.
- Show the item in purchase and buyback confirmations, and list each stack and its price in a themed, scrollable sale confirmation.
- Allow manual selection of crafting materials, with an optional protection toggle; automatic selection and junk sales continue to skip them. Add help for sale settings.
- Preload journal item names in the current client language so saved names from another language do not flash while browsing.
- Match the exclusions button height to the settings button in the merchant header.
- Record confirmed manual bag sales at merchants in the journal. Display item names in the current client language when available, and restore the version beside the merchant window title.

## 2.2.0

- The settings header shows the addon version.
- The merchant window shows the version beside the title.
- Made the purchase limit field more compact and added a gold coin icon.
- Reduced repeated bag scans and stabilized the exclusions list while item information loads.
- Shortened the purchase-limit field and moved its explanation to a help tooltip.
- Made exclusions compact with item icons and quality colors, and added a shortcut in the merchant window.
- Moved all selling options into one list and clarified the binding filter.
- Automatically exclude recognized profession tools in bags for each character, announce additions in chat, and preserve manual removals.
- Left-clicking the minimap icon opens or closes the window.
- Connected window scale, opacity, and layer to the shared Theme settings. The WoW AddOns settings launcher uses the shared Theme helper.
- Updated the project logo and in-game addon icon.
- Use Sintezza Disenchant estimates and restrictions whenever their API functions are available.

## 2.1.18

- Mastercraft recommendations in Loot Review follow the selected Sintezza language.

## 2.1.17

- Integrated Loot Review as a merchant tab and removed the Bags tab, bulk sales by quality, and catalogue drop-down filters.
- Use Sintezza Disenchant's restrictions when comparing loot values.

## 2.1.16

- Added themed hints for quick-sale confirmations and the sale binding filter.

## 2.1.15

- Added a **Last sale** shortcut to the catalogue footer. It shows the latest sold stack and its price, and advances after a confirmed buyback.

## 2.1.14

- Corrected auction and disenchant estimates from Mastercraft when its auction-fee option is disabled. Loot Review now accounts for the 5% fee once.
- Ignore incomplete or malformed Mastercraft price data and use a fallback estimate when one is available.
- Added the MIT license and updated the installation, usage, and integration documentation.
