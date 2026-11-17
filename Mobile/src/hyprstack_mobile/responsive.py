"""Allocation-driven container: no polling or display-specific configuration."""
from gi.repository import Gtk


class ResponsiveBin(Gtk.Widget):
    def __init__(self, child, on_allocate):
        super().__init__()
        self.child = child
        self.on_allocate = on_allocate
        child.set_parent(self)

    def do_measure(self, orientation, for_size):
        return self.child.measure(orientation, for_size)

    def do_size_allocate(self, width, height, baseline):
        self.on_allocate(width, height)
        self.child.allocate(width, height, baseline, None)

    def do_snapshot(self, snapshot):
        self.snapshot_child(self.child, snapshot)

    def release(self):
        if self.child.get_parent() is self:
            self.child.unparent()
