docker logs env-pingfederate-1 2>&1 | grep -i "subject\|USER_KEY\|puma" | tail -30
