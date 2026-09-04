# Auto 49/50 — USB Compression & Transfer Tool

A Windows PowerShell + WPF application that watches for USB drives, hashes their
contents for chain-of-custody, compresses everything with **7-Zip** into a
single combined archive, and transfers it to a destination — all tagged with a
**CMS case number** and/or OP name (one of the two is required), plus an
optional pass number.

> Designed for evidence/collection style workflows where integrity (SHA-256 /
> MD5) and a clear audit trail matter.

---

## Features

| Requirement | How it's delivered |
|---|---|
| Detect new USB drives | WMI `Win32_VolumeChangeEvent` watcher; the drive is detected on insert |
| Prompt before acting | Yes/No dialog on insert (`AutoPromptOnInsert`), plus a final confirm |
| Choose folders/files | Built entirely from standard Windows dialogs - **Browse Folders...** (folder browser, looped so several folders can be added in one flow; each captured recursively, in full) and **Add Files...** (multi-select file picker) - no in-app tree to navigate. Each item gets its own **Remove**; **Clear Selection** empties the list |
| Source drive list | The "Source drive" dropdown lists **every** drive letter Windows has (fixed, removable, network, CD/DVD, RAM disk) - not just removable media - with a `Get-PSDrive` fallback if WMI is unavailable. Picking a drive from this dropdown by hand opens a folder browser rooted at that drive so you can pick a folder/sub-folder straight from it. With "Select all folders/files by default" on, plugging in a drive adds the whole drive to the selection automatically |
| Confirmation detail | Confirm dialog shows the **full source path** of each item, the destination folder and the zip names |
| Completion summary | When a job finishes, the destination path and the name of every file written there (archive/volumes + transfer log) are logged to the Activity Log and the "Transfer finished" popup |
| Slow Machine Mode | Header button for old/low-spec hardware: turns off the System Monitor's CPU/Memory/Network/Temp polling and forces single-threaded, store-only (no compression math) 7-Zip — trades speed for the smallest possible CPU/RAM footprint. Hashing, manifest and verification are unaffected |
| Transfer popup | A "Transfer in progress" window opens on start, mirroring the live events + progress |
| Duplicate-safe destination | Never overwrites: a clashing destination file name gets a date/time appended |
| Fault handling | Per-item and per-file errors are logged and skipped without aborting the whole job |
| CMS / OP / Pass in the name | CMS case (`CMS-A…`) and/or **UPPERCASE** OP name (one required) plus an optional operator **pass number** are combined into the folder/archive name |
| Quick Transfer | One button applies the fastest settings (store, **split into 250 MB parts**, **no hashing, no manifest, no verify**) — warns first that integrity is not recorded |
| All options on the main screen | Every setting (incl. **sizing** dropdown) on the on-screen Options panel; **Browse…** pickers for share/staging/7-Zip |
| Compress with 7-Zip | `7z.exe`, level 0–9, `zip` (default) or `7z`, optional AES-256 password, **multi-threaded** (`-mmt=on`) for both formats |
| Split into multiple files | Split-size **dropdown** (presets or custom MB; default **2 GB**); `0` = single file. **A split always uses native 7z volumes**, regardless of the configured archive format — see [Split archives are always native 7z](#split-archives-are-always-native-7z) below |
| SHA-256 + MD5 of originals | Per-file manifest (`.txt` + `.csv`), **embedded in the archive** |
| Transfer to a destination | UNC share or local folder; robocopy (**restartable mode, `/Z`** — resumes from the last checkpoint instead of re-copying after a dropped connection) with Copy-Item fallback |
| Combined single archive | All selected folders/files are always packed into ONE archive (not configurable) — one manifest covers everything, entries prefixed by each item's own top-level folder name |
| Transfer starts as soon as it's ready | Un-split archives transfer once the whole file is confirmed complete. A split archive's volumes are only knowable/complete once 7-Zip's process has fully exited, so all of them are picked up for transfer together right after that — never early |
| `.001` always transfers last | Within that same batch, whichever volume is named `.001` is deliberately held back and sent only once every other volume has already been queued. Since nothing can be reassembled/opened at the destination without `.001`, this means an incomplete set can't be mistaken for a finished one |
| Live transfer status | Per-file transfer status + running count on screen |
| Instant cancel + cleanup | Cancel kills 7-Zip/robocopy in ~150 ms and deletes temp files |
| Local copies always kept | Nothing is auto-deleted after a completed job — remove local copies manually, or with **Delete Local Copies** on the transfer-finished window (confirms first). A cancelled job's partial output is still cleaned up automatically |
| Failed-transfer log | If some files were already sent, a "FAILED TRANSFER" log (names, hashes, times) is written and sent |
| Staging space guide | Before starting, estimates the source size vs. **local staging** free space only (never the destination, to avoid slow-link latency). Non-blocking: a shortfall just logs a warning and the job proceeds automatically |
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

1. Connect a USB drive → it's detected and available in the "Source drive" list.
2. Click **Browse Folders...** and/or **Add Files...** to build the selection
   (or leave "Select all folders/files by default" on in Options to add the
   whole drive automatically on insert).
3. Enter **either** a CMS case (e.g. `CMS-A12345`) **or** an **UPPERCASE** OP name.
4. Click **Start Capture** and confirm the summary.

All options — including **sizing/volume split** — live in the **Options** panel on
the main screen; **Save Options** persists them.

Output at the destination (default: `zip` format, split into 2 GB volumes;
everything selected is always combined into ONE archive). Files land
**directly in the destination — no per-case sub-folder** — so the name itself
carries the CMS case and/or OP name, pass number if given, and this job's
timestamp, keeping every job's files unique there:

```
C:\Destination\
    CMS-A12345_20260818_143000.7z.001      (volume 1 – incl. embedded manifest covering everything selected)
    CMS-A12345_20260818_143000.7z.002      (volume 2)
```

> When **split** is off (`VolumeSizeMB = 0`) you get a single file in
> whichever format is configured, e.g. `CMS-A12345_20260818_143000.zip`.

#### Split archives are always native 7z

> A split archive is **always** built as native 7z volumes, regardless of the
> configured archive format — `ArchiveFormat: zip` only takes effect for an
> **un-split** archive. This isn't a preference, it's a correctness fix:
> 7-Zip's own volume switch (`-v`) only splits its native `.7z` container — it
> silently ignores `-v` for `.zip` (writes one whole file and exits 0 as if
> nothing were wrong). An earlier version of this tool worked around that by
> raw-byte-splitting a finished `.zip` itself into `.001`/`.002`/… parts. That
> turned out to be a real integrity risk: 7-Zip only ever reports a genuine,
> checked volume count (`Volumes = N`) for its *own* native multi-volume
> format — tested against a raw-byte-split zip with a part deliberately
> withheld, `7z l` still happily reported the **wrong**, present-file-count
> "Volumes = N" as if that were the true total, rather than failing. A
> receiving tool that trusts that number (rather than requiring a full `7z t`
> pass with 7-Zip's own "Everything is Ok") could act on a truncated result
> without any error ever being raised. Native 7z volumes don't have this gap:
> `7z l`/`7z t`/`7z x` against a real multi-volume 7z archive **only** report
> a volume count — or succeed at all — once every volume is genuinely present
> (verified against the archive's real end-of-archive header); given a
> partial set they fail outright with a non-zero exit code and "Unexpected
> end of archive", every time.
>
> Reassemble by opening the `.001` file in 7-Zip (all parts must be in the
> same folder), or from the command line: `7z x CMS-A12345_20260818_143000.7z.001`.
> Plain `copy /b`/`cat` concatenation does **not** work for native 7z volumes
> (unlike the old raw byte split) — you need 7-Zip (or a compatible tool like
> `7-Zip-zstd`/`p7zip`/`py7zr`) at the receiving end to open a split delivery.
> If that's a hard requirement for some recipients, keep archives **un-split**
> (`VolumeSizeMB = 0`) — 7-Zip's normal `zip` creation there is completely
> standard and opens with any zip utility.
>
> `.001` is always the LAST volume to actually arrive at the destination,
> regardless of compression order — every other volume transfers the moment
> the whole batch is ready, but `.001` is deliberately held back until they've
> all been queued. You can't reassemble/open the set without it, so this stops
> a still-incomplete transfer from looking usable.

The archive embeds `CMS-A12345_20260818_143000_MANIFEST.txt` and `.csv`
listing every original file's size, timestamp and SHA-256 / MD5 hash, with
each entry prefixed by its original top-level folder name (e.g.
`Photos\IMG001.jpg`) — or left unprefixed if that item was an individually
selected file rather than a folder.

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
- **StagingFolder** — local temp area for archives before transfer, default `C:\temp`.
  Local copies are **always kept** here after a completed job - there's no
  auto-delete setting. Remove them manually, or via **Delete Local Copies** on
  the transfer-finished window, which prompts you to confirm the files have
  reached their destination before deleting (a cancelled job's partial output
  is still cleaned up automatically, since it has no evidentiary value).
- **Password** — optional AES-256 archive password (prefer setting per-session
  in the Options panel rather than storing in plain text).

### Staging space guide

Before a capture starts, the tool sums the size of the selected items and
compares it against an **estimate** of the compressed size at your current
settings, then checks that estimate against the free space available in the
**local staging folder only**. The destination is deliberately never probed
here — over a slow link that round-trip just adds delay before the job can
even start, for a number that's advisory at best.

This is a **guide, not a gate**: it never blocks and never prompts. If it
looks tight, a warning is logged and the job proceeds automatically
regardless — parts stream out to the destination as soon as each is written,
so staging was never going to need to hold the whole archive at once anyway.

The compression estimate is a **planning heuristic only** — real compression is
entirely data-dependent. Already-compressed media (photos, video, most zip/7z
files) will shrink far less than the estimate suggests; the number is meant to
flag an obvious shortfall, not to predict the exact archive size.

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
