#!/bin/bash
# Generate Plink_Full_Audit.txt — all Swift files in one file for Gemini audit

cd /home/z/my-project/raveclone-review-v2

OUTPUT="Plink_Full_Audit.txt"
> "$OUTPUT"

# Find all .swift files, sorted
find Plink -name "*.swift" -not -path "*/Assets/*" | sort | while read -r file; do
    echo "// ==========================================" >> "$OUTPUT"
    echo "// ФАЙЛ: $file" >> "$OUTPUT"
    echo "// ==========================================" >> "$OUTPUT"
    echo "" >> "$OUTPUT"
    cat "$file" >> "$OUTPUT"
    echo "" >> "$OUTPUT"
    echo "" >> "$OUTPUT"
done

# Also include Obj-C XCDYouTubeKit files (modified by us)
find Plink/Vendors/XCDYouTubeKit -name "*.m" -o -name "*.h" | sort | while read -r file; do
    echo "// ==========================================" >> "$OUTPUT"
    echo "// ФАЙЛ: $file" >> "$OUTPUT"
    echo "// ==========================================" >> "$OUTPUT"
    echo "" >> "$OUTPUT"
    cat "$file" >> "$OUTPUT"
    echo "" >> "$OUTPUT"
    echo "" >> "$OUTPUT"
done

# Include project.yml
echo "// ==========================================" >> "$OUTPUT"
echo "// ФАЙЛ: project.yml" >> "$OUTPUT"
echo "// ==========================================" >> "$OUTPUT"
echo "" >> "$OUTPUT"
cat project.yml >> "$OUTPUT"
echo "" >> "$OUTPUT"

# Include Info.plist
echo "// ==========================================" >> "$OUTPUT"
echo "// ФАЙЛ: Plink/Resources/Info.plist" >> "$OUTPUT"
echo "// ==========================================" >> "$OUTPUT"
echo "" >> "$OUTPUT"
cat Plink/Resources/Info.plist >> "$OUTPUT"

LINES=$(wc -l < "$OUTPUT")
SIZE=$(du -h "$OUTPUT" | cut -f1)
echo "✅ Generated $OUTPUT — $LINES lines, $SIZE"
