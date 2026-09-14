# Case-insensitive filesystems (macOS) can't hold a.txt and A.txt side by side,
# so A.txt only goes into the index.
git add a.txt
blob=$(git hash-object -w a.txt)
git update-index --add --cacheinfo "100644,$blob,A.txt"
