=== PKG SENDER FOR PS4 - iOS VERSION (source code) ===

IMPORTANT: this code has NOT been compiled or tested directly - I don't
have access to a Mac/Xcode in my environment. It was written carefully
by hand (matching FTP protocol semantics used by the Windows/macOS/
Linux/Android versions), and syntax-checked as much as possible without
a Swift compiler, but this will be the very first real compilation.
If GitHub Actions reports an error, copy the exact error message back
to me and I'll fix it.

===============================================
WHAT THIS IS
===============================================
A native iOS app (SwiftUI) with the exact same purpose as the other
versions: pick a .pkg file and send it straight to your PS4 over FTP,
to /data/pkg (the same place GoldHEN's Package Installer scans).

Since it's not distributed through the App Store, it's meant to be
installed via sideloading tools like KSign, ESign, AltStore, or
similar - which resign an unsigned .ipa with your own certificate.

===============================================
STEP 1: ADD THIS TO YOUR GITHUB REPO
===============================================
1. In your existing repo (kekeeek/pkgsenderps4), add a new folder
   called "PKGSenderIOS" and put all these files inside it, keeping
   the exact folder structure:

   PKGSenderIOS/
     project.yml
     Sources/
       PKGSenderApp.swift
       ContentView.swift
       SenderViewModel.swift
       FTPClient.swift
       DocumentPicker.swift

2. Also add the ".github" folder at the ROOT of your repo (not inside
   PKGSenderIOS) - if you already have a ".github/workflows" folder
   from before, just add "build-ios.yml" into it:

   .github/
     workflows/
       build-ios.yml

===============================================
STEP 2: TRIGGER THE BUILD
===============================================
Once both are pushed to your repo:

1. Go to the "Actions" tab on your GitHub repo page
2. You should see a workflow called "Build iOS IPA" in the list on
   the left
3. Click it, then click "Run workflow" (top right) -> "Run workflow"
   again to confirm
4. Wait for it to run (a macOS build usually takes a few minutes) -
   you'll see a yellow dot turn into a green checkmark (success) or
   red X (failed)

===============================================
STEP 3: DOWNLOAD THE IPA
===============================================
1. Once the workflow run finishes (green checkmark), click on that
   run
2. Scroll down to "Artifacts"
3. Download "PKGSenderForPS4-unsigned-ipa" - this is a zip containing
   the .ipa file

===============================================
STEP 4: INSTALL VIA KSIGN / ESIGN / ALTSTORE
===============================================
The .ipa produced here is UNSIGNED - that's expected and normal, since
I don't have an Apple Developer account to sign it with. Sideloading
tools like KSign/ESign/AltStore are specifically built to take an
unsigned or generically-packaged .ipa and re-sign it with your own
(free or paid) Apple ID before installing it on your device. Follow
your sideloading tool's normal "import IPA" flow with this file.

===============================================
IF THE GITHUB ACTIONS BUILD FAILS
===============================================
Go to the failed run, click on the "build" job, and expand the step
that has a red X - copy the error text you see there (especially any
line mentioning a specific .swift file and line number) and send it
to me. Since this is the first real compilation of this code, some
back-and-forth to fix small issues is expected - same as what happened
with the very first Android build.

===============================================
GITHUB ACTIONS FREE MINUTES
===============================================
macOS runners consume your free monthly Actions minutes about 10x
faster than Linux runners do. For occasional builds (testing this app,
fixing a bug once in a while) this should comfortably stay within
GitHub's free tier, but it's worth knowing if you plan to rebuild very
frequently.
