# oath-harness time decay filter (single pass over all domains)
# Usage:
#   jq --argjson hd 14 --argjson wo 5 --argjson now_epoch $(date -u +%s) \
#      -f time-decay.jq trust-scores.json
#
# For each domain: if days since last operation > $hd,
# apply 0.999^(days - hd) decay and set warmup flags.

reduce (.domains | keys[]) as $d (
    .;
    .domains[$d] as $dom |
    ($dom.last_operated_at | strptime("%Y-%m-%dT%H:%M:%SZ") | mktime) as $last_epoch |
    (($now_epoch - $last_epoch) / 86400 | floor) as $days_elapsed |
    if $days_elapsed > $hd then
        ($days_elapsed - $hd) as $decay_days |
        ($dom.score * pow(0.999; $decay_days) * 10000 | round / 10000) as $new_score |
        .domains[$d].score = $new_score |
        .domains[$d].is_warming_up = true |
        .domains[$d].warmup_remaining = $wo
    else
        .
    end
)
