# RUIN Exchange

RUIN's shared market knowledge: auction prices with a 7-day trend, a directory of who can craft what, the cheapest way to level your profession, a craft request board, and a bag sweep.

Part of the **RUIN Gaming Companion App**. Requires **RUIN Core** (0.3.16 or later). With **RUIN Codex** installed, the bag sweep keeps items that are upgrades for you.

## The experience
- **Where it lives:** the Exchange tab in the RUIN window (Search, Requests, Leveling, Bags, Treasury, History), item tooltips, and `/ex`.
- **Prices:** browse the auction house as usual; prices you saw are shared when you close it. Tooltips show the RUIN price, the 7-day average with its trend, and whether to sell or vendor.
- **Crafters:** opening a profession window shares your recipes, with the item each makes and its quality. At login Exchange shares the recipes it already knows and offers *Add your recipes* for professions it hasn't read yet (or that went up): one click each opens the profession, reads it and closes it, since the game lists recipes only while that window is open. *Find: Crafters* lists them by profession: each recipe (the item in its quality color), the RUIN member who can craft it, and the item's quality. Narrow it with a search or one profession, and whisper the crafter.
- **Leveling:** opening a profession also ranks your orange, yellow and green recipes by expected cost per skill point from RUIN prices. Hover one for its reagents.
- **Requests:** post what you need made, with a note ("have mats, 5g tip"). Members who know the recipe get an alert. Requests close after a day, or when you press Done.
- **Bag sweep:** *Sweep bags* labels every item Keep, Sell (AH), Vendor or Check AH, with totals.
- **Treasury:** your guild's treasurer (whoever holds the Treasurer office on Guild → People, or the guild master) keeps a book of the gold members give. Gold traded or mailed to the treasurer is written down by itself (auction house mail isn't); *Add entry* adds the rest (`50, Grimlock, raid repairs`, or `-20, ...` for gold paid out). The guild sees the book, this week's and all-time totals, the top givers (*Show: Givers*) and the guild bank's gold as last seen.
- **History:** when you trade someone an item you can craft, or enchant their item in the trade window, Exchange asks them to confirm the craft (*Log a craft* does it by hand: `Robe of Power, Grimlock`). Once they confirm, the whole org's History has it, and crafters are ranked by confirmed crafts this month. Only the customer can confirm.
- **Commands:** `/ex <search>`, `/ex request <item> -- <note>`, `/ex bags`, `/ex treasury`, `/ex history`.

## What it shares with RUIN
Lowest unit prices you saw (when you close the auction house), your recipe names per profession with the item each makes and its quality, and craft requests you post. The treasurer's book goes to their own guild only; crafts go to the customer to confirm, and confirmed crafts to the org.

## Notes
There is no full-scan button; prices come from what members browse. Price history is kept for 14 days.
