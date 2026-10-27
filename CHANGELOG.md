# RUIN Exchange changelog

Versioning: the third number counts the meaningful changes made since the second number last went up.

## Unreleased

(nothing yet)

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
