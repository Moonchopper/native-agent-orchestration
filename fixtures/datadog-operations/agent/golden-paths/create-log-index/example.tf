# Template — substitute the values enclosed in <> with the confirmed inputs.
# This file is copied (with substitutions) to terraform/logs/indexes/<team>.tf.

resource "datadog_logs_index" "<team>" {
  name = "<team>-<env>"

  filter {
    query = "<filter>"
  }

  retention {
    tier = "<tier>"  # "Flex" or "Standard"
    days = <days>
  }

  daily_limit = <quota>
}
