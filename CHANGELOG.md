# RUIN Exchange changelog

Versioning: the third number counts the meaningful changes made since the second number last went up.

## Unreleased

- **Waylaid Crates in the auction house.** The Buy list has a Waylaid Crates category after Miscellaneous, with Apprentice, Journeyman, Expert and Artisan under it and each crate under the tier in its name. Click a crate and the results list every reagent that fills it, while a card beside the auction house shows what each bundle costs with a mark by the cheapest (any one bundle fills the crate); click a bundle on the card to search for just that item. Crates you hover join the list.
- **Fill crates.** A Fill crates button beside your bags (shown while they're open with a Waylaid Crate in them, beside the game's bag windows or a bag addon's such as Baganator, and on a key in Key Bindings > RUIN Exchange) fills the Waylaid Crates in your bags (the reagent bag too, for crates and reagents alike) one click at a time, saying in chat which bundle each gets. Each click uses the crate and picks the reagent for it in the same press: your biggest stack of the bundle worth the least on the auction house among those you carry enough of. The button shows how many crates you can fill and reads Nothing to fill when you're done. `/exchange crates` lists each crate in your bags and what it would be filled with.
- **Bag sweep includes the reagent bag.**
- **Tooltips use the lowest price last seen.** Every Exchange price (the AH line, crate bundles, crafting and disenchanting values) now uses the lowest listing last seen on the auction house; the week's prices only stand in for an item never seen.
- **AH deposit follows the game.** What an item nets on the auction house now takes off a deposit of 15% of its vendor price (at least 1 copper) instead of a flat 1 silver.

## 0.9.0

- **Crate tooltips are sturdier**: if a Waylaid Crate's bundle list can't be worked out, the rest of the RUIN: Exchange box still shows and the error doesn't come back on every hover.
- **Waylaid Crate bundles.** A Waylaid Crate's RUIN: Exchange box lists each bundle it takes ("20 Dreamfoil") with what it costs on the auction house, and the price of one. A reagent with no AH price yet says so. /exchange tipdebug, then hovering a crate, prints what Exchange reads for each bundle.
- **Watch list.** A new Watch tab holds items you want to buy, each with the most you'll pay. *Add my Best in Slot* fills it from RUIN Codex (the pieces that can be traded, with today's price as the limit), or shift-click any item into the box (or `/exchange watch <item> <gold>`). When a price at or under your limit comes in, from your own auction house visit or one another RUIN member shares, Exchange tells you who saw it and for how much (once an hour per item).

- **Crafters summary fits**: in Find: Crafters the summary line keeps just the price and crafter counts, so it is no longer cut off mid-sentence beside Offline crafters and Add my recipes.

## 0.8.10

- **The auction house tooltip no longer bounces or grows a frame after it shows.** The blank line under the Exchange box is now decided once per item (remembered while you play) and the tooltip is resized in place rather than shown a second time, so a list that rebuilds its tooltip every frame keeps one steady size and position.

## 0.8.9

- **The auction house is scanned the whole time it's open.** After the full scan (when the game allows one, every 15 minutes), Exchange searches item by item: first the reagents of the crafts you know, then gear you can use, then everything else it has seen, then round again, skipping what you priced in the last 15 minutes. It searches at most once every 1.5 seconds and only when the game's query throttle is ready, only while you're on the browse list, and never for a few seconds after a search of your own, so your results are never swapped out. The full scan's listings are read within 3 ms a frame. Every price read goes to the org, with no cap: new ones every minute while you scan, the rest when you close. (The Scan & Share button is gone; `/ex scan` still asks for a full scan.)
- **Tidier tooltip lines.** What disenchanting gives sits on the same line as its value ("Disenchant: ~89g 99s · Nexus Crystal"), and a soulbound item says "Soulbound: can't be auctioned".
- **Codex lines under the Exchange box keep their gap.** On the Best in Slot tab, "Codex: your best in slot" no longer sits against the box.

## 0.8.4

- **A piece that binds when picked up** now reads *Binds to you: can't go on the auction house* in the tooltip, instead of calling an item you don't own yet soulbound.
- **Room under the Exchange section** of a tooltip, so a line another addon adds after it (where an item drops) doesn't sit against the box.
- **Price per Point prices reagents at the market.** Each reagent counts at the low end of the week on the auction house (or a merchant's price when cheaper), so one dear listing no longer makes a recipe look like it costs gold per point.
- **Price per Point is the cost of one craft divided by your chance of a point**, where the chance is the recipe's own (from its color) plus Working Overtime's bonus set in Exchange, at most 100%.
- **Hover a recipe's cost per point to see how it's worked out**: each reagent with its price and where the price is from (AH lowest and how long ago, the week's low end, or a merchant), the cost of one craft, the chance of a point with Working Overtime, and the result.

## 0.8.3

- **The AH price follows the auction house.** A price you just saw (a search, a browse row, an item's listings) now replaces the saved one even when it's higher; before, the lowest price of the visit stuck even after listings were bought out. A price seen in the last two hours is the one the tooltip uses (the low end of the week applies once it's older), and Craft uses the same price.
- **Craft counted the wrong number made.** It read the item's quality as how many one craft makes, so a blue item like Spidersilk Boots was treated as three and its margin tripled. It now uses how many the recipe really makes. Open each profession window once to record it.

## 0.8.2

- **The tooltip compares what an item is worth each way**, at the bottom: Vendor, Disenchant or Craft (whichever is worth more) and AH (what it nets after the deposit and cut, with what it lists at). The most is green, the least red and the one between amber. A soulbound item has no AH line.
- **Craft counts everything a recipe takes and looks a step further.** It finds the single most valuable thing your recipes make from the item, through up to three steps (Wool Cloth > Bolt of Woolen Cloth > Greater Adept's Robe). Each step is charged all of the item it uses (three cloth for a bolt) and the other reagents at what they cost to buy, and a product counts at the more of selling it and crafting it on. The line reads like *Craft: ~49s (3 per Bolt of Woolen Cloth > Greater Adept's Robe)*.
- **Craft and Disenchant use the market's prices** (the low end of the last week, like the AH line) rather than whatever single listing was seen last.
- **A craft is never suggested when its reagents sell for more than it does**, at any step: everything a recipe takes is counted at the market's price (or a merchant's, when cheaper), and only the craft with the biggest profit is shown.
- **A stack shows each one's price too** on every line: Vendor, Disenchant or Craft, and AH.
- **Craft shows its margin**: what to make, then *Margin: +X a craft (Y%): sells for Z, takes W*, the profit of crafting it and selling it on the AH after everything it takes.
- The AH line is just its value, without the listing prices after it.
- **A recipe is only priced from its whole reagent list.** A reagent the game hadn't loaded yet used to drop out of the list, so the craft looked far cheaper than it is (Spidersilk Boots from an Iridescent Pearl). Such lists aren't kept now, and the next look at the profession window fills in the whole one.
- **No lag when a tooltip opens**: the tooltip only looks at the recipes that use its item (it went through every recipe you know), and keeps its sums for a few seconds while the tooltip stays up.
- The 7-day average is gone from the tooltip, and a merchant who sells the item for less than the AH reads *Buy from vendor*.

## 0.8.1 — 2026-11-16

- **Soulbound items are never sent to the auction house.** For a soulbound item (or one that binds when picked up, or a quest item) the tooltip leaves out the AH prices and weighs only what's possible: disenchanting, crafting it into something, or selling it to a vendor, and recommends whichever is worth most. A craft's reagents count at what a vendor pays for the soulbound one. The bag sweep labels soulbound items Disenchant, Craft or Vendor the same way.
- A craft that makes a soulbound item is valued at its vendor price, not the auction house's.

## 0.8.0 — 2026-11-15

- **The tooltip's AH price is the low end**: what to expect on the auction house is the lowest of the last 7 days' prices (and today's), leaving out a mispriced listing far below the rest; when the current lowest listing is dearer it's shown as *now*. *Sell on AH* uses it too.
- **Less memory and a smaller saved file**: price history for items you stopped seeing is cleared at login (it was only trimmed when an item was seen again).

## 0.7.0 — 2026-11-12

- **A new look, with the rest of the suite.** Exchange's pages take its amber through and through: the open tab's underline, check marks, the bar on a row under the mouse and the edge a button gets when you point at it. Its header carries a drawing of a price chart with the latest price moving along the trend, and Exchange has its own icon (a merchant's scales) on its tab, its header and in the AddOns list. The Add your recipes window wears the same amber.
- **Security:** shared prices are checked. Another player's auction or vendor price never replaces one you saw yourself lately, an auction price a quarter or four times a recent one is ignored (and kept out of the 7-day average), and a shared vendor price can't undercut a known one by more than reputation could. A craft counts as confirmed only when its crafter logged it (everyone hears the claim) and its customer confirmed it; names are compared in full.
- With the What RUIN shares about you switches off (RUIN Core), Exchange doesn't send your prices or recipes; turning recipes off tells everyone to forget yours.
- **Working Overtime** (the Legacy talent): set your rank (0-5) on the Leveling page or with /ex overtime <rank>. Its +4% a rank is added on top of a yellow or green recipe's skill-up chance (a green at 25% is 45% at rank 5), in every Price per Point. RUIN can't read Legacy talents, so it's a setting.
- The price RUIN keeps is the lowest buyout. Clicking into a commodity or an item now reads every listing, not just the first ones (sorted dearest first, the first listing was the highest price). A look that isn't a full scan (a page of results, a browse, another player's share) no longer replaces a lower price seen in the last 6 hours; after that, or with a full scan, the newer price counts.
- The tooltip's recommendation is colored by what it says: Sell to Vendor stays green, Sell on AH is gold, and Craft and Disenchant are red.

## 0.6.0 — 2026-11-11

- Where to sell now also says **Disenchant** (with the expected value and the likely mat) when what an item breaks into is worth more than selling it, judged only on the mats' value. It uses the classic disenchanting tables by quality and item level, priced from RUIN's AH prices.
- And **Craft** for a reagent when one of your recipes turns it into something that sells for more than its reagents would (on the AH after the cut, or to a vendor): the most profitable one, with what it sells for and how much more that is.
- "Sell on AH" counts the auction house's cost: the deposit (at least 1 silver) and the 5% cut. It shows what you'd net, and recommends the vendor when that pays more. The bag sweep uses the same sums.
- A full auction house scan records the prices of the items in your bags first (as soon as they're read, before the rest) and always shares them.
- Item tooltips end with a RUIN: Exchange section in a box with a faint gold border: the AH price (for the whole stack you're pointing at, with the price each) and how long ago it was seen, a merchant that sells it cheaper ("Vendor: 1s 44c from Trade Goods NPC"), the AH 7-day average, and where to sell the stack: "Sell on AH: ..." or "Sell to Vendor: ...".
- The vendor line names the kind of merchant: "Vendor: 1s 44c from Trade Goods NPC". The merchant's title is kept when you open its window and shared with RUIN; prices seen before this show the merchant's name until you visit again.
- Money shows the game's gold, silver and copper icons instead of g, s and c everywhere in Exchange (needs RUIN Core 0.6.0).

## 0.5.2 — 2026-11-08

- Item names and details come from C_Item when the old global item functions aren't there (the Retail 12 client WoW Forever runs on), so items stop showing as "Loading item...".
- Item names are asked for through RUIN Core's queue, a few at a time.
- Exchange reads WoW Forever's modern auction house properly. Opening the auction house starts a full scan by itself (the game allows one every 15 minutes), which prices every listing at once instead of only what you searched for. `/ex scan` asks for one; `/ex autoscan` turns the automatic scan off or on.
- Clicking into an item or a stack of trade goods also records its cheapest price.
- After a full scan, Exchange shares up to 400 prices with RUIN when you close the auction house, picking the ones RUIN knew least about (new, older than 6 hours, or moved more than 5%), so the guild channel isn't flooded.
- The profession window shows each recipe's Price per Point beside it: one craft's reagents at the cheapest RUIN price (vendor or auction house) divided by the chance it gives a skill point. Orange always gives one and grey never does; between yellow and grey the chance falls in a straight line, `(grey - your skill) / (grey - yellow)`, the Classic rule WoW Forever's leveling calculators use. The game only shows a recipe's color, so RUIN learns where each recipe turns yellow, green and grey from what everyone in the org sees and shares it; until it knows, yellow counts as 3 in 4 and green as 1 in 4, marked with "~". `/ex costs` turns it off or on.
- Recipes you haven't learned are priced at the profession trainer: each recipe in the trainer's list gets its Price per Point (or Price per Craft when RUIN can't tell its color yet) under the training cost. The trainer's skill requirement is where a recipe starts orange, so RUIN notes it; reagents come from your profession window (RUIN remembers every recipe it lists, learned or not) or, failing that, from the trainer's tooltip. Leveling lists unlearned recipes that would give points at your skill as "(not learned)".
- Recipes that would be grey (no skill points) show nothing.
- Recipe items ("Recipe: Tasty Lion Steak") show their Price per Craft in the tooltip, plus the Price per Point at your skill when RUIN can tell (otherwise the price for each color: orange, yellow, green), or the skill you still need to learn it. Reagents come from RUIN's recipe book or the tooltip's own reagent line.
- Vendor prices. Opening a merchant records what it sells for gold (not limited stock or token items) and shares it with RUIN when you close it. A vendor price is used only when it's cheaper than the auction house, or when the auction house has none, and it's always marked: the item tooltip says "Vendor: 10c from Tharynn Bouden, cheaper than the AH (40c)", the Prices list adds "10c at a vendor (Tharynn Bouden)", and Leveling's reagent lines say "(vendor)" and where. Recipe costs and cost per point use the cheaper price.
- The Price per Point is short ("18s/pt", "1g 20s/pt") and a long recipe name, with the "[2]" count of how many you can make, now stops before it ("Enchant Chest - Minor Abso...") instead of running underneath it.
- Searching prices no longer asks the game about every unnamed item at once: names are fetched only while you search, at most 300 waiting.
- Prices show as soon as RUIN has them. Leveling prices your saved recipes from current RUIN prices instead of the prices when you last opened the profession, so "needs prices for 1 reagent" and "One craft: 0c" go away once someone has priced the reagents.
- The Prices list shows the newest 200 of all known prices (with thousands from a full scan it showed a random 200), and asks the game for missing item names a few at a time. While names are still arriving, the summary says how many, since a search can't match them yet.

## 0.5.1 — 2026-11-06

- Leveling: the profession picker opens a list of your professions instead of stepping through them; Crafters / Prices opens a list too (needs RUIN Core 0.5.3).
- Find: Crafters shows one row per recipe instead of one per crafter. Each recipe shows the online RUIN member with the lowest skill in the profession (they gain the most from crafting it), with their skill; you come after other members.
- Click the crafter's name for everyone who can craft it, lowest skill first, with their guild; pick one to make them the recipe's crafter.
- New *Offline crafters* switch: also lists recipes only offline members know, and offline crafters (marked offline, no Whisper) after the online ones.
- Your profession skill now travels with your recipes. Members on an older RUIN show "skill ?" and sort after known skills.
- *Whisper* opens a whisper to the crafter's full name. Before, the game's whisper helper typed "/cw First Last" into the chat box (/cw is the game's character whisper), and the chat box cut a WoW Forever name down to the first name.

## 0.5.0 — 2026-11-02

RUIN 0.5.0: every addon in the suite moves to 0.5.0 together. No changes to Exchange since 0.4.4.

## 0.4.4 — 2026-11-01

1 change since 0.4.3:

1. Other parts of RUIN can ask who can craft an item and RUIN's auction price for one (the Planner page uses both).

## 0.4.3 — 2026-10-28

Security update (works best with RUIN Core 0.4.5). 1 change since 0.4.2:

1. Only your guild's keeper (the guild master or its Treasurer) can write in the treasury book; a crafter's listing belongs to that crafter (same name and GUID); only whoever posted a craft request can close it; and prices, requests and crafting history dated in the future are refused.

## 0.4.2 — 2026-10-27

1 change since 0.4.1:

1. The History tab sits right after Requests: Search, Requests, History, Leveling, Bags, Treasury.

## 0.4.1 — 2026-10-27

1. **Treasury book.** Your guild's treasurer (whoever holds the Treasurer office on Guild → People, or the guild master) keeps a book of the gold members give: gold traded or mailed to the treasurer is written down by itself (auction house mail isn't), and the treasurer adds anything else by hand (*Add entry*: `50, Grimlock, raid repairs`, `-20` for gold paid out). The guild sees the book, this week's totals, the top givers, and the guild bank's gold as last seen.
2. **Crafting history.** When you trade someone an item you can craft, or enchant their item in the trade window, RUIN asks them to confirm the craft (*Log a craft* does it by hand). Confirmed crafts reach the whole org, and the History tab ranks crafters by confirmed crafts this month.
3. Guild → People can group members by profession from Exchange's crafters list (RUIN Core 0.4.3).
4. `/ex treasury`, `/ex history`.

## 0.4.0 — 2026-10-23 · Beta 1

The RUIN Gaming Companion App enters beta: every addon is now 0.4.0. Nothing changed since 0.3.6 apart from the version number. Report what you find under Settings → Feedback.

## 0.3.6 — 2026-10-23

2 changes since 0.3.5:

1. **Your professions are checked at login.** Exchange shares the recipes it already has on record as soon as you're connected (and when others ask), drops professions you no longer have, and lists the professions it hasn't read yet or whose skill went up. The game shows recipes only while a profession's window is open, so the *Add your recipes* window (also *Add my recipes* on the Search page) gives one click per profession: the window opens, Exchange reads it and closes it. Enchanting's separate window on classic clients is read too.
2. Fixed: opening the Leveling page with no plans emptied the Crafters list until you picked a profession again.

## 0.3.5 — 2026-10-22

1 change since 0.3.4 (needs RUIN Core 0.3.16):

1. **Crafters by profession, crafter and quality.** Searching for crafters lists each profession, then its recipes with the item they make (in its quality color), the RUIN member who can craft it, and the item's quality; pick one profession from the new list beside the search box. Opening a profession window now also shares the item each recipe makes and its quality (older RUIN versions still read the recipe names). Prices and reagents show item names instead of "item #1234".

## 0.3.4 — 2026-10-19

1 change since 0.3.3 (needs RUIN Core 0.3.12):

1. **Clearer pages, in Exchange's color.** Search's mode reads *Find: Crafters* or *Find: Prices*, and the search, request and note boxes show what to type in them.

## 0.3.3 — 2026-10-19

1 change since 0.3.2:

1. Back to the original name (Exchange) in the RUIN window and addon list, after 0.3.2's short-lived rename. Its tab now sits in the order Guild, Finder, Muster, Pathfinder, Codex, Exchange, Options.

## 0.3.2 — 2026-10-19

1 change since 0.3.1:

1. **New display name** (Market tab, Market page), to match the RUIN Gaming Companion App brief and RUIN Core 0.3.10's new tab order. The addon list shows it as "Market (Exchange)". The tabs now read in the brief's plain language. Only what players see changed: the addon folder, repository, command and saved-data names stay the same, so nothing needs reinstalling or re-setting.

## 0.3.1 — 2026-10-18

1 change since 0.3.0:

1. Picks up the new RUIN look from Core 0.3.7 and joins the RUIN Gaming Companion App (navy window, tabs across the top, the Exchange tab), and the TOC lists Retail's interface number next to WoW Forever's. Works with RUIN Core 0.3.0 or later.

## 0.3.0 — 2026-10-18

- Suite release: every RUIN addon moves to 0.3.0 together, bringing everything from the 0.2.x entries below. No further code changes.
- Needs RUIN Core 0.3.0.
- From now on a RUIN addon's 0.3.x number counts its own changes since this release.

## 0.2.6 — 2026-10-18

6 changes since 0.2.0:

Needs RUIN Core 0.2.6 or later.

1. Price history: daily lowest prices for 14 days, with the 7-day average and trend on tooltips and in the price list.
2. Profession leveling: opening a profession ranks your recipes by expected cost per skill point from RUIN prices.
3. Craft request board: post what you need made with a note. Members who know the recipe get an alert (`/ex request <item> -- <note>`).
4. Bag sweep: labels every item in your bags Keep, Sell (AH), Vendor or Check AH, with totals (`/ex bags`). With RUIN Codex it keeps your upgrades.
5. Fixed: item names in the price list showed without their colour and link.
6. The page is split into Search, Requests, Leveling and Bags.

## 0.2.0 — 2026-10-18

- Suite milestone: every RUIN addon moves to 0.2.0 together. No code changes since the last 0.1 release.
- With RUIN Core 0.2.0, this module's page opens in the new RUIN window with its own themed header: ledger lines and coins.

## 0.1.2 — 2026-10-18

- Fixed: "Binding header RUIN was attempted to be loaded more than once". Each module now has its own section under Key Bindings, and all of its bindings load.

## 0.1.0 — 2026-10-18

First proof of concept.
