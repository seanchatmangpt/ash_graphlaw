# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT

import Config

# UNSUPPORTED(generator-capability): hand-written config.
# The admission pool is opt-in; a host application starts AshGraphLaw.Pool itself
# or sets start_pool: true.
config :ash_graphlaw, start_pool: false
