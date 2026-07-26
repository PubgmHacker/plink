#!/bin/bash
# scripts/test-theme-memory.sh — Living Themes 30-min memory test
#
# Запускает Plink на симуляторе, открывает WatchRoom с каждой темой,
# замеряет memory через 5 мин на каждой теме.
# Target: <200MB на iOS, <150MB на Android
#
# Usage: ./scripts/test-theme-memory.sh [ios|android]

set -e

PLATFORM=${1:-ios}
DURATION_PER_THEME=${2:-300}  # 5 min per theme (default)
THEMES=("aurora" "cosmos" "verdant" "magma")

echo "╔════════════════════════════════════════════════════════════╗"
echo "║   Plink Living Themes Memory Test                          ║"
echo "║   Platform: $PLATFORM                                       ║"
echo "║   Duration per theme: ${DURATION_PER_THEME}s                ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

if [ "$PLATFORM" = "ios" ]; then
    echo "▶ Booting iPhone 15 Pro simulator..."
    xcrun simctl boot "iPhone 15 Pro" 2>/dev/null || true
    xcrun simctl bootstatus "iPhone 15 Pro"

    echo "▶ Installing Plink.app..."
    xcrun simctl install "iPhone 15 Pro" ~/Library/Developer/Xcode/DerivedData/Plink-*/Build/Products/Debug-iphonesimulator/Plink.app

    echo "▶ Launching Plink..."
    xcrun simctl launch "iPhone 15 Pro" com.syncwatch.plink
    sleep 10

    for theme in "${THEMES[@]}"; do
        echo ""
        echo "═════════════════════════════════════════════════════════════"
        echo "Testing theme: $theme"
        echo "═════════════════════════════════════════════════════════════"

        xcrun simctl openurl "iPhone 15 Pro" "plink://theme/$theme"
        sleep 5

        PID=$(xcrun simctl spawn "iPhone 15 Pro" launchctl list | grep Plink | awk '{print $1}')
        if [ -n "$PID" ]; then
            MEMORY=$(xcrun simctl spawn "iPhone 15 Pro" ps -o rss= -p "$PID" 2>/dev/null | awk '{print int($1/1024)}')
            echo "  Initial memory: ${MEMORY}MB"
        fi

        echo "  Running for ${DURATION_PER_THEME}s..."
        sleep $DURATION_PER_THEME

        if [ -n "$PID" ]; then
            MEMORY_AFTER=$(xcrun simctl spawn "iPhone 15 Pro" ps -o rss= -p "$PID" 2>/dev/null | awk '{print int($1/1024)}')
            echo "  Final memory:   ${MEMORY_AFTER}MB"

            if [ "$MEMORY_AFTER" -gt 200 ]; then
                echo "  ❌ FAIL: Memory exceeds 200MB limit!"
            else
                echo "  ✅ PASS: Memory under 200MB"
            fi
        fi
    done

elif [ "$PLATFORM" = "android" ]; then
    echo "▶ Starting Android emulator..."
    $ANDROID_HOME/emulator/emulator -avd Pixel_7_API_34 -no-window &
    EMULATOR_PID=$!

    adb wait-for-device
    adb shell 'while [[ -z $(getprop sys.boot_completed) ]]; do sleep 1; done;'

    echo "▶ Installing Plink APK..."
    adb install -r android-client/app/build/outputs/apk/debug/app-debug.apk

    echo "▶ Launching Plink..."
    adb shell am start -n com.plink.app/.MainActivity
    sleep 10

    for theme in "${THEMES[@]}"; do
        echo ""
        echo "═════════════════════════════════════════════════════════════"
        echo "Testing theme: $theme"
        echo "═════════════════════════════════════════════════════════════"

        adb shell am start -a android.intent.action.VIEW -d "plink://theme/$theme"
        sleep 5

        MEMORY=$(adb shell dumpsys meminfo com.plink.app | grep "TOTAL RSS" | awk '{print $3}')
        echo "  Initial memory: ${MEMORY}KB"

        echo "  Running for ${DURATION_PER_THEME}s..."
        sleep $DURATION_PER_THEME

        MEMORY_AFTER=$(adb shell dumpsys meminfo com.plink.app | grep "TOTAL RSS" | awk '{print $3}')
        MEMORY_MB=$((MEMORY_AFTER / 1024))
        echo "  Final memory:   ${MEMORY_MB}MB"

        if [ "$MEMORY_MB" -gt 150 ]; then
            echo "  ❌ FAIL: Memory exceeds 150MB limit!"
        else
            echo "  ✅ PASS: Memory under 150MB"
        fi
    done

    kill $EMULATOR_PID
fi

echo ""
echo "═════════════════════════════════════════════════════════════"
echo "Test complete."
echo "═════════════════════════════════════════════════════════════"
