#!/usr/bin/env python3
"""Copy Google's REVERSED_CLIENT_ID from the plist into the app's URL schemes.

Google sign-in on iOS returns to the app through a custom URL scheme, and the
scheme is the client id with its components reversed. Deriving it by hand is
where this goes wrong: the value must come from the *iOS* client, and a scheme
reversed from an Android or web client looks plausible, is accepted by Xcode,
and then the sign-in sheet opens and simply never comes back.

`GoogleService-Info.plist` only gains CLIENT_ID once Google sign-in is enabled
in the Firebase console, so run this after enabling it and re-running
`flutterfire configure`.

    python3 tool/sync_ios_url_scheme.py
"""

import plistlib
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SERVICE = ROOT / "ios" / "Runner" / "GoogleService-Info.plist"
INFO = ROOT / "ios" / "Runner" / "Info.plist"
NAME = "google-sign-in"


def main() -> int:
    if not SERVICE.exists():
        print(f"missing {SERVICE.relative_to(ROOT)} — run flutterfire configure")
        return 1

    service = plistlib.loads(SERVICE.read_bytes())
    reversed_id = service.get("REVERSED_CLIENT_ID")

    if not reversed_id:
        print(
            "GoogleService-Info.plist has no REVERSED_CLIENT_ID.\n"
            "Enable Google under Firebase console -> Authentication -> Sign-in\n"
            "method, then re-run `flutterfire configure`, then this script."
        )
        return 1

    info = plistlib.loads(INFO.read_bytes())
    schemes = [
        entry
        for entry in info.get("CFBundleURLTypes", [])
        if entry.get("CFBundleURLName") != NAME
    ]
    schemes.append(
        {
            "CFBundleTypeRole": "Editor",
            "CFBundleURLName": NAME,
            "CFBundleURLSchemes": [reversed_id],
        }
    )
    info["CFBundleURLTypes"] = schemes
    INFO.write_bytes(plistlib.dumps(info, sort_keys=False))

    print(f"Info.plist url scheme -> {reversed_id}")
    print("Rebuild natively for this to take effect: flutter clean && flutter run")
    return 0


if __name__ == "__main__":
    sys.exit(main())
