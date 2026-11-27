# SPDX-License-Identifier: MIT
"""A stand-in for bluetoothd on a private bus, for test/bt-agent-bus.py: one
adapter with the parts of BlueZ 5.88 that omamobile-bt-agent's pairing window
meets. As in src/agent.c and src/adapter.c, a default agent registering turns
Pairable on through a pending change, a Set of Pairable while that change is
pending answers org.bluez.Error.Busy, and the default agent leaving turns
Pairable off. Every call is logged to argv[1] as one JSON line. With
FAKE_BLUEZ_QUIET set, the registration's change sends no signal (one that
went out before the helper listened)."""
import json
import os
import sys

import dbus
import dbus.mainloop.glib
import dbus.service
from gi.repository import GLib

ADAPTER = "/org/bluez/hci0"
ADAPTER_IFACE = "org.bluez.Adapter1"
DEVICE = ADAPTER + "/dev_00_11_22_33_44_55"
DEVICE_IFACE = "org.bluez.Device1"
PROPS_IFACE = "org.freedesktop.DBus.Properties"
log_path = sys.argv[1]


def log(**entry):
    with open(log_path, "a") as f:
        f.write(json.dumps(entry) + "\n")


class Busy(dbus.DBusException):
    _dbus_error_name = "org.bluez.Error.Busy"


class Adapter(dbus.service.Object):
    def __init__(self, bus):
        super().__init__(bus, ADAPTER)
        self.props = {"Pairable": False, "PairableTimeout": dbus.UInt32(0), "Discovering": False}
        self.pending = False

    def change(self, name, value):
        if self.props.get(name) != value:
            self.props[name] = value
            self.PropertiesChanged(ADAPTER_IFACE, {name: value}, [])

    @dbus.service.signal(PROPS_IFACE, signature="sa{sv}as")
    def PropertiesChanged(self, interface, changed, invalidated):
        pass

    @dbus.service.method(PROPS_IFACE, in_signature="ss", out_signature="v")
    def Get(self, interface, name):
        return self.props[name]

    @dbus.service.method(PROPS_IFACE, in_signature="s", out_signature="a{sv}")
    def GetAll(self, interface):
        return self.props

    @dbus.service.method(PROPS_IFACE, in_signature="ssv", out_signature="")
    def Set(self, interface, name, value):
        if name == "Pairable" and self.pending:
            log(busy=name, value=bool(value))
            raise Busy("Busy")
        value = bool(value) if name == "Pairable" else int(value)
        log(set=name, value=value)
        self.change(name, dbus.Boolean(value) if name == "Pairable" else dbus.UInt32(value))

    @dbus.service.method(ADAPTER_IFACE, in_signature="", out_signature="")
    def StartDiscovery(self):
        pass

    @dbus.service.method(ADAPTER_IFACE, in_signature="", out_signature="")
    def StopDiscovery(self):
        pass

    # The bondable change an agent's registration starts (adapter_set_io_capability).
    def agent_bondable(self, on):
        self.pending = True

        def done():
            self.pending = False
            if os.environ.get("FAKE_BLUEZ_QUIET"):
                # A change whose signal went out before anyone listened.
                self.props["Pairable"] = dbus.Boolean(on)
            else:
                self.change("Pairable", dbus.Boolean(on))
            return False
        GLib.timeout_add(300, done)


class Rejected(dbus.DBusException):
    _dbus_error_name = "org.bluez.Error.Rejected"


class Device(dbus.service.Object):
    """One paired, trusted device (a placeholder address), which can be
    connected and disconnected, and whose own reconnect (Reconnect, a test
    call) is refused while it is Blocked and asks the default agent to
    authorize a service, as src/device.c does, while it isn't Trusted. With
    IncomingPair (a test call) it pairs to us as a car's "add phone" does:
    unpaired and untrusted, it asks the default agent to confirm a passkey
    and, on yes, is Paired (a PropertiesChanged signal, as BlueZ sends)."""

    def __init__(self, bus, manager):
        super().__init__(bus, DEVICE)
        self.manager = manager
        self.props = {"Address": "02:00:00:00:00:01", "Paired": dbus.Boolean(True),
                      "Trusted": dbus.Boolean(True), "Blocked": dbus.Boolean(False),
                      "Connected": dbus.Boolean(False)}

    @dbus.service.signal(PROPS_IFACE, signature="sa{sv}as")
    def PropertiesChanged(self, interface, changed, invalidated):
        pass

    @dbus.service.method(PROPS_IFACE, in_signature="ss", out_signature="v")
    def Get(self, interface, name):
        return self.props[name]

    @dbus.service.method(PROPS_IFACE, in_signature="s", out_signature="a{sv}")
    def GetAll(self, interface):
        return self.props

    @dbus.service.method(PROPS_IFACE, in_signature="ssv", out_signature="")
    def Set(self, interface, name, value):
        log(device_set=name, value=bool(value))
        self.props[name] = dbus.Boolean(bool(value))

    @dbus.service.method(DEVICE_IFACE, in_signature="", out_signature="")
    def Connect(self):
        log(device_call="Connect", trusted=bool(self.props["Trusted"]))
        self.props["Connected"] = dbus.Boolean(True)

    @dbus.service.method(DEVICE_IFACE, in_signature="", out_signature="")
    def Disconnect(self):
        log(device_call="Disconnect", trusted=bool(self.props["Trusted"]))
        self.props["Connected"] = dbus.Boolean(False)

    @dbus.service.method("org.omamobile.Test", in_signature="", out_signature="")
    def Reconnect(self):
        if self.props["Blocked"]:
            log(reconnect="rejected", why="blocked")
            return
        if self.props["Trusted"]:
            log(reconnect="trusted")
            return
        agent = self.manager.agent
        if not agent:
            log(reconnect="rejected", why="no agent")
            return
        # Asynchronously: the agent asks this process whether the device is
        # Trusted while it answers.
        bus = dbus.SystemBus()
        dbus.Interface(bus.get_object(agent[0], agent[1]), "org.bluez.Agent1").AuthorizeService(
            dbus.ObjectPath(DEVICE), "0000110b-0000-1000-8000-00805f9b34fb",
            reply_handler=lambda: log(reconnect="authorized"),
            error_handler=lambda error: log(reconnect="rejected", why=error.get_dbus_name()))


    @dbus.service.method("org.omamobile.Test", in_signature="", out_signature="")
    def IncomingPair(self):
        self.props["Paired"] = dbus.Boolean(False)
        self.props["Trusted"] = dbus.Boolean(False)
        agent = self.manager.agent
        if not agent:
            log(incoming="rejected", why="no agent")
            return

        def paired():
            log(incoming="paired")
            self.props["Paired"] = dbus.Boolean(True)
            self.PropertiesChanged(DEVICE_IFACE, {"Paired": dbus.Boolean(True)}, [])

        bus = dbus.SystemBus()
        dbus.Interface(bus.get_object(agent[0], agent[1]), "org.bluez.Agent1").RequestConfirmation(
            dbus.ObjectPath(DEVICE), dbus.UInt32(123456), reply_handler=paired,
            error_handler=lambda error: log(incoming="rejected", why=error.get_dbus_name()))


class Root(dbus.service.Object):
    def __init__(self, bus, adapter, device=None):
        super().__init__(bus, "/")
        self.adapter = adapter
        self.device = device

    @dbus.service.method("org.freedesktop.DBus.ObjectManager", in_signature="", out_signature="a{oa{sa{sv}}}")
    def GetManagedObjects(self):
        objects = {ADAPTER: {ADAPTER_IFACE: self.adapter.props}}
        if self.device:
            objects[DEVICE] = {DEVICE_IFACE: self.device.props}
        return objects


class AgentManager(dbus.service.Object):
    def __init__(self, bus, adapter):
        super().__init__(bus, "/org/bluez")
        self.adapter = adapter
        self.agent = None

    @dbus.service.method("org.bluez.AgentManager1", in_signature="os", out_signature="", sender_keyword="sender")
    def RegisterAgent(self, path, capability, sender=None):
        log(call="RegisterAgent", capability=str(capability))
        self.agent = (sender, path)
        self.adapter.agent_bondable(True)

    @dbus.service.method("org.bluez.AgentManager1", in_signature="o", out_signature="")
    def RequestDefaultAgent(self, path):
        log(call="RequestDefaultAgent")

    @dbus.service.method("org.bluez.AgentManager1", in_signature="o", out_signature="")
    def UnregisterAgent(self, path):
        log(call="UnregisterAgent")
        self.agent = None
        self.adapter.change("Pairable", dbus.Boolean(False))


def main():
    dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
    bus = dbus.SystemBus()
    adapter = Adapter(bus)
    manager = AgentManager(bus, adapter)
    Root(bus, adapter, Device(bus, manager))
    name = dbus.service.BusName("org.bluez", bus)  # noqa: F841 (held for the run)
    log(call="ready")
    GLib.MainLoop().run()


if __name__ == "__main__":
    main()
