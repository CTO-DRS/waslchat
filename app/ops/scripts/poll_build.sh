set -e
SHA=$1
for i in $(seq 1 70); do
  R=$(curl -s -H "User-Agent: wasl" "https://api.github.com/repos/CTO-DRS/wasl-chat/actions/runs?head_sha=$SHA")
  ST=$(echo "$R" | jq -r '.workflow_runs[0].status'); CO=$(echo "$R" | jq -r '.workflow_runs[0].conclusion'); ID=$(echo "$R" | jq -r '.workflow_runs[0].id')
  if [ "$ST" = "completed" ]; then echo "run $ID $CO"; break; fi
  sleep 15
done
[ "$CO" = "success" ] || exit 1
A=$(curl -s -H "User-Agent: wasl" "https://api.github.com/repos/CTO-DRS/wasl-chat/actions/runs/$ID/artifacts" | jq -r '.artifacts[0].archive_download_url')
curl -sL -H "User-Agent: wasl" -o /tmp/art.zip "$A"
rm -rf /tmp/art && mkdir /tmp/art && unzip -q -o /tmp/art.zip -d /tmp/art && ls -la /tmp/art
