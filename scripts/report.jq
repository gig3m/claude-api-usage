# Builds the widget report from Admin API responses (see claude-cost).
# Inputs: $start $end $prevStart $today (YYYY-MM-DD), $cost $prev $usage $hourly ({data: [...]}),
# $names ([{data: [api keys]}]). Cost amounts are cents; money in the output is dollars.

def day_index($from): ((. + "T00:00:00Z" | fromdate) - ($from + "T00:00:00Z" | fromdate)) / 86400 | floor;
def date_at($n): ($start + "T00:00:00Z" | fromdate) + $n * 86400 | todate | .[0:10];
def sum_by(f): map(f) | add // 0;
def dollars: . / 100;

# Usage rows carry token counts per type; cost rows name the same types in token_type.
def token_counts:
  {
    "uncached_input_tokens": (.uncached_input_tokens // 0),
    "output_tokens": (.output_tokens // 0),
    "cache_read_input_tokens": (.cache_read_input_tokens // 0),
    "cache_creation.ephemeral_5m_input_tokens": (.cache_creation.ephemeral_5m_input_tokens // 0),
    "cache_creation.ephemeral_1h_input_tokens": (.cache_creation.ephemeral_1h_input_tokens // 0)
  };

def type_label:
  if . == "uncached_input_tokens" then "Input"
  elif . == "output_tokens" then "Output"
  elif . == "cache_read_input_tokens" then "Cache read"
  elif . == "cache_creation.ephemeral_5m_input_tokens" then "Cache write 5m"
  elif . == "cache_creation.ephemeral_1h_input_tokens" then "Cache write 1h"
  else . end;

([$cost.data[].starting_at[0:10]] | max) as $through
| [$cost.data[] | .starting_at[0:10] as $d | .results[]
  | {d: $d, model: (.model // null), type: (.token_type // .cost_type // .description // "other"),
     cents: (.amount | tonumber)}] as $rows
| [$usage.data[] | .starting_at[0:10] as $d | .results[]
  | {d: $d, key: .api_key_id, model: .model, tokens: token_counts, searches: (.server_tool_use.web_search_requests // 0)}]
  | map(select($through != null and .d <= $through)) as $use
| [$hourly.data[] | (.starting_at[11:13] | tonumber) as $h | .results[]
  | {h: $h, model: .model, tokens: token_counts}] as $hours

# Effective cents per token for each model and token type, from what this cycle actually cost.
| ($rows | map(select(.model != null and (.type | type) == "string"))
    | group_by(.model + "|" + .type)
    | map({key: (.[0].model + "|" + .[0].type), value: sum_by(.cents)}) | from_entries) as $centsBy
| ($use | map(. as $u | .tokens | to_entries[] | {k: ($u.model + "|" + .key), n: .value})
    | group_by(.k) | map({key: .[0].k, value: sum_by(.n)}) | from_entries) as $tokensBy
| ($centsBy | with_entries(select(($tokensBy[.key] // 0) > 0) | .value = .value / $tokensBy[.key])) as $rate
| def estimate: . as $r | [$r.tokens | to_entries[] | select(.value > 0)
    | {n: .value, rate: $rate[$r.model + "|" + .key]}]
    | {cents: sum_by(.n * (.rate // 0)), unpriced: any(.[]; .rate == null)};

(if $through then ($through | day_index($start)) + 1 else 0 end) as $elapsed
| ($end | day_index($start)) as $cycleDays
| ($rows | group_by(.model // "other") | map({model: (.[0].model // "Other"), cents: sum_by(.cents)})
    | sort_by(-.cents)) as $models
| ($models[0:4] | map(.model)) as $topModels
| {
    cycleStart: $start,
    cycleEnd: $end,
    cycleDays: $cycleDays,
    through: $through,
    daysElapsed: $elapsed,
    total: ($rows | sum_by(.cents) | dollars),
    models: ($models | map({model, cost: (.cents | dollars)})),
    types: ($rows | group_by(.type) | map({type: (.[0].type | type_label), cost: (sum_by(.cents) | dollars)})
      | sort_by(-.cost)),
    daily: [range(0; $elapsed) as $i | date_at($i) as $d
      | ($rows | map(select(.d == $d))) as $day
      | {date: $d, cost: ($day | sum_by(.cents) | dollars),
         byModel: [$topModels[] as $m | $day | map(select((.model // "Other") == $m)) | sum_by(.cents) | dollars]}],
    topModels: $topModels,
    previous: (
      [$prev.data[] | {i: (.starting_at[0:10] | day_index($prevStart)), cents: ([.results[].amount | tonumber] | add // 0)}]
      | {start: $prevStart, total: (sum_by(.cents) | dollars),
         toDate: (map(select(.i < $elapsed)) | sum_by(.cents) | dollars)}),
    keys: ((($names[0].data // []) | map({key: .id, value: .name}) | from_entries) as $keyNames
      | $use | group_by(.key) | map(
          (map(estimate)) as $est
          | {name: (if .[0].key == null then "Console / Workbench" else ($keyNames[.[0].key] // .[0].key) end),
             cost: ($est | sum_by(.cents) | dollars),
             tokens: sum_by(.tokens | add),
             estimated: true,
             unpriced: any($est[]; .unpriced)})
      | sort_by(-.cost)),
    tokens: ($use | map(.tokens) | {
      input: sum_by(.uncached_input_tokens),
      output: sum_by(.output_tokens),
      cacheRead: sum_by(.cache_read_input_tokens),
      cacheWrite: sum_by(.["cache_creation.ephemeral_5m_input_tokens"] + .["cache_creation.ephemeral_1h_input_tokens"])
    } | . + {cacheHitRate: (if (.input + .cacheRead + .cacheWrite) > 0
        then .cacheRead / (.input + .cacheRead + .cacheWrite) else null end)}),
    webSearches: ($use | sum_by(.searches)),
    today: ($hours | map(. + (estimate)) as $priced | {
      date: $today,
      cost: ($priced | sum_by(.cents) | dollars),
      unpriced: any($priced[]; .unpriced),
      tokens: ($hours | sum_by(.tokens | add)),
      hours: [range(0; 24) as $h | {h: $h, cost: ($priced | map(select(.h == $h)) | sum_by(.cents) | dollars)}]
    }),
    updated: (now | floor)
  }
