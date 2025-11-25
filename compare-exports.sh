#!/bin/bash

# Check if two directories are provided
if [ $# -ne 2 ]; then
    echo "Usage: $0 <EXPORT_DIR_1> <EXPORT_DIR_2>"
    echo ""
    echo "Compares two export directories created by export-all.sh"
    echo ""
    echo "Example:"
    echo "  $0 export-before export-after"
    exit 1
fi

DIR1="$1"
DIR2="$2"

# Verify directories exist
if [ ! -d "$DIR1" ]; then
    echo "Error: Directory not found: $DIR1"
    exit 1
fi

if [ ! -d "$DIR2" ]; then
    echo "Error: Directory not found: $DIR2"
    exit 1
fi

echo "Comparing Helm release exports:"
echo "  Directory 1: $DIR1"
echo "  Directory 2: $DIR2"
echo ""
echo "===================="
echo ""

# Counters
IDENTICAL_COUNT=0
DIFFERENT_COUNT=0
ONLY_IN_DIR1=0
ONLY_IN_DIR2=0

# Arrays to store results
IDENTICAL_RELEASES=()
DIFFERENT_RELEASES=()

# Function to compare two release directories
compare_release() {
    local ns="$1"
    local release="$2"
    local rel_dir1="$DIR1/$ns/$release"
    local rel_dir2="$DIR2/$ns/$release"

    # Get sorted list of files in each directory
    FILES1=$(cd "$rel_dir1" 2>/dev/null && find . -type f -name "*.yaml" | sort)
    FILES2=$(cd "$rel_dir2" 2>/dev/null && find . -type f -name "*.yaml" | sort)

    # Compare file lists
    if [ "$FILES1" != "$FILES2" ]; then
        echo "[$ns/$release] DIFFERENT FILE STRUCTURE"
        echo "  Files only in DIR1: $(comm -23 <(echo "$FILES1") <(echo "$FILES2") | wc -l | tr -d ' ')"
        echo "  Files only in DIR2: $(comm -13 <(echo "$FILES1") <(echo "$FILES2") | wc -l | tr -d ' ')"
        DIFFERENT_RELEASES+=("$ns/$release (file structure)")
        DIFFERENT_COUNT=$((DIFFERENT_COUNT + 1))
        return
    fi

    # Compare each file
    DIFF_LINES=0
    DIFF_FILES=0

    for file in $FILES1; do
        file_path1="$rel_dir1/$file"
        file_path2="$rel_dir2/$file"

        if ! diff -q "$file_path1" "$file_path2" > /dev/null 2>&1; then
            DIFF_FILES=$((DIFF_FILES + 1))
            # Count different lines
            LINES=$(diff -u "$file_path1" "$file_path2" | grep -c '^[+-]' | tr -d ' ')
            DIFF_LINES=$((DIFF_LINES + LINES))
        fi
    done

    if [ "$DIFF_FILES" -eq 0 ]; then
        echo "[$ns/$release] IDENTICAL"
        IDENTICAL_RELEASES+=("$ns/$release")
        IDENTICAL_COUNT=$((IDENTICAL_COUNT + 1))
    else
        echo "[$ns/$release] DIFFERENT ($DIFF_FILES files, ~$DIFF_LINES lines)"
        DIFFERENT_RELEASES+=("$ns/$release ($DIFF_FILES files, ~$DIFF_LINES lines)")
        DIFFERENT_COUNT=$((DIFFERENT_COUNT + 1))

        # Show detailed diff if requested (could add a --verbose flag)
        # for file in $FILES1; do
        #     if ! diff -q "$rel_dir1/$file" "$rel_dir2/$file" > /dev/null 2>&1; then
        #         echo "  Changed: $file"
        #     fi
        # done
    fi
}

# Find all releases in DIR1
for ns_dir in "$DIR1"/*; do
    if [ -d "$ns_dir" ]; then
        ns=$(basename "$ns_dir")

        for release_dir in "$ns_dir"/*; do
            if [ -d "$release_dir" ]; then
                release=$(basename "$release_dir")

                # Check if release exists in DIR2
                if [ -d "$DIR2/$ns/$release" ]; then
                    compare_release "$ns" "$release"
                else
                    echo "[$ns/$release] ONLY IN DIR1"
                    ONLY_IN_DIR1=$((ONLY_IN_DIR1 + 1))
                fi
            fi
        done
    fi
done

echo ""

# Find releases only in DIR2
for ns_dir in "$DIR2"/*; do
    if [ -d "$ns_dir" ]; then
        ns=$(basename "$ns_dir")

        for release_dir in "$ns_dir"/*; do
            if [ -d "$release_dir" ]; then
                release=$(basename "$release_dir")

                if [ ! -d "$DIR1/$ns/$release" ]; then
                    echo "[$ns/$release] ONLY IN DIR2"
                    ONLY_IN_DIR2=$((ONLY_IN_DIR2 + 1))
                fi
            fi
        done
    fi
done

echo ""
echo "===================="
echo "SUMMARY"
echo "===================="
echo ""
echo "Identical releases: $IDENTICAL_COUNT"
echo "Different releases: $DIFFERENT_COUNT"
echo "Only in DIR1: $ONLY_IN_DIR1"
echo "Only in DIR2: $ONLY_IN_DIR2"
echo ""

if [ ${#IDENTICAL_RELEASES[@]} -gt 0 ]; then
    echo "Identical releases:"
    for release in "${IDENTICAL_RELEASES[@]}"; do
        echo "  ✓ $release"
    done
    echo ""
fi

if [ ${#DIFFERENT_RELEASES[@]} -gt 0 ]; then
    echo "Different releases:"
    for release in "${DIFFERENT_RELEASES[@]}"; do
        echo "  ✗ $release"
    done
    echo ""
fi

# Exit with error code if there are differences
if [ "$DIFFERENT_COUNT" -gt 0 ] || [ "$ONLY_IN_DIR1" -gt 0 ] || [ "$ONLY_IN_DIR2" -gt 0 ]; then
    exit 1
fi

exit 0
