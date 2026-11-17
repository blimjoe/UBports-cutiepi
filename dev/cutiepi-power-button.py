#!/usr/bin/python3
"""Bridge CutiePi MCU short presses to the repowerd power-button interface."""
import argparse
import fcntl
import os
import termios
import tty


HEADER = b"\x5a\xa5"
BUS_NAME = "com.lomiri.SystemCompositor.PowerButton"
BUS_PATH = "/com/lomiri/SystemCompositor/PowerButton"
ACKNOWLEDGEMENTS = {
    (1, b"\x01"): 0xF1,
    (3, b"\x04"): 0xF4,
    (3, b"\x05"): 0xF5,
}


def frame(message_type, payload):
    body = HEADER + bytes([message_type]) + len(payload).to_bytes(2, "little") + payload
    return body + bytes([sum(body) & 0xFF])


def read_frames(serial):
    pending = bytearray()
    while chunk := serial.read(1):
        pending.extend(chunk)
        while pending:
            start = pending.find(HEADER)
            if start < 0:
                # A split header can leave its first byte at the end.
                pending[:] = pending[-1:] if pending[-1] == HEADER[0] else b""
                break
            del pending[:start]
            if len(pending) < 5:
                break
            length = int.from_bytes(pending[3:5], "little")
            if not 1 <= length <= 64:
                del pending[0]
                continue
            end = 6 + length
            if len(pending) < end:
                break
            if sum(pending[:end - 1]) & 0xFF != pending[end - 1]:
                del pending[0]
                continue
            yield pending[2], bytes(pending[5:end - 1])
            del pending[:end]
    raise OSError("MCU serial port closed")


def power_button_bus():
    import dbus
    import dbus.lowlevel
    import dbus.service

    bus = dbus.SystemBus()
    name = dbus.service.BusName(BUS_NAME, bus=bus, do_not_queue=True)

    def press_and_release():
        connection = name.get_bus()
        for member in ("Press", "Release"):
            connection.send_message(dbus.lowlevel.SignalMessage(BUS_PATH, BUS_NAME, member))
        connection.flush()

    return press_and_release


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", default="/dev/ttyS0")
    parser.add_argument("--probe", action="store_true", help="Log MCU short presses without notifying Repowerd")
    options = parser.parse_args()

    with open(options.port, "r+b", buffering=0, opener=lambda path, flags: os.open(path, flags | os.O_NOCTTY)) as serial:
        fcntl.flock(serial, fcntl.LOCK_EX | fcntl.LOCK_NB)
        tty.setraw(serial)
        settings = termios.tcgetattr(serial)
        settings[2] |= termios.CLOCAL | termios.CREAD
        settings[2] &= ~termios.CRTSCTS
        settings[4:6] = [termios.B115200, termios.B115200]
        termios.tcsetattr(serial, termios.TCSANOW, settings)
        button = None if options.probe else power_button_bus()
        print(f"Listening for CutiePi MCU at {options.port} (115200 baud)", flush=True)
        seen_types = set()
        for event in read_frames(serial):
            if options.probe and event[0] not in seen_types:
                seen_types.add(event[0])
                print(f"Received valid MCU frame type {event[0]}", flush=True)
            ack = ACKNOWLEDGEMENTS.get(event)
            if ack is not None:
                serial.write(frame(1, bytes([ack])))
            # Firmware manages long press and power cut in its own state machine.
            if event == (1, b"\x01"):
                if button is not None:
                    button()
                print("MCU power button short press", flush=True)


if __name__ == "__main__":
    main()
