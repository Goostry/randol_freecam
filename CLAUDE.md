# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A FiveM (GTA V) resource: a cinematic free camera driven by an ox_lib menu. Originally by Randolio (rewrite of Kiminaze's cinematiccam), extended by Goostry with freeze modes, translations, instructional-button scaleform, and a DB-backed max-distance bypass. Lua 5.4 (`lua54 'yes'`), `fx_version 'cerulean'`.

There is no build, lint, or test tooling. Changes are verified in-game: `ensure randol_freecam` / `restart randol_freecam` from the server console (txAdmin), then `/ccam` (default key F7).

Runtime dependencies: `ox_lib` (menu, notify, callbacks, `lib.addCommand`, `lib.locale`, `lib.load`, `cache`) and `oxmysql`.

## Architecture

- **[cl_freecam.lua](cl_freecam.lua)** — all camera logic, held in file-local state (`FREE_CAM`, `camActive`, `camFrozen`, `freezeMode`, `followActive`, DOF/filter values).
  - `startCam` spawns a per-frame thread calling `processCamControls`; `stopCam(mode)` ends that loop. When it ends with `camFrozen == false`, the thread calls `resetEverything()`. With `'static'` the cam stays where it is; with `'follow'` `startFollowCam` runs a second thread that keeps the cam's offset and heading relative to the ped.
  - `/ccam` (F7) only toggles the camera: on, or fully off (also from a frozen state). `/ccammenu` (no default key) opens/closes the menu without touching the cam.
  - `freezeMode` mirrors the actual state: checking a freeze box freezes immediately (`setFreezeMode` → `stopCam`/`freezeCam`), unchecking it calls `startCam` to take back control, and `startCam`/`resetEverything` set it back to `'off'`. After such changes `refreshCamMenu(index)` re-renders the open menu so the checkboxes match. Closing the menu does not affect the cam.
  - `turnCamOff` saves `freezeMode` into `lastFreezeMode`; `turnCamOn` (F7, or the 'Toggle Camera' checkbox when no cam exists) recreates the cam and re-applies that freeze. The panic reset clears it.
  - The instructional buttons are only drawn while the menu is open.
  - `menuAutoOpen` (session only): when F7 turns the cam on, the menu opens automatically unless the player last hid it. `onClose` (player closes only) sets it to false; opening via `/ccammenu` sets it back to true. Internal closes (refresh, copycam, panic reset) must use `lib.hideMenu()` without `true` so they don't count as a player close.
  - Movement is clamped to `Config.MaxDistance` from the ped (a red sphere is drawn at the limit) unless `hasBypassPermission` is true. Collisions use a swept-sphere shape test and slide along the hit surface.
  - Menu callbacks branch on **positional option indices** (`selected == 2`, `== 9`, …). If you add, remove, or reorder entries in `options`, update `onSideScroll`, `onCheck`, and the submit callback to match.
  - `registerCamMenu()` is called again every time the menu opens, so `checked` and `defaultIndex` reflect the current state.
  - Death (`CEventNetworkEntityDamage` on the local player) force-resets the cam.
- **[sv_freecam.lua](sv_freecam.lua)** — the bypass permission system. Two layers:
  - Persistent permission in MySQL table `ccam_permissions`, keyed by the `license` identifier. The table is auto-created at startup; [ccam_permissions.sql](ccam_permissions.sql) has the same schema. `/ccamgrant <id> [on|off]` sets it and is restricted to `group.admin`.
  - Session toggle `bypassActive[source]` (in memory), flipped by `/ccambypass` when the player has the permission. It is pushed to the client via the `ccam:setBypass` event and resynced on client start through the `ccam:getBypassState` callback.
- **[config.lua](config.lua)** — returns a table and is loaded on the client with `lib.load('config')`. It is not a global `Config`. Holds the command name, distance/speed/FOV limits, disabled controls, the DOF value lists (strings, run through `tonumber` when used), and a long timecycle `Filters` list (index 1 `'None'`).
- **[locales/](locales/)** — `en.json` / `fr.json` loaded by `lib.locale()`. Every `locale('key')` used in code needs an entry in both files. Server chat messages are currently hardcoded in English and do not use locales.

## Conventions

- Client↔server event and callback names use the `ccam:` prefix.