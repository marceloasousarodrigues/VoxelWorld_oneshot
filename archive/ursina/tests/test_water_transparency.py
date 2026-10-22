import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from panda3d.core import TransparencyAttrib

from block_data import BlockType
from chunk import Chunk
from chunk_entity import create_chunk_entity


def _water_chunk_with_entity():
    chunk = Chunk(0, 0, 0)
    chunk.set_block(0, 0, 0, BlockType.WATER)
    entity = create_chunk_entity(chunk, (0, 0, 0))
    assert entity is not None
    return chunk


def test_water_child_uses_alpha_blending():
    chunk = _water_chunk_with_entity()
    child = chunk.entity_transparent
    assert child is not None
    assert child.model is not None
    assert child.model.getTransparency() == TransparencyAttrib.M_alpha


def test_water_child_does_not_write_depth():
    chunk = _water_chunk_with_entity()
    model = chunk.entity_transparent.model
    assert model.getDepthWrite() is False
    assert model.getDepthTest() is True


def test_water_child_renders_in_transparent_bin():
    chunk = _water_chunk_with_entity()
    model = chunk.entity_transparent.model
    assert model.getBinName() == "transparent"


def test_water_child_configuration_survives_mesh_refresh():
    chunk = _water_chunk_with_entity()

    chunk.refresh()

    child = chunk.entity_transparent
    assert child.model is not None
    assert child.model.getTransparency() == TransparencyAttrib.M_alpha
    assert child.model.getDepthWrite() is False
    assert child.model.getBinName() == "transparent"
