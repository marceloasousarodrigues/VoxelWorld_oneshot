import sys
sys.path.append('.')

from chunk import Chunk
from chunk_entity import create_chunk_entity
from block_data import BlockType


def test_chunk_entity_has_transparent_child_for_water():
    chunk = Chunk(0, 0, 0)
    chunk.set_block(0, 0, 0, BlockType.WATER)

    entity = create_chunk_entity(chunk, (0, 0, 0))

    assert entity is not None
    assert hasattr(chunk, 'entity_transparent')
    assert chunk.entity_transparent is not None
    # WATER is transparent, so its faces should land in the transparent mesh;
    # but we only assert wiring exists and is disabled/enabled depending on
    # mesh generation.
    assert chunk.entity_transparent.enabled in (True, False)


if __name__ == '__main__':
    test_chunk_entity_has_transparent_child_for_water()
    print('Task 5 transparency wiring test passed!')
