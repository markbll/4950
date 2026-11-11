# Change summary (Pass number mandatory)

## Behaviour
- Pass number is **required** for every job (standard app and Kiosk).
- CMS case number and OP name are **optional**.
- Destination path is now: `NetworkShare\\<PassNumber>\\` (subfolder named after the Pass).
- Setup includes **Remove Kiosk Auto-Start** to delete the Startup-folder shortcut.

## Files changed
- usb-transfer-tool/Start-Auto4950.ps1
- usb-transfer-tool/Start-Auto4950-Kiosk.ps1
- usb-transfer-tool/Setup.ps1
- usb-transfer-tool/Modules/Auto4950.Worker.psm1

## Note
If Auto4950.Worker.psm1 was temporarily overwritten, restore it from the release zip
or from the working tree that contains the PassNumber / ContainsKey destination logic.
