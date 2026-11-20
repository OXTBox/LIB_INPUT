# LIB_INPUT

Mouse, keyboard and game controller as **named actions**, with presets and profiles.
A game asks "is *jump* down?", never "is 32 down?"; people change keys without touching the game.
Plan: `PLAN.md`. Where we are: `NEXT.md`.

## Use it

```
start using stack "<projects>/LIB_INPUT/livecode/lib_input.livecodescript"
Input.Load "Hunter", tFolder & "/Vibecode3D_Play_Hunter.input.txt"   -- once
Input.Poll                                                            -- once a step
if Input.Down("jump") then ...
put Input.Axis("move_x") into tSide                                   -- -1 .. 1
Input.ShowSettings                                                    -- the app face
```

In the Game Player a game does none of the loading: put `<script name>.input.txt` beside the
game's script and the player reads it, polls every step and adds **Controls...** to its `...` menu.

## Three layers, the last wins

| Layer | What | File |
|---|---|---|
| Actions | what the app needs, in its own words, with its own default inputs | `<App>.input.txt`, beside the app |
| Preset | a ready layout for the common action names (`WASD`, `Arrows`, `Left hand`, `Gamepad`) | `Input/Default/Presets/<Name>.txt` here; yours in the Data folder, `Scripts/Input/Presets/` (yours win, name by name) |
| Profile | one person's own changes and settings | Data folder, `Users/<who>/Input/<Profile>/<App>.txt` and `settings.txt`; `Users/<who>/Input/current.txt` names the profile in use |

An actions file (tabs between columns):

```
input	1
move_x	axis	Step left / Step right	key:A|key:Left	key:D|key:Right	pad:LX
jump	button	Jump	key:Space|pad:A
```

- A **button**: its inputs. An **axis**: the negative side, the positive side, then a whole stick
  (`pad:LX` gives its left half to the first side and its right half to the second).
- An axis title written `a / b` names its two lines in the Controls window.
- Preset and profile files are shorter: `action <tab> inputs`, or `action <tab> negative <tab> positive`.
  A profile file keeps only what differs from the preset, plus a `preset: <Name>` line.
- The common action names the shipped presets know: `move_x move_y fire jump run reload use`.

Raw inputs are spelled one way everywhere (`Input/Default/names.txt` is the table):
`key:W key:Left key:Space key:Shift key:F5`, `mouse:1 mouse:2 mouse:3 mouse:wheel+ mouse:wheel-`,
`pad:A pad:B pad:X pad:Y pad:LB pad:RB pad:LT pad:RT pad:Start pad:Back pad:DUp ... pad:LX- pad:LX+ pad:LY- pad:RX+ ...`.
A key the table does not know is `key:#<code>`. **Escape is never bound**: it belongs to the player.

## The two faces

| Face | For | Shows |
|---|---|---|
| **App** (`Input.ShowSettings`, `gui/input_app.gui`) | whoever plays | only this app's actions, in its words. Click a line, press the key or button. A Layout choice, Clear this line, Reset to default, Done. |
| **Developer** (`Input.ShowDeveloper`, or More... on the app face; `gui/input_dev.gui`) | whoever builds | tabs: **Live** (every raw input held now), **Actions** (every slot as raw text, add by pressing, conflicts), **Presets** (use, save your own), **Profiles** (switch, new, copy; dead zone, sensitivity, invert Y), **Files** (where each layer came from, Explore here...) |

On the app face a new key takes the place of that line's keys and mouse buttons, a new controller
button the place of its controller buttons: one line holds one of each. The developer face adds and
removes freely. Every change is saved at once. Two actions on one input are said, not refused.
The faces need LIB_GUI (and LIB_THEME); they are loaded from beside LIB_INPUT when not in use.
Saving needs LIB_DATA; without it everything works for the session and `Input.Error()` says why nothing was saved.

## Handlers

| Handler | Does |
|---|---|
| `Input.Load pApp, pFile` | read the actions, lay the preset and the profile over them |
| `Input.Poll` | read the devices once; work out down / pressed / released |
| `Input.Down(a)` `Input.Pressed(a)` `Input.Released(a)` | held; went down this step; let go this step |
| `Input.Axis(a)` | -1..1 (a button: 0 or 1). A key is the whole way, a stick part of the way |
| `Input.Pulse pRaw` | a one-step input that comes as a message (the wheel) |
| `Input.Actions()` `Input.Kind(a)` `Input.Title(a)` `Input.App()` | what is loaded |
| `Input.Bindings(a, pSide)` `Input.Words(a, pSide)` `Input.Label(pRaw)` | raw; in words; one input in words. `pSide`: `pos` (a button's only side) or `neg` |
| `Input.Bind` / `Input.Unbind` / `Input.SetBindings a, pSide, ...` | add; take away (nothing named: all); replace |
| `Input.Rebind a, pSide, pRaw` | replace the inputs of the same device on that line (the app face's rule) |
| `Input.Conflicts()` | `raw <tab> action,action` for inputs on more than one action |
| `Input.ResetApp` | back to the app's own file |
| `Input.CaptureStart`, `Input.Capture()` | "press a key...": the next input pressed; `cancel` for Escape |
| `Input.Presets()` `Input.Preset()` `Input.UsePreset pName` `Input.SavePreset pName` | presets |
| `Input.Profiles()` `Input.Profile()` `Input.UseProfile pName` `Input.NewProfile pName, pCopyFrom` | profiles |
| `Input.Setting(n)` `Input.SetSetting n, v` | `deadzone` (0.2), `sensitivity` (1), `invert_y` (false), `pad` (0: which controller) |
| `Input.Save` | the profile's lines for this app and the settings |
| `Input.Devices()` `Input.Raw()` `Input.Layers()` | what is plugged in; what is held; which files |
| `Input.ShowSettings` `Input.ShowDeveloper` `Input.BuildFace "app"/"dev"` | the faces |
| `Input.Error()` | why the last handler did nothing |
| `Input.Feed pList`, `Input.UseFolders` | test hooks: fake devices (`"key:W,pad:LX+=0.4"`, `"none"`, empty = real), fake folders |

## Devices

- **Keyboard**: `the keysDown`, on every edition.
- **Mouse**: the three buttons (not read while `gNoMouse` is true); the wheel through `Input.Pulse`.
- **Controller**: through the xt3d bridge (`xt3d_IsGamepadButtonDown`, `xt3d_GetGamepadAxisMovement`),
  so only where raylib owns the window. Elsewhere `Input.Devices()` says so and controller
  bindings are simply never down. The dead zone is applied to the sticks.
- `sensitivity` and `invert_y` are kept and saved for the app to read; the library does not apply
  them yet (mouse-look has no contract form).

## Tests

`OXT-BEYOND/tests/t48_lib_input.txt`, headless, in a throwaway Data folder: 113 checks, all pass on
OXT-Beyond's engine and on LiveCode 9.6.3. It covers the layers, polling, rebinding, conflicts,
save and reload, presets, profiles, both faces (built, their buttons used) and Hunter played in
the Game Player with fed keys.

```
cd ~/projects/OXT-BEYOND/tests && python3 -I oxt_headless.py --engine both t48_lib_input.txt
```

## Licence

GPL-3.0 (see `LICENSE`), because the xTalk work here is built on the GPL-licensed LiveCode Community 9 engine. Copyright (c) 2026 xAction.
