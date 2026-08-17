import hashlib
import json
import os
import tarfile
import urllib.request

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PATCHES = os.path.join(REPO, "patches")
VERSION = "0.1.0-rc.7"

# package -> list of (target file relative to repo patches dir, file inside tarball package/)
PKGS = {
    "dsh-sandbox-policy": ["lib/index.js"],
    "dsh-sandbox": ["lib/index.js"],
    "dsh-permission-presets": ["lib/index.js"],
    "dsh-sandbox-windows-acl": ["lib/runner.js", None],  # None = the types-*.js bundle (name discovered)
    "dsh-sandbox-local": ["lib/index.js"],
    "dsh-tool-pwsh": ["lib/index.js"],
    "dsh-client-connection": ["lib/client.js"],
    "dsh-client-ui-conversation": ["lib/client.js"],
}

def fetch(url, timeout=120):
    req = urllib.request.Request(url, headers={"User-Agent": "dsh-netaccess-manifest"})
    return urllib.request.urlopen(req, timeout=timeout)

def sha256_of(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()

def find_types_bundle(tar, prefix):
    for m in tar.getmembers():
        if m.name.startswith(prefix + "lib/") and m.name.endswith(".js") and "types-" in m.name:
            return m.name
    return None

targets = []
tmp = os.path.join(REPO, ".packtmp")
os.makedirs(tmp, exist_ok=True)
try:
    for pkg, files in PKGS.items():
        url = "https://registry.npmjs.org/@deepseek-ai/{0}/-/{0}-{1}.tgz".format(pkg, VERSION)
        tgz = os.path.join(tmp, pkg + ".tgz")
        print("fetch", pkg)
        with open(tgz, "wb") as out:
            out.write(fetch(url).read())
        with tarfile.open(tgz, "r:gz") as tar:
            prefix = "package/"
            names = []
            for f in files:
                if f is None:
                    inside = find_types_bundle(tar, prefix)
                    if inside is None:
                        raise SystemExit("types bundle not found in " + pkg)
                    names.append(inside)
                else:
                    names.append(prefix + f)
            for inside in names:
                member = tar.getmember(inside)
                fh = tar.extractfile(member)
                raw = fh.read()
                rel = inside[len(prefix):]
                # original hash
                orig = hashlib.sha256(raw).hexdigest()
                # patched hash from repo
                patched_path = os.path.join(PATCHES, pkg, rel.replace("/", os.sep))
                patched = sha256_of(patched_path)
                targets.append({"file": pkg + "/" + rel, "original": orig, "sha256": patched})
                print("  ", rel, "orig", orig[:12], "patched", patched[:12])
finally:
    import shutil
    shutil.rmtree(tmp, ignore_errors=True)

manifest = {
    "name": "dsh-plugin-net-access",
    "version": "0.2.0",
    "note": "Patched files for DeepSeek Harness 0.1.0-rc.7 (built bundles). install.ps1 verifies the ORIGINAL hash before overwriting and aborts on mismatch.",
    "targets": targets,
}
with open(os.path.join(REPO, "manifest.json"), "w", encoding="utf-8") as f:
    json.dump(manifest, f, indent=2, ensure_ascii=False)
print("manifest.json written:", len(targets), "targets")
