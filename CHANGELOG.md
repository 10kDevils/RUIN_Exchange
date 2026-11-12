# RUIN Exchange changelog

Versioning: the third number counts the meaningful changes made since the second number last went up.

## Unreleased

(nothing yet)

## 0.6.1 — 2026-11-11

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
