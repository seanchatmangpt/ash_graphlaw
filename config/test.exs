# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT

import Config

# UNSUPPORTED(generator-capability): hand-written config.
# Tests start their own supervised hosts/pools (AshGraphLaw.Test.Case), never the global pool.
config :ash_graphlaw, start_pool: false

# Fixture domains under test/support are not registered application domains.
config :ash, :validate_domain_config_inclusion?, false
config :ash, :validate_domain_resource_inclusion?, false
config :ash, :missed_notifications, :ignore
