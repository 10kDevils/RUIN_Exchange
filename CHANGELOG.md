# RUIN Exchange changelog

Versioning: the third number counts the meaningful changes made since the second number last went up.

## Unreleased

(nothing yet)

## 0.5.2 — 2026-11-08

- Item names are asked for through RUIN Core's queue, a few at a time.
- Exchange reads WoW Forever's modern auction house properly. Opening the auction house starts a full scan by itself (the game allows one every 15 minutes), which prices every listing at once instead of only what you searched for. `/ex scan` asks for one; `/ex autoscan` turns the automatic scan off or on.
- Clicking into an item or a stack of trade goods also records its cheapest price.
- After a full scan, Exchange shares up to 400 prices with RUIN when you close the auction house, picking the ones RUIN knew least about (new, older than 6 hours, or moved more than 5%), so the guild channel isn't flooded.
- The profession window shows each recipe's cost per skill point beside it, from current RUIN prices (one craft's reagents divided by the chance of a point: orange always, yellow 3 in 4, green 1 in 4). "?" means a reagent has no price yet; grey recipes show nothing. `/ex costs` turns it off or on.
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
