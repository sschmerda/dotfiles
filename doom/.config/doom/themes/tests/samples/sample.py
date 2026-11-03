"""A long readable docstring; keywords inside documentation stay comments."""
from dataclasses import dataclass
from enum import Enum

LIMIT = 42
class State(Enum):
    READY = True

@dataclass
class Landscape:
    name: str
    def describe(self, prefix: str = "Region\n") -> str:
        # Ordinary parameters/properties stay quiet; calls use function color.
        return prefix + self.name

print(Landscape("Provence").describe())
