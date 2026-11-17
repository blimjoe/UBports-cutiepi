import QtQuick 2.12
import QtQuick.Window 2.12

Window {
    id: probe
    visible: true
    visibility: Window.FullScreen
    color: "#142437"
    title: "CutiePi touch test"
    onWidthChanged: console.log("SIZE", width, height, Screen.devicePixelRatio)
    onHeightChanged: console.log("SIZE", width, height, Screen.devicePixelRatio)

    Text {
        anchors.centerIn: parent
        text: "按顺序点 1 → 2 → 3 → 4"
        color: "white"
        font.pixelSize: 24
    }

    Repeater {
        model: [
            { x: 0.15, y: 0.17, color: "#e24f55" },
            { x: 0.85, y: 0.17, color: "#238e68" },
            { x: 0.15, y: 0.82, color: "#337ac7" },
            { x: 0.85, y: 0.82, color: "#ad6228" }
        ]
        Rectangle {
            width: Math.min(probe.width, probe.height) * 0.13
            height: width
            radius: width / 2
            x: modelData.x * probe.width - width / 2
            y: modelData.y * probe.height - height / 2
            color: modelData.color
            Text {
                anchors.centerIn: parent
                text: index + 1
                color: "white"
                font.pixelSize: parent.width * 0.55
            }
        }
    }

    MultiPointTouchArea {
        anchors.fill: parent
        maximumTouchPoints: 1
        onPressed: function(points) {
            const point = points[0]
            const x = point.x / width
            const y = point.y / height
            console.log("TOUCH", x.toFixed(4), y.toFixed(4))
            marker.x = point.x - marker.width / 2
            marker.y = point.y - marker.height / 2
            marker.visible = true
        }
    }
    Rectangle {
        id: marker
        visible: false
        width: 22
        height: width
        radius: width / 2
        border.color: "white"
        border.width: 3
        color: "transparent"
    }

    Timer {
        interval: 300000
        running: true
        onTriggered: Qt.quit()
    }
}
