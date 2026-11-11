#!/usr/bin/env python3
# ergou-ime — check every download in ModelCatalog against its source.
# SPDX-License-Identifier: GPL-3.0-only
#
#   python3 scripts/check-model-urls.py
#
# Settings downloads models and dictionaries from fixed URLs and rejects any
# file whose SHA-256 differs from the value in the code. Some publishers
# replace a release file in place (RIME-LMDG's "LTS" 万象整句模型 was
# re-uploaded 2026-11-10), after which every download fails. This script
# asks each host for the file's current SHA-256 without downloading it:
#   GitHub Releases  the asset "digest" in the releases API
#   Hugging Face     the LFS sha256 in the x-linked-etag header
# and exits 1 if one is gone or changed. scripts/release.sh runs it first.
# Set GITHUB_TOKEN to avoid the API's 60-requests-an-hour limit.
import json
import os
import pathlib
import re
import sys
import urllib.error
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parent.parent
CATALOG = ROOT / "ErgouIMESettings/Model/ModelCatalog.swift"
GITHUB = re.compile(r"^https://github\.com/([^/]+)/([^/]+)/releases/download/([^/]+)/([^/]+)$")
HF = re.compile(r"^https://huggingface\.co/.+/resolve/.+$")


def pairs():
    text = CATALOG.read_text(encoding="utf-8")
    return re.findall(r'sourceURL: URL\(string: "([^"]+)"\)!,\s*sha256: "([0-9a-f]{64})"', text)


def request(url, method="GET"):
    req = urllib.request.Request(url, method=method, headers={"User-Agent": "ergou-ime-release-check"})
    token = os.environ.get("GITHUB_TOKEN")
    if token and url.startswith("https://api.github.com/"):
        req.add_header("Authorization", f"Bearer {token}")
    return req


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):
        return None


def current_sha(url):
    m = GITHUB.match(url)
    if m:
        owner, repo, tag, name = m.groups()
        api = f"https://api.github.com/repos/{owner}/{repo}/releases/tags/{tag}"
        with urllib.request.urlopen(request(api), timeout=30) as r:
            release = json.load(r)
        for asset in release.get("assets", []):
            if asset["name"] == urllib.request.unquote(name):
                digest = asset.get("digest") or ""
                return digest.removeprefix("sha256:") or None, "GitHub"
        raise LookupError("asset not in the release")
    if HF.match(url):
        opener = urllib.request.build_opener(NoRedirect)
        try:
            opener.open(request(url, "HEAD"), timeout=30)
            raise LookupError("no redirect, not an LFS file")
        except urllib.error.HTTPError as e:
            if e.code not in (301, 302, 307, 308):
                raise
            etag = (e.headers.get("x-linked-etag") or "").strip('"')
            return (etag if re.fullmatch(r"[0-9a-f]{64}", etag) else None), "Hugging Face"
    with urllib.request.urlopen(request(url, "HEAD"), timeout=30):
        return None, "HEAD"


def main():
    failed = 0
    found = pairs()
    if not found:
        sys.exit("no sourceURL/sha256 pairs found in ModelCatalog.swift")
    for url, sha in found:
        name = url.rsplit("/", 1)[-1]
        try:
            now, how = current_sha(url)
        except Exception as e:  # noqa: BLE001 — report and keep checking the rest
            print(f"FAIL  {name}: {e}")
            failed += 1
            continue
        if now is None:
            print(f"ok?   {name}: reachable, {how} gives no SHA-256 to compare")
        elif now != sha:
            print(f"FAIL  {name}: SHA-256 changed at the source ({how})\n      code   {sha}\n      source {now}")
            failed += 1
        else:
            print(f"ok    {name}")
    if failed:
        sys.exit(f"{failed} download(s) would fail; update ModelCatalog/SpeechModelFiles or the source first")


if __name__ == "__main__":
    main()
