"""Module documentation remains a comment, not an ordinary string."""
from dataclasses import dataclass
from enum import Enum

LIMIT = 42
FLAG = True
EMPTY = None

class State(Enum):
    READY = 1

@dataclass
class Landscape:
    name: str

    def describe(self, prefix: str = "Region\n") -> str:
        """Method documentation is also a comment."""
        # A real comment.
        count = 12.5
        local = len(prefix)
        return prefix + self.name

region = Landscape("Provence")
result = region.describe()
print(result)
converted = str(42)
status = State.READY
escaped = "tab\tend"
