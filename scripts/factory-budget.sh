# shellcheck shell=bash
# Sourced (never run): the one place that says where an instance's installed budget lives and what a worker count
# may be, so the installer, which writes it, and factory-status.sh, which judges the running workers against it,
# cannot drift apart. The drop-in sits on the fast-lane template, so every worker instance reads it. Needs NAME
# (the instance name, factory_config's FACTORY_NAME).
FACTORY_UNITS="${FACTORY_UNITS:-$HOME/.config/systemd/user}"
factory_budget_file() { echo "$FACTORY_UNITS/factory-$NAME-fast@.service.d/budget.conf"; }

# <variable name> -> the value installed on this host, or empty when the drop-in does not name it.
factory_budget() {
  sed -n "s/^Environment=$1=//p" "$(factory_budget_file)" 2> /dev/null | head -n 1 || true
}

# <value> -> true when it is a worker count the installer accepts (1-9).
factory_budget_valid() { [[ $1 =~ ^[1-9]$ ]]; }
