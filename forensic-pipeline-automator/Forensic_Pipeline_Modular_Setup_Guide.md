# Air-Gapped Forensic Pipeline Deployment Manual

## 1. Storage Topology Requirements
To prevent catastrophic write bottlenecks and I/O deadlocks, your forensic workstation should use an isolated drive layout:
* **Drive C:\ (OS & System Binaries):** Running Windows 10/11 Pro and software roots.
* **Drive D:\ (Source Repository):** A high-capacity drive containing the pristine `.ufd` mobile images. Kept in a Read-Only state.
* **One dedicated drive per enabled engine:** a separate high-speed NVMe PCIe Gen 4/5 M.2 SSD for each forensic engine you enable (E:\, F:\, G:\, …). The script duplicates the case data there first, preventing the engines from fighting over read access on a single drive.

Every drive backing an **enabled** engine needs **at least 500 GB free** before a run will start — the pipeline checks this up front (once per unique drive letter, so two engines sharing a drive are only checked once) and refuses to launch if any of them fall short.

You don't strictly have to give every engine its own physical drive — the pipeline will happily run several engines against the same drive letter — but doing so is what avoids I/O contention between engines running concurrently on the same case.

## 2. Supported Engines
The pipeline now supports six forensic engines, each individually enabled with its own target drive/folder and executable path:

| Engine | Launch mode | Automation reality check |
|---|---|---|
| Cellebrite Physical Analyzer (PA10) | Runs `pas.exe` with command-line switches | Switches are a starting point — confirm against your installed build's CLI reference. |
| Magnet AXIOM Process | Runs `AxiomProcess.exe` with command-line switches | Same caveat — Magnet changes switches between releases. |
| Autopsy (Sleuth Kit) | **Watched-folder drop**, not a direct launch | Autopsy's real unattended pipeline is its multi-user **Automated Ingest** architecture (PostgreSQL + Solr) that watches an input folder — it does not process a case via command-line flags on the desktop app. This tool copies the case into the folder you configure and stops there; Autopsy itself picks it up on its own schedule. Set up Automated Ingest per Autopsy's own documentation first, and point the "Watched Ingest Folder" field at its configured input directory. |
| Oxygen Forensic Detective | Runs its `.exe` with command-line switches | Unattended/batch processing is normally gated behind Oxygen's own Automation/SDK add-on — confirm your license tier and the exact invocation before relying on this. |
| X-Ways Forensics | Runs `WinHex64.exe` with command-line switches | X-Ways automation is normally driven through X-Tensions or a refinement/scripting (`.txt`) file rather than simple flags — confirm the correct invocation in the X-Ways manual for your version. |
| MSAB XRY / XAMN | Runs its `.exe` with command-line switches | Unattended decode of an extraction typically requires the licensed XRY/XAMN Automate add-on — confirm your license includes it and check its own CLI reference. |

**None of the command-line switches shipped with this tool should be trusted blind in casework.** They are pre-filled starting points; every argument field is editable in the GUI, and the in-app notes under each engine restate the caveat above. Verify against your specific installed version before you rely on the output for anything evidentiary.

## 3. Setting Workstation Permissions
Because this script runs inside a secure, air-gapped laboratory environment, Windows execution policies must be adjusted to allow the unsigned script to initialize native .NET graphical forms.
1. Right-click your Windows Start button and select **PowerShell (Admin)** or **Terminal (Admin)**.
2. Run the following command to allow execution specifically within your current active session:
   ```powershell
   Set-ExecutionPolicy RemoteSigned -Scope Process
   ```
   To avoid repeating this every session, you can instead set it once for your user account (no admin rights required):
   ```powershell
   Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
   ```
   If your organisation enforces execution policy via Group Policy, neither option can override it — launch the script with `powershell -ExecutionPolicy Bypass -File .\ForensicPipeline_Modular.ps1` instead, or ask an administrator to allow `RemoteSigned`.

## 4. Running the Pipeline Interactively
1. Copy `ForensicPipeline_Modular.ps1` onto your forensic station.
2. Right-click the file and select **Run with PowerShell**.
3. In **Source Collection**, browse to the folder holding your `.ufd` collections.
4. In **Forensic Engines**, tick **Enable** for every engine you want this run to use. For each one you enable:
   * Set its **Target Drive/Folder** (for Autopsy, this is its Automated Ingest **watched input folder**, not an arbitrary drive).
   * Set its **Executable Path** (disabled/greyed out for Autopsy, since it isn't launched directly).
   * Read the small grey note under each engine — it states what that tool's automation actually requires.
5. Click **Initialize Pipeline**. The window runs the pipeline in a background job, so the on-screen log updates live and the window never shows "Not Responding".

## 5. What Happens During a Run
For each `.ufd` collection found in the source folder, the pipeline:
1. Runs the **500 GB free-space check** against every unique drive backing an enabled engine — if any is short, or an executable path for a "Process"-mode engine is missing, the run stops immediately with no files touched.
2. **Duplicates** the `.ufd` (and its sidecar `.bin`/`.tar` payload, if present) into a dedicated `<Case>_<Engine>_Run` folder on each enabled engine's target drive.
3. For each **Process**-mode engine (PA10, AXIOM, Oxygen, X-Ways, XRY), launches it against its own copy — all enabled Process-mode engines for a case start **at the same time**, so none of them wait on another's disk I/O.
4. For **Autopsy** (watched-folder mode), just leaves the copied case in the watched folder and logs it as queued — it is not tracked further by this pipeline.
5. Waits for every launched Process-mode engine to exit, logs its exit code, then moves on to the next case.

Cases are processed **one at a time** (all enabled engines run in parallel *within* a case, not across cases), so a run of 10 collections runs 10 sequential engine-batches rather than all of them at once — this keeps CPU/RAM contention predictable on a single workstation.

## 6. Monitoring, Logs and Output
* The **Terminal Execution Log** panel mirrors every step, heartbeat (every ~60 seconds while at least one engine is still running) and exit code live.
* A full-run text log is written to `ForensicPipeline_RunLog.txt` on the **first enabled engine's target drive** (not the read-only source drive) — keep this with the case files for an audit trail.
* Decoded output for a Process-mode engine lands under `<Engine Drive>\<Case>_<Engine>_Run\<Engine>_Decoded_Case`.
* Autopsy's case data lands wherever you pointed the watched ingest folder — check Autopsy's own Automated Ingest status for its processing state.
* The status label above **Initialize Pipeline** turns green on a clean finish or red if the background job terminated unexpectedly — either way, check the log for the per-case exit codes before considering a case complete. A "successful" case with a Watched-Folder engine only means the copy succeeded, not that Autopsy finished processing it.

## 7. Adjusting the Engine Command-Line Switches
Every vendor above changes its command-line syntax between releases, and the automation model differs by product (see the table in section 2). The argument fields in the GUI use these placeholders, which get substituted per case before launch:
* `{SOURCE}` — the full path to that engine's copy of the `.ufd` file.
* `{OUTPUT}` — the per-case output folder for that engine.
* `{CASE}` — the case name (the `.ufd` file's base name).

Edit the executable path and argument template directly in the GUI for any engine before clicking **Initialize Pipeline** — there is no need to edit the script itself unless you want to change the defaults for future runs (the registry lives near the top of `ForensicPipeline_Modular.ps1`, in the `$script:EngineDefinitions` array).

## 8. Troubleshooting

| Symptom | Fix |
|---|---|
| "executable not found" for a given engine | Fix that engine's executable path text box to match your actual install location. |
| "CRITICAL CAPACITY ERROR" | Free up space (or pick a different drive) so every drive backing an enabled engine has at least 500 GB free. |
| "Could not resolve a drive letter" | Point that engine's Target field at a local drive path (e.g. `E:\Cases`), not a UNC network share. |
| "Zero (.ufd) metadata collections found" | Confirm the source folder actually contains `.ufd` files, and that you selected the right folder. |
| "Select at least one forensic engine to run" | Tick the **Enable** checkbox for at least one engine before clicking Initialize. |
| An engine exits with a non-zero code | The engine itself failed — check that engine's own case log inside its decoded-output folder for the underlying error. |
| Autopsy never seems to process anything | This pipeline only copies the case into the watched folder — confirm Autopsy's Automated Ingest service is actually running and configured to watch that exact folder. |
| Window says "A pipeline run is already in progress" | Wait for the current run to finish (log ends with "Pipeline finished") before starting another. |
| Script won't run at all | Launch with `powershell -ExecutionPolicy Bypass -File .\ForensicPipeline_Modular.ps1`. |
