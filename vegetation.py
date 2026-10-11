"""
Deterministic vegetation generation for VoxelWorld (M14).

This module is deliberately Ursina-free so it can be imported and tested
headlessly.

Every generation decision is a pure function of ``(seed, world coordinates)``.
No code here calls Python's builtin ``hash()`` (salted per process) or the
``random`` module, so identical seeds produce identical worlds regardless of
chunk generation order, load order or process.
"""

UINT32_MASK = 0xFFFFFFFF
UINT64_MASK = 0xFFFFFFFFFFFFFFFF

# splitmix64 constants.
_GOLDEN = 0x9E3779B97F4A7C15
_MIX_A = 0xBF58476D1CE4E5B9
_MIX_B = 0x94D049BB133111EB

# Per-channel odd multipliers used to fold the four inputs together before
# mixing, so that e.g. (x=1, z=0) and (x=0, z=1) cannot collide.
_SALT_MUL_SEED = 0x9E3779B1
_SALT_MUL_X = 0x85EBCA77
_SALT_MUL_Z = 0xC2B2AE3D
_SALT_MUL_SALT = 0x27D4EB2F


def _mix64(value: int) -> int:
    """Finalize a 64-bit accumulator with the splitmix64 mixer."""
    value = (value + _GOLDEN) & UINT64_MASK
    value = ((value ^ (value >> 30)) * _MIX_A) & UINT64_MASK
    value = ((value ^ (value >> 27)) * _MIX_B) & UINT64_MASK
    return (value ^ (value >> 31)) & UINT64_MASK


def hash32(seed: int, x: int, z: int, salt: int = 0) -> int:
    """
    Deterministic 32-bit hash of ``(seed, x, z, salt)``.

    Explicit 32-bit arithmetic over a 64-bit accumulator, so negative
    coordinates and negative salts are handled uniformly and the result is
    identical in every process.

    Args:
        seed: World seed
        x: X world coordinate
        z: Z world coordinate
        salt: Domain separator so one coordinate can serve several decisions

    Returns:
        Integer in ``[0, 2**32)``
    """
    combined = (
        ((seed & UINT32_MASK) * _SALT_MUL_SEED)
        ^ ((x & UINT32_MASK) * _SALT_MUL_X)
        ^ ((z & UINT32_MASK) * _SALT_MUL_Z)
        ^ ((salt & UINT32_MASK) * _SALT_MUL_SALT)
    ) & UINT64_MASK
    return _mix64(combined) & UINT32_MASK
