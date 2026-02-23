# oath-harness trust score update filter
# Usage:
#   Success: jq --arg d "domain" --arg action "success" \
#                --argjson bt 20 --arg now "2024-..." \
#                -f trust-update.jq file.json
#   Failure: jq --arg d "domain" --arg action "failure" \
#                --argjson fd 0.85 --arg now "2024-..." \
#                -f trust-update.jq file.json

if $action == "success" then
    .domains[$d] as $dom |
    (if $dom.total_operations < $bt then
        (if $dom.is_warming_up then 0.10 else 0.05 end)
    else
        (if $dom.is_warming_up then 0.04 else 0.02 end)
    end) as $rate |
    (($dom.score + (1 - $dom.score) * $rate) * 100000 | round / 100000) as $new_score |
    (if $new_score > 1 then 1 elif $new_score < 0 then 0 else $new_score end) as $clamped |
    (if $dom.is_warming_up then $dom.warmup_remaining - 1 else $dom.warmup_remaining end) as $wr |
    (if $dom.is_warming_up and $wr <= 0 then false else $dom.is_warming_up end) as $wu |
    (if $wr < 0 then 0 else $wr end) as $wr_final |
    .domains[$d].score = $clamped |
    .domains[$d].successes = ($dom.successes + 1) |
    .domains[$d].total_operations = ($dom.total_operations + 1) |
    .domains[$d].last_operated_at = $now |
    .domains[$d].is_warming_up = $wu |
    .domains[$d].warmup_remaining = $wr_final |
    .global_operation_count = (.global_operation_count + 1) |
    .updated_at = $now
elif $action == "failure" then
    .domains[$d].score = (.domains[$d].score * $fd) |
    .domains[$d].failures = (.domains[$d].failures + 1) |
    .domains[$d].total_operations = (.domains[$d].total_operations + 1) |
    .domains[$d].last_operated_at = $now |
    .global_operation_count = (.global_operation_count + 1) |
    .updated_at = $now
else
    error("Unknown action: \($action)")
end
