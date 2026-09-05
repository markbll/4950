# Auto 49/50 — USB Transfer Tool — Operator Guide

This guide explains day-to-day operation, what happens under the hood, and how
to troubleshoot.

---

## 1. Before you start

1. Install **7-Zip** (<https://www.7-zip.org>).
2. Run `Setup.ps1`:
   - On first launch it checks PowerShell's **execution policy**. If scripts are
     blocked it offers to set **`RemoteSigned` for your account** (no admin
     rights). Click **Yes** once and future launches "just work".
   - Set the **network share** (UNC) and click **Test** — it checks the share is
     reachable *and* writable.
   - Click **Auto-detect** for 7-Zip (or browse to `7z.exe`).
   - Choose your **compression level**, **hashing** (SHA-256/MD5), and defaults.
   - **Save**. This writes `config.json`.

**Execution policy.** These scripts are unsigned. If you'd rather not let Setup
change the policy, either set it once yourself:

```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
```

or bypass it per launch (changes nothing permanently):

```powershell
powershell -ExecutionPolicy Bypass -File .\Setup.ps1
powershell -ExecutionPolicy Bypass -File .\Start-Auto4950.ps1
```

If the policy is locked by **Group Policy**, use the Bypass option — Setup
detects this and will tell you.

---

## 2. The main window

```
┌ Header ───────────────────────────────────────────────────────────────────────────┐
│ Auto 49/50 + status  [Quick Transfer][Rescan Drives][Slow Machine: OFF][Hide Options][Help] │
├ System Monitor ─┬ Details + Selection ─┬ Options ───────────┬ Activity Log ────────┤
│ CPU             │ CMS Case Number      │ Destination         │ [09:31:02] ...        │
│ Memory          │ OP Name (UPPERCASE)  │ Format / Split size │ colour-coded          │
│ Network Mbps    │ Pass Number          │ Level / Hashing     │ events                │
│ Temp free space │ Drive ▼ [Refresh]    │ ...all options...   │                       │
│ Job progress    │ [Browse][Add Files]  │ [ Save Options ]    ├ Job Queue ────────────┤
│                 │                      │                     │ 2 job(s) queued       │
│                 │                      │                     │ [Start Queue][Stop]   │
│                 │                      │                     │ JobA - Edit - Remove  │
│                 │                      │                     │ JobB - Edit - Remove  │
├─────────────────┴──────────────────────┴─────────────────────┴───────────────────────┤
│ Destination: C:\Destination...   [Add to Queue] [Start Capture]  [Cancel]              │
└─────────────────────────────────────────────────────────────────────────────────────┘
```

Click **Hide Options** to collapse the Options column and give the Activity
Log more room (click **Show Options** to bring it back — nothing you've set is
lost either way).

### System Monitor (Task-Manager style)
- **CPU** — average processor load.
- **Memory** — used %, with used/total MB.
- **Network** — live throughput in **Mbps** (delta of adapter byte counters).
- **Temp folder free space** — free/total GB on the staging drive.
- **Job progress** — current stage (hashing / compressing) and percentage.

### Selection panel
The selection is built entirely from **native Windows multi-select dialogs** —
there's no in-app tree to expand level by level. Reaching a specific deep
sub-folder is just normal Explorer navigation inside the picker, not custom
UI.

- **Browse Folders...** opens the native Windows folder browser with
  **multi-select turned on** — pick several folders in one dialog
  (Ctrl/Shift-click, same as picking files in Explorer). Each one is added as
  a top-level entry and captured **recursively, in full** — everything
  beneath it — at capture time.
- **Add Files...** opens a multi-select file picker for individual files.
- Both **add to** the existing selection rather than replacing it, so folders
  and loose files combine freely. Each row in the list has its own
  **Remove**; **Clear Selection** empties the whole list.
- Pick the **source drive** from the dropdown (auto-selected on USB insert) —
  it's shown in the confirm summary and used by "Select all by default"
  below, but doesn't scan or list anything on its own.
- **"Select all folders/files by default"** (Options → Behaviour): when on,
  plugging in a USB drive adds the **whole drive** to the selection
  automatically, with no dialog — the flat-list equivalent of the old tree
  opening fully ticked. When off, nothing is added automatically; build the
  selection with Browse Folders.../Add Files... instead.
- Everything in the list is combined into **one** archive for the job.

### CMS case number / OP name
- Provide **at least one** of:
  - a **CMS case** — must begin with the configured prefix (default **`CMS-A`**)
    and include an identifier, e.g. `CMS-A12345`; **and/or**
  - an **OP name** — must be **UPPERCASE** (the box forces upper case as you type).
- A **pass number** on its own does not satisfy this requirement — it's always
  optional and only ever adds to the name.
- If **both** CMS case and OP name are filled in, **both** are used - the
  archive file name prefix is built from whichever of CMS case, OP name and
  pass number you supplied, joined together, plus the job's own timestamp.
  There is no destination sub-folder - see "Destination naming" below. Each
  hint highlights until its value is valid.

### Options panel (all settings, on the main screen)
Everything is editable on the right-hand **Options** panel — destination,
7-Zip path, staging folder, case prefix, **archive format**, **volume/split
size (sizing)**, **archive volume transfer mode**, compression level,
password, hashing, manifest embedding, verification, prompt-on-insert,
select-all default and exclude patterns. Changes apply immediately when you
press **Start**; **Save Options** writes them to `config.json` and then hides
the Options panel. Every checkbox can be ticked *and* un-ticked.

**Combined archive** — every folder/file you select is always packed into a
**single** archive (this is fixed behavior, not a setting): one shared
manifest lists every file, prefixed with its original top-level folder name so
nothing collides. With the default transfer mode, nothing transfers until
that one compression pass finishes; with **Transfer files instantly** (see
below), a split archive's volumes can start transferring well before
compression is done.

**Destination naming** — files land **directly in the destination**, with no
per-case sub-folder (this is fixed behavior, not a setting). Uniqueness comes
entirely from the file name: CMS case and/or OP name, pass number if given,
and this job's own timestamp, e.g. `CMS-A12345_JBLOGGS_20260818_143000.zip`.
The embedded manifest and the transfer log sent to the destination share the
same name. This keeps repeated jobs - even with the same case/OP/pass - from
ever colliding at the destination, without needing a folder per case.

### Slow Machine Mode
Click **Slow Machine: OFF** in the header to turn it **ON** for an old or
low-spec machine. While it's on:
- The **System Monitor** (CPU/Memory/Network/Temp) stops polling entirely and
  is hidden, rather than just polling less often.
- Compression is forced to **store** (no compression math) and
  **single-threaded**, regardless of the Level/format set in Options - this
  trades speed and archive size for the smallest possible CPU/RAM load.
- Hashing, the manifest and verification are **not** affected — integrity is
  never traded away for resource usage.

Click the button again to turn it back off. It's a session toggle rather
than an Options-panel checkbox, so it takes effect immediately without
needing **Save Options**.

### Completion summary
When a job finishes, the Activity Log (and the "Transfer finished" popup)
lists the **destination** path and the **name of every file** written there
— the archive (or each of its volumes) plus the transfer log — so you can
see exactly what landed where without opening the destination folder.

---

## 3. Running a capture

1. **Connect the USB drive** — it becomes available in the "Source drive"
   list, and (with "Select all folders/files by default" on) is added to the
   selection automatically. With prompt-on-insert on, a **Yes/No** dialog
   appears.
2. Build/adjust the **selection** with Browse Folders.../Add Files..., or by
   picking a drive from the "Source drive" dropdown (opens a folder browser
   rooted at that drive so you can add a folder/sub-folder straight from it —
   handy for local drives and external HDDs, not just USB sticks). Enter a
   **CMS case and/or OP name**
   (at least one is required), plus an optional **pass number**.
3. Click **Start Capture**. The tool logs a **staging space guide** (see
   below) and shows a confirm summary dialog listing every selected item's
   full source path, the destination folder and the resulting archive names.
   Or click **Add to Queue** to queue this job and build another one instead
   of starting immediately — see [Job queue](#job-queue) below.
4. A **"Transfer in progress"** window opens, mirroring the activity log and
   showing compress/transfer progress and a running transferred-file count.
5. Watch the **activity log**:
   - `STEP` (blue) = stage boundaries, `OK` (green) = success,
     `WARN` (amber), `ERROR` (red).

### Staging space guide
Before the job starts, the tool sums the size of your selected items,
estimates the compressed size at your current settings, and logs that against
the free space in the **local staging folder only** — the destination is
never checked here, so a slow link never adds delay before a job can start.
This is a **guide, not a gate**: it never prompts and never blocks. If it
looks tight, a warning is logged and the job proceeds automatically
regardless, since parts stream out to the destination as soon as each is
written rather than needing to fit all at once. It's a **planning estimate
only**: already-compressed data (photos, video, zip/7z files) shrinks far
less than typical documents.

### What happens internally
1. **Hash** every original file across your whole selection → one manifest
   (`.txt` human-readable + `.csv`), each entry prefixed by its top-level
   folder name.
2. **Compress** everything together with 7-Zip into ONE archive, **embedding
   the manifest**.
3. The archive (or its volumes) is **queued for transfer** to the
   destination per the "Archive volume transfer" setting — see § 4.
4. **Transfer** via robocopy (retry/resume) to `<dest>\<CASE>\<CASE>.<fmt>`.
   A destination file name clash is never overwritten — a date/time is
   appended instead.
5. If **VerifyAfterTransfer** is on, the archive is **re-hashed at the
   destination** and compared (SHA-256).
6. Local copies are **always kept** in the staging folder after a completed
   job — see "Temp cleanup" below.

A per-case log is also written to
`…\StagingFolder\<CASE>\<CASE>.log`.

### Temp cleanup
There is no auto-delete setting: local copies (the zip/7z file(s), manifest
and transfer log) stay in the staging folder after a completed job, whether
every file was confirmed or not. Remove them once you've confirmed the files
reached their destination — either manually, or with **Delete Local Copies**
on the transfer-finished window, which prompts you to confirm the destination
first and cannot be undone. A **cancelled** job is the one exception: its
partial output has no evidentiary value and is cleaned up automatically.

### Cancelling
**Cancel** is immediate: it kills the running 7-Zip/robocopy process within a
fraction of a second and deletes the temp files for the job. Archives already
confirmed on the share stay there, and a "FAILED TRANSFER" log listing them
(names, SHA-256, sizes, times) is written and sent to the destination.

### Job queue
This tool runs **one capture job at a time** — the job queue doesn't change
that, it just lines several jobs up to take their turn automatically instead
of needing a click between each one.

- **Add to Queue** — snapshots the current selection, CMS case/OP/pass **and
  every Options setting** into a queue entry, then clears the screen so you
  can build the next job. Because it's a full snapshot, a later change to
  Options (or Quick Transfer, or Slow Machine Mode) can never retroactively
  change a job that's already queued — each one runs with exactly the
  settings it had at the moment it was queued.
- **Start Queue** — runs queued jobs one after another, front of the queue
  first, automatically starting the next one the moment each finishes. No
  confirmation dialog interrupts an auto-started job (it was already
  reviewed when queued), but the same summary information is still logged.
- **Edit** (per queued job, in the Job Queue list) — pulls that job back out
  of the queue onto the main screen — selection, identifiers and Options all
  reload — so you can change anything, then either **Start Capture** it
  immediately or **Add to Queue** it again.
- **Remove** (per queued job) — cancels it outright; it's gone and will
  never run.
- **Stop Queue** — stops auto-advance only. Whatever job is currently
  running keeps running to completion (use the ordinary **Cancel** button
  for that); no further queued job starts by itself until you click
  **Start Queue** again.

A queued job still can't start while another job — queued or manually
started — is already running; the queue takes turns, it doesn't run jobs
concurrently.

### Notification sounds
The tool plays the Windows **Critical Stop** sound the moment any error is
logged (compress/transfer/verify failures, etc.), and the Windows
**Asterisk** (information) sound once a job finishes with everything
confirmed. Both use your system's default sound scheme, so they follow your
Windows volume/mute settings automatically.

---

## 4. Output layout

Files land **directly in the destination — no per-case sub-folder**.
Uniqueness comes from the file name itself (CMS case and/or OP name, pass
number if given, and the job's own timestamp):

```
C:\Destination\
    CMS-A12345_20260818_143000.zip            ← un-split (VolumeSizeMB = 0): one combined archive, manifest embedded inside
```

or, with a split size set:

```
C:\Destination\
    CMS-A12345_20260818_143000.7z.001         ← volume 1, manifest embedded inside
    CMS-A12345_20260818_143000.7z.002         ← volume 2
```

Inside the archive:
```
Photos\...                         (original files, grouped by top-level folder)
Documents\...
CMS-A12345_20260818_143000_MANIFEST.txt      (human-readable hashes, all items)
CMS-A12345_20260818_143000_MANIFEST.csv      (machine-readable hashes, all items)
```

Manifest header records: case number, source path, UTC timestamp, machine,
operator, file count and algorithms — a lightweight chain-of-custody record.

**A split archive is always native 7z, regardless of the configured archive
format.** `ArchiveFormat: zip` only takes effect for an **un-split** archive
(`VolumeSizeMB = 0`). This is a correctness fix, not a preference: 7-Zip's own
volume switch (`-v`) only splits its native `.7z` container — it silently
ignores `-v` for `.zip` (writes one whole file and exits 0 as if nothing were
wrong). An earlier version of this tool worked around that by raw-byte-
splitting a finished `.zip` into `.001`/`.002`/… parts. That turned out to be
a real integrity risk: 7-Zip only ever reports a genuine, checked volume
count for its *own* native format — tested against a raw-byte-split zip with
a part deliberately withheld, `7z l` still reported the wrong, present-file-
count "Volumes = N" as if that were the true total, rather than failing. A
receiving/watch-folder tool that trusts that number (instead of requiring a
full `7z t` pass with 7-Zip's own "Everything is Ok") could act on a
truncated result without any error ever being raised. Native 7z volumes
don't have this gap: `7z l`/`7z t`/`7z x` against a real multi-volume 7z
archive only report a volume count — or succeed at all — once every volume
is genuinely present; given a partial set they fail outright with a non-zero
exit code and "Unexpected end of archive", every time, with no misleading
count printed first.

Reassemble by opening the `.001` file in 7-Zip (all parts must be in the same
folder), or `7z x CMS-A12345_20260818_143000.7z.001` from the command line.
Plain `copy /b`/`cat` concatenation does **not** work for native 7z volumes —
you need 7-Zip (or a compatible tool) at the receiving end to open a split
delivery. If that's a hard requirement for some recipients, keep archives
**un-split** (`VolumeSizeMB = 0`); 7-Zip's normal `zip` creation there is
unaffected and opens with any zip utility.

**When each volume actually transfers is controlled by "Archive volume
transfer" in Options** (only relevant when split):

- **Transfer all files once completed** (default, safest) — 7-Zip is a
  separate process, and it does **not** necessarily finish writing its
  volumes in ascending numeric order internally (the first volume file can,
  in some cases, be the *last* one it actually finishes) — so no volume is
  picked up for transfer early; all of them are only reported once the whole
  7-Zip process has exited and every volume is confirmed complete.
- **Transfer files instantly** — each volume is picked up for transfer the
  moment 7-Zip finishes writing it, rather than waiting for the rest.
  Verified against real 7-Zip 23.01: 7-Zip writes each volume to a temporary
  file and only renames it to its final name once that volume's content is
  completely flushed and will never be touched again — that rename is the
  signal this mode watches for while 7-Zip is still running, backed by an
  exclusive-open probe as a second, best-effort check that nothing still has
  the file open before it's treated as safe to move. **Quick Transfer always
  turns this on.**

**Either way, `.001` is always the last volume to actually arrive.** It's
deliberately held back and queued last regardless of transfer mode — and
this isn't just an extra safety margin, it matches 7-Zip's own behaviour:
confirmed empirically, 7-Zip defers finalising volume `.001` until the exact
same instant as the very last volume, since the archive's start header can
only be written once the whole body is known. Since the set can't be
reassembled or opened at the destination without `.001`, this means a
still-incomplete transfer can never be mistaken for a finished one.

---

## 5. Settings reference

Edit the **Options** panel on the main screen and click **Save Options** (or
re-run `Setup.ps1`). All values persist to `config.json`.

| Setting | Meaning |
|---|---|
| Destination | UNC share or local folder for archives; default `C:\Destination` |
| 7-Zip path | Blank = auto-detect |
| Staging folder | Local temp area for archives; default `C:\temp` |
| Case prefix | Required prefix for case numbers (`CMS-A`) |
| Archive format | `zip` (default, portable) or `7z` (smaller) |
| Split into volumes (MB) | Max size per file; default **2048** (2 GB); `0` = single file |
| Archive volume transfer | "Transfer all files once completed" (default) or "Transfer files instantly"; only relevant when split - see § 4 |
| Compression level | 0 (store) … 9 (ultra) |
| Archive password | Optional AES-256 (encrypts headers too on `7z`) |
| Hash SHA-256 / MD5 | Which hashes to compute |
| Embed manifest | Include the manifest inside each archive |
| Prompt on insert | Show the Yes/No dialog automatically on USB insert |
| Select all by default | On USB insert, add the whole drive to the selection automatically |
| Verify after transfer | Re-hash the archive at the destination |
| Exclude patterns | Names to skip when compressing (e.g. `System Volume Information`) |

Local copies are always kept in the staging folder (no setting for this) -
see "Temp cleanup" above for how to remove them.

---

## 6. Troubleshooting

| Symptom | Fix |
|---|---|
| "7-Zip not found" | Install 7-Zip or set the path in the Options panel. |
| "USB auto-detection unavailable" | WMI eventing blocked; use **Rescan Drives** and pick the drive manually. |
| Share "not writable" in Setup | Check the UNC path, permissions, and that you're authenticated to it. |
| Nothing selected | Add at least one item with **Browse Folders...** or **Add Files...**, or turn on "Select all folders/files by default" in Options. |
| Case number rejected | It must start with `CMS-A` (or your prefix) and have an identifier. |
| Slow compression | Lower the compression level; level 1–3 is much faster. |
| Verify fails | Re-run; check network stability and destination free space. |
| Script won't run | Launch with `powershell -ExecutionPolicy Bypass -File …`. |

---

## 7. Forensic / integrity notes

- This tool **reads** originals and records hashes; it does **not** write-block
  the source. For evidential work, use a **write blocker**.
- Hashes are computed on the **original** files (pre-compression), so integrity
  can be proven independent of the archive.
- For a full audit trail, keep the per-case `.log` and the manifest `.csv`
  together with the archive.
- Consider signing the manifest and generating a chain-of-custody document —
  see "Recommended next steps" in the README.
