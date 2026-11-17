#!/usr/bin/env python3
"""Expose native Mir input-method surfaces omitted from workspace notifications."""
from pathlib import Path
import sys

p = Path(sys.argv[1]) / 'usr/share/lomiri/Components/InputMethod.qml'
s = p.read_text()
old = '    property var surface: root.enabled ? InputMethodManager.surface : null;'
new = '''    // Mir 2 input panels may not be assigned to a workspace by MirAL.
    property var nativeInputSurface: null
    property var surface: root.enabled ? (nativeInputSurface || InputMethodManager.surface) : null

    Connections {
        target: SurfaceManager
        function onSurfaceCreated(surface) {
            if (surface.type === Mir.InputMethodType)
                root.nativeInputSurface = surface
        }
        function onSurfaceRemoved(surface) {
            if (surface === root.nativeInputSurface)
                root.nativeInputSurface = null
        }
    }
'''
if 'property var nativeInputSurface:' not in s:
    assert old in s
    s = s.replace(old, new)
    old_handler = '''        onLiveChanged: {
            if (surface !== null && !live) {
                surface = null;
            }
        }'''
    assert old_handler in s
    s = s.replace(old_handler, '')
    p.write_text(s)

oriented = Path(sys.argv[1]) / 'usr/share/lomiri/OrientedShell.qml'
s = oriented.read_text()
old = 'oskEnabled: (!hasKeyboard && Screens.count === 1) ||'
new = '''// CutiePi exposes touch/remote and virtual keyboard devices without a physical keyboard.
        oskEnabled: (deviceConfiguration.category === "tablet" && hasTouchscreen) ||
                    (!hasKeyboard && Screens.count === 1) ||'''
if old in s:
    oriented.write_text(s.replace(old, new))
else:
    assert 'CutiePi exposes touch/remote' in s
