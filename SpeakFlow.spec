# -*- mode: python ; coding: utf-8 -*-

from pathlib import Path

from PyInstaller.utils.hooks import collect_data_files, collect_dynamic_libs

block_cipher = None

project_root = str(Path(__file__).resolve().parent)

datas = []
datas += collect_data_files("faster_whisper", include_py_files=True)
datas += collect_data_files("tokenizers", include_py_files=True)

datas += collect_data_files("onnxruntime", include_py_files=False)

datas += [(f"{project_root}/packaging/Info.plist", "packaging")]

binaries = []
binaries += collect_dynamic_libs("ctranslate2")
binaries += collect_dynamic_libs("onnxruntime")

hiddenimports = [
    "Quartz",
    "AppKit",
    "Cocoa",
    "sounddevice",
    "faster_whisper",
]

a = Analysis(
    ["app_main.py"],
    pathex=["src"],
    binaries=binaries,
    datas=datas,
    hiddenimports=hiddenimports,
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=[],
    win_no_prefer_redirects=False,
    win_private_assemblies=False,
    cipher=block_cipher,
    noarchive=False,
)
pyz = PYZ(a.pure, a.zipped_data, cipher=block_cipher)

exe = EXE(
    pyz,
    a.scripts,
    [],
    exclude_binaries=True,
    name="SpeakFlow",
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=True,
    console=False,
)

coll = COLLECT(
    exe,
    a.binaries,
    a.zipfiles,
    a.datas,
    strip=False,
    upx=True,
    upx_exclude=[],
    name="SpeakFlow",
)

app = BUNDLE(
    coll,
    name="SpeakFlow.app",
    icon=None,
    bundle_identifier="com.speakflow.desktop",
    info_plist={
        "CFBundleDisplayName": "SpeakFlow",
        "CFBundleName": "SpeakFlow",
        "LSUIElement": False,
        "NSMicrophoneUsageDescription": "SpeakFlow uses microphone access for local dictation.",
        "NSAppleEventsUsageDescription": "SpeakFlow uses System Events automation for text insertion in other apps.",
    },
)
