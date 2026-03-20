# Extracting Data from the APK

> Extract `assets/**/dictdata/` directory from the official KBBI Android app to access encrypted dictionary data.

## Overview

The KBBI dictionary data is bundled inside the official KBBI Android app. You need to extract the `dictdata/` directory from the APK.

## Prerequisites

- **KBBI APK file** — Download from [Google Play Store](https://play.google.com/store/apps/details?id=yuku.kbbi5) or an APK mirror site
- **Zip extraction tool** — APKs are standard ZIP files
  - **Linux/macOS:** `unzip` (usually pre-installed)
  - **Windows:** Built-in Explorer, or [7-Zip](https://www.7-zip.org/), or WSL

## Steps

### 1. Rename the APK to `.zip`

```bash
cp KBBI.apk kbbi.zip
```

### 2. Extract the assets directory

```bash
unzip kbbi.zip "assets/*" -d kbbi_extracted/
```

On Windows, open the `.zip` file in Explorer and copy the `assets/` folder out.

### 3. Locate the data files

Inside `assets/` find `dictdata/` you should find:

```
dictdata/
  acu_nilai.txt          headword index (binary encoded)
  acu_offlens.txt        byte-offset index (maps entry ID → file + offset)
  acu_desc_0.s           encrypted entry data, file 0
  acu_desc_1.s           encrypted entry data, file 1
  ...
  acu_desc_27.s          encrypted entry data, file 27
  kat_index_bahasa.txt   category: language of origin
  kat_index_bidang.txt   category: subject domain
  kat_index_ragam.txt    category: language register
  kat_index_kelas.txt    category: word class / POS
  kat_index_jenis.txt    category: entry type markers
```

### 4. Keep the Files

Keep the extracted `dictdata/` directory — it's needed to build the database.

---

## Troubleshooting

| Issue | Solution |
|-------|----------|
| **APK not extracting** | Make sure your unzip tool supports ZIP64 (for large files). Upgrade to WSL or 7-Zip if using old Windows tools. |
| **`dictdata/` folder not found** | Verify you're looking at the correct KBBI app APK, not a different app. Check the APK's package name: `yuku.kbbi5` |
| **`acu_desc_*.s` files are empty** | The app may have updated. Try a different version of the APK. |
| **File extraction stops halfway** | Your antivirus may be interfering. Try the extraction on a different machine or disable antivirus temporarily. |

---

## Next Steps

1. Once extracted, review [How the encryption works](crypto.md) to understand Salsa20 and gzip decompression
2. Build the database: `./bin/kbbi_build path/to/dictdata/ kbbi.db`
3. If you get decryption errors, check [How to find the encryption key](key.md) — your APK version may have a different key

---

## 💡 Technical Details

- **Files:** The `dictdata/` directory contains encrypted dictionary data split across 28 files (`acu_desc_0.s` through `acu_desc_27.s`)
- **Encryption:** Each file is encrypted with Salsa20 stream cipher then compressed with gzip
- **Format:** Binary-encoded indexes (`acu_nilai.txt`, `acu_offlens.txt`) plus category metadata

See [docs/crypto.md](crypto.md) for cryptography details.
- Exposes the structure
- Makes it reusable
- Enables new tools to be built on top
