# RetroDojo Device Bench Suite - NEWBIE GUIDE

This guide is for someone who has never used ADB, PowerShell, or a command line before.

**ADB** means **Android Debug Bridge**. It is the official Google tool that lets your Windows PC talk to your Android device over USB.

**PowerShell** is the command window built into Windows that you will use to start the suite.

**Telemetry** means device readings such as temperature, battery, CPU load, and similar hardware numbers.

**JSON** means a plain-text settings file. In this tool, `devices.json` and `apps.json` are just editable lists of what device and apps to use.

**Package name** means the app's internal Android ID, such as `com.futuremark.dmandroid.application` for 3DMark.

Follow these steps in order.

## 1. One-time PC setup

1. On your Windows PC, open your web browser.
2. Go to the official Android platform-tools download page:  
   **https://developer.android.com/tools/releases/platform-tools**
3. Find the **Windows** download for **SDK Platform-Tools**.
4. Download the `.zip` file.
5. After the download finishes, open File Explorer.
6. Go to your **Downloads** folder.
7. Right-click the platform-tools `.zip` file and choose **Extract All...**
8. Extract it somewhere easy to find. Good example:  
   `C:\platform-tools`
9. Check whether PowerShell is already on your PC:
   - On Windows 10 and Windows 11, it normally already is.
   - Click **Start**, type **PowerShell**, and open **Windows PowerShell**.
10. Learn the 2 easiest ways to open PowerShell:
    - Method A: press **Windows key + X**, then click **Windows PowerShell** or **Terminal**
    - Method B: click **Start**, type **PowerShell**, then press **Enter**
11. In the PowerShell window, test ADB using the full path first. Type this exactly, then press **Enter**:

    ```powershell
    C:\platform-tools\adb.exe version
    ```

12. If you see version text that starts with something like `Android Debug Bridge version...`, ADB is installed correctly.
13. Optional: if you want to type just `adb` instead of the full path every time, add `C:\platform-tools` to your Windows PATH:
    - Click **Start**
    - Type **environment variables**
    - Click **Edit the system environment variables**
    - Click **Environment Variables...**
    - In the **User variables** section, click **Path**, then **Edit**
    - Click **New**
    - Add: `C:\platform-tools`
    - Click **OK** on every open window
    - Close PowerShell and open it again
14. Test the short command. In the new PowerShell window, type:

    ```powershell
    adb version
    ```

15. If that works, your PC setup is done.

## 2. One-time setup on each Android device

1. Turn on the Android device and complete normal first-time setup first.
2. Open **Settings** on the device.
3. Find the **About** section. Depending on the brand, it may be called:
   - **About phone**
   - **About tablet**
   - **About device**
4. Find **Build number**.
5. Tap **Build number** **7 times**.
   - Some brands hide it inside another page first.
   - If you cannot find it, use the Settings search box and search for **Build number**.
6. The device should show a message like:
   - `You are now a developer!`
   - or `Developer mode has been enabled`
7. Go back to the main **Settings** screen.
8. Find **Developer options**.
   - It is often under **System**
   - On some brands it is under **Additional settings**
9. Open **Developer options**.
10. Turn on **USB debugging**.
11. Confirm any warning message.
12. Important: **this tool does not require root**.
13. **Root** means changing Android so you get full system-level access. You do **not** need to root the device for this suite.
14. Connect the device to your PC with a USB cable.
15. Look at the device screen carefully.
16. The first time, you should get a pop-up that says something like:
    - `Allow USB debugging?`
    - It usually shows a long computer key or fingerprint
17. On that pop-up:
    - Check **Always allow from this computer** if that option is shown
    - Tap **Allow**
18. On the PC, open PowerShell.
19. Type this and press **Enter**:

    ```powershell
    adb devices
    ```

20. You want to see your device listed under `List of devices attached`.
21. A healthy result looks like this:

    ```text
    List of devices attached
    MC94516AQF051901944    device
    ```

22. If it says `unauthorized` instead of `device`, the PC is not approved yet.
23. Fix `unauthorized` like this:
    - Unlock the device screen
    - Unplug and reconnect the USB cable
    - Watch for the `Allow USB debugging?` pop-up again
    - Tap **Allow**
24. If the pop-up never comes back:
    - Go to **Settings > Developer options**
    - Tap **Revoke USB debugging authorizations**
    - Unplug and reconnect the USB cable
    - Run `adb devices` again
25. If the device does not show up at all:
    - Try a different USB cable
    - Try a different USB port on the PC
    - Avoid very cheap charge-only cables
    - Open **Device Manager** in Windows and look for any device with a yellow warning icon
    - Some brands need their own USB driver before ADB works correctly
26. If the device is company-managed, carrier-locked in a restrictive way, or has Developer Options hidden by policy, this tool may not be usable on that device without extra steps outside this guide.
27. When `adb devices` shows your device with the word `device`, this part is done.

## 3. Configure the device and the apps you want to test

1. Open File Explorer on your PC.
2. Go to this folder:

   `C:\Users\User\OneDrive\Retro Dojo\RD-Gauntlet`

3. Find the file `devices.json`.
4. Right-click it and choose **Open with > Notepad**.
5. You will see a list like this:

    ```json
    [
      {
        "name": "RPC6",
        "adbSerial": "MC94516AQF051901944",
        "notes": "Retroid Pocket Classic 6, Snapdragon G1 Gen2 (parrot), GammaOS Next Android 14 GSI reference device.",
        "checkStickDrift": false,
        "sampleHaptics": false,
        "capturePerfetto": false,
        "perfettoDurationSec": 15,
        "captureStorageSpeed": false,
        "captureWifiThroughput": false
      }
    ]
    ```

6. `name` is the nickname you will type later when you run the suite.
7. `adbSerial` is the device's unique ADB ID.
8. To find the correct `adbSerial`, run:

    ```powershell
    adb devices
    ```

9. In this example:

    ```text
    List of devices attached
    MC94516AQF051901944    device
    ```

   the `adbSerial` is `MC94516AQF051901944`.

10. To add a new device, copy the same shape and fill in your own values.
11. Example fill-in-the-blank device entry:

    ```json
    {
      "name": "MyHandheld",
      "adbSerial": "PUT-YOUR-ADB-SERIAL-HERE",
      "notes": "My review unit",
      "checkStickDrift": true,
      "sampleHaptics": true,
      "capturePerfetto": false,
      "perfettoDurationSec": 15,
      "captureStorageSpeed": false,
      "captureWifiThroughput": false
    }
    ```

12. If you keep more than one device in the file, make sure each device block is separated by a comma, except the last one.
13. Save `devices.json`.
14. Now open `apps.json` in Notepad.
15. This file lists the apps the suite will open and measure.
16. Important: **the apps in `apps.json` must already be installed on the Android device first**.
17. Install them on the device yourself from the Play Store, Aurora Store, or your normal app source before running the suite.
18. Example apps already in the file include 3DMark, Geekbench 6, PPSSPP, and RetroArch.
19. A typical app entry looks like this:

    ```json
    {
      "name": "3DMark",
      "package": "com.futuremark.dmandroid.application",
      "type": "benchmark",
      "durationSec": 180,
      "monkeyEnabled": true,
      "monkeyPctTouch": 70,
      "monkeyPctMotion": 20,
      "capturePerfetto": false,
      "perfettoDurationSec": 15,
      "captureStorageSpeed": false,
      "captureWifiThroughput": false,
      "notes": "Manual: user should tap through to Wild Life Extreme or Solar Bay; monkey only adds supplemental input/load variation and does not guarantee an official score run."
    }
    ```

20. What the important app fields mean:
    - `name` = friendly label shown in the report
    - `package` = the app's internal Android ID
    - `type` = general category such as `benchmark` or `game`
    - `durationSec` = how many seconds that app gets for its main test window
    - `monkeyEnabled` = whether the tool will auto-tap and auto-swipe inside the app
21. **Monkey** is Android's built-in random input tool. It sends lots of fake taps and swipes so an app keeps doing something even when you are not touching the device.
22. What `durationSec` means in plain English:
    - `180` = 3 minutes
    - `120` = 2 minutes
23. What `monkeyEnabled` means in plain English:
    - `true` = the tool will make the device look like it is “using itself” by sending lots of taps and swipes
    - `false` = the tool will just wait while **you** do the interaction
24. Leave `monkeyEnabled` on for unattended stress-style runs.
25. Use manual control instead for apps where you need an official benchmark score screen and a real **Start Test** button.
26. Save `apps.json`.

## 4. Run the automated part

1. Open PowerShell.
2. Go to the suite folder by typing this exactly, then press **Enter**:

    ```powershell
    cd "C:\Users\User\OneDrive\Retro Dojo\RD-Gauntlet"
    ```

3. Run the suite for your device name from `devices.json`. Example:

    ```powershell
    .\Invoke-BenchmarkSuite.ps1 -DeviceName RPC6
    ```

4. Replace `RPC6` with whatever `name` you put in `devices.json`.
5. If Windows blocks the script with an execution-policy message, run this once in that same PowerShell window:

    ```powershell
    Set-ExecutionPolicy -Scope Process Bypass
    ```

   then run the suite command again.

6. What the suite does on its own:
    - checks that the app is installed
    - launches the app
    - takes a beginning screenshot
    - starts telemetry logging
    - runs either an automatic monkey window or a manual waiting window
    - saves frame and battery information
    - takes an ending screenshot
    - records a 15-second cooldown after each app
    - builds `report.md` at the end
7. What you will see in PowerShell:
    - status lines with timestamps
    - countdown messages like `Monkey run for ...` or `Manual window for ...`
    - a final message saying the report was written
8. How long it takes:
    - about the total of all `durationSec` values in `apps.json`
    - plus about **15 extra seconds per app** for cooldown
    - plus a little extra for screenshots and file saving
9. If monkey is enabled, the device may:
    - tap itself rapidly
    - swipe around
    - look like it is “possessed”
10. That is normal. It is not a crash. The suite is intentionally sending random input inside that app.

## 5. The manual parts: exactly when you must step in

1. For **official 3DMark or Geekbench score runs**, do **not** rely on monkey.
2. Use this command instead:

    ```powershell
    .\Invoke-BenchmarkSuite.ps1 -DeviceName RPC6 -SkipMonkey
    ```

3. `-SkipMonkey` means the tool will still log everything, but it will stop auto-tapping and give you a manual interaction window instead.
4. Use `-SkipMonkey` when you want the real benchmark score flow.
5. Why: the scripts and research documents are very clear that monkey-based random tapping cannot reliably find the real **Start Test** button in 3DMark or Geekbench on every layout or version.
6. During a manual 3DMark or Geekbench run:
    - let the suite launch the app
    - look at the device screen
    - navigate to the exact benchmark you want
    - tap the real **Start Test** button yourself
    - wait for it to finish
    - avoid touching anything else during the run
7. For 3DMark specifically, the notes mention manual navigation to tests such as **Wild Life Extreme** or **Solar Bay**.
8. For Geekbench 6, use `-SkipMonkey` when you want the official CPU or GPU benchmark flow and score capture.
9. For emulator or game-style apps such as PPSSPP or RetroArch:
    - the app may launch successfully
    - but meaningful load still depends on having real content already loaded
10. In plain English: if the emulator is just sitting at a menu, the numbers will not represent real gameplay.
11. For the stick-drift check:
    - if `checkStickDrift` is turned on in `devices.json`, the suite will run a countdown
    - during that countdown and sampling window, **do not touch the controller at all**
12. Why: any accidental stick movement can make the drift result useless.
13. If the report later says stick drift is `unsupported`, that can be normal on some devices.
14. The script only works if the device exposes the needed analog-stick input data to ADB.
15. For haptic testing:
    - if `sampleHaptics` is turned on, the script will try a best-effort test
    - the research and helper script are honest that this may come back as `unsupported`
16. That is expected on some devices and is **not** your fault.
17. The current pure-ADB haptic method can fail because Android may not let the shell trigger the vibrator service, or because there is no reliable live motion reading available to score the rumble.
18. For Perfetto FPS capture:
    - treat it as a prototype feature only
    - the research explicitly says it is not yet a trustworthy final truth source for every game or benchmark
19. **Perfetto** is an advanced Android tracing system. In this suite it is only an experimental extra, not the main score you should trust for gameplay FPS.
20. After the run finishes, the report is saved inside the results folder.
21. Default results location:

    ```text
    .\results\<timestamp>\<deviceName>\
    ```

22. Inside that folder, open `report.md`.
23. `report.md` is a **Markdown** file, which means a plain-text report with simple formatting marks.
24. To open it:
    - easiest: right-click `report.md` and choose **Open with > Notepad**
    - if you use VS Code, you can also use its Markdown preview
25. Even in Notepad, it is readable as plain text.

## 6. Common troubleshooting / FAQ

1. **Problem: `adb` is not recognized**
   - Cause: Windows cannot find platform-tools
   - Fix: either use the full path:

     ```powershell
     C:\platform-tools\adb.exe devices
     ```

     or add `C:\platform-tools` to PATH as described earlier.

2. **Problem: `.\Invoke-BenchmarkSuite.ps1` is not recognized**
   - Cause: you are not inside the correct folder
   - Fix: run:

     ```powershell
     cd "C:\Users\User\OneDrive\Retro Dojo\RD-Gauntlet"
     ```

3. **Problem: `no devices/emulators found`**
   - Cause: USB debugging is not authorized, or the cable is power-only
   - Fix:
     - unlock the device
     - reconnect the cable
     - watch for the `Allow USB debugging?` pop-up
     - tap **Allow**
     - try another cable or USB port

4. **Problem: `unauthorized` in `adb devices`**
   - Fix:
     - on the device, go to **Developer options**
     - tap **Revoke USB debugging authorizations**
     - reconnect the cable
     - tap **Allow** on the device pop-up

5. **Problem: the app did not launch**
   - Cause: the `package` name in `apps.json` may be wrong, or the app is not installed on the device
   - Fix:
     - make sure the app is installed
     - double-check the `package` line in `apps.json`

6. **Problem: the script says the package is not installed**
   - Cause: same as above
   - Fix: install the app first, then run again

7. **Problem: monkey stopped early or the device seems frozen**
   - Fix:
     - in PowerShell, press **Ctrl + C**
     - if needed, just close the PowerShell window
     - on the device, open **Settings > Apps**
     - find the app
     - tap **Force stop**

8. **Problem: PowerShell says script execution is disabled**
   - Fix: in that same PowerShell window, run:

     ```powershell
     Set-ExecutionPolicy -Scope Process Bypass
     ```

     then run the suite command again.

9. **Problem: the report shows lots of `NA` values**
   - This is normal.
   - Different devices expose different hardware readings.
   - `NA` usually means that device did not provide that sensor or counter to the script.
   - It does **not** automatically mean you did something wrong.

10. **Problem: haptic test says `unsupported`**
    - This is expected on some Android builds.
    - The current pure-ADB method has real limitations.

11. **Problem: stick drift says `unsupported`**
    - This can also be expected.
    - Some devices do not expose the required analog-stick data in a way the script can read.

12. **Problem: the report file exists but looks plain**
    - That is fine.
    - `report.md` is a Markdown file, which is just plain text with simple formatting marks.
    - It is still readable in Notepad.

## 7. What this tool can and cannot tell you

1. What this tool **can** do well:
   - log real hardware telemetry while apps run
   - capture CPU and GPU activity when the device exposes it
   - log temperatures, battery level, and battery drain information when available
   - save screenshots and a repeatable report
   - run optional storage and Wi-Fi checks

2. What this tool **cannot** fully guarantee yet:
   - a trustworthy in-game frame-rate number for every emulator or game
   - a real button-to-screen input-lag measurement

3. Why the frame-rate limit exists:
   - many games, emulators, and benchmark apps draw their graphics in a way Android does not fully expose to simple ADB-only measurement
   - the research documents call this a real platform limitation, not a bug in your setup
   - the current Perfetto method is still prototype-quality

4. In plain English: for many games and emulators, this suite is excellent for thermals, battery, and system load, but it is **not yet the final truth tool for gameplay FPS**.

5. Why input lag is not included:
   - input lag means the delay between pressing a button and seeing the response on screen
   - ADB cannot measure that end-to-end delay correctly by itself
   - the honest method is filming the button press and screen together in slow motion, then counting frames by hand

6. In plain English: if you want real input-lag numbers for a video review, you still need a separate manual slow-motion camera test.

7. The honest expectation for this suite is:
   - **very useful for repeatable hardware numbers**
   - **not a magic one-button replacement for every kind of game-analysis measurement**

## Quick start summary

1. Install Android platform-tools from Google.
2. Confirm `adb version` works in PowerShell.
3. Turn on **Developer options** and **USB debugging** on the Android device.
4. Approve the `Allow USB debugging?` pop-up on the device.
5. Confirm `adb devices` shows your device as `device`.
6. Edit `devices.json` and `apps.json`.
7. Install the listed apps on the device.
8. Run:

   ```powershell
   cd "C:\Users\User\OneDrive\Retro Dojo\RD-Gauntlet"
   .\Invoke-BenchmarkSuite.ps1 -DeviceName YOUR-DEVICE-NAME
   ```

9. For official 3DMark or Geekbench score runs, use:

   ```powershell
   .\Invoke-BenchmarkSuite.ps1 -DeviceName YOUR-DEVICE-NAME -SkipMonkey
   ```

10. Open the finished `report.md` in the results folder.
