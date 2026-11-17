Levelmate 1.0.0 – Leveling assistant for WoW Forever
====================================================

Levelmate plans the most efficient quest route from level 1 to 60: which
quest to accept, complete or turn in next, where to fly, when your
hearthstone is worth it and when to visit your class trainer.

Requirements
- QuestieDB (provides quest and NPC data).
- Optional: TomTom (extra waypoints), What's Training (spell prices with
  reputation discounts).

Installation
1. Close WoW.
2. Copy the "Levelmate" folder to World of Warcraft\_forever_\Interface\AddOns
   (or install it with the CurseForge app).
3. Start WoW. On first login you choose a mode.

The window
- Top: level, time to next level, unspent talent points. On the right:
  scroll (new spells at your trainer), arrow on/off, mode, settings.
- Below: recommended zones for your level.
- The card shows the current step with a rating, XP and time.
  "Skip" postpones the step (it returns after half a level), the arrow next
  to it brings it back right away.
- "Next steps" and "Quest log" can be folded open/closed with a click.
- Class trainer: becomes a step when you can learn new spells and the
  trainer is nearby or you are in their capital city.

Language
- Settings (gear icon) → "Language": Automatic (game language), Deutsch or
  English. Quest, NPC and zone names always follow your game language.

Minimap button
- Left-click: window, right-click: mode, Shift+left-click: arrow.

Commands
/lm            show window
/lm hide       hide window
/lm options    settings
/lm mode       choose mode
/lm arrow      arrow on/off
/lm tomtom     TomTom waypoints on/off
/lm minimap    minimap button on/off
/lm scale 0.8  window size (0.5 to 1.5)
/lm reset      reset skipped quests and window position
/lm why <quest>  explains why a quest is (not) suggested
/lm trainer    shows what Levelmate knows about trainers and spells
/lm export     learned paths as text to copy (e.g. to send to the developer)
/lm import     add paths from such a text
/lm smart      measured XP per minute
/lm perf       addon processing time
/lm diag       diagnostics

Notes
- Times and XP are estimates; Levelmate learns your pace while you play.
- Levelmate ships with starter knowledge (known zone crossings and paths)
  and keeps learning while you play. Learned paths are stored on your PC
  only and shared with other Levelmate users in your group.
- Unofficial fan-made addon, not affiliated with Blizzard Entertainment.
