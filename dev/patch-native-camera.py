#!/usr/bin/env python3
"""Supply the built-in camera mounting angle missing from Qt's V4L2 backend."""
from pathlib import Path
import sys

root = Path(sys.argv[1])
targets = list(root.glob('usr/share/click/preinstalled/camera.ubports/*/qml/Viewfinder/ViewFinderView.qml'))
assert targets, 'Preinstalled camera QML not found'
for target in targets:
    text = target.read_text()
    if 'mountedCameraOrientation' in text:
        continue
    assert '    id: viewFinderView\n' in text
    assert text.count('camera.orientation') == 3
    text = text.replace('camera.orientation', 'viewFinderView.mountedCameraOrientation')
    text = text.replace('    id: viewFinderView\n', '''    id: viewFinderView
    // Qt's V4L2 camera info reports 0 for the built-in CSI sensor.
    readonly property int mountedCameraOrientation: (camera.orientation + 90) % 360
''')
    target.write_text(text)
