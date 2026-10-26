# Made-up report for --demo, in the same shape as report.jq, dated to the current cycle.
# Inputs: $start $end $prevStart $today (YYYY-MM-DD).

def day_index($from): ((. + "T00:00:00Z" | fromdate) - ($from + "T00:00:00Z" | fromdate)) / 86400 | floor;
def date_at($n): ($start + "T00:00:00Z" | fromdate) + $n * 86400 | todate | .[0:10];
def round2: . * 100 | round / 100;

["claude-sonnet-5-5", "claude-haiku-5-5", "claude-opus-5-5", "claude-fable-5-1"] as $topModels
| ($end | day_index($start)) as $cycleDays
| ($today | day_index($start)) as $elapsed
# A weekday rhythm with a couple of busy days, split across models in fixed shares.
| [range(0; $elapsed) as $i
    | (($i * 37 + 11) % 23) as $wobble
    | (if ($i % 7) >= 5 then 1.1 else 4.2 end + $wobble / 9 + (if $i % 9 == 4 then 6.5 else 0 end)) as $cost
    | {date: date_at($i), cost: ($cost | round2),
       byModel: [$cost * 0.62, $cost * 0.14, $cost * 0.16, $cost * 0.05] | map(round2)}] as $daily
| ([$daily[].cost] | add // 0) as $total
| {
    cycleStart: $start,
    cycleEnd: $end,
    cycleDays: $cycleDays,
    through: (if $elapsed > 0 then date_at($elapsed - 1) else null end),
    daysElapsed: $elapsed,
    total: $total,
    models: [
      {model: $topModels[0], cost: ($total * 0.62)},
      {model: $topModels[2], cost: ($total * 0.16)},
      {model: $topModels[1], cost: ($total * 0.14)},
      {model: $topModels[3], cost: ($total * 0.05)},
      {model: "claude-haiku-4-5", cost: ($total * 0.03)}
    ],
    types: [
      {type: "Cache write 5m", cost: ($total * 0.41)},
      {type: "Output", cost: ($total * 0.29)},
      {type: "Cache read", cost: ($total * 0.17)},
      {type: "Input", cost: ($total * 0.13)}
    ],
    daily: $daily,
    topModels: $topModels,
    previous: {start: $prevStart, total: 158.4, toDate: ($total * 1.18)},
    keys: [
      {name: "my-app (production)", cost: ($total * 0.58), tokens: 61200000, estimated: true, unpriced: false},
      {name: "nightly-batch", cost: ($total * 0.27), tokens: 33900000, estimated: true, unpriced: false},
      {name: "dev-scripts", cost: ($total * 0.11), tokens: 9400000, estimated: true, unpriced: false},
      {name: "Console / Workbench", cost: ($total * 0.04), tokens: 2100000, estimated: true, unpriced: false}
    ],
    tokens: {input: 5800000, output: 1900000, cacheRead: 79000000, cacheWrite: 19900000, cacheHitRate: 0.75},
    webSearches: 0,
    today: ([range(0; 24) as $h | {h: $h,
        cost: (if $h >= 13 and $h <= 22 then (($h * 7) % 5 + 1) * 0.11 else 0 end | round2)}] as $hours
      | {date: $today, cost: ([$hours[].cost] | add | round2), unpriced: false, tokens: 4100000, hours: $hours}),
    updated: (now | floor)
  }
