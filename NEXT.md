# LIB_INPUT: what next

18 Nov 2026, by Claude (Fable 5.2). On branch `input-steps` (a local repo, no remote), waiting for the owner.

## Done

- **Steps 1-2, the library** (`livecode/lib_input.livecodescript`): actions files, the three layers
  (app -> preset -> profile), polling (down / pressed / released / axis), rebinding, conflicts,
  four shipped presets, your own presets in the Data folder, profiles and settings, save and reload.
- **Step 3, the app face** (`gui/input_app.gui`): only the app's actions; click a line, press a key.
- **Step 4, the developer face** (`gui/input_dev.gui`): Live / Actions / Presets / Profiles / Files.
- **Step 5, first real use**: the Game Player loads LIB_INPUT for any game with
  `<script name>.input.txt` beside its script, polls each step and offers `...` > **Controls...**
  (the game pauses). **Hunter** has `Vibecode3D_Play_Hunter.input.txt` and asks the actions; without
  LIB_INPUT (another host) it reads the key codes as before. `Input.` is in the contract's libraries table.
- Test: t48, 113 checks on both engines, Hunter walking on fed and rebound keys included.
  Both faces were also looked at in OXT-Beyond (built there, screenshots read).

## For the owner

- Game Player -> Hunter -> `...` -> **Controls...**: click "Jump", press another key, Done, play.
  Quit, start again: it stuck. Then **More...** for the developer face; the Live tab shows keys as you hold them.
- **The installed player on V: is a copy**: it has no "Controls..." until LIB_DEV's
  `game_player.livecodescript` is copied there the usual way.
- Is the app face what "only the required inputs" meant? Is the developer face too much or too little?
- A controller: **written, never tried with a real one**. It reads through the xt3d bridge, so only
  in an xt3d bench where raylib owns the window. Plug one in, open the developer face there, look at Live.

## Not done (said plainly)

- The developer face edits the loaded app only, not "any app" as the plan said: that needs a list
  of known apps and a way to edit one without disturbing a running game.
- `sensitivity` and `invert_y` are saved but nothing applies them: mouse-look has no contract form.
- Hunter's look, grab and shoot stay on the mouse (`Game.OnClick`), so they are not on the Controls list.
- The wheel reaches the library only when a host calls `Input.Pulse`; no host does yet.
- The other games still read key codes. Each needs a small actions file and five or so changed lines.
- No controller on the plain XT edition (no raylib window): its own later job (an XInput shim).

## Uncommitted in other repos (their branches are someone else's work)

- `LIB_DEV/livecode/game_player.livecodescript` (branch `on-git-or-not`)
- `LIB_GAMES/Vibecode3D_Games/Vibecode3D_Play_Hunter.livecodescript` and `.input.txt` (branch `vector-toss-dangle`)
- `LIB_ig3d/ENGINE_CONTRACT.md` (one row), `LIB_DEV/ProjectMap/board.txt` (the LIB_INPUT block)
- `OXT-BEYOND/tests/t48_lib_input.txt` (not a git repo)
