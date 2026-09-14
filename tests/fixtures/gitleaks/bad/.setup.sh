# A random GitHub-token-shaped string, built at test time so no secret-shaped
# text is ever committed to this repo (or trips push protection).
# Bounded input: with SIGPIPE ignored (some CI/tool runners), `tr </dev/urandom`
# would never exit after `head` closes the pipe.
token=$(head -c 4096 /dev/urandom | LC_ALL=C tr -dc 'A-Za-z0-9' | head -c 36)
printf 'GITHUB_TOKEN = "ghp_%s"\n' "$token" >config.txt
