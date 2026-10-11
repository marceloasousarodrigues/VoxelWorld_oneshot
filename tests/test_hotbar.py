import sys
sys.path.append('.')
from player import VoxelPlayer
from world import World

def test_hotbar_selection():
    player = VoxelPlayer(World())
    player.input('2')
    assert player.hotbar_index == 1
    player.input('9')
    assert player.hotbar_index == 8

def test_inventory_toggle():
    player = VoxelPlayer(World())
    assert player.inventory_ui.ui_entity.enabled == False
    player.input('e')
    assert player.inventory_ui.ui_entity.enabled == True
    player.input('e')
    assert player.inventory_ui.ui_entity.enabled == False

if __name__ == "__main__":
    test_hotbar_selection()
    test_inventory_toggle()
    print("All hotbar tests passed!")
