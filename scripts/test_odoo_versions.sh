#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TESTS_DIR="${ROOT_DIR}/tests"
rm -rf ${TESTS_DIR}

ODOO_VERSIONS=(12 13 14 15 16 17 18 19)

for odoo_ver in "${ODOO_VERSIONS[@]}"; do
  project_dir="${TESTS_DIR}/odoo${odoo_ver}"
  project_ini="${project_dir}/odoo-project.ini"

  echo "=== Odoo ${odoo_ver} ==="
  mkdir -p "${project_dir}"

  cat > "${project_ini}" <<EOF
[virtualenv]
requirements =
  lxml>=6

[odoo]
version = ${odoo_ver}.0

[config]
db_host = 127.0.0.1
db_name = odoo
db_user = odoo
db_password = odoo
EOF

  echo "Creating workspace for Odoo ${odoo_ver}..."
  odt-env "${project_ini}" --sync-all --create-venv

  #echo "Running initdb.sh for Odoo ${odoo_ver}..."
  #bash "${project_dir}/odoo-scripts/initdb.sh"

  #echo "Running update.sh for Odoo ${odoo_ver}..."
  #bash "${project_dir}/odoo-scripts/update.sh"

  echo "Done for Odoo ${odoo_ver}"
  echo
done

echo "All Odoo versions processed successfully."
