# -*- coding: utf-8 -*-
"""Pass 125: builds the crowd's compiled library (native/, class CrowdCore) -> game/bin/crowd.windows.x86_64.dll and
game/bin/libcrowd.android.arm64.so, both committed, so a build of the game needs no compiler. Run it after changing native/src.

    python tools/build_native.py [--windows] [--android] [--clean] [--setup]

--setup fetches what the build needs into the git-ignored tools/dl/native/: SCons in a venv, godot-cpp at GODOT_CPP_TAG, the
Android NDK. On Windows the compiler is MSVC (Visual Studio or its Build Tools).
"""
import argparse
import os
import shutil
import subprocess
import sys
import urllib.request
import zipfile

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
BASE = os.path.join(ROOT, "tools", "dl", "native")
CPP = os.path.join(BASE, "godot-cpp")
NDK = os.path.join(BASE, "ndk", "android-ndk-r29")
SCONS = os.path.join(BASE, "venv", "Scripts", "scons.exe")
GODOT_CPP_TAG = "godot-4.5-stable"
NDK_URL = "https://dl.google.com/android/repository/android-ndk-r29-windows.zip"


def setup():
    os.makedirs(BASE, exist_ok=True)
    if not os.path.exists(SCONS):
        subprocess.check_call([sys.executable, "-m", "venv", os.path.join(BASE, "venv")])
        subprocess.check_call([os.path.join(BASE, "venv", "Scripts", "python.exe"), "-m", "pip", "-q", "install", "scons"])
    if not os.path.isdir(CPP):
        subprocess.check_call(["git", "clone", "-q", "--depth", "1", "--branch", GODOT_CPP_TAG, "https://github.com/godotengine/godot-cpp", CPP])
    patch_cpp()
    if not os.path.isdir(NDK):
        z = os.path.join(BASE, "ndk.zip")
        print("downloading the NDK (830 MB)")
        urllib.request.urlretrieve(NDK_URL, z)
        zipfile.ZipFile(z).extractall(os.path.join(BASE, "ndk"))
        os.remove(z)


def patch_cpp():
    """godot-cpp clears the compiler's version before SCons looks for one, and SCons then found an ancient cl on this PC, or none:
    SCons is told the environment script of the Visual Studio vswhere names."""
    win = os.path.join(CPP, "tools", "windows.py")
    with open(win, encoding="utf-8", newline="") as f:
        src = f.read()
    old = 'env["MSVC_VERSION"] = None'
    if old in src:
        with open(win, "w", encoding="utf-8", newline="") as f:
            f.write(src.replace(old, old + '\n        env["MSVC_USE_SCRIPT"] = os.environ.get("GODOT_CPP_VCVARS", True)'))


def vcvars():
    where = os.path.join(os.environ.get("ProgramFiles(x86)", r"C:\Program Files (x86)"), "Microsoft Visual Studio", "Installer", "vswhere.exe")
    out = subprocess.check_output([where, "-latest", "-products", "*", "-requires", "Microsoft.VisualStudio.Component.VC.Tools.x86.x64", "-property", "installationPath"], text=True).strip()
    return os.path.join(out, "VC", "Auxiliary", "Build", "vcvars64.bat")


def scons(platform, arch, clean=False):
    env = dict(os.environ)
    env["GODOT_CPP_DIR"] = CPP
    for k in ("ANDROID_HOME", "ANDROID_SDK_ROOT"):
        env.pop(k, None)
    if platform == "windows":
        env["GODOT_CPP_VCVARS"] = vcvars()
    cmd = [SCONS, "platform=" + platform, "arch=" + arch, "target=template_release", "optimize=speed", "debug_symbols=no", "-j8"]
    if platform == "android":
        # godot-cpp looks for <ANDROID_HOME>/ndk/<ndk_version>
        cmd += ["ANDROID_HOME=" + BASE, "ndk_version=" + os.path.basename(NDK)]
    if clean:
        cmd.append("-c")
    print(" ".join(cmd[1:]))
    subprocess.check_call(cmd, cwd=os.path.join(ROOT, "native"), env=env)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--windows", action="store_true")
    ap.add_argument("--android", action="store_true")
    ap.add_argument("--clean", action="store_true")
    ap.add_argument("--setup", action="store_true")
    a = ap.parse_args()
    if a.setup or not os.path.exists(SCONS) or not os.path.isdir(CPP) or not os.path.isdir(NDK):
        setup()
    patch_cpp()
    both = not a.windows and not a.android
    if a.windows or both:
        scons("windows", "x86_64", a.clean)
    if a.android or both:
        scons("android", "arm64", a.clean)
    out = os.path.join(ROOT, "game", "bin")
    for f in sorted(os.listdir(out)):
        if f.endswith((".dll", ".so")):
            print(f, os.path.getsize(os.path.join(out, f)))
        elif f.endswith((".lib", ".exp")):
            os.remove(os.path.join(out, f))


if __name__ == "__main__":
    main()
