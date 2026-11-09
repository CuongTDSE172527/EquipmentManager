"""Run on the disposable Android emulator runner; all data is synthetic."""
import hashlib
import json
import pathlib
import re
import sqlite3
import subprocess
import time
import xml.etree.ElementTree as ET

PACKAGE = "vn.cah.equipment_manager"

def adb(*args, check=True, binary=False):
    result = subprocess.run(["adb", *args], check=check, capture_output=True)
    return result.stdout if binary else result.stdout.decode("utf-8", errors="replace")

def evidence():
    return adb("shell", "run-as", PACKAGE, "cat", "files/updates/evidence.txt", check=False)

adb("install", "-r", "ota-harness.apk")
adb("shell", "run-as", PACKAGE, "mkdir", "-p", "files/updates")
for source, target in [("ota-candidate.apk", "valid.apk"), ("ota-wrong-signer.apk", "wrong-signer.apk")]:
    adb("push", source, "/data/local/tmp/" + target)
    adb("shell", "run-as", PACKAGE, "cp", "/data/local/tmp/" + target, "files/updates/" + target)
pathlib.Path("ota-fixture.json").write_text(json.dumps({
    "validHash": hashlib.sha256(pathlib.Path("ota-candidate.apk").read_bytes()).hexdigest(),
    "wrongHash": hashlib.sha256(pathlib.Path("ota-wrong-signer.apk").read_bytes()).hexdigest(),
}))
adb("push", "ota-fixture.json", "/data/local/tmp/ota-fixture.json")
adb("shell", "run-as", PACKAGE, "cp", "/data/local/tmp/ota-fixture.json", "files/updates/fixture.json")
adb("shell", "am", "start", "-n", PACKAGE + "/.MainActivity")
for _ in range(120):
    text = evidence()
    if "FAIL" in text:
        raise RuntimeError(text)
    if "READY" in text:
        break
    time.sleep(1)
else:
    raise RuntimeError("Harness did not become ready: " + evidence())
adb("shell", "appops", "set", PACKAGE, "REQUEST_INSTALL_PACKAGES", "allow")
adb("shell", "am", "start", "-n", PACKAGE + "/.MainActivity")
adb("shell", "run-as", PACKAGE, "touch", "files/updates/install-now")
installed = False
for _ in range(90):
    dump = adb("shell", "dumpsys", "package", PACKAGE)
    if re.search(r"versionCode=1004\b", dump):
        installed = True
        break
    adb("shell", "uiautomator", "dump", "/sdcard/ota-window.xml", check=False)
    xml = adb("shell", "cat", "/sdcard/ota-window.xml", check=False)
    pathlib.Path("ota-installer-window.xml").write_text(xml)
    try:
        for node in ET.fromstring(xml).iter("node"):
            if node.attrib.get("text", "").strip().lower() == "install" and node.attrib.get("enabled") == "true":
                coordinates = list(map(int, re.findall(r"\d+", node.attrib["bounds"])))
                adb("shell", "input", "tap", str((coordinates[0]+coordinates[2])//2), str((coordinates[1]+coordinates[3])//2))
                break
    except ET.ParseError:
        pass
    time.sleep(1)
if not installed:
    raise RuntimeError("Native installer did not upgrade the fixture: " + evidence())
adb("shell", "am", "force-stop", PACKAGE)
pathlib.Path("ota-result.txt").write_text(evidence() + "PASS OS installed versionCode 1004\n")
for suffix in ["", "-wal", "-shm"]:
    data = adb("exec-out", "run-as", PACKAGE, "cat", "files/equipment_manager.db"+suffix, check=False, binary=True)
    if data:
        pathlib.Path("ota-preserved.db"+suffix).write_bytes(data)
connection = sqlite3.connect("ota-preserved.db")
assert connection.execute("select count(*) from equipment where id='ota-preserved-fixture'").fetchone()[0] == 1
connection.close()
with pathlib.Path("ota-result.txt").open("a") as output:
    output.write("PASS SQLite equipment survived APK update\n")
print(pathlib.Path("ota-result.txt").read_text())
