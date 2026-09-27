# Nofoxy's Loot

A Master Loot addon for WotLK 3.3.5 that combines:
- **Master Loot rolling** (item cards, roll timers, tied-roll re-rolls, one-click
  Award with automatic trade-window handoff).
- **Soft-Reserve integration** from [softres.it](https://softres.it) (or a WeakAura-style
  export): paste your raid's reservation list in, and reserved items get tagged on
  sight — you decide when to announce and award/roll them.
- **Auto-Loot** for trash: anything at or below a quality threshold goes straight into
  your own bags, no clicking required.

## Install

1. Unzip this into `World of Warcraft/Interface/AddOns/` so you end up with
   `Interface/AddOns/NofoxysLoot/NofoxysLoot.toc`.
2. Enable it on the character select screen if needed.
3. In-game: `/nofoxy`, `/nfx`, or `/karu` (all identical) to open the window — or just
   click the minimap button (drag it around the minimap edge to reposition; hide it
   in Options → Misc if you'd rather not have it).

## How it works

### Master Loot
This only activates when your **loot method is set to Master Loot** (right-click your
portrait or use the raid options). When you (the Master Looter) open a corpse:

- Items reserved by someone show up tagged **"Soft-Reserved: Name(s)"**, but nothing
  happens automatically — they just sit there until you act:
  - **1 reserver** → an **Award** button. Click it, and it announces the reservation to
    raid chat and awards it in one step.
  - **2+ reservers** → a **Roll** button. Click it, and it announces the contest,
    starts a roll restricted to just those reservers, and auto-awards the winner when
    the timer ends (ties automatically re-roll among the tied players until there's a
    winner).
- Items below your Auto-Loot quality threshold (and not reserved by anyone) go
  straight into your own bags automatically.
- Everything else shows up as a normal item card with a **Start Roll** button — click
  it, raiders `/roll`, you **Award** (or the highest roller auto-fills the Award
  button).

**Anything that's going to roll gets pulled into your own bags immediately by default**
— the instant a roll starts, not when it ends. This guarantees Award can always
deliver the item afterward via a quick trade, no matter what happens between the roll
starting and ending. You'll see these items sitting in your bags until you award them;
that's expected. Turn this off in Options → Roll Settings if you'd rather items not
sit in your bags while a roll is open — with it off, Award tries a direct hand-off
first and only falls back to a trade if that's no longer possible by the time you
click it.

Raiders in your group see the same item cards (read-only mirror) so everyone can watch
rolls happen live, even without their own copy of the Soft-Reserve list.

### Soft Reserves tab
Paste one of the following into the box and click **Import** (it auto-detects the
format):

- **softres.it CSV export** — the "Export as CSV" button on your softres.it raid page.
- **WeakAura-style export** — `ItemId,Name,Class,Note` rows.

Importing **replaces** the previously loaded list, so just re-paste an updated export
before pull to refresh reservations. The list is saved between sessions.

**Reservations are consumed as they're awarded.** The moment you (the Master Looter)
successfully hand a Soft-Reserved item to its winner, that person's reservation for
that item is cleared automatically. If someone else also reserved the same item, their
reservation stays active — so if the item drops again later (common with repeat-drop
bosses, e.g. AQ40), the next copy correctly goes to whoever's still owed one, without
re-prompting the person who already got theirs. This bookkeeping lives only on the
Master Looter's own copy of the list — raiders' own imported copies (if any) aren't
updated remotely, since only the ML's copy drives any actual loot decisions.

### Auto-Loot
Off by default. Turn it on in Options and pick a quality ceiling (default: Poor only)
— anything at or below that quality is handed straight into your bags when you open a
corpse. Soft-Reserved items are always excluded from Auto-Loot, no matter their
quality.

There's a second, independent option: **"Also auto-loot non-BoP items."** Quality
alone is a poor signal for "is this trash" — recipes, patterns, and bags are very
often plain white (Common) quality, so a pure quality filter can't tell them apart
from genuine vendor junk. This option instead auto-loots anything that ISN'T Bind on
Pickup (no-bind or Bind on Equip), regardless of its quality, since those are always
freely tradeable/sellable/mailable either way. True Bind-on-Pickup drops NEVER
auto-loot under this setting no matter how low their quality is — they always land on
the Master Loot tab for a proper roll. Combine both settings freely: e.g. "Poor and
below" for definite junk, plus "non-BoP items" so recipes/bags get swept up too
without risking any real BoP upgrade.

## Slash commands

```
/nfx               Toggle window            (also /nofoxy or /karu)
/nfx lock          Toggle window lock
/nfx clear         Clear "Done" items from the Master Loot tab
/nfx roll          Add a bag item to roll for — type this, then shift-click the item
                   from your bags into the same line before pressing Enter (e.g. for
                   something crafted, banked, or already Auto-Looted that you've
                   decided is worth a proper roll after all)
/nfx sr clear      Clear all imported Soft Reserves
/nfx test          Inject mock Master Loot data to preview the UI (local only)
/nfx srtest        Seed sample Soft Reserves + simulate the SR flow (local only)
/nfx debug         Toggle debug chat logging
```

## Notes

- Master Loot state, rolls, and awards are synced between the Master Looter and
  raiders over an addon message channel (prefix `NOFOXY`) — nothing is sent outside
  your raid/party.
- **Awarding prefers a direct hand-off, but items that roll get secured to your bags
  up front so award always works.** The moment a roll starts (manual or Soft-Reserve),
  the item is pulled into your own bags right away — see the Master Loot section above
  for why. Awarding then initiates a trade and drops the item in automatically once
  the trade window opens; you still click Accept.
  - The only items that skip this and get handed out directly are ones resolved
    instantly, with no roll — a single-reserver Soft-Reserve Award click, or reopening
    a corpse where a winner was already decided while its loot session was closed.
  - If you win your own roll and the item's already in your bags, awarding it to
    yourself just marks it done — no pointless self-trade attempt.
  - If securing an item to your bags fails for some reason (bags full, etc.), reopening
    the same corpse retries it automatically, and the Master Loot tab always shows a
    manual Award button as a fallback.

## Credits

This is an independent implementation — no code was copied from either project — but
the design was directly shaped by studying two existing addons:

- **[Looty](https://www.curseforge.com/wow/addons/looty)** — the Master Loot rolling
  UI (item cards, roll timers, tie handling, one-click Award) follows the shape Looty
  established, since that's the workflow its author was already used to and wanted
  kept.
- **[MagicLooter](https://www.curseforge.com/wow/addons/magiclooter)** — the
  quality-threshold Auto-Loot concept is based on MagicLooter's approach to
  auto-distributing sub-threshold items.

Full thanks to their authors for the original ideas. If you're looking for those
addons' actual, more broadly-tested implementations rather than this one (built
specifically for one raid group's workflow, including Soft-Reserve integration these
don't have), go support the originals.

## License

MIT — see [LICENSE](LICENSE). Do whatever you want with this, just don't remove the
credit above.
