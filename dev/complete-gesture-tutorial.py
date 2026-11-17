#!/usr/bin/env python3
"""Complete Lomiri edge tutorials while preserving other account settings."""
import configparser
from pathlib import Path
import shutil
import sys

STEPS = ['left', 'top', 'right', 'left-long', 'left-drawer']
INTERFACE = 'com.lomiri.shell.AccountsService'


def main():
    if sys.argv[1:] == ['--live']:
        import dbus
        bus = dbus.SystemBus()
        accounts = dbus.Interface(bus.get_object('org.freedesktop.Accounts',
                                  '/org/freedesktop/Accounts'), 'org.freedesktop.Accounts')
        account = bus.get_object('org.freedesktop.Accounts', accounts.FindUserByName('phablet'))
        properties = dbus.Interface(account, 'org.freedesktop.DBus.Properties')
        completed = list(properties.Get(INTERFACE, 'DemoEdgesCompleted'))
        merged = completed + [step for step in STEPS if step not in completed]
        if merged != completed:
            properties.Set(INTERFACE, 'DemoEdgesCompleted', dbus.Array(merged, signature='s'))
        actual = list(properties.Get(INTERFACE, 'DemoEdgesCompleted'))
        assert all(step in actual for step in STEPS), actual
        print('Completed tutorials: ' + ', '.join(actual))
        return

    if len(sys.argv) != 2:
        raise SystemExit('Usage: complete-gesture-tutorial.py ROOT | --live')
    target = Path(sys.argv[1]) / 'var/lib/AccountsService/users/phablet'
    config = configparser.ConfigParser(interpolation=None)
    config.optionxform = str
    config.read(target)
    if not config.has_section(INTERFACE):
        config.add_section(INTERFACE)
    # These booleans mean "has run", rather than "enabled".
    for key in ('demo-edges', 'DemoEdges2'):
        if not config.has_option(INTERFACE, key):
            config.set(INTERFACE, key, 'true')
    # GLib keyfiles store this property as a GVariant string array.
    from ast import literal_eval
    previous = literal_eval(config.get(INTERFACE, 'DemoEdgesCompleted', fallback='[]'))
    merged = previous + [step for step in STEPS if step not in previous]
    config.set(INTERFACE, 'DemoEdgesCompleted', repr(merged))
    target.parent.mkdir(parents=True, exist_ok=True)
    if target.exists():
        backup = target.with_name('phablet.before-gesture-completion')
        if not backup.exists():
            shutil.copy2(target, backup)
    with target.open('w') as output:
        config.write(output, space_around_delimiters=False)
    target.chmod(0o600)


if __name__ == '__main__':
    main()
