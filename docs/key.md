# Reverse-Engineering the Encryption Key

> Extract the Salsa20 key and nonce from the KBBI Android app to support new APK versions.

## Overview

The Salsa20 key and nonce used to decrypt `acu_desc_*.s` are hardcoded in the KBBI Android app. This page explains how they were found, so you can re-derive them if a newer APK version changes the key.

## Tools

| Tool | Purpose | Optional? |
|------|---------|----------|
| [jadx](https://github.com/skylot/jadx) | Decompile APK to Java/Smali bytecode | No — preferred |
| [apktool](https://apktool.org) | Alternative APK decompiler | Yes — use if jadx fails |
| `grep` (or equivalent) | Search for key patterns in decompiled code | Yes — use any text search tool |
| Hex editor (e.g., `hexdump`, VS Code) | Search for key in binary .so files | Yes — only needed for native libraries |

**Install:**
- **jadx:** Download from [GitHub releases](https://github.com/skylot/jadx/releases), add to PATH
- **apktool:** Download from [apktool.org](https://apktool.org)
- **grep:** Pre-installed on Linux/macOS; use WSL or Git Bash on Windows

## Method 1: Decompile & Search Java/Smali Code

**Best approach — usually the key is in Java bytecode.**

### Step 1: Decompile the APK

```bash
jadx -d kbbi_src/ KBBI.apk
```

This creates `kbbi_src/` directory with decompiled Java code.

### Step 2: Search for the Key

The key is a 64-character hex string (32 bytes). Known patterns:

```bash
# Search for the known key prefix (adjust if searching for a new version)
grep -r "ffef8a8d" kbbi_src/

# Or search for Salsa20 sigma constant
grep -r "expand 32" kbbi_src/

# Or search for nonce patterns
grep -rE "[0-9a-f]{16}" kbbi_src/
```

### Step 3: Extract the Key

Once found, the key may be stored as a static array or constructed dynamically. For KBBI VI October 2025, the key is built by concatenating string parts and computed values:

```java
// Example decompiled output (KBBI VI October 2025)
L117:
    return (byte[]) r4.i("ffef8a8d11f535b73cd24fd31e" + r12 + O3.m.a(r11) + "d4036e");
```

Where:
- `"ffef8a8d11f535b73cd24fd31e"` — key prefix (28 hex chars)
- `r12` — computed value yielding `"f296d0573ade68b1"` (16 hex chars)
- `O3.m.a(r11)` — computed value yielding `"f079cbdea460149e"` (16 hex chars)
- `"d4036e"` — key suffix (6 hex chars)

Final key: `ffef8a8d11f535b73cd24fd31ef296d0573ade68b1f079cbdea460149ed4036e`

Convert to hex string format and record both key and nonce.

---

## Method 2: Search Native `.so` Libraries

**If the key is hardcoded in ARM/x86 native code instead of Java.**

### Step 1: Extract Native Libraries

```bash
unzip KBBI.apk "lib/*" -d lib_extracted/
```

### Step 2: Search for Binary Patterns

```bash
# Search for Salsa20 sigma constant (ASCII text)
grep -r "expand 32" lib_extracted/lib/

# Or use hexdump to find byte patterns
hexdump -C lib_extracted/lib/arm64-v8a/libnative.so | grep -i "expand"
```

Near the sigma constant, the key and nonce will be stored as byte sequences.

---

## Step 3: Update Crypto Module

Once extracted, update `src/kbbi/crypto.nim` with the new key and nonce:

```nim
# src/kbbi/crypto.nim

const key: array[32, byte] = block:
  const keyHex = "ffef8a8d...your_new_64_char_hex_string_here"
  # Conversion from hex string to byte array
  var k: array[32, byte]
  for i in 0..<32:
    k[i] = byte(fromHex[int](keyHex[i*2..<i*2+2]))
  k

const nonce: array[8, byte] = block:
  const nonceHex = "your_new_16_char_hex_nonce_here"
  var n: array[8, byte]
  for i in 0..<8:
    n[i] = byte(fromHex[int](nonceHex[i*2..<i*2+2]))
  n
```

### Step 4: Rebuild

```bash
# Rebuild the builder and database
nimble builddb

# Test with the new key
./bin/kbbi_build path/to/new_assets/ kbbi_new.db

# If successful, the database will be populated with dictionary entries
echo "SELECT COUNT(*) FROM entries;" | sqlite3 kbbi_new.db
```

---

## Troubleshooting

| Problem | Solution |
|---------|----------|
| **No key found in decompiled code** | The key may be in native `.so` library — try Method 2, or contact the project maintainers |
| **Decompiler crashes** | Try a different version of jadx, or use apktool as alternative |
| **Key extracted but decryption still fails** | Double-check byte order (big-endian vs little-endian), or try keys from multiple APK versions |
| **Database builds but has 0 entries** | The key is wrong — try other candidates or extract again |

---

## Verification

After updating the key, verify it works:

```bash
# This should show the number of dictionary entries
echo "SELECT COUNT(*), SUM(LENGTH(text)) FROM senses;" | sqlite3 kbbi.db
```

If output is empty or shows 0, the key is incorrect — try a different candidate.

---

## Verification

A correct decryption produces valid gzip data. If the key is wrong, `zippy` raises a decompression error during `kbbi_build`. You can also verify by checking that the first two bytes of the decrypted output are `0x1f 0x8b` (the gzip magic number).
