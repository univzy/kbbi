# Encryption & Decryption

> Technical deep-dive into Salsa20 stream cipher and gzip compression protecting KBBI dictionary data.

## Overview

Each `acu_desc_N.s` file is compressed with **gzip** and then encrypted with **Salsa20** (stream cipher). Decryption happens entirely at build time in `src/kbbi/crypto.nim` — the browser never sees encrypted data.

## Salsa20 Algorithm

**Salsa20** is a stream cipher designed by D. J. Bernstein. It's faster than AES and doesn't require specialized CPU instructions.

### How it works:

1. **Input:** 256-bit key + 64-bit nonce + 64-bit block counter
2. **State:** 4×4 matrix of 32-bit words (little-endian)
3. **Rounds:** Apply 10 double rounds (column round + row round) to the state
4. **Output:** Add original state back, serialize to 64-byte little-endian output
5. **Keystream:** Repeat for each 64-byte block, incrementing counter each time
6. **Decryption:** `plaintext = ciphertext XOR keystream`

### Initial state matrix:

```
sigma[0]    key[0]      key[1]      key[2]
key[3]      sigma[1]    nonce[0]    nonce[1]
counter_lo  counter_hi  sigma[2]    key[4]
key[5]      key[6]      key[7]      sigma[3]
```

Where `sigma = "expand 32-byte k"` is a standard Salsa20 constant.

### Key & Nonce:

Both are hardcoded constants reverse-engineered from the KBBI Android app:

**Current key (hex):** `ffef8a8d11f535b73cd24fd31ef296d0573ade68b1f079cbdea460149ed4036e`  
**Current nonce (hex):** `fa1f5b7694c268fc`

Stored in `src/kbbi/crypto.nim`. If you're working with a newer KBBI APK version, these may differ. See [How to find the encryption key](key.md) to reverse-engineer them from a different APK.

## Decryption Pipeline

```
acu_desc_N.s (encrypted)
    │
    ├─ Read raw bytes (N × 64-byte blocks)
    │
    ├─ Initialize Salsa20 state (key, nonce, block counter = 0)
    │
    ├─ Generate keystream via Salsa20 rounds
    │
    └─→ XOR ciphertext with keystream → plaintext bytes
                          │
                          ▼
                  gzip decompress (using zippy library)
                          │
                          ▼
              seq[byte] (raw binary data)
                  │
                  ├─ parseEntry()
                  │
                  └─→ SQLite INSERT (entries, senses, examples, xrefs, ...)
```

## Counter & Overflow Protection

The block counter is stored as two 32-bit words in the Salsa20 state, allowing up to 2⁶⁴ × 64 bytes ≈ **1.18 × 10²¹ bytes** per (key, nonce) pair.

The implementation checks for counter overflow and raises an exception if exceeded — this is a safety measure. In practice, KBBI data is only ~30 MB, so never comes close.
