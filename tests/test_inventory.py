import sys
sys.path.append('.')
from inventory import Inventory, ItemStack
from block_data import BlockType

def test_inventory_add_and_get():
    inv = Inventory(size=27)
    inv.add_item(BlockType.DIRT, 10)
    assert inv.get_qty(BlockType.DIRT) == 10

def test_inventory_stack_limit():
    inv = Inventory(size=27)
    inv.add_item(BlockType.DIRT, 70) # 64 in one slot, 6 in another
    assert inv.get_qty(BlockType.DIRT) == 70
    # verify it used two slots
    assert inv.slots[0].quantity == 64
    assert inv.slots[1].quantity == 6

def test_inventory_remove():
    inv = Inventory(size=27)
    inv.add_item(BlockType.DIRT, 10)
    assert inv.remove_qty(BlockType.DIRT, 5) == True
    assert inv.get_qty(BlockType.DIRT) == 5
    assert inv.remove_qty(BlockType.DIRT, 6) == False # Too many

def test_inventory_full_rejection():
    inv = Inventory(size=1)
    inv.add_item(BlockType.DIRT, 64)
    assert inv.add_item(BlockType.DIRT, 1) == False # Slot full

if __name__ == "__main__":
    test_inventory_add_and_get()
    test_inventory_stack_limit()
    test_inventory_remove()
    test_inventory_full_rejection()
    print("All inventory tests passed!")
