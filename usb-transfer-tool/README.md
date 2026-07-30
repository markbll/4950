# Auto 49/50 — USB Compression & Transfer Tool

A Windows PowerShell + WPF application that watches for USB drives, hashes their
contents for chain-of-custody, compresses everything with **7-Zip** into a
single combined archive, and transfers it to a destination — all tagged with a
**CMS case number**, OP name and/or pass number.

> Designed for evidence/collection style workflows where integrity (SHA-256 /
> MD5) and a clear audit trail matter.

---

## Features

| Requirement | How it's delivered |
|---|---|
| Detect new USB drives | WMI `Win32_VolumeChangeEvent` watcher; the drive is scanned and listed on insert |
| Prompt before acting | Yes/No dialog on insert (`AutoPromptOnInsert`), plus a final confirm |
| Auto-transfer | Tick-box: start automatically on insert, needing only a CMS case, OP name **or** pass number |
| Choose folders/files/drives | Checkbox tree with **selectable sub-folders/files**; Select All / **Deselect All clears every level**; drive Refresh |
| Confirmation detail | Confirm dialog shows the **full source path** of each item, the destination folder and the zip names |
| Transfer popup | A "Transfer in progress" window opens on start, mirroring the live events + progress |
| Duplicate-safe destination | Never overwrites: a clashing destination file name gets a date/time appended |
| Fault handling | Per-item and per-file errors are logged and skipped without aborting the whole job |
| CMS / OP / Pass in the name | CMS case (`CMS-A…`), **UPPERCASE** OP name, and operator **pass number** are combined into the folder/archive name |
| Quick Transfer | One button applies the fastest settings (store, **split into 250 MB parts**, **no hashing, no manifest, no verify**) — warns first that integrity is not recorded |
| All options on the main screen | Every setting (incl. **sizing** dropdown) on the on-screen Options panel; **Browse…** pickers for share/staging/7-Zip |
| Compress with 7-Zip | `7z.exe`, level 0–9, `zip` (default) or `7z`, optional AES-256 password |
| Split into multiple files | Split-size **dropdown** (presets or custom MB; default **2 GB**); `0` = single file |
| SHA-256 + MD5 of originals | Per-file manifest (`.txt` + `.csv`), **embedded in the archive** |
| Transfer to a destination | UNC share or local folder; robocopy with Copy-Item fallback |
| Combined single archive | All selected folders/files are always packed into ONE archive (not configurable) — one manifest covers everything, entries prefixed by each item's own top-level folder name |
| Transfer starts as soon as it's ready | For a split `zip`, each volume (`.001`, `.002`, …) begins transferring the instant it's fully written — no need to wait for the rest. `7z` volumes and unsplit archives transfer once the whole file is confirmed complete |
| Live transfer status | Per-file transfer status + running count on screen |
| Instant cancel + cleanup | Cancel kills 7-Zip/robocopy in ~150 ms and deletes temp files |
| Temp cleanup on success | Each file is removed from staging once its transfer is **confirmed** (copied, and hash-verified if verification is on); the whole temp job folder is swept at the end once *everything* is confirmed. Nothing is deleted if a file failed or failed verification |
| Failed-transfer log | If some files were already sent, a "FAILED TRANSFER" log (names, hashes, times) is written and sent |
| Destination space check | Before starting, estimates the source size vs. destination free space; if it looks tight, suggests a compression level/format estimated to fit (or lets you continue/cancel) |
| Full-screen GUI | The window opens maximised |
| Collapsible Options | "Hide Options" in the header collapses the Options panel, giving the Activity Log more room |
| Real-time events/log | Colour-coded activity log (auto-scrolls) with hashes, file names, dates/times; per-case `.log` file |
| Post-transfer verification | Re-hash the archive at the destination (SHA-256 match) |
| Notification sounds | An audible chime on a clean finish, and an alert sound on any error — Windows system sounds, respecting your OS volume/mute |

---

## Requirements

- **Windows 10/11** (or Windows Server) with **Windows PowerShell 5.1** or **PowerShell 7**.
- **7-Zip** installed — <https://www.7-zip.org>. The tool auto-detects `7z.exe`;
  otherwise set its path in the Options panel.
- Permission to write to the configured network share.
- A PowerShell **execution policy** that allows local scripts to run (see below).

---

## Execution policy

These scripts are **unsigned**, so Windows' default policy (`Restricted` on
client editions) will block them. You have three options:

1. **Let Setup fix it (recommended).** The first time you run `Setup.ps1`, it
   detects a restrictive policy and offers to set **`RemoteSigned` for your user
   account** — no administrator rights needed, and it only affects you. After
   that you can just right-click the scripts → **Run with PowerShell**.

2. **Set it yourself, once**, in a normal (non-admin) PowerShell window:

   ```powershell
   Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
   ```

3. **Bypass per launch** (nothing is changed permanently):

   ```powershell
   powershell -ExecutionPolicy Bypass -File .\Setup.ps1
   powershell -ExecutionPolicy Bypass -File .\Start-Auto4950.ps1
   ```

> If your organisation enforces the policy via **Group Policy**, option 1/2
> can't override it — use option 3, or ask an administrator to allow
> `RemoteSigned`. Setup detects this case and tells you.

---

## Quick start

**Easiest — just double-click the batch launchers** (they run PowerShell with the
execution policy bypassed for that one process, so nothing on the machine is
changed):

- **`Setup.bat`** — first-time configuration wizard
- **`Start-Auto4950.bat`** — start the tool

Or from a PowerShell prompt:

```powershell
powershell -ExecutionPolicy Bypass -File .\Setup.ps1
powershell -ExecutionPolicy Bypass -File .\Start-Auto4950.ps1
```

Or right-click either `.ps1` and choose **Run with PowerShell**.

1. Connect a USB drive → it is **scanned** and its folders/files are listed.
2. Tick what to capture (all pre-selected); use **Select All** / **Deselect All**.
3. Enter **either** a CMS case (e.g. `CMS-A12345`) **or** an **UPPERCASE** OP name.
4. Click **Start Capture** and confirm — or tick **Auto-transfer** to skip the
   prompts and start automatically whenever a drive is plugged in (it just needs
   a CMS case or OP name to already be filled in).

All options — including **sizing/volume split** — live in the **Options** panel on
the main screen; **Save Options** persists them.

Output at the destination (default: `zip` format, split into 2 GB volumes;
everything selected is always combined into ONE archive):

```
C:\Destination\CMS-A12345\
    CMS-A12345.001      (volume 1 – incl. embedded manifest covering everything selected)
    CMS-A12345.002      (volume 2)
```

> When **split** is off (`VolumeSizeMB = 0`) you get a single file, e.g.
> `CMS-A12345.zip`. Reassemble volumes by opening the `.001` file in 7-Zip (all
> parts must be in the same folder) — or, without 7-Zip, concatenate the parts
> in order: `copy /b CMS-A12345.001+CMS-A12345.002 CMS-A12345.zip`.
>
> 7-Zip's own volume switch only splits its native `.7z` format — it silently
> ignores splitting for `.zip`. So for `zip` archives, this tool builds the
> complete archive first and then splits it itself into `.001`/`.002`/… parts
> (the same raw sequential-byte layout 7-Zip's own volumes use), so the split
> size setting works for **both** archive formats.

The archive embeds `CMS-A12345_MANIFEST.txt` and `.csv` listing every original
file's size, timestamp and SHA-256 / MD5 hash, with each entry prefixed by its
original top-level folder name (e.g. `Photos\IMG001.jpg`).

---

## Files

| File | Purpose |
|---|---|
| `Start-Auto4950.bat` | **Double-click launcher** for the tool (bypasses execution policy) |
| `Setup.bat` | Double-click launcher for the Setup wizard |
| `Start-Auto4950.ps1` | Main GUI application (**Auto 49/50**) |
| `Setup.ps1` | First-run / reconfiguration wizard |
| `Modules/Auto4950.Core.psm1` | Config, 7-Zip, hashing, transfer, stats (UI-free) |
| `Modules/Auto4950.Worker.psm1` | Background compress→transfer pipeline |
| `config.json` | Your saved settings (created by Setup) |
| `config.example.json` | Template you can copy to `config.json` |
| `docs/USER_GUIDE.md` | Full operator guide |

---

## Configuration (`config.json`)

See `config.example.json`. Key settings:

- **NetworkShare** — destination (UNC share or local folder), default `C:\Destination`.
- **SevenZipPath** — leave blank to auto-detect.
- **ArchiveFormat** — `zip` (default, portable) or `7z` (smaller, AES-256).
- All selected folders/files are always combined into **one** archive — this
  is fixed behavior, not a setting.
- **VolumeSizeMB** — split the archive into volumes of this size in MB
  (default **2048** = 2 GB); `0` = one file. Changeable in Setup **and** Settings.
- **CompressionLevel** — `0` (store, fastest) … `9` (ultra, smallest).
- **HashAlgorithms** — any of `SHA256`, `MD5`.
- **VerifyAfterTransfer** — re-hash the archive at the destination.
- **AutoTransfer** — start automatically on USB insert (needs a CMS case or OP name).
- **StagingFolder** — local temp area for archives before transfer, default `C:\temp`.
- **DeleteLocalArchive** — delete each staged file once its transfer is
  **confirmed** (default **on**); the whole temp job folder is removed once every
  file in the job is confirmed. Anything not confirmed (failed copy, failed
  verification, or a cancelled job) is left in place for review.
- **Password** — optional AES-256 archive password (prefer setting per-session
  in the Options panel rather than storing in plain text).

### Destination free-space check

Before a capture starts, the tool sums the size of the selected items and
compares it against an **estimate** of the compressed size at your current
settings, then checks that estimate against the free space actually available
at the destination (works for both UNC shares and local folders). If it looks
like it won't fit:

- **Auto-transfer** just logs a warning and continues — it never prompts.
- **Manual start** shows a dialog with a suggested format/level expected to fit,
  and lets you **apply it and continue**, **continue anyway**, or **cancel**.

The compression estimate is a **planning heuristic only** — real compression is
entirely data-dependent. Already-compressed media (photos, video, most zip/7z
files) will shrink far less than the estimate suggests; the number is meant to
catch an obvious shortfall, not to predict the exact archive size.

---

## Suggested enhancements (implemented / recommended)

**Implemented**
- Post-transfer SHA-256 verification of each archive.
- Embedded + sidecar hash manifest (`.txt` and `.csv`).
- AES-256 archive encryption option.
- robocopy transfer with retry + Copy-Item fallback.
- Per-case operator/machine/timestamp metadata in the manifest.

**Recommended next steps**
- **Write-blocking**: pair with a hardware/software write blocker for true
  forensic soundness (this tool reads originals but does not block writes).
- **Digital signing** of manifests (e.g. sign the `.csv` with a certificate).
- **Central audit log** (append case events to a database or SIEM).
- **Bit-level imaging** option (e.g. capture a raw image with FTK/dd) for cases
  needing a full disk image rather than file-level collection.
- **Chain-of-custody PDF** generated per case.
- **Run as a service / auto-launch** on login for kiosk-style intake stations.

See `docs/USER_GUIDE.md` for operating detail and troubleshooting.
