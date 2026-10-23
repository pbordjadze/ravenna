#!/usr/bin/env python3
"""Writes the SideStore/AltStore source (JSON) listing the latest IPA builds. Adapted from
paint-by-number's ci/sidestore_source.py.

    ci/sidestore_source.py <Ravenna.app> <icon-url>  > source.json

Versions come from this repository's `build-<n>` releases that carry an .ipa asset (newest
first); privacy usage descriptions come from the built app's Info.plist, so the source always
declares exactly what the app asks for. Needs `gh` with GH_TOKEN and GITHUB_REPOSITORY.
"""
import json
import os
import plistlib
import re
import subprocess
import sys

# The app's version is MARKETING.<build> (the ipa job's MARKETING_VERSION): SideStore compares the
# source's version with the installed app's.
MARKETING = "0.1"
# Builds listed; the ipa job in .github/workflows/ci.yml keeps this many releases (its `tail -n +6`).
KEEP = 5

app_path, icon_url = sys.argv[1], sys.argv[2]
repo = os.environ["GITHUB_REPOSITORY"]
info = plistlib.load(open(os.path.join(app_path, "Info.plist"), "rb"))

releases = json.loads(subprocess.run(
    ["gh", "api", f"repos/{repo}/releases?per_page=30"], check=True, capture_output=True, text=True).stdout)
versions = []
for r in releases:
    tag = r["tag_name"]
    ipa = next((a for a in r["assets"] if a["name"].endswith(".ipa")), None)
    if not tag.startswith("build-") or ipa is None:
        continue
    build = tag.removeprefix("build-")
    versions.append({
        "version": f"{MARKETING}.{build}",
        "buildVersion": build,
        "date": r["published_at"] or r["created_at"],
        # Release notes without CI tags ([compile], [ipa]), which older releases carry.
        "localizedDescription": re.sub(r" *\[(compile|ipa)\]", "", r["body"] or "").strip() or f"Build {build}",
        "downloadURL": ipa["browser_download_url"],
        "size": ipa["size"],
        "minOSVersion": info.get("MinimumOSVersion", "26.0"),
    })
versions.sort(key=lambda v: int(v["buildVersion"]), reverse=True)
versions = versions[:KEEP]
if not versions:
    sys.exit("no build-* release with an .ipa asset")
latest = versions[0]

description = (
    "Ancient pictures laid as Byzantine mosaics, to set tile by tile. A workshop build: "
    "unfinished, and not announced.")
app = {
    "name": info.get("CFBundleDisplayName", "Ravenna"),
    "bundleIdentifier": info["CFBundleIdentifier"],
    "developerName": repo.split("/")[0],
    "subtitle": "Set a mosaic, tile by tile",
    "localizedDescription": description,
    "iconURL": icon_url,
    "tintColor": "#C9A24A",
    "category": "entertainment",
    "versions": versions,
    # Legacy fields for clients that predate `versions`.
    "version": latest["version"],
    "versionDate": latest["date"],
    "versionDescription": latest["localizedDescription"],
    "downloadURL": latest["downloadURL"],
    "size": latest["size"],
    "appPermissions": {
        "entitlements": [],
        "privacy": {k: v for k, v in sorted(info.items()) if k.startswith("NS") and k.endswith("UsageDescription")},
    },
}
source = {
    "name": "Ravenna (CI builds)",
    "identifier": f"{info['CFBundleIdentifier']}.source",
    "subtitle": "Automatic builds",
    "iconURL": icon_url,
    "website": f"https://github.com/{repo}",
    "tintColor": "#C9A24A",
    "apps": [app],
    "news": [],
}
json.dump(source, sys.stdout, indent=2)
print()
