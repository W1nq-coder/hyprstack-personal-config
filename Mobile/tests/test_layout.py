import unittest
from hyprstack_mobile.layout import choose, TEST_SIZES

class LayoutTest(unittest.TestCase):
    def test_matrix(self):
        expected = [4, 5, 4, 4, 3, 8]
        for size, columns in zip(TEST_SIZES, expected):
            w, h = map(int, size.split('x'))
            with self.subTest(size=size):
                state = choose(w, h)
                self.assertEqual(state.columns, columns)
                self.assertLessEqual(state.columns * 80 + (state.columns - 1)*8, w - 2*state.margin)

    def test_modes(self):
        for width, mode in [(320,'compact'), (393,'standard'), (540,'expanded'), (800,'tablet')]:
            self.assertEqual(choose(width,800).mode, mode)

    def test_rotation(self):
        portrait, landscape = choose(360,800), choose(800,360)
        self.assertFalse(portrait.short)
        self.assertTrue(landscape.short)
        self.assertGreater(landscape.columns, portrait.columns)

    def test_font_and_small_width(self):
        for width in (240,320,360,412,540,800):
            for scale in (1,1.5,2):
                state = choose(width,640,scale)
                self.assertGreaterEqual(state.columns,1)
                self.assertLessEqual(state.columns,choose(width,640).columns)
                self.assertLessEqual(state.columns*80*scale+(state.columns-1)*8,width-2*state.margin)

    def test_dashboard_reflow(self):
        self.assertEqual(choose(320,640).card_columns,1)
        self.assertEqual(choose(800,360).card_columns,4)
