import sys
sys.path.append('.')

from chunk import Chunk

def test_chunk_refresh():
    # Create chunk and validate refresh can be called
    chunk = Chunk(0, 0, 0)  
    assert hasattr(chunk, 'refresh')
    
    # Verify it doesn't crash
    try:
        chunk.refresh()
    except Exception as e:
        pytest.fail(f"refresh() raised {type(e).__name__}: {e}")