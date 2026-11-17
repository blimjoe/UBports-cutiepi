#!/usr/bin/env python3
"""Supply the built-in camera mounting angle missing from Qt's V4L2 backend."""
from pathlib import Path
import sys

root = Path(sys.argv[1])
targets = list(root.glob('usr/share/click/preinstalled/camera.ubports/*/qml/Viewfinder/ViewFinderView.qml'))
assert targets, 'Preinstalled camera QML not found'
for target in targets:
    text = target.read_text()
    if 'mountedCameraOrientation' not in text:
        assert '    id: viewFinderView\n' in text
        assert text.count('camera.orientation') == 3
        text = text.replace('camera.orientation', 'viewFinderView.mountedCameraOrientation')
        text = text.replace('    id: viewFinderView\n', '''    id: viewFinderView
    // Qt's V4L2 camera info reports 0 for the built-in CSI sensor.
    readonly property int mountedCameraOrientation: (camera.orientation + 90) % 360
''')
    if 'previewCameraOrientation' not in text:
        marker = '    readonly property int mountedCameraOrientation: (camera.orientation + 90) % 360'
        assert marker in text
        text = text.replace(marker, marker + '''
    // VideoOutput positive angles are counterclockwise; keep capture metadata separate.
    readonly property int previewCameraOrientation: (mountedCameraOrientation + 90) % 360''')
        text = text.replace('return (360 - viewFinderView.mountedCameraOrientation) % 360;',
                            'return (360 - viewFinderView.previewCameraOrientation) % 360;')
        text = text.replace('return viewFinderView.mountedCameraOrientation;',
                            'return viewFinderView.previewCameraOrientation;')
        # The corrected preview swaps aspect ratio. Crop to fill the existing
        # viewport instead of retaining the old fit-mode letterbox offset.
        assert '            y: -viewFinderGeometry.y' in text
        text = text.replace('            y: -viewFinderGeometry.y',
                            '            y: 0\n            fillMode: VideoOutput.PreserveAspectCrop')
        marker = '            id: viewFinderGeometry\n'
        assert marker in text
        text = text.replace(marker, marker + '            width: viewFinder.width\n            height: viewFinder.height\n')
    target.write_text(text)
