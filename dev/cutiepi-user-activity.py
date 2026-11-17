#!/usr/bin/python3
"""Report Goodix touch activity to Repowerd without grabbing input events."""
import glob
import os
import select
import struct
import time

EVENT = struct.Struct('@llHHi')
NAME = 'com.lomiri.SystemCompositor.UserActivity'
PATH = '/com/lomiri/SystemCompositor/UserActivity'


def touch_device():
    for entry in glob.glob('/sys/class/input/event*/device/name'):
        with open(entry) as source:
            if source.read().strip() == 'Goodix Capacitive TouchScreen':
                return '/dev/input/' + entry.split('/')[4]
    return None


def monitor(stream, notify):
    pending = b''
    changed = False
    last = float('-inf')
    while True:
        select.select([stream], [], [])
        chunk = os.read(stream.fileno(), EVENT.size * 64)
        if not chunk:
            raise OSError('Touch device disconnected')
        pending += chunk
        while len(pending) >= EVENT.size:
            _, _, kind, code, value = EVENT.unpack(pending[:EVENT.size])
            pending = pending[EVENT.size:]
            if kind == 3 or (kind == 1 and code == 330):  # ABS or BTN_TOUCH
                changed = True
            elif kind == 0 and code == 3:  # SYN_DROPPED: resync next frame
                changed = False
            elif kind == 0 and code == 0:  # SYN_REPORT
                now = time.monotonic()
                if changed and now - last >= 1:
                    notify()
                    last = now
                changed = False


def main():
    import dbus
    import dbus.lowlevel
    import dbus.service

    bus = dbus.SystemBus()
    name = dbus.service.BusName(NAME, bus=bus, do_not_queue=True)

    def notify():
        signal = dbus.lowlevel.SignalMessage(PATH, NAME, 'Activity')
        signal.append(dbus.Int32(0), signature='i')
        name.get_bus().send_message(signal)
        name.get_bus().flush()

    while True:
        device = touch_device()
        if device:
            try:
                with open(device, 'rb', buffering=0) as stream:
                    print('Monitoring ' + device, flush=True)
                    monitor(stream, notify)
            except OSError as error:
                print(str(error), flush=True)
        time.sleep(2)


if __name__ == '__main__':
    main()
