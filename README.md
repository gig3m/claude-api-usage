# Claude API Usage

An [Omarchy](https://omarchy.org) bar widget that tracks your Claude API spend against a monthly credit, using the Anthropic [Usage and Cost Admin API](https://platform.claude.com/docs/en/manage-claude/usage-cost-api).

The bar shows a small **pace gauge**:

- the solid fill is how much of the credit you've used,
- the faint fill is where you're projected to end the cycle,
- the tick is how far through the cycle you are.

If the fill runs ahead of the tick you're burning faster than the credit allows, and the gauge turns your theme's urgent colour once the projection passes the credit.

Click it for a flyout with:

- spend vs. credit, burn per day vs. budget per day, and what's left per day
- today's spend (estimated, see below) and the same point in the previous cycle
- daily spend for the whole cycle, stacked by model, with a budget line
- today by hour
- breakdowns by model, by API key, and by token type, plus cache hit rate

It was built for the API credit that comes with Claude Max plans ($100/month on Max 5x, $200 on Max 20x), but any monthly budget works.

## Requirements

- Omarchy with the Quickshell-based shell (plugins under `~/.config/omarchy/plugins/`)
- `curl`, `jq`, `flock` (util-linux)
- An **Admin API key** (`sk-ant-admin01-…`)

### Getting an Admin API key

Admin keys are created in the Claude Console under **Settings → Admin keys**. That page only exists for **organizations**. If you don't see it, your Console account is an individual one: set up an organization at [platform.claude.com/settings/organization](https://platform.claude.com/settings/organization) first. You also need the admin role in that organization.

An Admin key can manage your whole organization (members, workspaces, API keys), not just read usage. Store it like any other high-value secret.

## Install

```sh
omarchy plugin add https://github.com/gig3m/claude-api-usage --enable
```

Then give the widget your key, using one of the three methods below. The fetch script tries them in this order.

1. **Environment variable.** Set `ANTHROPIC_ADMIN_KEY` in the environment the Omarchy shell runs in. On Omarchy, session variables go in `~/.config/uwsm/env`. Use `keyEnv` to pick a different name; it must be upper case.
2. **Wrapper command.** Set `keyExec` to a command prefix that runs its arguments with the variable set. This keeps the key in a password manager. With 1Password, put `ANTHROPIC_ADMIN_KEY=op://<vault>/<item>/<field>` in an env file, then:
   ```sh
   omarchy bar set gig3m.claude-api-usage keyExec "op run --env-file='$HOME/.config/claude-api-usage/op.env' --"
   ```
   The command is split into words with shell-style quoting, but nothing in it is expanded or run through a shell. If the wrapper fails, its first error line shows in the flyout.
3. **Key file.** Put the key in `~/.config/claude-api-usage/admin-key`. A symlink is fine. The script refuses the file if anyone but you can read it:
   ```sh
   mkdir -p ~/.config/claude-api-usage
   install -m 600 /dev/null ~/.config/claude-api-usage/admin-key
   $EDITOR ~/.config/claude-api-usage/admin-key
   ```

Finally, tell it when your credit renews and how much it is:

```sh
omarchy bar set gig3m.claude-api-usage cycleStartDay 3 --json   # credit renews on the 3rd
omarchy bar set gig3m.claude-api-usage credit 200 --json
```

## Settings

| Key | Default | |
|---|---|---|
| `credit` | `200` | Monthly budget in USD. |
| `cycleStartDay` | `1` | Day of the month the credit renews, in UTC. Days past a month's end fall on its last day. |
| `refreshMinutes` | `5` | How often to poll. |
| `barLabel` | `none` | Text next to the gauge: `none`, `spent`, `percent` or `projected`. |
| `keyEnv` | `ANTHROPIC_ADMIN_KEY` | Variable that holds the key. |
| `keyExec` | *(empty)* | Optional wrapper command (see Install). |

**Mouse:** left click opens the flyout, right click refreshes, middle click opens the Console cost page. In the flyout, `R` refreshes and `O` opens the Console. The flyout can also be toggled with `omarchy-shell gig3m.claude-api-usage toggle`.

## How the numbers work

- **The cost report has only complete UTC days.** It has no bucket for the day in progress. So the total, the pace, and the projection run up to a day behind, and on the first day of a cycle there is nothing to show yet.
- **Today's spend is an estimate.** The hourly usage report does include today, but it gives tokens, not dollars. The widget prices today's tokens at the per-model, per-token-type rates you were actually charged earlier in the cycle. If a model has no history in the cycle it can't be priced, and the flyout says so.
- **Spend per API key is also an estimate,** made the same way. The cost report can't be grouped by key. Across the days the cost report covers, the per-key estimates add up to the billed total.
- **The previous cycle** is compared over the same number of complete days.

## Privacy and API use

- The key is passed to `curl` as a config file on stdin, so it never appears in a process's arguments. With methods 1 and 2 it is in the fetch script's environment, which only your user can read.
- Anything that doesn't look like an Anthropic key (`sk-ant-…`) is refused before a request is made. This stops a mistyped `keyEnv` from sending some other value to the API.
- Results are cached for 60 seconds in `$XDG_RUNTIME_DIR/claude-api-usage/` (mode 700). The bar runs one widget per monitor, and they all share one fetch. API key names are cached for an hour.
- Each refresh makes four Admin API requests, plus one for key names once an hour.

## License

MIT
