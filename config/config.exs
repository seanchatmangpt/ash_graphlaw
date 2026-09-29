# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT

import Config

# UNSUPPORTED(generator-capability): hand-written config.
# Ash requires an explicit string length counting mode for the fixture resources under test/support.
config :ash, default_string_length_count: :codepoints

import_config "#{config_env()}.exs"
