# LIB_INPUT: mouse / keyboard / game controller settings, with profiles and presets

## Context

Today every game reads `the keysDown` and tests raw key codes itself (Hunter: `119 or 87 or 65362`
for "forward"; 30+ games repeat the same WASD / arrows / space codes). Nothing can be rebound, there
is no left-handed or controller layout, and the gamepad calls that already exist in the raylib bridge
(`xt3d_IsGamepadButtonDown`, `xt3d_GetGamepadAxisMovement`, ...) are used by no game.

LIB_INPUT is one library every stack uses to ask "is *fire* down?" instead of "is 32 down?", plus
one settings stack with **two faces**:

- **App face**: only the inputs that app declared, in its own words. Clean, one screen.
- **Developer face**: everything: every device, every app, every slot, presets, profiles, raw codes.

It follows the house shape of LIB_MENU: a `Input.` prefix, plain text files, a shipped Default set,
the user's own files in the Data folder winning, one headless test.

## The model (three small things)

| Thing | What | File |
|---|---|---|
| **Actions** | what an app needs: `move_x`, `fire`, `reload`... with a label and a kind (`button` / `axis`) and its default inputs | `<App>.input.txt`, beside the app (a game finds it with `Game.FindFile`) |
| **Presets** | named layouts for the common action names: `WASD`, `Arrows`, `Left hand`, `Gamepad` | shipped: `LIB_INPUT/Input/Default/Presets/<Name>.txt`; yours: Data `Scripts/Input/Presets/` (yours win, as LIB_MENU) |
| **Profiles** | one person's choices: per-app bindings + settings (stick dead zone, mouse sensitivity, invert Y) | Data `Users/<who>/Input/<Profile>/<App>.txt` and `settings.txt`; `current.txt` names the profile in use |

Order, last wins: the app's defaults -> the preset picked -> the profile's own lines for that app.

Raw inputs have one spelling everywhere: `key:W`, `key:Left`, `key:Space`, `mouse:1`, `mouse:wheel+`,
`pad:A`, `pad:LX+`, `pad:LT`. A table (`Input/Default/names.txt`) maps key codes <-> names <-> the
words shown to people ("Left Arrow"); upper and lower case letter codes (119 / 87) are one key.

Action file, one action a line (tabs):

```
input	1
move_x	axis	Move left / right	key:A|key:Left	key:D|key:Right	pad:LX
fire	button	Fire	key:Space|mouse:1|pad:A
reload	button	Reload	key:R|pad:X
```

## The library: `LIB_INPUT/livecode/lib_input.livecodescript`

| Handler | Does |
|---|---|
| `Input.Load pApp, pFile` | read the app's actions, lay the preset and the current profile over them |
| `Input.Poll` | once a step: read the devices, work out down / pressed / released |
| `Input.Down(a)`, `Input.Pressed(a)`, `Input.Released(a)`, `Input.Axis(a)` | what a game asks (`Axis` is -1..1, dead zone applied) |
| `Input.Actions()`, `Input.Bindings(a)`, `Input.Label(raw)` | for the settings faces |
| `Input.Bind a, slot, raw`, `Input.Unbind`, `Input.Conflicts()`, `Input.ResetApp` | change bindings; two actions on one key are listed, not refused |
| `Input.Capture()` | the next raw input pressed ("press a key...") |
| `Input.Presets()`, `Input.UsePreset`, `Input.SavePreset` | presets |
| `Input.Profiles()`, `Input.UseProfile`, `Input.NewProfile`, `Input.Save` | profiles |
| `Input.Setting(name)`, `Input.SetSetting` | dead zone, sensitivity, invert Y |
| `Input.Devices()`, `Input.Raw()` | developer face: what is plugged in, what is held now |
| `Input.ShowSettings pApp`, `Input.ShowDeveloper` | open a face |
| `Input.Error()`, test hooks `Input.Feed raw,...` and `Input.UseFolders` | why nothing happened; fake devices and folders for the headless test |

Devices:
- **Keyboard**: `the keysDown` (the contract's normal way; works on every edition).
- **Mouse**: `Engine.Mouse()` when the engine has it, else `the mouse` / wheel messages in tool stacks.
  Never read while `gNoMouse` is true.
- **Gamepad**: the bridge's `xt3d_IsGamepad*` / `xt3d_GetGamepadAxisMovement` when xt3d is in use
  (raylib owns the window). Otherwise `Input.Devices()` says "no controller on this edition" and pad
  bindings are simply never down.
- **Escape is never bindable**: it belongs to the player (contract rule).

Reused, not rewritten: `Data.Folder` / `Data.Path` / `Data.UseRoot` (LIB_DATA), `Users.Current()`
(LIB_USERS; without it the person is `PLAYER`), `Menu.WithEnd` / `Menu.AppendLine` / `Menu.Explore`
(LIB_MENU), `Gui.Load` / `Gui.Build` / `Gui.Get` / `Gui.Set` / `Gui.TabPick` (LIB_GUI), colours from LIB_THEME.
As with the boards, LIB_INPUT still polls and binds without LIB_GUI / LIB_MENU; only the faces need them.

## The two faces (both `.gui` files, shown by LIB_GUI)

**`gui/input_app.gui`, the app face.** Title "Controls: Hunter". One list: the app's actions by label,
with what is bound ("Fire ... Space, Left Mouse, A"). Click a line -> "Press a key or button..." ->
bound. A preset popup, "Reset to default", "Done". A small "More..." opens the developer face.
Nothing else: no codes, no devices, no other apps.

**`gui/input_dev.gui`, the developer face.** Tabs:
1. *Live*: every raw input held right now, with its code and name (finds a dead button in seconds)
2. *Actions*: any app, every slot, conflicts marked, raw spelling editable
3. *Presets*: edit, "Save as preset..."
4. *Profiles*: new / copy / switch, settings sliders (dead zone, sensitivity, invert Y)
5. *Files*: where each layer came from (Default / User), each line ending "Explore here..."

## Steps (each ends with the test passing and a for_review line)

1. **Core, headless**: names table, action files, `Load / Poll / Down / Pressed / Released / Axis`,
   `Input.Feed`. Test `OXT-BEYOND/tests/t48_lib_input.txt` in a throwaway Data folder.
2. **Presets and profiles**: the four shipped presets, layering, `Bind / Conflicts / Save`, settings.
3. **App face**: `input_app.gui`, `Input.Capture`, `Input.ShowSettings`.
4. **Developer face**: `input_dev.gui`, the five tabs.
5. **First real use**: the Game Player's `...` menu gets "Controls..." (`LIB_DEV/livecode/game_player.livecodescript`);
   **Hunter** gets `Hunter.input.txt` and asks `Input.Down("fire")` instead of key codes
   (`LIB_GAMES/Vibecode3D_Games/Vibecode3D_Play_Hunter.livecodescript`, lines ~414-477).
   Add `Input.` to the libraries table in `LIB_ig3d/ENGINE_CONTRACT.md` (`contract:libraries`) so
   `tools/contract_check.py` lets it pass. The other games stay as they are until asked.
6. **Controller**: the pad source through the bridge, tried by the owner with a real controller in an xt3d bench.

New folder `~/projects/LIB_INPUT/`: `README.md`, `PLAN.md` (this plan, house style), `NEXT.md`,
`livecode/lib_input.livecodescript`, `Input/Default/` (names, presets), `gui/`, `.gitignore` as LIB_MENU's.
Housekeeping per `LIB_DEV/CLAUDE.md`: `for_review.py add` for every file, a size line in
`PriorityTube/claude_sizes.txt`, the part on the Project Map board.

## Open, with my suggestion (say otherwise when approving)

| # | Question | Suggested |
|---|---|---|
| 1 | Controller on the plain XT edition (no raylib window)? | Not now: bridge only. A small XInput shim is its own later job. |
| 2 | Profiles under `Data/Users/<who>/Input/` (LIB_USERS question 6 said "not yet" for saves)? | Yes for input: it is exactly a per-person setting. |
| 3 | First game converted | Hunter (uses WASD + arrows + shift + space + R: a full test). |
| 4 | Git | `git init`, work on a branch `input-steps`, no remote until you say. |
| 5 | Mouse-look (Hunter, uDead lock the cursor; the contract has no form yet) | Out of this plan; `Input.Axis("look_x")` leaves room for it. |

## Verification

- Headless: run `t48_lib_input.txt` with `OXT-BEYOND/tests/oxt_headless.py` (as t43): fed inputs give the
  right Down / Pressed / Released / Axis; preset then profile layering; a user preset wins over Default;
  conflicts listed; Escape refused; save and reload round-trips; the owner's real Data folder untouched.
- `xtalk_lint.py` on the new script; t13 / t39 / t40 / t43 still pass; `contract_check.py` passes on Hunter.
- By hand (owner): Game Player -> Hunter -> `...` -> Controls...: rebind Fire, play, quit, reopen: it stuck.
  Open the developer face: the Live tab shows keys as they are held; with a pad in an xt3d bench, its buttons too.
