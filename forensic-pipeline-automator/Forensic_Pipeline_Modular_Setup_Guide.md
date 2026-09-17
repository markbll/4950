# Air-Gapped Forensic Pipeline Deployment Manual

## 1. Storage Topology Requirements
To prevent catastrophic write bottlenecks and I/O deadlocks, your forensic workstation must use the following isolated three-drive layout:
* **Drive C:\ (OS & System Binaries):** Running Windows 10/11 Pro and software roots.
* **Drive D:\ (Source Repository):** A high-capacity drive containing the pristine `.ufd` mobile images. Kept in a Read-Only state.
* **Drive E:\ & F:\ (NVMe Processing Spaces):** Two separate high-speed NVMe PCIe Gen 4/5 M.2 SSDs. The script duplicates data arrays here first, preventing `pas.exe` and `AxiomProcess.exe` from fighting over read access on a single drive.

Each of `E:\` and `F:\` needs **at least 500 GB free** before a run will start — the script checks this up front and refuses to launch if either drive falls short.

## 2. Setting Workstation Permissions
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

## 3. Running the Pipeline Interactively
1. Copy `ForensicPipeline_Modular.ps1` onto your forensic station.
2. Right-click the file and select **Run with PowerShell**.
3. Use the built-in **Browse** buttons to map your paths:
   * Source folder with your `.ufd` collections.
   * Work paths on your designated high-speed E:\ and F:\ storage spaces.
4. Confirm the **Static Tool Executable Paths** point at your installed `pas.exe` and `AxiomProcess.exe` (edit the text boxes if your install location differs from the defaults).
5. Click **Initialize Dual Pipeline**. The window runs the pipeline in a background job, so the on-screen log updates live and the window never shows "Not Responding".

## 4. What Happens During a Run
For each `.ufd` collection found in the source folder, the pipeline:
1. Runs the **500 GB free-space check** against both the PA10 and Axiom target drives — if either is short, the run stops immediately with no files touched.
2. **Duplicates** the `.ufd` (and its sidecar `.bin`/`.tar` payload, if present) into a dedicated `<Case>_PA10_Run` folder on the PA10 drive and a `<Case>_AXIOM_Run` folder on the Axiom drive.
3. Launches **PA10** and **AXIOM Process** against their own copies **at the same time**, so neither engine waits on the other's disk I/O.
4. Waits for both engines to exit, logging exit codes for each, then moves on to the next case.

Cases are processed **one at a time** (PA10 and AXIOM run in parallel *within* a case, not across cases), so a run of 10 collections runs 10 sequential PA10+AXIOM pairs rather than 20 processes at once — this keeps CPU/RAM contention predictable on a single workstation.

## 5. Monitoring, Logs and Output
* The **Terminal Execution Log** panel mirrors every step, heartbeat (every ~60 seconds while an engine is still running) and exit code live.
* A full-run text log is written to `ForensicPipeline_RunLog.txt` on the **PA10 NVMe drive** (not the read-only source drive) — keep this with the case files for an audit trail.
* Decoded PA10 output lands under `<PA10 Drive>\<Case>_PA10_Run\PA10_Decoded_Case`.
* Decoded AXIOM output lands under `<Axiom Drive>\<Case>_AXIOM_Run\Axiom_Decoded_Case`.
* The status label above **Initialize Dual Pipeline** turns green on a clean finish or red if the background job terminated unexpectedly — either way, check the log for the per-case exit codes before considering a case complete.

## 6. Adjusting the Engine Command-Line Switches
Cellebrite and Magnet periodically change their command-line syntax between releases. The script ships with:
```
pas.exe          -open "<file>" -method Forensic -project "<output>" -examine
AxiomProcess.exe /v "Mobile" /i "<file>" /o "<output>" /g
```
Before relying on this in casework, confirm these switches against the CLI reference shipped with **your installed version** of PA10 and AXIOM Process, and update the `$ProcPA` / `$ProcAX` lines in the script if they differ.

## 7. Troubleshooting

| Symptom | Fix |
|---|---|
| "PA10 engine not found" / "Axiom engine not found" | Fix the executable path text boxes to match your actual install location. |
| "CRITICAL CAPACITY ERROR" | Free up space (or pick different drives) so both E:\ and F:\ have at least 500 GB free. |
| "Could not resolve a drive letter" | Point the PA10/Axiom fields at a local drive path (e.g. `E:\Cases`), not a UNC network share. |
| "Zero (.ufd) metadata collections found" | Confirm the source folder actually contains `.ufd` files, and that you selected the right folder. |
| PA10 or Axiom exits with a non-zero code | The engine itself failed — check that engine's own case log inside its decoded-output folder for the underlying error. |
| Window says "A pipeline run is already in progress" | Wait for the current run to finish (log ends with "Pipeline finished") before starting another. |
| Script won't run at all | Launch with `powershell -ExecutionPolicy Bypass -File .\ForensicPipeline_Modular.ps1`. |
