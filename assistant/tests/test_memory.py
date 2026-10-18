import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from glass_assistant import memory, tools
from glass_assistant.memory import Memory


class MemoryTest(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.path = Path(tmp.name) / "memory.json"

    def test_add_persist_reload(self):
        m = Memory(self.path)
        m.add("Пользователя зовут Рома")
        m.add("Любит Linkin Park")
        self.assertEqual(Memory(self.path).facts(), ["Пользователя зовут Рома", "Любит Linkin Park"])

    def test_duplicates_ignored(self):
        m = Memory(self.path)
        m.add("Любит Linkin Park")
        m.add("любит linkin park.")
        self.assertEqual(len(m.facts()), 1)

    def test_cap_drops_oldest(self):
        m = Memory(self.path)
        for i in range(memory.MAX + 3):
            m.add(f"факт номер {i}")
        self.assertEqual(len(m.facts()), memory.MAX)
        self.assertEqual(m.facts()[0], "факт номер 3")

    def test_forget_by_words(self):
        m = Memory(self.path)
        m.add("Пользователя зовут Рома")
        m.add("Любит Linkin Park")
        self.assertEqual(m.forget("про linkin park"), ["Любит Linkin Park"])
        self.assertEqual(m.facts(), ["Пользователя зовут Рома"])

    def test_forget_all(self):
        m = Memory(self.path)
        m.add("а")
        m.add("б")
        self.assertEqual(len(m.forget("всё")), 2)
        self.assertEqual(m.facts(), [])

    def test_forget_unknown(self):
        m = Memory(self.path)
        m.add("Пользователя зовут Рома")
        self.assertEqual(m.forget("про машину"), [])

    def test_broken_file_is_empty(self):
        self.path.write_text("{не json")
        self.assertEqual(Memory(self.path).facts(), [])

    def test_prompt_block(self):
        m = Memory(self.path)
        self.assertEqual(m.prompt(), "")
        m.add("Пользователя зовут Рома")
        self.assertEqual(m.prompt(), "\n\nЧто ты знаешь о пользователе (он сам просил запомнить):\n- Пользователя зовут Рома")


class MemoryToolsTest(unittest.IsolatedAsyncioTestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        p = patch.object(memory, "store", Memory(Path(tmp.name) / "m.json"))
        p.start()
        self.addCleanup(p.stop)

    async def test_remember_and_forget(self):
        r = await tools.run("remember", {"fact": "Пользователя зовут Рома"})
        self.assertEqual((r.ok, r.show), (True, "Запомнил: Пользователя зовут Рома"))
        self.assertEqual(memory.store.facts(), ["Пользователя зовут Рома"])
        r = await tools.run("forget", {"what": "имя"})
        self.assertFalse(r.ok)                            # «имя» не совпало ни с одним словом
        r = await tools.run("forget", {"what": "как меня зовут, Рома"})
        self.assertEqual((r.ok, r.show), (True, "Забыл: Пользователя зовут Рома"))


if __name__ == "__main__":
    unittest.main()
