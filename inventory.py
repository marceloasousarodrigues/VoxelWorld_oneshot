from dataclasses import dataclass
from block_data import BlockType

@dataclass
class ItemStack:
    item_type: BlockType
    quantity: int = 1

class Inventory:
    def __init__(self, size: int = 27):
        self.size = size
        self.slots = [None] * size  # List of ItemStack or None
        self.on_changed = None

    def _notify(self):
        if self.on_changed:
            self.on_changed()

    def get_qty(self, item_type: BlockType) -> int:
        return sum(s.quantity for s in self.slots if s and s.item_type == item_type)

    def can_add(self, item_type: BlockType, qty: int) -> bool:
        remaining = qty
        # 1. Check existing compatible stacks
        for slot in self.slots:
            if slot and slot.item_type == item_type and slot.quantity < 64:
                remaining -= min(remaining, 64 - slot.quantity)
            if remaining == 0: return True
            
        # 2. Check empty slots
        for i in range(self.size):
            if not self.slots[i]:
                remaining -= min(remaining, 64)
            if remaining == 0: return True
            
        return False

    def add_item(self, item_type: BlockType, qty: int) -> bool:
        if not self.can_add(item_type, qty):
            return False
        
        remaining = qty
        # 1. Fill existing compatible stacks
        for slot in self.slots:
            if slot and slot.item_type == item_type and slot.quantity < 64:
                can_add = min(remaining, 64 - slot.quantity)
                slot.quantity += can_add
                remaining -= can_add
            if remaining == 0:
                self._notify()
                return True
        
        # 2. Fill empty slots
        for i in range(self.size):
            if not self.slots[i]:
                can_add = min(remaining, 64)
                self.slots[i] = ItemStack(item_type, can_add)
                remaining -= can_add
            if remaining == 0:
                self._notify()
                return True
        
        return False 

    def get_selected_item(self, index: int) -> ItemStack | None:
        if 0 <= index < self.size:
            return self.slots[index]
        return None

    def remove_qty(self, item_type: BlockType, qty: int) -> bool:
        if self.get_qty(item_type) < qty:
            return False
            
        remaining = qty
        for i in range(self.size):
            slot = self.slots[i]
            if slot and slot.item_type == item_type:
                can_remove = min(remaining, slot.quantity)
                slot.quantity -= can_remove
                remaining -= can_remove
                if slot.quantity == 0:
                    self.slots[i] = None
            if remaining == 0:
                self._notify()
                return True
        return False
