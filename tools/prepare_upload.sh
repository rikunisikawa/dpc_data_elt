#!/usr/bin/env bash
set -euo pipefail

show_help() {
  cat <<'USAGE'
Usage: tools/prepare_upload.sh --facility <FACILITY_CD> --month <YYYY-MM|YYYYMM> --file-type <TYPE> --input <FILE> [options]

Options:
  --facility <FACILITY_CD>   9 digit facility code (e.g. 131000123)
  --month <YYYY-MM|YYYYMM>   Target month. Hyphenated or compact form is accepted.
  --file-type <TYPE>         One of: y1, y3, y4, ef_in, ef_out, d, h, k
  --input <FILE>             Source file to be copied into the upload directory.
  --dest <DIR>               Base directory for the upload tree. Defaults to ./upload_work/
  --seq <NNN>                Sequence number (3 digits). Autodetected if omitted.
  --move                     Move the file instead of copying it.
  --dry-run                  Show the planned actions without copying/moving files.
  --help                     Show this help.

The script prepares an S3-compatible directory layout for manual uploads.
It creates raw/yyyymm=<YYYY-MM>/<file_type>/ and renames the input file
according to docs/03_s3_naming.md.
USAGE
}

FACILITY=""
MONTH=""
FILE_TYPE=""
INPUT_FILE=""
DEST_DIR="./upload_work"
SEQ=""
MOVE="false"
DRY_RUN="false"

ALLOWED_TYPES=(y1 y3 y4 ef_in ef_out d h k)

while [[ $# -gt 0 ]]; do
  case "$1" in
    --facility)
      FACILITY="$2"
      shift 2
      ;;
    --month)
      MONTH="$2"
      shift 2
      ;;
    --file-type)
      FILE_TYPE="$2"
      shift 2
      ;;
    --input)
      INPUT_FILE="$2"
      shift 2
      ;;
    --dest)
      DEST_DIR="$2"
      shift 2
      ;;
    --seq)
      SEQ="$2"
      shift 2
      ;;
    --move)
      MOVE="true"
      shift
      ;;
    --dry-run)
      DRY_RUN="true"
      shift
      ;;
    --help|-h)
      show_help
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      show_help >&2
      exit 1
      ;;
  esac
done

if [[ -z "$FACILITY" || -z "$MONTH" || -z "$FILE_TYPE" || -z "$INPUT_FILE" ]]; then
  echo "Missing required arguments." >&2
  show_help >&2
  exit 1
fi

if [[ ! -f "$INPUT_FILE" ]]; then
  echo "Input file not found: $INPUT_FILE" >&2
  exit 1
fi

if [[ ! "$FACILITY" =~ ^[0-9]{9}$ ]]; then
  echo "Facility code must be 9 digits." >&2
  exit 1
fi

NORMALISED_MONTH=""
if [[ "$MONTH" =~ ^[0-9]{6}$ ]]; then
  NORMALISED_MONTH="${MONTH:0:4}-${MONTH:4:2}"
elif [[ "$MONTH" =~ ^[0-9]{4}-[0-9]{2}$ ]]; then
  NORMALISED_MONTH="$MONTH"
else
  echo "Month must be in YYYYMM or YYYY-MM format." >&2
  exit 1
fi

if [[ ! " ${ALLOWED_TYPES[*]} " =~ (^|[[:space:]])${FILE_TYPE}($|[[:space:]]) ]]; then
  echo "Invalid file type: $FILE_TYPE" >&2
  echo "Allowed values: ${ALLOWED_TYPES[*]}" >&2
  exit 1
fi

EXTENSION="${INPUT_FILE##*.}"
if [[ "$EXTENSION" == "$INPUT_FILE" ]]; then
  EXTENSION="dat"
fi

DEST_FOLDER="$DEST_DIR/raw/yyyymm=$NORMALISED_MONTH/$FILE_TYPE"
TARGET_NAME=""

calculate_next_seq() {
  local existing max_seq numeric
  max_seq=0
  if [[ -d "$DEST_FOLDER" ]]; then
    shopt -s nullglob
    for existing in "$DEST_FOLDER"/${FACILITY}_??????_${FILE_TYPE}_???.*; do
      existing="${existing##*/}"
      numeric="${existing%.*}"
      numeric="${numeric##*_}"
      if [[ "$numeric" =~ ^[0-9]{3}$ ]]; then
        if ((10#$numeric > max_seq)); then
          max_seq=$((10#$numeric))
        fi
      fi
    done
    shopt -u nullglob
  fi
  printf "%03d" $((max_seq + 1))
}

if [[ -z "$SEQ" ]]; then
  mkdir -p "$DEST_FOLDER"
  SEQ="$(calculate_next_seq)"
else
  if [[ ! "$SEQ" =~ ^[0-9]{3}$ ]]; then
    echo "Sequence must be a 3 digit number (e.g. 001)." >&2
    exit 1
  fi
  mkdir -p "$DEST_FOLDER"
  TARGET_CHECK="$DEST_FOLDER/${FACILITY}_$(echo "$NORMALISED_MONTH" | tr -d -)_${FILE_TYPE}_${SEQ}."
  if compgen -G "$TARGET_CHECK*" > /dev/null; then
    echo "Target sequence already exists: ${SEQ}" >&2
    exit 1
  fi
fi

COMPACT_MONTH="$(echo "$NORMALISED_MONTH" | tr -d -)"
TARGET_NAME="${FACILITY}_${COMPACT_MONTH}_${FILE_TYPE}_${SEQ}.${EXTENSION}"
TARGET_PATH="$DEST_FOLDER/$TARGET_NAME"

if [[ "$DRY_RUN" == "true" ]]; then
  echo "[DRY-RUN] Would create directory: $DEST_FOLDER"
  if [[ "$MOVE" == "true" ]]; then
    echo "[DRY-RUN] Would move $INPUT_FILE -> $TARGET_PATH"
  else
    echo "[DRY-RUN] Would copy $INPUT_FILE -> $TARGET_PATH"
  fi
  exit 0
fi

mkdir -p "$DEST_FOLDER"

if [[ "$MOVE" == "true" ]]; then
  mv "$INPUT_FILE" "$TARGET_PATH"
else
  cp "$INPUT_FILE" "$TARGET_PATH"
fi

echo "Prepared file: $TARGET_PATH"

MANIFEST_HINT="$DEST_FOLDER/_manifest.json"
if [[ ! -f "$MANIFEST_HINT" ]]; then
  cat <<EONOTE
Next step: generate a manifest at $MANIFEST_HINT using tools/generate_manifest.py.
EONOTE
fi
