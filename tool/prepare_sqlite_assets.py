"""CI cache warm-up via GitHub's asset API; retain sqlite3's pinned SHA-256.

The normal release/download URLs occasionally return cached gateway errors.
This only fills the package hook's verified cache, never changes its checks.
"""
import hashlib
import json
import os
import pathlib
import re
import sys
import time
import urllib.parse
import urllib.request

ALLOWED = {"api.github.com", "github.com", "release-assets.githubusercontent.com", "objects.githubusercontent.com"}

class SafeRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        uri = urllib.parse.urlparse(newurl)
        if uri.scheme != "https" or uri.hostname not in ALLOWED:
            raise RuntimeError("Unexpected native asset redirect")
        redirected = super().redirect_request(req, fp, code, msg, headers, newurl)
        redirected.remove_header("Authorization")
        return redirected

opener = urllib.request.build_opener(SafeRedirect())
def request(url, binary=False):
    headers = {"User-Agent": "EquipmentManager-CI", "Accept": "application/octet-stream" if binary else "application/vnd.github+json"}
    token = os.environ.get("GH_TOKEN")
    if token and urllib.parse.urlparse(url).hostname == "api.github.com":
        headers["Authorization"] = "Bearer " + token
    return opener.open(urllib.request.Request(url, headers=headers), timeout=60)

def digest(path):
    sha = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(65536), b""):
            sha.update(chunk)
    return sha.hexdigest()

config = pathlib.Path(".dart_tool/package_config.json").resolve()
package = next(p for p in json.loads(config.read_text())["packages"] if p["name"] == "sqlite3")
uri = urllib.parse.urljoin(config.as_uri(), package["rootUri"])
package_root = pathlib.Path(urllib.request.url2pathname(urllib.parse.urlparse(uri).path))
hash_source = (package_root / "lib/src/hook/asset_hashes.dart").read_text()
tag = re.search(r"releaseTag = '([^']+)'", hash_source).group(1)
hashes = dict(re.findall(r"'([^']+)': '([a-f0-9]{64})'", hash_source))
files = ["libsqlite3.x64.linux.so"]
if "--android" in sys.argv:
    files += ["libsqlite3.arm.android.so", "libsqlite3.arm64.android.so", "libsqlite3.x64.android.so"]
metadata = None
for name in files:
    expected = hashes[name]
    target = pathlib.Path(".dart_tool/hooks_runner/shared/sqlite3/build") / ("download-" + expected[:8]) / "libsqlite3.so"
    if target.is_file() and digest(target) == expected:
        print("Verified cached " + name)
        continue
    target.parent.mkdir(parents=True, exist_ok=True)
    partial = target.with_suffix(".verified-part")
    for attempt in range(5):
        try:
            if metadata is None:
                with request("https://api.github.com/repos/simolus3/sqlite3.dart/releases/tags/" + tag) as response:
                    metadata = json.load(response)
            asset = next(a for a in metadata["assets"] if a["name"] == name)
            if asset.get("digest") != "sha256:" + expected:
                raise RuntimeError("Published SQLite asset digest differs from package pin")
            with request(asset["url"] + "?download=1", binary=True) as response, partial.open("wb") as output:
                count = 0
                for chunk in iter(lambda: response.read(65536), b""):
                    count += len(chunk)
                    if count > asset["size"] or count > 64 * 1024 * 1024:
                        raise RuntimeError("Native asset exceeded expected size")
                    output.write(chunk)
            if count != asset["size"] or digest(partial) != expected:
                raise RuntimeError("Native asset failed size/SHA-256 verification")
            partial.replace(target)
            print("Verified downloaded " + name)
            break
        except Exception:
            partial.unlink(missing_ok=True)
            if attempt == 4:
                raise
            time.sleep(2 ** attempt)
