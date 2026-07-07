#!/usr/bin/env bash
set -euo pipefail

MOD_JAR="${1:?Usage: $0 <path-to-mod-jar>}"
TEST_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "=== NeoForge Mod Server Test ==="
echo "Mod: $MOD_JAR"
echo ""

cd "$TEST_DIR"

# Clean previous runs
rm -rf world/ config/ logs/ crash-reports/ defaultconfigs/ server.log mods/*.jar

# Accept EULA
echo "eula=true" > eula.txt

# Copy the mod
cp "$MOD_JAR" mods/

# Start server in background
java @user_jvm_args.txt \
    @libraries/net/neoforged/neoforge/21.1.228/unix_args.txt \
    --nogui > server.log 2>&1 &

# Wait for "Done (" or timeout (120s)
for i in $(seq 1 120); do
    if grep -q "Done (" server.log 2>/dev/null; then
        echo ""
        echo "=== Server ready after ~${i}s ==="
        grep "Done (" server.log
        echo ""

        # World creation check
        if grep -q "No existing world data, creating new world" server.log; then
            echo "[PASS] Server created a new world"
        elif grep -q "Preparing spawn area:" server.log; then
            echo "[PASS] World loaded and spawn area prepared"
        else
            echo "[WARN] Could not confirm world creation - check server.log"
        fi

        # world/ directory check
        if [ -d "world/region" ] && [ "$(ls world/region/ 2>/dev/null | wc -l)" -gt 0 ]; then
            echo "[PASS] world/region directory has saved chunks"
        else
            echo "[FAIL] world/region directory is missing or empty"
        fi

        # Mod initialization check
        if grep -q "Initializing" server.log; then
            echo "[PASS] Mods initialized"
        fi

        # Error check
        ERRORS=$(grep -ciE "error|exception" server.log || true)
        FILTERED=$(grep -ciE "error|exception" server.log \
            | grep -v "translation" || true)
        if [ -n "$FILTERED" ] && [ "$FILTERED" -gt 0 ] 2>/dev/null; then
            echo "[FAIL] Found errors in server.log:"
            grep -iE "error|exception" server.log | grep -v "translation" | head -10
        else
            echo "[PASS] No critical errors in server.log"
        fi

        break
    fi

    # Timeout after 120s
    if [ "$i" -ge 120 ]; then
        echo "[FAIL] Server did not reach 'Done' within 120 seconds"
        tail -30 server.log
        exit 1
    fi

    sleep 1
done

# Stop server
echo ""
echo "=== Stopping server ==="
SERVER_PID=$(pgrep -f "neoforge/21.1.228/unix_args" | head -1) || true
if [ -n "$SERVER_PID" ]; then
    kill "$SERVER_PID" 2>/dev/null || true
    # Wait for graceful shutdown (up to 10s)
    for j in $(seq 1 10); do
        if ! kill -0 "$SERVER_PID" 2>/dev/null; then
            break
        fi
        sleep 1
    done
    # Force kill if still running
    if kill -0 "$SERVER_PID" 2>/dev/null; then
        kill -9 "$SERVER_PID" 2>/dev/null || true
    fi
fi
echo "Server stopped"

# Clean up mod (leave other infrastructure for next test)
rm -f mods/*.jar
rm -rf world/ config/ logs/ crash-reports/ defaultconfigs/ server.log

echo ""
echo "=== Test complete ==="
