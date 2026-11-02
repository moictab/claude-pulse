#!/bin/bash
# claude-pulse subagent rows for Claude Code's agent panel (the `subagentStatusLine` setting).
# Reads {columns, cwd, tasks: [...]} on stdin and writes one {"id", "content"} JSON line per row:
# status name (type) · model effort · tokens context-bar % activity · elapsed · dir · label
# If jq is missing or fails, nothing is printed and Claude Code keeps its default rows.

IFS= read -r -d '' input  # all of stdin, without spawning cat
[ -z "$input" ] && exit 0
command -v jq >/dev/null 2>&1 || exit 0

jq -c '
    # ANSI truecolor codes, same palette as statusline.sh
    def blue: "\u001b[38;2;0;153;255m";
    def orange: "\u001b[38;2;255;176;85m";
    def green: "\u001b[38;2;0;160;0m";
    def cyan: "\u001b[38;2;46;149;153m";
    def red: "\u001b[38;2;255;85;85m";
    def yellow: "\u001b[38;2;230;200;0m";
    def white: "\u001b[38;2;220;220;220m";
    def dim: "\u001b[2m";
    def reset: "\u001b[0m";
    def sep: " \(dim)·\(reset) ";

    def round0: . + 0.5 | floor;
    def repeat($n): if $n > 0 then . * $n else "" end;
    def tok:
        if . >= 1000000 then (. / 100000 | round0) as $d | "\($d / 10 | floor).\($d % 10)m"
        elif . >= 1000 then "\(. / 1000 | round0)k"
        else "\(floor)" end;
    def dur:
        (. / 1000 | floor) as $s
        | if $s >= 3600 then "\($s / 3600 | floor)h \($s % 3600 / 60 | floor)m"
          elif $s >= 60 then "\($s / 60 | floor)m \($s % 60)s"
          else "\($s)s" end;
    # Width as the terminal sees it: drop color codes
    def visible_length: gsub("\u001b\\[[0-9;]*m"; "") | length;

    # Colored progress bar, same thresholds as statusline.sh
    def bar($pct; $width):
        ([[$pct, 0] | max, 100] | min) as $p
        | ($p * $width / 100 | floor) as $filled
        | (if $p >= 90 then red elif $p >= 70 then yellow elif $p >= 50 then orange else green end)
          + ("█" | repeat($filled)) + dim + ("░" | repeat($width - $filled)) + reset;

    # Activity sparkline: tokens added per refresh tick over the last samples
    def spark:
        [range(1; length) as $i | .[$i] - .[$i - 1] | if . < 0 then 0 else . end][-8:] as $deltas
        | ($deltas | max // 0) as $max
        | if $max <= 0 then ""
          else $deltas | map(["▁","▂","▃","▄","▅","▆","▇","█"][. * 7 / $max | round0]) | join("")
          end;

    # claude-opus-5-5 → opus 5.5, claude-haiku-4-5-20251001 → haiku 4.5; anything else is kept as is
    def model_short:
        (capture("^claude-(?<family>[a-z]+)-(?<major>[0-9]+)(-(?<minor>[0-9]{1,2}))?(?=-|\\[|$)")
         | "\(.family) \(.major)\(if .minor then ".\(.minor)" else "" end)") // .;

    def basename: gsub("\\\\"; "/") | sub("/+$"; "") | split("/") | last // "";

    (.columns // 100) as $columns
    | (.cwd // "") as $session_cwd
    | .tasks[]?
    | select(.id)
    | (.status // "") as $status
    | ($status == "running") as $running
    | (if $status == "running" then yellow + "●"
       elif $status == "completed" then green + "✔"
       elif $status == "failed" then red + "✘"
       elif $status == "killed" then dim + "⊘"
       else dim + "○" end) + reset as $icon
    | (.name // .agentType // "agent") as $name
    | (blue + $name + reset
       + (if .name and .agentType and .agentType != .name then " \(dim)(\(.agentType))\(reset)" else "" end)
      ) as $who
    | ([(.model // "" | select(. != "") | cyan + model_short + reset),
        (.effort | select(. != null) | dim + (if type == "number" then "\(tok) tok" else tostring end) + reset)]
       | join(" ")) as $model
    | (.tokenCount // 0) as $token_count
    | (orange + ($token_count | tok) + reset) as $tokens
    | ($tokens
       + (if (.contextWindowSize // 0) > 0
          then ($token_count * 100 / .contextWindowSize | floor) as $pct
               | " \(bar($pct; 5)) \(cyan)\($pct)%\(reset)"
          else "" end)
      ) as $usage
    | (if $running then .tokenSamples // [] | spark | if . != "" then " \(green)\(.)\(reset)" else "" end
       else "" end) as $activity
    | (if $running and .startTime then white + ([now * 1000 - .startTime, 0] | max | dur) + reset else "" end) as $elapsed
    | (if .cwd and .cwd != $session_cwd then dim + "@" + reset + cyan + (.cwd | basename) + reset else "" end) as $dir
    # Richest layout first; drop activity, dir, model and elapsed until the row fits
    | ([[$model, $usage + $activity, $elapsed, $dir],
        [$model, $usage, $elapsed, $dir],
        [$model, $usage, $elapsed],
        [$usage, $elapsed],
        [$tokens]]
       | map($icon + " " + $who + (map(select(. != "")) | map(sep + .) | join("")))
      ) as $layouts
    | (first($layouts[] | select(visible_length < $columns)) // $layouts[-1]) as $fixed
    | (.label // .description // "" | if . == $name then "" else . end) as $label
    | ($columns - ($fixed | visible_length) - 4) as $room
    | {
        id,
        content: ($fixed
          + if $label == "" or $room < 8 then ""
            elif ($label | length) > $room then sep + white + $label[:$room - 1] + "…" + reset
            else sep + white + $label + reset end)
      }
' <<<"$input" 2>/dev/null | tr -d '\r'  # native jq.exe on Windows writes CRLF

exit 0
