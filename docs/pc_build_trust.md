# Why Windows warns before 88fits.exe starts, and what each fix costs

Garry asked (pass 73): *"any way you can make it 'trustworthy' in the eyes of Windows so I don't get the warning
before launching it?"* This is the researched answer, written 2026-10-14. Every claim has a source at the end with
its date. Nothing was bought, no account was made and no certificate store was changed.

## The short answer

- **Why you see it.** Two causes stack up.
  - The Google Drive drive (E:, Google Drive for desktop) tells Windows that **every file in My Drive was downloaded
    from the Internet**. We checked on this PC: `88fits.exe`, the APK and the zips in `E:\My Drive\88fits builds\` all
    carry the "Mark of the Web" (`ZoneId=3`, the Internet zone). The local export
    `D:\_projects\88fits\game\export\88fits.exe` has no mark.
  - Windows SmartScreen checks a marked program before it runs. 88fits.exe is unsigned, and every build is a new file
    nobody has run before, so SmartScreen knows nothing about it and shows *"Windows protected your PC"* [1][2].
  - The Drive drive is a FAT32 virtual disk that hands Windows the mark itself. So "Run anyway" most likely cannot
    clear the mark there, and the question comes back every time you start that copy. This is inferred from how the
    mark works on such a drive; it was not tested.
- **The free fix for your own PCs: run a local copy.** Copy `88fits.exe` out of the Drive folder to a folder on the
  PC (the Desktop, `C:\Games\88fits`, ...) and start that copy.
  - A copy made with Explorer or PowerShell carries **no mark**. Both were tested on this PC: copied from
    `E:\My Drive`, the copy had no `Zone.Identifier`.
  - Without the mark SmartScreen does not check the file, so it starts without the warning [2].
  - On this PC you can also start `D:\_projects\88fits\game\export\88fits.exe` directly. It never had the mark, and
    ship.sh replaces it with every build.
- **For other people there is no cheap switch.** A paid code-signing certificate puts your name on the dialog. But
  Microsoft says a signed new app is still flagged *"unrecognized until reputation accumulates"*, which *"can take
  several weeks and hundreds of clean installs from a wide audience"* [1]. A handful of friends will not get there.
- **The only route that removes the warning at once for everyone is the Microsoft Store.**
  - An individual developer account has been free since September 2025 [9].
  - Microsoft re-signs MSIX packages, and Store apps never get the SmartScreen warning [1].
  - A "private audience" limits the app to Microsoft accounts you list [10].
  - The cost is packaging the game as MSIX and a certification wait of up to 3 business days per update [11].
- **Recommendation: buy nothing now.**
  - Run a local copy yourself.
  - Tell friends to use *More info → Run anyway* once per build.
  - Look at the Store (free) or an individual certificate (about €140-210 a year) only when the game goes to more
    people, or when a friend has Smart App Control on (see below).

## What was built in pass 73, so a certificate can drop in later

- **The icon.** `game/icon.ico` is made by `tools/make_win_icon.py` from the app icon `game/icon.png`. Each size is
  framed for its size:
  - 96 px and up: the whole picture.
  - 40-64 px: closer.
  - 16-32 px: the hat almost fills the tile, so the taskbar and Explorer show a hat, not a brown speck.

  The Windows preset embeds it. Godot keeps the 16, 32, 48, 64, 128 and 256 px images inside the exe. Checked on an
  export, both by reading the resources back and with Windows' own icon extraction.
- **The version info.** The exe's version now follows the game's (`application/config/version` in project.godot,
  0.58 → "0.58.0.0"), because the preset's version fields are empty [16].
  - Before this, the exe always said 0.50.0.0.
  - ship.sh checks this after every export (`tools/exe_info.py`).
  - Company "Teatree", product "88fits", description "88fits" and copyright "© 2026 Teatree" are filled in.
- **No rcedit.** The brief said Godot needs the rcedit tool to set the icon. That was true up to Godot 4.4. Since
  4.5, Godot writes the icon and version info itself; the change was merged on 2025-06-05 and removed the rcedit
  code [15]. Our 4.7.2 binary does not even contain the word "rcedit". So nothing was downloaded, and the leftover
  `export/windows/rcedit` line in the editor settings does nothing.
- **Signing, off until you add a certificate.** After the PC export, ship.sh signs the exe only if
  `tools/keys/codesign.env` exists (git-ignored, like the Android keystore). The script is `tools/sign_exe.ps1`.
  - It uses the Windows SDK's signtool, which is installed on this PC, or PowerShell's own signing if signtool is
    missing. It then reads the signature back.
  - If signing fails, the exe is **not** copied to Drive.
  - The file holds one of these three:

  ```
  CODESIGN_PFX=D:/keys/88fits.pfx        a certificate file ...
  CODESIGN_PASSWORD=...                  ... and its password
  CODESIGN_SHA1=<thumbprint>             or: a certificate in the Windows store (USB token, Certum SimplySign,
                                             SSL.com eSigner's card)
  CODESIGN_CMD=<command with {exe}>      or: a signing service's own tool
  CODESIGN_TIMESTAMP=http://timestamp.digicert.com   (default; "none" for no time-stamp)
  ```

  Tested with a throwaway self-signed certificate made as files only and deleted afterwards:
  - No `codesign.env`: copied unsigned.
  - A working certificate: signed, verified, copied.
  - A wrong password: stopped, not copied.
  - The signed exe still starts and loads the game packed inside it.

## Why Windows warns: the details

- **SmartScreen** looks at two things [1]:
  - whether the publisher's certificate is known and trusted;
  - whether this exact file (its hash) has been run safely by many people.

  An unsigned file starts from zero with every new version. Unsigned or self-signed, the dialog is "Windows protected
  your PC" and you must press *Run anyway*.
- **The check only happens for files marked as coming from the Internet** [2]. The mark is the `Zone.Identifier`
  stream that browsers attach to downloads [3]. Windows also used to show an older dialog for marked files, *"Open
  File - Security Warning"*; *Properties → Unblock* removes the mark [4][5].
  - Here the mark comes from the Drive drive itself, for every file. Google does not document this; it was measured
    on this PC (`Google Drive`, FAT32, Drive for desktop 132.0).
  - Copying the file to a normal disk drops the mark (tested: Explorer and PowerShell copies).
- **Smart App Control** (Windows 11) is stricter, and it is **off on this PC**.
  - When it is on, it *"will block execution of unsigned files unless the file has a positive reputation"*. Its
    checks apply to all programs, downloaded or not [1].
  - There is no per-app exception [6].
  - A friend with it on cannot run an unsigned 88fits.exe at all. A file signed with a certificate from a real
    certificate authority passes it [6][7].
- **Why not just turn SmartScreen off?** It would stop the question, but for every program you ever download. That
  is not a fix.

## Every route: cost, whether you can get it, what it gives, what it does not

You are an individual in the EU, with no company.

| Route | Cost (Oct 2026) | Open to you? | Your PCs | Friends | Notes |
|---|---|---|---|---|---|
| Run a local copy (or *Properties → Unblock* on a local copy) | free | yes | **no warning** | each friend must do the same | repeat per build: copy the new exe out of Drive |
| *More info → Run anyway* | free | yes | asks again each time on the Drive copy | works, except with Smart App Control on | |
| Self-signed certificate | free | yes | only if you install your own root certificate | **nothing** | SmartScreen treats it as *"same behavior as no signature"* [1]; a trusted root you made yourself is a security risk [8] |
| Individual (IV) code-signing certificate | Certum Standard: from **€139-209**/yr [12]; SSL.com IV: **$129**/yr plus a $379 YubiKey or eSigner cloud signing [13]; Sectigo via resellers about €285/yr [17] | **yes**, with ID checks | warning stays until reputation builds (your name shows) | same; **passes Smart App Control** | key on a token or in the CA's cloud since 2023 [14]; certificates last at most 460 days since 2026-03-01 [14] |
| EV certificate | €329-379 (Certum) [12] | **no**: organisations only [18] | no better than IV since 2024 [1] | | not worth it |
| Microsoft Artifact Signing (was Trusted Signing) | $9.99/month + a paid Azure subscription [16b] | **no**: individuals must live in the US or Canada [16b] | | | open to EU companies only |
| Microsoft Store (MSIX, private audience) | **free** for individuals [9] | **yes** (ID + selfie) | **no warning** (installed from the Store) | **no warning** | needs MSIX packaging; up to 3 business days per update [11]; private audience [10] |
| Steam (keys for friends) | $100 per game [19] | yes | probably none (Steam installs it) | probably none | 30-day wait, store page first; Valve does not document how it treats the mark |
| itch.io | free | yes | the itch app is said to avoid it (not confirmed) | same | restricted page with keys |
| Certum Open Source certificate | €25-69 | only for a **public open-source** project [18] | | | revoked if used for commercial software [18]; not for 88fits |

What an IV certificate needs and gives [12][13][14][18]:
- **Proof of who you are**: a passport or ID card with a selfie or video check, plus a utility bill or a phone
  callback.
- **A protected key**: a hardware key (USB token or card) or the CA's cloud signing. The old "certificate file" (.pfx)
  is no longer sold, so `CODESIGN_SHA1` or `CODESIGN_CMD` is the line you would use.
- **What it gives**: your name as the publisher in the dialog, Smart App Control's approval, and reputation that grows
  across versions signed with the same certificate.
- **What it does not give**: a warning-free first run. SSL.com says it plainly: *"A new IV certificate starts with no
  reputation"* [13].

## Recommendation

1. **Now:**
   - On this PC, start the local export or a Desktop copy.
   - On another PC, drag 88fits.exe from the Drive folder to the Desktop and start it there. No warning, no cost.
2. **Friends who try a build:** *More info → Run anyway*, once per build.
3. **If the game goes to more people, or a friend has Smart App Control on:** the Microsoft Store with a private
   audience is free and removes the warning for everyone. It costs one packaging step per release. An individual
   certificate (Certum Standard in the Cloud, about €209 a year, a Polish CA) is the alternative if you want to keep
   the single exe. It shows your name and passes Smart App Control, but the warning fades only as reputation builds.
4. **Skip:** EV certificates (no SmartScreen benefit any more, and companies only), Artifact Signing (closed to EU
   individuals), self-signed certificates (they change nothing for anyone else).

## Sources

- [1] Microsoft Learn, *SmartScreen reputation for Windows app developers*,
  https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/smartscreen-reputation (ms.date 2026-05-04,
  updated 2026-08-17).
- [2] Eric Lawrence (Microsoft), *Best Practices for SmartScreen AppRep*,
  https://textslashplain.com/2024/11/15/best-practices-for-smartscreen-apprep/ (2024-11-15, updated 2026-09-24).
- [3] *Mark of the Web*, https://en.wikipedia.org/wiki/Mark_of_the_Web (last edited 2026-08-03); Eric Lawrence,
  *Downloads and the Mark-of-the-Web*, https://textslashplain.com/2016/04/04/downloads-and-the-mark-of-the-web/
  (2016-04-04, updated 2026-09-01).
- [4] Microsoft Support, *Information about the Attachment Manager in Microsoft Windows*,
  https://support.microsoft.com/help/883260 (accessed 2026-10-14).
- [5] Microsoft Learn, *Unblock-File*,
  https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.utility/unblock-file (updated 2026-06-16).
- [6] Microsoft Support, *Smart App Control frequently asked questions*,
  https://support.microsoft.com/en-us/windows/smart-app-control-frequently-asked-questions-285ea03d-fa88-4d56-882e-6698afdb7003
  (accessed 2026-10-14).
- [7] Microsoft Learn, *Sign your app for Smart App Control compliance*,
  https://learn.microsoft.com/en-us/windows/apps/develop/smart-app-control/code-signing-for-smart-app-control
  (ms.date 2026-09-25).
- [8] Microsoft Learn, *Code signing options for Windows app developers*,
  https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/code-signing-options (ms.date 2026-08-29);
  *Create a certificate for package signing*,
  https://learn.microsoft.com/en-us/windows/msix/package/create-certificate-package-signing (updated 2025-06-10).
- [9] Windows Developer Blog, *Free developer registration for individual developers on Microsoft Store*,
  https://blogs.windows.com/windowsdeveloper/2025/09/10/free-developer-registration-for-individual-developers-on-microsoft-store/
  (2025-09-10).
- [10] Microsoft Learn, *Choose visibility options*,
  https://learn.microsoft.com/en-us/windows/apps/publish/publish-your-app/msix/visibility-options (ms.date 2026-08-28).
- [11] Microsoft Learn, *App certification process*,
  https://learn.microsoft.com/en-us/windows/apps/publish/publish-your-app/msix/app-certification-process
  (updated 2026-08-24).
- [12] Certum shop, *Code Signing*, https://shop.certum.eu/code-signing.html (accessed 2026-10-14; "from" prices in
  EUR, net and gross shown alike; "a single Code Signing certificate may be valid for a maximum of 459 days").
- [13] SSL.com, *IV Code Signing*, https://www.ssl.com/products/software-integrity/code-signing/iv/ (accessed
  2026-10-14: $129/yr for 1 year down to $96.75/yr for 5, YubiKey $379, government ID and a phone callback).
- [14] CA/Browser Forum, *Ballot CSC-31: maximum validity reduction*,
  https://cabforum.org/2025/11/17/ballot-csc-31-maximum-validity-reduction (adopted 2025-11-17, in force 2026-03-01:
  39 months → 460 days); *Code Signing Baseline Requirements* v3.11.0,
  https://cabforum.org/working-groups/code-signing/requirements/ (2026-06-16; keys in hardware since 2023-06-01).
- [15] Godot pull request #75950, *Export: Modify Windows template without rcedit*,
  https://github.com/godotengine/godot/pull/75950 (merged 2025-06-05, milestone 4.5).
- [16] Godot docs, *EditorExportPreset.get_version* ("fall back to the application/config/version project setting if
  set to an empty string"), https://docs.godotengine.org/en/stable/classes/class_editorexportpreset.html (accessed
  2026-10-14).
- [16b] Microsoft Learn, *Quickstart: Set up Artifact Signing*,
  https://learn.microsoft.com/en-us/azure/artifact-signing/quickstart (ms.date 2026-05-21, updated 2026-10-08:
  *"Individual developers must be located in the United States or Canada"*); price: Azure Retail Prices API
  (Basic $9.99/month), https://prices.azure.com/api/retail/prices (accessed 2026-10-14).
- [17] SSL Dragon, *Sectigo Code Signing*, https://www.ssldragon.com/product/sectigo-code-signing-ssl/ (accessed
  2026-10-14).
- [18] Certum, *Required documents*, https://www.support.certum.eu/en/required-documents/ (accessed 2026-10-14:
  Standard for individuals with ID verification and a utility bill; *"EV Code Signing certificates are issued only
  for organization"*; Open Source only for public open-source projects).
- [19] Steamworks, *Steam Direct*, https://partner.steamgames.com/steamdirect (accessed 2026-10-14).

Measured on this PC (2026-10-14, read-only apart from copies into a temporary folder):
- `Get-Content -Stream Zone.Identifier` on `E:\My Drive\88fits builds\88fits.exe` gives `ZoneId=3`. The local export
  has no such stream.
- The E: volume reads "Google Drive", FAT32, with Drive for desktop 132.0.0.0.
- A file copied from `E:\My Drive` with `Copy-Item` and with Explorer's copy engine (`Shell.Application.CopyHere`)
  has only `:$DATA`, so no mark.
- Smart App Control is off (`VerifiedAndReputablePolicyState = 0`).
