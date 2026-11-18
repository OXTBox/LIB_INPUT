script "LIB_INPUT"
-- LIB_INPUT: mouse, keyboard and game controller as named actions (plan: LIB_INPUT/PLAN.md).
-- A game asks "is fire down?", never "is 32 down?"; people rebind without touching the game.
--
--   start using stack "<path>/LIB_INPUT/livecode/lib_input.livecodescript"
--   Input.Load "Hunter", tFolder & "/Hunter.input.txt"     -- once
--   Input.Poll                                             -- once a step
--   if Input.Down("fire") then ...     put Input.Axis("move_x") into tSide
--
-- Three layers, the last wins: the app's own file -> the preset picked -> the profile's lines.
--   the app's actions   <App>.input.txt, beside the app:
--                         input <tab> 1
--                         fire <tab> button <tab> Fire <tab> key:Space|mouse:1|pad:A
--                         move_x <tab> axis <tab> Move left / right <tab> key:A|key:Left <tab> key:D|key:Right <tab> pad:LX
--                       (an axis: the negative side, the positive side, then a whole stick)
--   presets             LIB_INPUT/Input/Default/Presets/<Name>.txt; yours in the Data folder,
--                       Scripts/Input/Presets, win file by file
--   profiles            Data folder, Users/<who>/Input/<Profile>/<App>.txt and settings.txt;
--                       Users/<who>/Input/current.txt names the profile in use
-- Raw inputs are spelled one way: key:W key:Left key:Space mouse:1 mouse:wheel+ pad:A pad:LX+
-- (the table: Input/Default/names.txt; a key not in it is key:#<code>).
--
-- What a game asks:
--   Input.Load pApp, pFile      read the actions, lay the preset and the profile over them
--   Input.Poll                  read the devices; work out down / pressed / released
--   Input.Down(a) Input.Pressed(a) Input.Released(a)      true or false
--   Input.Axis(a)               -1..1 (a button: 0 or 1)
--   Input.Pulse pRaw            a one-step input from a message (the wheel: Input.Pulse "mouse:wheel+")
-- What the settings faces ask:
--   Input.App() Input.Actions() Input.Kind(a) Input.Title(a)
--   Input.Bindings(a, pSide)    the raw inputs, commas; pSide "pos" (a button's only side) or "neg"
--   Input.Words(a, pSide)       the same in words: "Space, Left Mouse, A"
--   Input.Label(pRaw)           one raw input in words
--   Input.Bind a, pSide, pRaw   add;  Input.Unbind a, pSide, pRaw  take away (no pRaw: all of that side)
--   Input.SetBindings a, pSide, pList
--   Input.Conflicts()           raw <tab> action,action  for every input on more than one action
--   Input.ResetApp              back to the app's own file (no preset, no profile lines)
--   Input.CaptureStart / Input.Capture()   the next input pressed ("press a key..."); Escape = "cancel"
--   Input.Presets() Input.Preset() Input.UsePreset pName Input.SavePreset pName
--   Input.Profiles() Input.Profile() Input.UseProfile pName Input.NewProfile pName, pCopyFrom
--   Input.Save                  the profile's lines for this app (only what differs) and the settings
--   Input.Setting(pName) Input.SetSetting pName, pValue   deadzone (0.2), sensitivity (1), invert_y (false), pad (0)
--   Input.Devices()             keyboard / mouse / controller lines
--   Input.Raw()                 every raw input held now, with its value
--   Input.Layers()              where each layer came from (file paths)
--   Input.Error()               why the last handler did nothing
-- Test hooks: Input.Feed pList ("key:W,pad:LX+=0.4"; empty = the real devices again),
--   Input.UseFolders pDefault, pUserPresets, pProfiles.
-- Escape is never bound: it belongs to the player.

global gNoMouse        -- the engine contract: true while an AI tests; the mouse is not read

local sLabels          -- raw -> words
local sCodeRaw         -- key code -> raw
local sPadButtons      -- raw -> raylib button number
local sPadAxes         -- raw (a half: pad:LX-) -> "axis,sign"
local sNamesRead

local sApp, sAppFile
local sOrder           -- the actions in the file's order, one a line
local sAct             -- action -> kind, title, neg, pos (comma lists of raw inputs)
local sOwn             -- action -> neg, pos as the app's file gave them
local sBase            -- action -> neg, pos after the preset (what a profile is compared with)
local sState           -- action -> value, down, pressed, released
local sHeld            -- raw -> value 0..1, at the last poll
local sPulse           -- raw -> 1, waiting for the next poll
local sPreset, sProfile
local sSettings
local sFeedOn, sFeed
local sCaptureFrom
local sPadOK, sPadSeen
local sError
local sTestDefault, sTestPresets, sTestProfiles, sTestOn

constant kSettingDefaults = "deadzone,0.2|sensitivity,1|invert_y,false|pad,0"

-------------------------------------------------------------------- folders

command Input.UseFolders pDefault, pUserPresets, pProfiles
   put pDefault into sTestDefault
   put pUserPresets into sTestPresets
   put pProfiles into sTestProfiles
   put (pDefault is not empty or pUserPresets is not empty or pProfiles is not empty) into sTestOn
   put false into sNamesRead
end Input.UseFolders

function Input.DefaultFolder
   local tPath
   if sTestDefault is not empty then return sTestDefault
   put the effective fileName of stack "LIB_INPUT" into tPath
   set the itemDelimiter to "/"
   return item 1 to -3 of tPath & "/Input/Default"
end Input.DefaultFolder

-- your own presets: Scripts/Input/Presets in the Data folder (empty without LIB_DATA)
function Input.UserPresetFolder
   local tPath, tErr
   if sTestOn then return sTestPresets
   try
      put Data.Folder("Scripts", "Input") into tPath
   catch tErr
      return empty
   end try
   if tPath is empty then return empty
   put "/Presets" after tPath
   inputMakeFolder tPath
   return tPath
end Input.UserPresetFolder

-- Users/<who>/Input in the Data folder (empty without LIB_DATA)
function Input.ProfilesFolder
   local tPath, tWho, tErr
   if sTestOn then return sTestProfiles
   try
      put Users.Current() into tWho
   catch tErr
      put "PLAYER" into tWho
   end try
   if tWho is empty then put "PLAYER" into tWho
   try
      put Data.Folder("Users", inputSafeName(tWho)) into tPath
   catch tErr
      return empty
   end try
   if tPath is empty then return empty
   put "/Input" after tPath
   inputMakeFolder tPath
   return tPath
end Input.ProfilesFolder

private command inputMakeFolder pPath
   if pPath is empty or there is a folder pPath then exit inputMakeFolder
   create folder pPath
end inputMakeFolder

private function inputSafeName pName
   local tOut, tChar
   repeat for each char tChar in pName
      if tChar is in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 _-" then put tChar after tOut
   end repeat
   return word 1 to -1 of tOut
end inputSafeName

private function inputRead pFile
   local tData
   if pFile is empty or there is no file pFile then return empty
   put textDecode(URL ("binfile:" & pFile), "UTF-8") into tData
   replace numToChar(13) & numToChar(10) with numToChar(10) in tData
   return tData
end inputRead

private function inputWrite pFile, pData
   put textEncode(pData, "UTF-8") into URL ("binfile:" & pFile)
   if the result is not empty then
      put "could not write " & pFile & ": " & the result into sError
      return sError
   end if
   return empty
end inputWrite

function Input.Error
   return sError
end Input.Error

-------------------------------------------------------------------- the names table

private command inputNames
   local tLine, tRaw, tCode, tN, tWhat
   if sNamesRead is true then exit inputNames
   put empty into sLabels
   put empty into sCodeRaw
   put empty into sPadButtons
   put empty into sPadAxes
   repeat with tN = 0 to 25
      put "key:" & numToChar(65 + tN) into tRaw
      put numToChar(65 + tN) into sLabels[tRaw]
      put tRaw into sCodeRaw[65 + tN]
      put tRaw into sCodeRaw[97 + tN]
   end repeat
   repeat with tN = 0 to 9
      put "key:" & tN into tRaw
      put tN into sLabels[tRaw]
      put tRaw into sCodeRaw[48 + tN]
   end repeat
   set the itemDelimiter to tab
   repeat for each line tLine in inputRead(Input.DefaultFolder() & "/names.txt")
      if tLine is empty or char 1 of tLine is "#" then next repeat
      put item 1 of tLine into tRaw
      put item 2 of tLine into sLabels[tRaw]
      put item 3 of tLine into tWhat
      if tRaw begins with "key:" then
         set the itemDelimiter to comma
         repeat for each item tCode in tWhat
            put tRaw into sCodeRaw[tCode]
         end repeat
         set the itemDelimiter to tab
      else if tRaw begins with "pad:" then
         if word 1 of tWhat is "button" then
            put word 2 of tWhat into sPadButtons[tRaw]
         else if word 1 of tWhat is "axis" then
            put word 2 of tWhat & comma & word 3 of tWhat into sPadAxes[tRaw]
         end if
      end if
   end repeat
   put true into sNamesRead
end inputNames

function Input.Label pRaw
   inputNames
   if sLabels[pRaw] is not empty then return sLabels[pRaw]
   if pRaw begins with "key:#" then return "Key" && char 6 to -1 of pRaw
   return pRaw
end Input.Label

-- one spelling: key:w -> key:W; a whole stick (pad:LX) is left for inputSpread
private function inputTidy pRaw
   local tKind, tRest
   put word 1 to -1 of pRaw into pRaw
   set the itemDelimiter to ":"
   put toLower(item 1 of pRaw) into tKind
   put item 2 to -1 of pRaw into tRest
   if tKind is "key" and the number of chars of tRest is 1 then put toUpper(tRest) into tRest
   return tKind & ":" & tRest
end inputTidy

-- "key:A|key:Left" or "key:A,key:Left" -> a clean comma list, nothing twice, no Escape
private function inputList pText
   local tOut, tRaw
   replace "|" with comma in pText
   set the itemDelimiter to comma
   repeat for each item tRaw in pText
      if word 1 of tRaw is empty then next repeat
      put inputTidy(tRaw) into tRaw
      if tRaw is "key:Escape" then next repeat
      if tRaw is among the items of tOut then next repeat
      put tRaw & comma after tOut
   end repeat
   delete the last char of tOut
   return tOut
end inputList

-- is it a whole stick ("pad:LX"): its two halves go to the two sides of an axis
private function inputIsStick pRaw
   inputNames
   return (sPadAxes[pRaw & "-"] is not empty)
end inputIsStick

-- an axis' two sides from the columns: whole sticks in either column are spread over both
private command inputSpread pNeg, pPos, pStick, @rNeg, @rPos
   local tRaw, tAll
   put empty into rNeg
   put empty into rPos
   set the itemDelimiter to comma
   repeat for each item tRaw in inputList(pNeg)
      if inputIsStick(tRaw) then
         put tRaw & comma after tAll
      else
         put tRaw & comma after rNeg
      end if
   end repeat
   repeat for each item tRaw in inputList(pPos)
      if inputIsStick(tRaw) then
         put tRaw & comma after tAll
      else
         put tRaw & comma after rPos
      end if
   end repeat
   put inputList(pStick) after tAll
   repeat for each item tRaw in tAll
      if tRaw is empty then next repeat
      if inputIsStick(tRaw) then
         put tRaw & "-" & comma after rNeg
         put tRaw & "+" & comma after rPos
      end if
   end repeat
   put inputList(rNeg) into rNeg
   put inputList(rPos) into rPos
end inputSpread

-------------------------------------------------------------------- loading an app

command Input.Load pApp, pFile
   local tData, tLine, tName, tKind, tNeg, tPos
   put empty into sError
   inputNames
   put inputRead(pFile) into tData
   if tData is empty then
      put "no actions file " & pFile into sError
      return sError
   end if
   put pApp into sApp
   put pFile into sAppFile
   put empty into sOrder
   put empty into sAct
   put empty into sOwn
   put empty into sState
   put empty into sHeld
   put empty into sPulse
   set the itemDelimiter to tab
   repeat for each line tLine in tData
      if tLine is empty or char 1 of tLine is "#" then next repeat
      put word 1 to -1 of item 1 of tLine into tName
      put toLower(word 1 of item 2 of tLine) into tKind
      if tName is "input" and item 2 of tLine is a number then next repeat
      if tKind is not among the items of "button" & tab & "axis" then next repeat
      if sAct[tName]["kind"] is not empty then next repeat      -- a name listed twice: the first counts
      put tName & return after sOrder
      put tKind into sAct[tName]["kind"]
      put item 3 of tLine into sAct[tName]["title"]
      if sAct[tName]["title"] is empty then put tName into sAct[tName]["title"]
      if tKind is "axis" then
         inputSpread item 4 of tLine, item 5 of tLine, item 6 of tLine, tNeg, tPos
      else
         put empty into tNeg
         put inputList(item 4 of tLine) into tPos
      end if
      put tNeg into sOwn[tName]["neg"]
      put tPos into sOwn[tName]["pos"]
      set the itemDelimiter to tab
   end repeat
   delete the last char of sOrder
   if sOrder is empty then
      put "no actions in " & pFile into sError
      return sError
   end if
   inputReadProfileName
   inputReadSettings
   inputLayers
   inputPadCheck
   return empty
end Input.Load

-- the three layers again: own -> preset -> profile
private command inputLayers
   local tName, tData, tLine, tFile
   put empty into sPreset
   put Input.ProfileFile() into tFile
   put inputRead(tFile) into tData
   set the itemDelimiter to tab
   repeat for each line tLine in tData
      if tLine begins with "preset:" then put word 1 to -1 of (char 8 to -1 of tLine) into sPreset
   end repeat
   repeat for each line tName in sOrder
      put sOwn[tName]["neg"] into sAct[tName]["neg"]
      put sOwn[tName]["pos"] into sAct[tName]["pos"]
   end repeat
   if sPreset is not empty then inputApplyLines inputRead(inputPresetFile(sPreset))
   repeat for each line tName in sOrder
      put sAct[tName]["neg"] into sBase[tName]["neg"]
      put sAct[tName]["pos"] into sBase[tName]["pos"]
   end repeat
   inputApplyLines tData
end inputLayers

-- binding lines (a preset, a profile): action <tab> inputs   or   action <tab> negative <tab> positive
private command inputApplyLines pData
   local tLine, tName, tNeg, tPos
   set the itemDelimiter to tab
   repeat for each line tLine in pData
      if tLine is empty or char 1 of tLine is "#" or tLine begins with "preset:" then next repeat
      put word 1 to -1 of item 1 of tLine into tName
      if sAct[tName]["kind"] is empty then next repeat
      if sAct[tName]["kind"] is "axis" then
         inputSpread item 2 of tLine, item 3 of tLine, empty, tNeg, tPos
         put tNeg into sAct[tName]["neg"]
         put tPos into sAct[tName]["pos"]
      else
         put inputList(item 2 of tLine) into sAct[tName]["pos"]
      end if
      set the itemDelimiter to tab
   end repeat
end inputApplyLines

function Input.App
   return sApp
end Input.App

function Input.Actions
   return sOrder
end Input.Actions

function Input.Kind pAction
   return sAct[pAction]["kind"]
end Input.Kind

function Input.Title pAction
   return sAct[pAction]["title"]
end Input.Title

private function inputSide pSide
   if pSide is "neg" then return "neg"
   return "pos"
end inputSide

function Input.Bindings pAction, pSide
   return sAct[pAction][inputSide(pSide)]
end Input.Bindings

function Input.Words pAction, pSide
   local tOut, tRaw
   repeat for each item tRaw in sAct[pAction][inputSide(pSide)]
      put Input.Label(tRaw) & ", " after tOut
   end repeat
   delete char -2 to -1 of tOut
   return tOut
end Input.Words

-------------------------------------------------------------------- changing bindings

private function inputKnown pAction
   if sAct[pAction]["kind"] is not empty then return true
   put "no action " & pAction into sError
   return false
end inputKnown

command Input.SetBindings pAction, pSide, pList
   put empty into sError
   if not inputKnown(pAction) then return sError
   if sAct[pAction]["kind"] is "button" then put "pos" into pSide
   put inputList(pList) into sAct[pAction][inputSide(pSide)]
   return empty
end Input.SetBindings

command Input.Bind pAction, pSide, pRaw
   local tSide, tList
   put empty into sError
   if not inputKnown(pAction) then return sError
   put inputTidy(pRaw) into pRaw
   if pRaw is "key:Escape" then
      put "Escape belongs to the player" into sError
      return sError
   end if
   if char -1 of pRaw is ":" then
      put "no input given" into sError
      return sError
   end if
   put inputSide(pSide) into tSide
   if sAct[pAction]["kind"] is "button" then put "pos" into tSide
   put sAct[pAction][tSide] into tList
   if pRaw is among the items of tList then return empty
   if tList is not empty then put comma after tList
   put pRaw after tList
   put tList into sAct[pAction][tSide]
   return empty
end Input.Bind

command Input.Unbind pAction, pSide, pRaw
   local tSide, tList, tN
   put empty into sError
   if not inputKnown(pAction) then return sError
   put inputSide(pSide) into tSide
   if sAct[pAction]["kind"] is "button" then put "pos" into tSide
   if pRaw is empty then
      put empty into sAct[pAction][tSide]
      return empty
   end if
   put sAct[pAction][tSide] into tList
   put itemOffset(inputTidy(pRaw), tList) into tN
   if tN > 0 then delete item tN of tList
   put tList into sAct[pAction][tSide]
   return empty
end Input.Unbind

function Input.Conflicts
   local tUse, tName, tRaw, tSide, tOut, tKeys
   repeat for each line tName in sOrder
      repeat for each item tSide in "neg,pos"
         repeat for each item tRaw in sAct[tName][tSide]
            if tName is among the items of tUse[tRaw] then next repeat
            if tUse[tRaw] is not empty then put comma after tUse[tRaw]
            put tName after tUse[tRaw]
         end repeat
      end repeat
   end repeat
   put the keys of tUse into tKeys
   sort lines of tKeys
   repeat for each line tRaw in tKeys
      if tUse[tRaw] contains comma then put tRaw & tab & tUse[tRaw] & return after tOut
   end repeat
   delete the last char of tOut
   return tOut
end Input.Conflicts

-- back to the app's own file: no preset, none of the profile's lines (Input.Save makes it stay)
command Input.ResetApp
   local tName
   put empty into sPreset
   repeat for each line tName in sOrder
      put sOwn[tName]["neg"] into sAct[tName]["neg"]
      put sOwn[tName]["pos"] into sAct[tName]["pos"]
      put sOwn[tName]["neg"] into sBase[tName]["neg"]
      put sOwn[tName]["pos"] into sBase[tName]["pos"]
   end repeat
end Input.ResetApp

-------------------------------------------------------------------- presets

private function inputPresetFile pName
   local tFile
   put inputSafeName(pName) into pName
   if pName is empty then return empty
   put Input.UserPresetFolder() into tFile
   if tFile is not empty then
      put "/" & pName & ".txt" after tFile
      if there is a file tFile then return tFile
   end if
   put Input.DefaultFolder() & "/Presets/" & pName & ".txt" into tFile
   if there is a file tFile then return tFile
   return empty
end inputPresetFile

private function inputTxtNames pFolder
   local tOut, tFile
   if pFolder is empty or there is no folder pFolder then return empty
   repeat for each line tFile in files(pFolder)
      if tFile ends with ".txt" then put char 1 to -5 of tFile & return after tOut
   end repeat
   return tOut
end inputTxtNames

-- name <tab> Default|User, one a line
function Input.Presets
   local tSeen, tName, tOut, tNames
   repeat for each line tName in inputTxtNames(Input.DefaultFolder() & "/Presets")
      put "Default" into tSeen[tName]
   end repeat
   repeat for each line tName in inputTxtNames(Input.UserPresetFolder())
      put "User" into tSeen[tName]
   end repeat
   put the keys of tSeen into tNames
   sort lines of tNames
   repeat for each line tName in tNames
      put tName & tab & tSeen[tName] & return after tOut
   end repeat
   delete the last char of tOut
   return tOut
end Input.Presets

function Input.Preset
   return sPreset
end Input.Preset

-- a preset replaces the bindings of the actions it names; the others keep the app's own
command Input.UsePreset pName
   local tFile, tName
   put empty into sError
   if pName is empty then
      Input.ResetApp
      return empty
   end if
   put inputPresetFile(pName) into tFile
   if tFile is empty then
      put "no preset " & pName into sError
      return sError
   end if
   Input.ResetApp
   put inputSafeName(pName) into sPreset
   inputApplyLines inputRead(tFile)
   repeat for each line tName in sOrder
      put sAct[tName]["neg"] into sBase[tName]["neg"]
      put sAct[tName]["pos"] into sBase[tName]["pos"]
   end repeat
   return empty
end Input.UsePreset

private function inputLineOf pName
   local tLine
   put pName & tab into tLine
   if sAct[pName]["kind"] is "axis" then
      put sAct[pName]["neg"] & tab & sAct[pName]["pos"] after tLine
   else
      put sAct[pName]["pos"] after tLine
   end if
   replace comma with "|" in tLine
   return tLine
end inputLineOf

-- today's bindings as a preset of yours (Scripts/Input/Presets in the Data folder)
command Input.SavePreset pName
   local tFolder, tData, tName
   put empty into sError
   put inputSafeName(pName) into pName
   put Input.UserPresetFolder() into tFolder
   if pName is empty or tFolder is empty then
      put "no name, or no Data folder (LIB_DATA is not in use)" into sError
      return sError
   end if
   put "# LIB_INPUT preset " & pName & ", saved from " & sApp & return into tData
   repeat for each line tName in sOrder
      put inputLineOf(tName) & return after tData
   end repeat
   return inputWrite(tFolder & "/" & pName & ".txt", tData)
end Input.SavePreset

-------------------------------------------------------------------- profiles and settings

private command inputReadProfileName
   local tFolder
   put "Default" into sProfile
   put Input.ProfilesFolder() into tFolder
   if tFolder is empty then exit inputReadProfileName
   get inputSafeName(line 1 of inputRead(tFolder & "/current.txt"))
   if it is not empty then put it into sProfile
end inputReadProfileName

function Input.Profile
   if sProfile is empty then inputReadProfileName
   return sProfile
end Input.Profile

function Input.ProfileFolder
   local tFolder
   put Input.ProfilesFolder() into tFolder
   if tFolder is empty then return empty
   put "/" & Input.Profile() after tFolder
   inputMakeFolder tFolder
   return tFolder
end Input.ProfileFolder

function Input.ProfileFile
   local tFolder
   put Input.ProfileFolder() into tFolder
   if tFolder is empty or sApp is empty then return empty
   return tFolder & "/" & inputSafeName(sApp) & ".txt"
end Input.ProfileFile

function Input.Profiles
   local tFolder, tOut, tName
   put Input.ProfilesFolder() into tFolder
   if tFolder is not empty then
      repeat for each line tName in folders(tFolder)
         if char 1 of tName is not "." then put tName & return after tOut
      end repeat
   end if
   if "Default" is not among the lines of tOut then put "Default" & return before tOut
   delete the last char of tOut
   return tOut
end Input.Profiles

command Input.UseProfile pName
   local tFolder
   put empty into sError
   put inputSafeName(pName) into pName
   put Input.ProfilesFolder() into tFolder
   if pName is empty or tFolder is empty then
      put "no name, or no Data folder (LIB_DATA is not in use)" into sError
      return sError
   end if
   put pName into sProfile
   inputMakeFolder tFolder & "/" & pName
   get inputWrite(tFolder & "/current.txt", pName & return)
   inputReadSettings
   if sApp is not empty then inputLayers
   return it
end Input.UseProfile

-- a new profile, empty or a copy of another; it becomes the one in use
command Input.NewProfile pName, pCopyFrom
   local tFolder, tFile
   put empty into sError
   put inputSafeName(pName) into pName
   put Input.ProfilesFolder() into tFolder
   if pName is empty or tFolder is empty then
      put "no name, or no Data folder (LIB_DATA is not in use)" into sError
      return sError
   end if
   if there is a folder (tFolder & "/" & pName) then
      put "there is a profile " & pName & " already" into sError
      return sError
   end if
   create folder (tFolder & "/" & pName)
   put inputSafeName(pCopyFrom) into pCopyFrom
   if pCopyFrom is not empty and there is a folder (tFolder & "/" & pCopyFrom) then
      repeat for each line tFile in files(tFolder & "/" & pCopyFrom)
         put URL ("binfile:" & tFolder & "/" & pCopyFrom & "/" & tFile) into URL ("binfile:" & tFolder & "/" & pName & "/" & tFile)
      end repeat
   end if
   Input.UseProfile pName
   return the result
end Input.NewProfile

private command inputReadSettings
   local tPair, tLine, tFolder
   put empty into sSettings
   set the itemDelimiter to "|"
   repeat for each item tPair in kSettingDefaults
      set the itemDelimiter to comma
      put item 2 of tPair into sSettings[item 1 of tPair]
      set the itemDelimiter to "|"
   end repeat
   put Input.ProfileFolder() into tFolder
   if tFolder is empty then exit inputReadSettings
   set the itemDelimiter to tab
   repeat for each line tLine in inputRead(tFolder & "/settings.txt")
      if tLine is empty or char 1 of tLine is "#" then next repeat
      put item 2 of tLine into sSettings[item 1 of tLine]
   end repeat
end inputReadSettings

function Input.Setting pName
   if sSettings is not an array then inputReadSettings
   return sSettings[pName]
end Input.Setting

command Input.SetSetting pName, pValue
   if sSettings is not an array then inputReadSettings
   if pName is "deadzone" then
      if pValue is not a number then put 0.2 into pValue
      put max(0, min(0.9, pValue)) into pValue
   end if
   put pValue into sSettings[pName]
end Input.SetSetting

-- the profile's lines for this app (the preset's name, then only what differs from it) and the settings
command Input.Save
   local tFile, tData, tName, tFolder, tKeys
   put empty into sError
   put Input.ProfileFolder() into tFolder
   if tFolder is empty then
      put "no Data folder (LIB_DATA is not in use): nothing saved" into sError
      return sError
   end if
   if sApp is not empty then
      put "# LIB_INPUT: " & sApp & ", profile " & sProfile & return into tData
      if sPreset is not empty then put "preset: " & sPreset & return after tData
      repeat for each line tName in sOrder
         if sAct[tName]["neg"] is sBase[tName]["neg"] and sAct[tName]["pos"] is sBase[tName]["pos"] then next repeat
         put inputLineOf(tName) & return after tData
      end repeat
      get inputWrite(Input.ProfileFile(), tData)
      if it is not empty then return it
   end if
   put "# LIB_INPUT settings, profile " & sProfile & return into tData
   put the keys of sSettings into tKeys
   sort lines of tKeys
   repeat for each line tName in tKeys
      put tName & tab & sSettings[tName] & return after tData
   end repeat
   return inputWrite(tFolder & "/settings.txt", tData)
end Input.Save

-- layer <tab> file, for the developer face
function Input.Layers
   local tOut, tFile
   put "names" & tab & Input.DefaultFolder() & "/names.txt" & return into tOut
   put "app" & tab & sAppFile & return after tOut
   if sPreset is not empty then put "preset" & tab & inputPresetFile(sPreset) & return after tOut
   put Input.ProfileFile() into tFile
   if tFile is not empty and there is a file tFile then put "profile" & tab & tFile & return after tOut
   put Input.ProfileFolder() into tFile
   if tFile is not empty and there is a file (tFile & "/settings.txt") then put "settings" & tab & tFile & "/settings.txt" & return after tOut
   delete the last char of tOut
   return tOut
end Input.Layers

-------------------------------------------------------------------- the devices

command Input.Feed pList
   local tRaw, tValue
   put empty into sFeed
   if pList is empty then
      put false into sFeedOn
      exit Input.Feed
   end if
   put true into sFeedOn
   if pList is "none" then exit Input.Feed
   repeat for each item tRaw in pList
      put 1 into tValue
      set the itemDelimiter to "="
      if the number of items of tRaw > 1 then
         put item 2 of tRaw into tValue
         put item 1 of tRaw into tRaw
      end if
      set the itemDelimiter to comma
      put tValue into sFeed[inputTidy(tRaw)]
   end repeat
end Input.Feed

command Input.Pulse pRaw
   put 1 into sPulse[inputTidy(pRaw)]
end Input.Pulse

private command inputPadCheck
   local tErr
   put false into sPadOK
   put false into sPadSeen
   try
      put (xt3d_IsGamepadAvailable(Input.Setting("pad")) is true) into sPadSeen
      put true into sPadOK
   catch tErr
      put false into sPadOK
   end try
end inputPadCheck

private function inputDevicesNow
   local tHeld, tCode, tRaw, tN, tValue, tPad, tDead, tErr
   if sFeedOn is true then return sFeed
   inputNames
   repeat for each item tCode in the keysDown
      put sCodeRaw[tCode] into tRaw
      if tRaw is empty then put "key:#" & tCode into tRaw
      put 1 into tHeld[tRaw]
   end repeat
   if gNoMouse is not true then
      try
         repeat with tN = 1 to 3
            if mouse(tN) is "down" then put 1 into tHeld["mouse:" & tN]
         end repeat
      catch tErr
      end try
   end if
   if sPadOK is true then
      put Input.Setting("pad") into tPad
      put Input.Setting("deadzone") into tDead
      try
         if xt3d_IsGamepadAvailable(tPad) then
            put true into sPadSeen
            repeat for each key tRaw in sPadButtons
               if xt3d_IsGamepadButtonDown(tPad, sPadButtons[tRaw]) then put 1 into tHeld[tRaw]
            end repeat
            repeat for each key tRaw in sPadAxes
               put xt3d_GetGamepadAxisMovement(tPad, item 1 of sPadAxes[tRaw]) into tValue
               if item 2 of sPadAxes[tRaw] is "-" then multiply tValue by -1
               if tValue > tDead then put (tValue - tDead) / (1 - tDead) into tHeld[tRaw]
            end repeat
         else
            put false into sPadSeen
         end if
      catch tErr
         put false into sPadOK
      end try
   end if
   return tHeld
end inputDevicesNow

private function inputMost pList
   local tMost, tRaw
   put 0 into tMost
   repeat for each item tRaw in pList
      if sHeld[tRaw] is not empty and sHeld[tRaw] > tMost then put sHeld[tRaw] into tMost
   end repeat
   return min(1, tMost)
end inputMost

command Input.Poll
   local tName, tValue, tWas, tNow, tRaw
   put inputDevicesNow() into sHeld
   repeat for each key tRaw in sPulse
      put 1 into sHeld[tRaw]
   end repeat
   put empty into sPulse
   repeat for each line tName in sOrder
      put (sState[tName]["down"] is true) into tWas
      put inputMost(sAct[tName]["pos"]) - inputMost(sAct[tName]["neg"]) into tValue
      put (abs(tValue) >= 0.5) into tNow
      put tValue into sState[tName]["value"]
      put tNow into sState[tName]["down"]
      put (tNow and not tWas) into sState[tName]["pressed"]
      put (tWas and not tNow) into sState[tName]["released"]
   end repeat
end Input.Poll

function Input.Down pAction
   return (sState[pAction]["down"] is true)
end Input.Down

function Input.Pressed pAction
   return (sState[pAction]["pressed"] is true)
end Input.Pressed

function Input.Released pAction
   return (sState[pAction]["released"] is true)
end Input.Released

function Input.Axis pAction
   if sState[pAction]["value"] is empty then return 0
   return sState[pAction]["value"]
end Input.Axis

-- raw <tab> value <tab> words, for everything held at this moment (the developer face's Live tab)
function Input.Raw
   local tHeld, tKeys, tRaw, tOut
   put inputDevicesNow() into tHeld
   repeat for each key tRaw in sPulse
      put 1 into tHeld[tRaw]
   end repeat
   put the keys of tHeld into tKeys
   sort lines of tKeys
   repeat for each line tRaw in tKeys
      put tRaw & tab & round(tHeld[tRaw], 2) & tab & Input.Label(tRaw) & return after tOut
   end repeat
   delete the last char of tOut
   return tOut
end Input.Raw

function Input.Devices
   local tOut, tErr, tPadName
   inputPadCheck
   put "keyboard" & tab & "yes" & return into tOut
   if gNoMouse is true then
      put "mouse" & tab & "not read (a test is running)" & return after tOut
   else
      put "mouse" & tab & "yes" & return after tOut
   end if
   if sPadOK is not true then
      put "controller" & tab & "no controller on this edition (needs the xt3d bridge)" after tOut
   else if sPadSeen is not true then
      put "controller" & tab & "none plugged in" after tOut
   else
      try
         put xt3d_GetGamepadName(Input.Setting("pad")) into tPadName
      catch tErr
         put "controller" into tPadName
      end try
      put "controller" & tab & tPadName after tOut
   end if
   return tOut
end Input.Devices

-------------------------------------------------------------------- press a key...

command Input.CaptureStart
   put inputDevicesNow() into sCaptureFrom
   if sCaptureFrom is not an array then put empty into sCaptureFrom
end Input.CaptureStart

-- the first input held now that was not held at CaptureStart; "cancel" for Escape; empty = keep waiting
function Input.Capture
   local tHeld, tKeys, tRaw
   put inputDevicesNow() into tHeld
   repeat for each key tRaw in sPulse
      put 1 into tHeld[tRaw]
   end repeat
   put empty into sPulse
   if tHeld is not an array then
      put empty into sCaptureFrom
      return empty
   end if
   put the keys of tHeld into tKeys
   sort lines of tKeys
   if "key:Escape" is among the lines of tKeys then return "cancel"
   repeat for each line tRaw in tKeys
      if sCaptureFrom[tRaw] is empty and tHeld[tRaw] >= 0.5 then return tRaw
   end repeat
   -- a key let go since the start can be pressed again
   repeat for each key tRaw in sCaptureFrom
      if tHeld[tRaw] is empty then delete variable sCaptureFrom[tRaw]
   end repeat
   return empty
end Input.Capture

-- the new input takes the place of that line's inputs from the same device (keyboard and mouse
-- count as one device, the controller as another): what the app face does when a line is clicked
command Input.Rebind pAction, pSide, pRaw
   local tSide, tList, tOld, tIsPad
   put empty into sError
   if not inputKnown(pAction) then return sError
   put inputTidy(pRaw) into pRaw
   if pRaw is "key:Escape" then
      put "Escape belongs to the player" into sError
      return sError
   end if
   put inputSide(pSide) into tSide
   if sAct[pAction]["kind"] is "button" then put "pos" into tSide
   put (pRaw begins with "pad:") into tIsPad
   repeat for each item tOld in sAct[pAction][tSide]
      if (tOld begins with "pad:") is not tIsPad then put tOld & comma after tList
   end repeat
   put pRaw after tList
   put inputList(tList) into sAct[pAction][tSide]
   return empty
end Input.Rebind

-------------------------------------------------------------------- the two faces (they need LIB_GUI)
-- Input.ShowSettings   the app face (gui/input_app.gui): the app's own actions, nothing else
-- Input.ShowDeveloper  the developer face (gui/input_dev.gui): Live / Actions / Presets / Profiles / Files
-- Input.BuildFace "app" | "dev"   builds the window without showing it (tests)
-- The windows send their uses here: Input.FaceDo pStack, pName, pValue; Input.FaceTick pStack.
-- Every change is saved at once (Input.Save).

local sRows            -- app face: list line -> action,side
local sDevRows         -- developer face: list line -> action,side
local sCapFace, sCapAction, sCapSide, sCapAdd
local sTicking         -- stack -> true while a tick is on its way
local sLiveShown

constant kFaceScript = "on guiDo pName, pValue|   Input.FaceDo the short name of me, pName, pValue|end guiDo||on inputFaceTick|   Input.FaceTick the short name of me|end inputFaceTick|"
constant kNoPreset = "App default"

private function inputHome
   local tPath
   put the effective fileName of stack "LIB_INPUT" into tPath
   set the itemDelimiter to "/"
   return item 1 to -3 of tPath
end inputHome

-- a sister library, loaded from beside LIB_INPUT when it is not in use yet
private function inputNeed pStackName, pRelative
   local tPath
   if pStackName is among the lines of the stacksInUse then return true
   put inputHome() into tPath
   set the itemDelimiter to "/"
   put item 1 to -2 of tPath & "/" & pRelative into tPath
   if there is a file tPath then
      start using stack tPath
      return true
   end if
   return false
end inputNeed

command Input.BuildFace pWhich
   local tFile, tStack, tLayoutA, tScript
   put empty into sError
   if sApp is empty then
      put "no app loaded (Input.Load first)" into sError
      return sError
   end if
   if not inputNeed("lib_gui", "LIB_GUI/livecode/lib_gui.livecodescript") then
      put "The settings window needs LIB_GUI" into sError
      return sError
   end if
   if pWhich is "dev" then
      put "input_dev.gui" into tFile
      put "InputDev" into tStack
   else
      put "input_app.gui" into tFile
      put "InputApp" into tStack
   end if
   if there is no stack tStack then
      put Gui.Load(inputHome() & "/gui/" & tFile) into tLayoutA
      if tLayoutA is not an array then
         put "could not read " & tFile & ": " & Gui.Problems() into sError
         return sError
      end if
      put kFaceScript into tScript
      replace "|" with return in tScript
      Gui.Build tLayoutA, tStack, tScript
   end if
   inputFill tStack
   return empty
end Input.BuildFace

command Input.ShowSettings
   Input.BuildFace "app"
   if the result is not empty then return the result
   go stack "InputApp"
   return empty
end Input.ShowSettings

command Input.ShowDeveloper
   Input.BuildFace "dev"
   if the result is not empty then return the result
   go stack "InputDev"
   inputTickSoon "InputDev", 100
   return empty
end Input.ShowDeveloper

private command inputTickSoon pStack, pMS
   if sTicking[pStack] is true then exit inputTickSoon
   if there is no stack pStack then exit inputTickSoon
   put true into sTicking[pStack]
   send "inputFaceTick" to stack pStack in pMS milliseconds
end inputTickSoon

private function inputPicked pStack, pList
   local tN, tErr
   try
      put item 1 of the hilitedLines of control pList of card 1 of stack pStack into tN
   catch tErr
      put empty into tN
   end try
   return tN
end inputPicked

private command inputPick pStack, pList, pLineNumber
   local tErr
   if pLineNumber is empty then exit inputPick
   try
      set the hilitedLines of control pList of card 1 of stack pStack to pLineNumber
      Gui.ListMark the long id of control pList of card 1 of stack pStack
   catch tErr
   end try
end inputPick

private function inputOrNone pWords
   if pWords is empty then return "none"
   return pWords
end inputOrNone

private function inputOrNothing pWords
   if pWords is empty then return "(nothing)"
   return pWords
end inputOrNothing

-- the names of an axis' two lines: a title "Left / Right" gives both, else "<title> -" and "<title> +"
private command inputSideTitles pAction, @rNeg, @rPos
   local tTitle, tAt
   put sAct[pAction]["title"] into tTitle
   put offset(" / ", tTitle) into tAt
   if tAt > 0 then
      put char 1 to tAt - 1 of tTitle into rNeg
      put char tAt + 3 to -1 of tTitle into rPos
   else
      put tTitle && "-" into rNeg
      put tTitle && "+" into rPos
   end if
end inputSideTitles

private function inputConflictWords
   local tLine, tOut, tNames, tName, tTitles
   set the itemDelimiter to tab
   repeat for each line tLine in Input.Conflicts()
      put item 2 of tLine into tNames
      put empty into tTitles
      set the itemDelimiter to comma
      repeat for each item tName in tNames
         put sAct[tName]["title"] & " and " after tTitles
      end repeat
      delete char -5 to -1 of tTitles
      set the itemDelimiter to tab
      put Input.Label(item 1 of tLine) && "is on" && tTitles & ".  " after tOut
   end repeat
   return word 1 to -1 of tOut
end inputConflictWords

private command inputFill pStack
   if there is no stack pStack then exit inputFill
   if pStack is "InputDev" then
      inputFillDev
   else
      inputFillApp
   end if
end inputFill

private command inputFillApp
   local tLines, tName, tN, tNeg, tPos, tWas, tItems, tLine, tErr
   Gui.Window "InputApp"
   put inputPicked("InputApp", "actions") into tWas
   put empty into sRows
   put 0 into tN
   repeat for each line tName in sOrder
      if sAct[tName]["kind"] is "axis" then
         inputSideTitles tName, tNeg, tPos
         add 1 to tN
         put tName & ",neg" into sRows[tN]
         put tNeg & tab & inputOrNothing(Input.Words(tName, "neg")) & return after tLines
         add 1 to tN
         put tName & ",pos" into sRows[tN]
         put tPos & tab & inputOrNothing(Input.Words(tName, "pos")) & return after tLines
      else
         add 1 to tN
         put tName & ",pos" into sRows[tN]
         put sAct[tName]["title"] & tab & inputOrNothing(Input.Words(tName, "pos")) & return after tLines
      end if
   end repeat
   delete the last char of tLines
   put kNoPreset into tItems
   set the itemDelimiter to tab
   repeat for each line tLine in Input.Presets()
      put return & item 1 of tLine after tItems
   end repeat
   try
      set the title of stack "InputApp" to "Controls:" && sApp
      set the tabStops of control "actions" of card 1 of stack "InputApp" to 200
      set the text of control "actions" of card 1 of stack "InputApp" to empty
      set the text of control "preset" of card 1 of stack "InputApp" to tItems
   catch tErr
   end try
   Gui.Set "actions", tLines
   inputPick "InputApp", "actions", tWas
   if sPreset is empty then
      Gui.Set "preset", kNoPreset
   else
      Gui.Set "preset", sPreset
   end if
   Gui.Set "status", inputConflictWords()
end inputFillApp

private command inputFillDev
   local tLines, tName, tN, tSide, tRaws, tWas, tLine, tText, tErr
   Gui.Window "InputDev"
   Gui.Set "appname", "App:" && sApp & "      Profile:" && Input.Profile() & "      Preset:" && inputOrNone(sPreset)
   put Input.Devices() into tText
   replace tab with ": " in tText
   Gui.Set "devices", tText
   -- Actions
   put inputPicked("InputDev", "dactions") into tWas
   put empty into sDevRows
   put 0 into tN
   repeat for each line tName in sOrder
      repeat for each item tSide in "neg,pos"
         if tSide is "neg" and sAct[tName]["kind"] is not "axis" then next repeat
         add 1 to tN
         put tName & comma & tSide into sDevRows[tN]
         put sAct[tName][tSide] into tRaws
         replace comma with "|" in tRaws
         if sAct[tName]["kind"] is "axis" then
            put tName && tSide & tab & tRaws & return after tLines
         else
            put tName & tab & tRaws & return after tLines
         end if
      end repeat
   end repeat
   delete the last char of tLines
   try
      set the tabStops of control "dactions" of card 1 of stack "InputDev" to 160
      set the text of control "dactions" of card 1 of stack "InputDev" to empty
   catch tErr
   end try
   Gui.Set "dactions", tLines
   inputPick "InputDev", "dactions", tWas
   put Input.Conflicts() into tText
   replace tab with ":  " in tText
   Gui.Set "dconf", inputOrNone(tText)
   -- Presets
   put empty into tLines
   set the itemDelimiter to tab
   repeat for each line tLine in Input.Presets()
      put item 1 of tLine & tab & item 2 of tLine into tText
      if item 1 of tLine is sPreset then put tab & "in use" after tText
      put tText & return after tLines
   end repeat
   delete the last char of tLines
   inputSetList "InputDev", "dpresets", tLines
   -- Profiles
   put empty into tLines
   repeat for each line tLine in Input.Profiles()
      if tLine is sProfile then
         put tLine & tab & "in use" & return after tLines
      else
         put tLine & return after tLines
      end if
   end repeat
   delete the last char of tLines
   inputSetList "InputDev", "dprofiles", tLines
   Gui.Set "deadzone", round(Input.Setting("deadzone") * 100)
   Gui.Set "sensitivity", round(Input.Setting("sensitivity") * 100)
   Gui.Set "invert_y", (Input.Setting("invert_y") is true)
   -- Files
   inputSetList "InputDev", "dfiles", Input.Layers()
end inputFillDev

private command inputSetList pStack, pList, pLines
   local tWas, tErr
   put inputPicked(pStack, pList) into tWas
   try
      set the tabStops of control pList of card 1 of stack pStack to 160
      set the text of control pList of card 1 of stack pStack to empty
   catch tErr
   end try
   Gui.Set pList, pLines
   inputPick pStack, pList, tWas
end inputSetList

-- the first word(s) of the picked line of a developer list (before its first tab)
private function inputPickedName pStack, pList
   local tN, tLine, tErr
   put inputPicked(pStack, pList) into tN
   if tN is empty then return empty
   try
      put line tN of the text of control pList of card 1 of stack pStack into tLine
   catch tErr
      return empty
   end try
   set the itemDelimiter to tab
   return item 1 of tLine
end inputPickedName

private command inputSaveAndFill
   Input.Save
   inputFill "InputApp"
   inputFill "InputDev"
end inputSaveAndFill

private command inputStatus pStack, pWords
   if there is no stack pStack then exit inputStatus
   Gui.Window pStack
   if pStack is "InputDev" then
      Gui.Set "dstatus", pWords
   else
      Gui.Set "status", pWords
   end if
end inputStatus

command Input.FaceDo pStack, pName, pValue
   local tRow, tAction, tSide, tName, tLine, tErr, tRaws
   Gui.Window pStack
   if pStack is "InputApp" then
      put sRows[inputPicked(pStack, "actions")] into tRow
   else
      put sDevRows[inputPicked(pStack, "dactions")] into tRow
   end if
   put item 1 of tRow into tAction
   put item 2 of tRow into tSide
   switch pName
      -- the app face
      case "actions"
         if tAction is empty then exit Input.FaceDo
         inputCaptureFor pStack, tAction, tSide, false
         break
      case "preset"
         if pValue is kNoPreset then put empty into pValue
         Input.UsePreset pValue
         inputSaveAndFill
         break
      case "clear"
         if tAction is empty then
            inputStatus pStack, "Click a line first."
            exit Input.FaceDo
         end if
         Input.Unbind tAction, tSide
         inputSaveAndFill
         break
      case "reset"
         Input.ResetApp
         inputSaveAndFill
         break
      case "more"
         Input.ShowDeveloper
         break
      case "done"
         put empty into sCapFace
         Input.Save
         close stack pStack
         break
      -- the developer face
      case "pages"
         inputFill pStack
         break
      case "dactions"
         if tAction is empty then exit Input.FaceDo
         put sAct[tAction][tSide] into tRaws
         replace comma with "|" in tRaws
         Gui.Set "draw", tRaws
         break
      case "dset"
      case "draw"
         if tAction is empty then
            inputStatus pStack, "Click a line first."
            exit Input.FaceDo
         end if
         Input.SetBindings tAction, tSide, Gui.Get("draw")
         inputSaveAndFill
         break
      case "dadd"
         if tAction is empty then
            inputStatus pStack, "Click a line first."
            exit Input.FaceDo
         end if
         inputCaptureFor pStack, tAction, tSide, true
         break
      case "duse"
         put inputPickedName(pStack, "dpresets") into tName
         if tName is empty then exit Input.FaceDo
         Input.UsePreset tName
         inputSaveAndFill
         break
      case "dnone"
         Input.UsePreset empty
         inputSaveAndFill
         break
      case "dpsave"
         Input.SavePreset Gui.Get("dpname")
         inputStatus pStack, the result
         inputFill pStack
         inputFill "InputApp"
         break
      case "dprofuse"
         put inputPickedName(pStack, "dprofiles") into tName
         if tName is empty then exit Input.FaceDo
         Input.UseProfile tName
         inputFill pStack
         inputFill "InputApp"
         break
      case "dprofnew"
         Input.NewProfile Gui.Get("dprofname")
         inputStatus pStack, the result
         inputFill pStack
         inputFill "InputApp"
         break
      case "dprofcopy"
         Input.NewProfile Gui.Get("dprofname"), sProfile
         inputStatus pStack, the result
         inputFill pStack
         inputFill "InputApp"
         break
      case "deadzone"
         Input.SetSetting "deadzone", pValue / 100
         Input.Save
         break
      case "sensitivity"
         Input.SetSetting "sensitivity", pValue / 100
         Input.Save
         break
      case "invert_y"
         Input.SetSetting "invert_y", (pValue is true)
         Input.Save
         break
      case "dexplore"
         put inputPickedName(pStack, "dfiles") into tName
         put inputPicked(pStack, "dfiles") into tLine
         if tLine is empty then exit Input.FaceDo
         set the itemDelimiter to tab
         put item 2 of line tLine of Input.Layers() into tName
         if inputNeed("LIB_MENU", "LIB_MENU/livecode/lib_menu.livecodescript") then
            try
               Menu.Explore tName, false
            catch tErr
            end try
         end if
         inputStatus pStack, tName
         break
   end switch
end Input.FaceDo

private command inputCaptureFor pStack, pAction, pSide, pAdd
   local tNeg, tPos, tTitle
   put pStack into sCapFace
   put pAction into sCapAction
   put pSide into sCapSide
   put (pAdd is true) into sCapAdd
   put sAct[pAction]["title"] into tTitle
   if sAct[pAction]["kind"] is "axis" then
      inputSideTitles pAction, tNeg, tPos
      if pSide is "neg" then
         put tNeg into tTitle
      else
         put tPos into tTitle
      end if
   end if
   Input.CaptureStart
   inputStatus pStack, "Press the key or button for" && tTitle & " ...   (a mouse button: click these words.  Escape: leave it as it is)"
   inputTickSoon pStack, 50
end inputCaptureFor

-- a mouse button is bound by clicking the status line (which says so); a click anywhere else
-- is a click, not a binding, and ends the waiting
private function inputOverList pStack
   local tErr, tOver
   put false into tOver
   try
      put (the short name of the mouseControl is among the items of "status,dstatus") into tOver
   catch tErr
      put false into tOver
   end try
   return tOver
end inputOverList

command Input.FaceTick pStack
   local tRaw, tText
   put false into sTicking[pStack]
   if there is no stack pStack then
      if sCapFace is pStack then put empty into sCapFace
      exit Input.FaceTick
   end if
   if sCapFace is pStack then
      put Input.Capture() into tRaw
      if tRaw is "cancel" then
         put empty into sCapFace
         inputStatus pStack, "Left as it was."
      else if tRaw begins with "mouse:" and sFeedOn is not true and not inputOverList(pStack) then
         put empty into sCapFace
         inputStatus pStack, empty
      else if tRaw is not empty then
         put empty into sCapFace
         if sCapAdd then
            Input.Bind sCapAction, sCapSide, tRaw
         else
            Input.Rebind sCapAction, sCapSide, tRaw
         end if
         inputSaveAndFill
         put inputConflictWords() into tText
         if tText is empty then put "Now:" && Input.Label(tRaw) into tText
         inputStatus pStack, tText
      end if
   end if
   if sCapFace is pStack then
      inputTickSoon pStack, 50
   else if pStack is "InputDev" then
      -- the Live tab: what is held, as it changes
      Gui.Window pStack
      if Gui.Get("pages") is "Live" then
         put Input.Raw() into tText
         if tText is not sLiveShown then
            put tText into sLiveShown
            Gui.Set "live", inputOrNothing(tText)
         end if
      end if
      inputTickSoon pStack, 100
   end if
end Input.FaceTick
