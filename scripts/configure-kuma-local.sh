#!/usr/bin/env bash
set -euo pipefail

TRAEFIK_HOST="${TRAEFIK_HOST:-localhost}"

echo "==> Waiting for Kuma container..."
until docker exec dusty-utility-kuma true 2>/dev/null; do sleep 2; done

echo "==> Waiting for Kuma DB..."
until docker exec dusty-utility-kuma sqlite3 /app/data/kuma.db \
    ".tables" 2>/dev/null | grep -q monitor; do
  sleep 2
done

db() { docker exec dusty-utility-kuma sqlite3 -cmd ".timeout 30000" /app/data/kuma.db "$@"; }

# 0. Drop Kuma v2 triggers that block direct SQLite inserts
docker exec dusty-utility-kuma sqlite3 /app/data/kuma.db \
  "SELECT 'DROP TRIGGER IF EXISTS ' || name || ';'
   FROM sqlite_master
   WHERE type='trigger' AND tbl_name IN ('monitor','monitor_group');" \
  | docker exec -i dusty-utility-kuma sqlite3 /app/data/kuma.db

# 1. Remove obsolete monitors not in the known set
KNOWN=("'kuma'" "'freellmapi'" )
KNOWN_SQL=$(IFS=,; echo "${KNOWN[*]}")
db "DELETE FROM monitor WHERE LOWER(name) NOT IN (${KNOWN_SQL});"

# 2. Deduplicate monitors
db "DELETE FROM monitor WHERE id NOT IN (SELECT MIN(id) FROM monitor GROUP BY LOWER(name));"

# 3. Correct stale URLs
db "UPDATE monitor SET url = 'http://host.docker.internal:3001'  WHERE name = 'Kuma';"
db "UPDATE monitor SET url = 'http://host.docker.internal:3002'  WHERE name = 'FreeLLMAPI';"

# 4. Fix corrupted accepted_statuscodes_json (was stored without inner quotes)
db "UPDATE monitor SET accepted_statuscodes_json = '[\"200-299\"]'
     WHERE accepted_statuscodes_json = '[200-299]';"

# 5. Insert missing monitors
insert_monitor_codes() {
  local name="$1" url="$2" codes="$3"
  db "INSERT INTO monitor (name, active, user_id, interval, url, type, maxretries, accepted_statuscodes_json)
       SELECT '${name}', 1, 1, 60, '${url}', 'http', 1, '${codes}'
       WHERE NOT EXISTS (SELECT 1 FROM monitor WHERE LOWER(name) = LOWER('${name}'));
       UPDATE monitor SET accepted_statuscodes_json = '${codes}' WHERE LOWER(name) = LOWER('${name}');"
}

insert_monitor() {
  local name="$1" url="$2"
  insert_monitor_codes "${name}" "${url}" '["200-299"]'
}

insert_monitor "Kuma"  "http://host.docker.internal:3001"
insert_monitor "FreeLLMAPI"  "http://host.docker.internal:3002"

# 6. Ensure status page exists
db "INSERT INTO status_page (slug, title, description, icon, theme, published, show_tags, footer_text, custom_css, show_powered_by, show_certificate_expiry)
     SELECT 'status', 'Status', '', '', 'light', 1, 0, '', '', 1, 0
     WHERE NOT EXISTS (SELECT 1 FROM status_page WHERE slug = 'status');"
db "UPDATE status_page SET footer_text='' WHERE slug='status';"

# 7. Ensure all monitors are linked to the status page
db "
  INSERT INTO \"group\" (name, public, active, weight, status_page_id)
  SELECT 'Services', 1, 1, 1000, (SELECT id FROM status_page WHERE slug = 'status')
  WHERE NOT EXISTS (
    SELECT 1 FROM \"group\" WHERE status_page_id = (SELECT id FROM status_page WHERE slug = 'status')
  );

  INSERT INTO monitor_group (monitor_id, group_id, weight)
  SELECT m.id,
    (SELECT id FROM \"group\" WHERE status_page_id = (SELECT id FROM status_page WHERE slug = 'status') LIMIT 1),
    1000
  FROM monitor m
  WHERE NOT EXISTS (SELECT 1 FROM monitor_group mg WHERE mg.monitor_id = m.id)
    AND (SELECT id FROM \"group\" WHERE status_page_id = (SELECT id FROM status_page WHERE slug = 'status') LIMIT 1) IS NOT NULL;
"

# 8. Restart Kuma
docker restart dusty-utility-kuma
