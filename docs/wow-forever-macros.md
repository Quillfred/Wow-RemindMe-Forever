# WoW Forever macros: reference notes

Compiled 2026-11-12 from community guides (Blizzard has published no Forever macro
reference). Sources are listed at the bottom. Items marked **(unconfirmed)** come from
one source only or conflict between sources; check them in game.

## The client
- WoW Forever is Blizzard's Classic+ (launched 2026-11-04), interface 16001/16000.
- It reportedly uses the modern Mainline client and API (one source says 12.1.5). That
  matches what we hit in this addon: secret values in combat, `C_Item.GetItemCount`,
  `C_SpellBook`, the Cooldown Manager, and pet spells placeable on player action bars.
- Focus target exists (Classic Era doesn't have it). A "Clear Focus" menu item was added 2026-11-02.
- Built-in **Mouseover Cast** option (search "mouseover" in Options). It only works with key presses, not mouse clicks.

## Limits
- 255 characters per macro. `#showtooltip` and comments count toward this.
- Slots: 18 account-wide + 18 per character **(unconfirmed, one source)**.
- Shift-clicking a spell into the editor inserts its name, sometimes with rank, which costs characters.
- One global-cooldown ability fires per press. Lines after the first GCD spell do nothing,
  so put off-GCD things (`/use 13`, `/petattack`, `/stopcasting`) first. One source disagrees.

## Directives
- `#showtooltip` with no argument shows whatever the macro will cast.
- `#showtooltip Spell` pins it; `#showtooltip 18` shows an equipped slot (18 = wand).
- `#show` works like `#showtooltip`, without the tooltip.
- A question-mark icon means the spell name doesn't match a spell you know.

## Slash commands
Confirmed by several sources:
- Casting: `/cast` (`/spell`), `/use`, `/castsequence`, `/castrandom`, `/stopcasting`, `/stopmacro`
- Combat: `/startattack`, `/stopattack`, `/dismount`
- Targeting: `/target` (`/tar`), `/targetenemy`, `/assist` (`/a`), `/cleartarget`, `/focus`, `/clearfocus`, `/targetmarker` (`/tm`)
- Pet: `/petattack`, `/petfollow`, `/petstay`, `/petpassive`, `/petdefensive`
- Gear: `/equip` (`/eq`), `/equipslot`, `/equipset`
- Cancelling: `/cancelaura` (name or spell ID), `/cancelform`

Raid marker numbers for `/tm`: 1 Star, 2 Circle, 3 Diamond, 4 Triangle, 5 Moon, 6 Square, 7 Cross, 8 Skull, 0 clears.

Restricted or changed:
- `/run`, `/script`: these exist, but protected functions are blocked (e.g. `CastSpellByName`),
  and modern addon restrictions apply. Don't use them for combat decisions.
- `/click` from an action-bar macro does **not** run the clicked button's macro text in Forever, so
  the retail trick of chaining long macros doesn't work. Split them instead.
- `/ginvite` hit a restriction on Blizzard-reserved actions (reported Nov 5–7).
- Old inventory API calls (`GetContainerNumSlots`, ...) shouldn't be assumed to work.

## Conditionals
Logic:
- Comma = AND.
- `;` separates alternatives.
- A second `[...]` on the same line is a fallback target.
- `no` prefix negates.
- Empty `[]` = always true, and acts as the current-target fallback.
- `!Spell` = don't toggle off when pressed again (`/cast !Shoot`).
- A misspelled condition is silently treated as true **(unconfirmed)**.

Units:
- `@mouseover`, `@focus`, `@target`, `@player`, `@targettarget`, `@pet`
- `@cursor` (ground spells, e.g. Rain of Fire)
- `@party1`–`@party4`
- legacy `target=` form (`target=none`)

States:
- `help` / `harm`, `exists` / `noexists`, `dead` / `nodead`
- `combat` / `nocombat`
- `mod`, `mod:shift`, `mod:ctrl`, `mod:alt`, `nomod`
- `pet` / `nopet`
- `stance:N` / `nostance`, `form:N` / `noform`
- `stealth`, `mounted`, `swimming`, `outdoors`
- `channeling` / `nochanneling`, also `nochanneling:Spell`
- `btn:2` (right mouse button)
- `worn:` / `noworn:` and `equipped:` / `noequipped:` (e.g. `worn:Shields`)

Doubtful: `known` and `spec`. Treat them as not working **(unconfirmed)**.
**Named-pet checks like `[pet:Voidwalker]` do NOT work in Forever (confirmed in game 2026-11-12)**;
only `[pet]`, `[nopet]` and `[@pet]`. `talent` was not found in any source.

Gotchas:
- Alt is the default Self Cast modifier. `[mod:alt]` macros work, but can clash with self-cast.
- A keybinding that includes a modifier (e.g. Shift+3 bound to something else) overrides `[mod:shift]` on that key.
- Stance numbering for Warriors differs between sources.

## /castsequence
- Advances only after a successful cast. If a spell can't be cast (cooldown, range, mana), the sequence gets stuck on it.
- A press during a cast does nothing. The sequence resets on death.
- `reset=` takes one word with no spaces: `reset=target`, `reset=combat`, `reset=10`, `reset=target/15`,
  `reset=combat/target`, `reset=shift`. The timer counts from your **last press**, so it can't track a cooldown.
- Conditionals go before `reset`: `/castsequence [@mouseover,harm][] reset=target Immolate, Corruption`.

## Spell ranks
- `/cast Spell` with no rank casts the **highest rank you know**.
- A spell dragged to the bar does **not** upgrade after you train a new rank: drag it again from the
  spellbook, or use a no-rank macro.
- `/cast Spell(Rank 1)` (the classic way to cast a lower rank) is **unconfirmed** in Forever.
  Downranking is still mana-efficient for some spells.

## Renamed spells (old names are silently skipped)
- Curse of Agony → **Bane of Agony**
- Curse of Doom → **Bane of Doom**
- Elemental Mastery → Lightning Mastery
- Totemic Projection → Totemic Call
- Feral Charge → (Bear) / (Cat)
- Faerie Fire (Feral) → Faerie Fire
- Judgment → Judgement
- Strider's Kick → Strider Kick
- Remove Curse → Remove Lesser Curse (level 18)
- Removed: Lava Burst (now from the Call of Thunder talent), Blessings of Salvation/Light/Sanctuary
- New for Warlock: **Bane of Havoc**, **Incinerate**, **Conflagrate**

## Warlock macros (from the guides; untested)
```
#showtooltip
/petattack [harm,nodead]
/cast Shadow Bolt
```
```
#showtooltip Immolate
/cast [@mouseover,harm,nodead][] Immolate
```
```
#showtooltip Bane of Havoc
/cast [@focus,harm,nodead][@mouseover,harm,nodead][] Bane of Havoc
```
```
#showtooltip
/petattack
/castsequence reset=target/15 Immolate, Corruption, Bane of Agony
```
```
#showtooltip Drain Soul
/cleartarget [dead]
/targetenemy [noexists]
/petattack [harm,nodead]
/cast [harm,nodead] Drain Soul
```
```
#showtooltip
/cast [mod:shift] Drain Soul; Drain Life
```
```
#showtooltip Shadowburn
/stopcasting
/cast [@mouseover,harm,nodead][] Shadowburn
```
```
#showtooltip Rain of Fire
/cast [@cursor] Rain of Fire
```
```
#showtooltip Fear
/cast [@mouseover,harm,nodead][@focus,harm,nodead][] Fear
```
```
#showtooltip Death Coil
/stopcasting
/cast [@mouseover,harm,nodead][@focus,harm,nodead][] Death Coil
```
```
#showtooltip
/cast [nochanneling,mod:shift] Health Funnel; [nochanneling] Life Tap
```
```
#showtooltip
/cast [nocombat,mod:shift] Demon Skin; [nocombat] Demon Armor
```
Pet macros:
```
#showtooltip
/cast [nopet] Summon Voidwalker; Sacrifice
```
(Confirmed working in game: summons the Voidwalker if no pet is out, otherwise Sacrifice.
With another demon out, the Sacrifice part just errors.)
```
#showtooltip Sacrifice
/cast [@pet,exists] Sacrifice
```
```
#showtooltip
/cast [nopet,mod:shift] Summon Imp; [nopet] Summon Voidwalker; [@pet,nodead,nochanneling] Health Funnel
```
```
#showtooltip Summon Voidwalker
/cast [mod:shift] Summon Imp; [mod:ctrl] Summon Succubus; [mod:alt] Summon Felhunter; Summon Voidwalker
```
```
#showtooltip Fel Domination
/cast Fel Domination
/stopcasting
/cast Summon Imp
```
```
/petfollow [mod:shift]
/stopmacro [mod:shift]
/petattack [@mouseover,harm,nodead][]
```
```
#showtooltip
/cast [mod:shift] Create Soulstone; [mod:ctrl] Create Spellstone; [mod:alt] Create Firestone; Create Healthstone
```

Known Warlock bugs (player reports):
- `/cast !Shoot` doesn't restart the wand after Shadow Bolt.
- A previously summoned demon can stay stunned (reported after the Oct 8 patch).
- The Voidwalker stays in combat for 10 s after each kill. A suggested workaround is adding `/cast [target=none] Consume Shadows`.

## Relevance to RemindMe Forever
- Pet spells can be on player action bars, directly or inside a macro. The addon finds them with
  `GetActionInfo` / `GetMacroSpell` (covers `/cast [@pet,exists] Sacrifice` style macros).
- Macros resolve to the highest rank, so the addon matches spells by any rank ID or by name.
- Mouseover/focus variants still resolve to the same spell, so keybind detection works for them.

## Sources
- https://rankedboost.com/world-of-warcraft/forever/macros/
- https://rankedboost.com/world-of-warcraft/forever/macros/warlock/
- https://rankedboost.com/world-of-warcraft/forever/downranking/warlock/
- https://kami-labs.fr/en/macros-wow-forever/?classe=warlock
- https://kami-labs.fr/en/wow-forever/macros-wow-forever-9-classes/
- https://www.curseforge.com/wow/addons/forever-macros
- https://realmfirst.net/news/wow-forever-macro-beginner-guide/
- https://wow4ever.quest/en/articles/macros-wow-forever
- https://www.chaosboost.com/articles/wow-forever-macros-for-all-classes
- https://worldeka.com/wow-forever-macro-commands-guide-best-beginner-macros-list-2026/
