"""Real GTK measurements; explicitly skipped when no display is available."""
import unittest
import gi
gi.require_version('Gtk', '4.0')
from gi.repository import Gtk, Gdk, Pango

@unittest.skipUnless(Gdk.Display.get_default() is not None, 'GTK display unavailable')
class GtkMeasurementTest(unittest.TestCase):
    def test_long_caption_large_font(self):
        label = Gtk.Label(label='ОченьДлинноеНазваниеПриложения'*8,
                          ellipsize=Pango.EllipsizeMode.END, width_chars=1, max_width_chars=8)
        attrs = Pango.AttrList()
        attrs.insert(Pango.attr_scale_new(2))
        label.set_attributes(attrs)
        self.assertLessEqual(label.measure(Gtk.Orientation.HORIZONTAL,-1)[0],80)

    def test_many_dock_items_fit_minimum_width(self):
        dock = Gtk.FlowBox(min_children_per_line=1,max_children_per_line=3,homogeneous=True)
        for _ in range(16):
            button = Gtk.Button()
            button.set_child(Gtk.Label(label='ДлинноеИмя'*20,ellipsize=Pango.EllipsizeMode.END,width_chars=1,max_width_chars=8))
            dock.append(button)
        self.assertLessEqual(dock.measure(Gtk.Orientation.HORIZONTAL,-1)[0],304)
