#!/usr/bin/env bash
# Prints a read-only report of the live app taxonomy. It never opens SQLite in a
# write-capable mode, and `query_only` rejects accidental writes on this connection.
set -euo pipefail

readonly app_bundle_identifier="com.jonphillips.yeschef"
readonly database_file_name="SQLiteData.db"

usage() {
  cat <<'EOF'
Usage: scripts/facet-taxonomy-report.sh [path-to-SQLiteData.db]

Without a path, resolves the currently booted iOS simulator's Yes Chef app-group
container. Supplying a path is useful for inspecting a device copy or a backup.

The database is opened read-only. The script makes no writes or schema changes.
EOF
}

if (( $# > 1 )); then
  usage >&2
  exit 64
fi

if ! command -v sqlite3 >/dev/null; then
  printf 'facet-taxonomy-report.sh: sqlite3 is required.\n' >&2
  exit 69
fi

if (( $# == 1 )); then
  database_path="$1"
else
  if ! command -v xcrun >/dev/null; then
    printf 'facet-taxonomy-report.sh: pass the database path when xcrun is unavailable.\n' >&2
    exit 69
  fi

  set +e
  app_group_path="$(xcrun simctl get_app_container booted "$app_bundle_identifier" group 2>/dev/null)"
  simctl_status=$?
  set -e
  if (( simctl_status != 0 || -z "$app_group_path" )); then
    cat >&2 <<EOF
facet-taxonomy-report.sh: could not find a booted simulator's app-group container.
Boot Yes Chef in a simulator, or pass the path to $database_file_name explicitly.
EOF
    exit 66
  fi
  database_path="$app_group_path/$database_file_name"
fi

if [[ ! -f "$database_path" ]]; then
  printf 'facet-taxonomy-report.sh: database not found: %s\n' "$database_path" >&2
  exit 66
fi

# `-readonly` preserves WAL visibility while ensuring SQLite cannot create or
# modify a database file. `query_only` is a second, connection-local guard.
query() {
  sqlite3 -readonly -noheader -separator $'\x1f' "$database_path" "PRAGMA query_only = ON; $1"
}

print_section() {
  printf '\n%s\n' "$1"
  printf '%*s\n' "${#1}" '' | tr ' ' '-'
}

printf 'Yes Chef taxonomy report (read-only)\n'
printf 'Database: %s\n' "$database_path"

print_section "Facets"
facet_rows="$(query "
  SELECT
    f.name,
    CASE WHEN f.hidden THEN 'hidden' ELSE 'visible' END,
    c.name,
    COALESCE(parent.name, ''),
    COUNT(DISTINCT rc.recipeID)
  FROM facets AS f
  LEFT JOIN categories AS c ON c.facetID = f.id
  LEFT JOIN categories AS parent ON parent.id = c.parentCategoryID
  LEFT JOIN recipeCategories AS rc ON rc.categoryID = c.id
  GROUP BY f.id, f.name, f.hidden, c.id, c.name, parent.name
  ORDER BY f.sortOrder, f.name COLLATE NOCASE, c.sortOrder, c.name COLLATE NOCASE
")"

if [[ -z "$facet_rows" ]]; then
  printf '(none)\n'
else
  current_facet=""
  while IFS=$'\x1f' read -r facet_name visibility category_name parent_name recipe_count; do
    if [[ "$facet_name" != "$current_facet" ]]; then
      printf '%s (%s)\n' "$facet_name" "$visibility"
      current_facet="$facet_name"
    fi
    if [[ -z "$category_name" ]]; then
      printf '  (no values)\n'
    elif [[ -n "$parent_name" ]]; then
      printf '  - %s (under %s): %s recipe(s)\n' "$category_name" "$parent_name" "$recipe_count"
    else
      printf '  - %s: %s recipe(s)\n' "$category_name" "$recipe_count"
    fi
  done <<< "$facet_rows"
fi

print_section "Loose labels"
loose_label_rows="$(query '
  SELECT c.name, COUNT(DISTINCT rc.recipeID)
  FROM categories AS c
  LEFT JOIN recipeCategories AS rc ON rc.categoryID = c.id
  WHERE c.facetID IS NULL
    AND c.parentCategoryID IS NULL
    AND NOT EXISTS (
      SELECT 1 FROM categories AS child WHERE child.parentCategoryID = c.id
    )
  GROUP BY c.id, c.name
  ORDER BY c.name COLLATE NOCASE, c.sortOrder
')"
if [[ -z "$loose_label_rows" ]]; then
  printf '(none)\n'
else
  while IFS=$'\x1f' read -r category_name recipe_count; do
    printf -- '- %s: %s recipe(s)\n' "$category_name" "$recipe_count"
  done <<< "$loose_label_rows"
fi

print_section "FLAGS — unresolved roots"
unresolved_root_rows="$(query '
  SELECT
    root.name,
    COUNT(DISTINCT child.id),
    COUNT(DISTINCT root_assignment.recipeID),
    GROUP_CONCAT(child.name, ", ")
  FROM categories AS root
  JOIN categories AS child ON child.parentCategoryID = root.id
  LEFT JOIN recipeCategories AS root_assignment ON root_assignment.categoryID = root.id
  WHERE root.facetID IS NULL
  GROUP BY root.id, root.name
  ORDER BY root.name COLLATE NOCASE
')"
if [[ -z "$unresolved_root_rows" ]]; then
  printf 'None.\n'
else
  while IFS=$'\x1f' read -r root_name child_count root_recipe_count child_names; do
    printf 'FLAG: %s has %s child category(s) [%s] and %s direct recipe assignment(s).\n' \
      "$root_name" "$child_count" "$child_names" "$root_recipe_count"
  done <<< "$unresolved_root_rows"
fi

print_section "FLAGS — invalid parent/facet relationships"
invalid_parent_rows="$(query '
  SELECT
    child.name,
    COALESCE(child_facet.name, "loose label"),
    parent.name,
    COALESCE(parent_facet.name, "loose label")
  FROM categories AS child
  JOIN categories AS parent ON parent.id = child.parentCategoryID
  LEFT JOIN facets AS child_facet ON child_facet.id = child.facetID
  LEFT JOIN facets AS parent_facet ON parent_facet.id = parent.facetID
  WHERE child.parentCategoryID IS NOT NULL
    AND (parent.facetID IS NULL OR child.facetID IS NOT parent.facetID)
  ORDER BY child.name COLLATE NOCASE, parent.name COLLATE NOCASE
')"
if [[ -z "$invalid_parent_rows" ]]; then
  printf 'None.\n'
else
  while IFS=$'\x1f' read -r child_name child_facet_name parent_name parent_facet_name; do
    printf 'FLAG: %s (%s) is parented under %s (%s).\n' \
      "$child_name" "$child_facet_name" "$parent_name" "$parent_facet_name"
  done <<< "$invalid_parent_rows"
fi

print_section "FLAGS — categories with a missing facet"
missing_facet_rows="$(query '
  SELECT c.name
  FROM categories AS c
  LEFT JOIN facets AS f ON f.id = c.facetID
  WHERE c.facetID IS NOT NULL AND f.id IS NULL
  ORDER BY c.name COLLATE NOCASE
')"
if [[ -z "$missing_facet_rows" ]]; then
  printf 'None.\n'
else
  while IFS= read -r category_name; do
    printf 'FLAG: %s references a facet row that is not present.\n' "$category_name"
  done <<< "$missing_facet_rows"
fi

print_section "FLAGS — duplicate names within a facet"
duplicate_rows="$(query '
  SELECT f.name, d.name, d.category_count
  FROM (
    SELECT facetID, name COLLATE NOCASE AS name, COUNT(*) AS category_count
    FROM categories
    WHERE facetID IS NOT NULL
    GROUP BY facetID, name COLLATE NOCASE
    HAVING COUNT(*) > 1
  ) AS d
  JOIN facets AS f ON f.id = d.facetID
  ORDER BY f.name COLLATE NOCASE, d.name COLLATE NOCASE
')"
if [[ -z "$duplicate_rows" ]]; then
  printf 'None.\n'
else
  while IFS=$'\x1f' read -r facet_name category_name category_count; do
    printf 'FLAG: %s has %s values named %s.\n' "$facet_name" "$category_count" "$category_name"
  done <<< "$duplicate_rows"
fi

print_section "FLAGS — loose labels matching a facet value"
matching_loose_rows="$(query '
  SELECT DISTINCT loose.name, facet.name, value.name
  FROM categories AS loose
  JOIN categories AS value ON value.name = loose.name COLLATE NOCASE
  JOIN facets AS facet ON facet.id = value.facetID
  WHERE loose.facetID IS NULL
    AND loose.parentCategoryID IS NULL
    AND NOT EXISTS (
      SELECT 1 FROM categories AS child WHERE child.parentCategoryID = loose.id
    )
  ORDER BY loose.name COLLATE NOCASE, facet.name COLLATE NOCASE, value.name COLLATE NOCASE
')"
if [[ -z "$matching_loose_rows" ]]; then
  printf 'None.\n'
else
  while IFS=$'\x1f' read -r loose_name facet_name value_name; do
    printf 'FLAG: loose label %s matches %s in facet %s.\n' "$loose_name" "$value_name" "$facet_name"
  done <<< "$matching_loose_rows"
fi

print_section "Recipes without category assignments"
zero_assignment_count="$(query '
  SELECT COUNT(*)
  FROM recipes AS r
  WHERE NOT EXISTS (
    SELECT 1 FROM recipeCategories AS rc WHERE rc.recipeID = r.id
  )
')"
printf '%s recipe(s) have zero category assignments.\n' "$zero_assignment_count"
