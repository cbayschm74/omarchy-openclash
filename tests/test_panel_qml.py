import pathlib
import re
import unittest


PANEL_PATH = pathlib.Path(__file__).resolve().parents[1] / "Panel.qml"


class PanelTextSecurityTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.panel = PANEL_PATH.read_text(encoding="utf-8")

    def test_every_local_text_item_is_explicitly_plain_text(self):
        text_items = list(re.finditer(r"\bText\s*\{(?P<body>.*?)\n\s*\}", self.panel, re.DOTALL))
        self.assertGreater(len(text_items), 0)
        for item in text_items:
            self.assertRegex(
                item.group("body"),
                r"\btextFormat\s*:\s*Text\.PlainText\b",
                "Text item near line "
                + str(self.panel.count("\n", 0, item.start()) + 1)
                + " must opt out of rich-text auto-detection",
            )

    def test_shared_panel_hero_never_receives_controller_names(self):
        hero = re.search(r"\bPanelHero\s*\{(?P<body>.*?)\n\s*iconComponent\s*:", self.panel, re.DOTALL)
        self.assertIsNotNone(hero)
        body = hero.group("body")
        self.assertNotIn("selectedGroup.name", body)
        self.assertNotIn("selectedGroup.now", body)

    def test_controller_group_label_is_rendered_as_plain_text(self):
        self.assertRegex(
            self.panel,
            r'text:\s*selectedGroup\s*\?.*?selectedGroup\.name.*?selectedGroup\.now.*?\n\s*textFormat:\s*Text\.PlainText',
        )


if __name__ == "__main__":
    unittest.main()
