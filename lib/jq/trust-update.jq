# oath-harness trust score update filter
# Usage:
#   Success: jq --arg d "domain" --arg action "success" \
#                --argjson bt 20 --arg now "2024-..." \
#                --argjson rb 1.5 \
#                -f trust-update.jq file.json
#   Failure: jq --arg d "domain" --arg action "failure" \
#                --argjson fd 0.85 --arg now "2024-..." \
#                --argjson rb 1.5 \
#                -f trust-update.jq file.json

if $action == "success" then
    .domains[$d] as $dom |
    (if $dom.total_operations < $bt then
        (if $dom.is_warming_up then 0.10 else 0.05 end)
    else
        (if $dom.is_warming_up then 0.04 else 0.02 end)
    end) as $rate |

    # Recovery boost: multiply rate by $rb (default 1.5) when recovering
    (if ($dom.is_recovering // false) then
        $rate * ($rb // 1.5)
    else
        $rate
    end) as $final_rate |

    (($dom.score + (1 - $dom.score) * $final_rate) * 100000 | round / 100000) as $new_score |
    (if $new_score > 1 then 1 elif $new_score < 0 then 0 else $new_score end) as $clamped |
    (if $dom.is_warming_up then $dom.warmup_remaining - 1 else $dom.warmup_remaining end) as $wr |
    (if $dom.is_warming_up and $wr <= 0 then false else $dom.is_warming_up end) as $wu |
    (if $wr < 0 then 0 else $wr end) as $wr_final |

    # Recovery completion: clear recovery state when score reaches pre_failure_score
    (if ($dom.is_recovering // false) and
        $clamped >= ($dom.pre_failure_score // 1.0) then
        false
    else
        ($dom.is_recovering // false)
    end) as $still_recovering |

    # Clear pre_failure_score when recovery just completed (was recovering, now done)
    (if $still_recovering == false and ($dom.is_recovering // false) then
        null
    else
        ($dom.pre_failure_score // null)
    end) as $pfs |

    .domains[$d].score = $clamped |
    .domains[$d].successes = ($dom.successes + 1) |
    .domains[$d].total_operations = ($dom.total_operations + 1) |
    .domains[$d].last_operated_at = $now |
    .domains[$d].is_warming_up = $wu |
    .domains[$d].warmup_remaining = $wr_final |
    .domains[$d].is_recovering = $still_recovering |
    .domains[$d].pre_failure_score = $pfs |
    .domains[$d].consecutive_failures = 0 |
    .global_operation_count = (.global_operation_count + 1) |
    .updated_at = $now
elif $action == "failure" then
    .domains[$d] as $dom |

    # Determine whether this is the first failure in a new sequence
    ((($dom.consecutive_failures // 0) == 0) and
     (($dom.is_recovering // false) | not)) as $is_first_failure |

    # On first failure: record score before decay and start recovery tracking
    (if $is_first_failure then $dom.score else ($dom.pre_failure_score // null) end) as $pfs |
    (if $is_first_failure then true else ($dom.is_recovering // false) end) as $recovering |

    .domains[$d].score = (.domains[$d].score * $fd) |
    .domains[$d].failures = ($dom.failures + 1) |
    .domains[$d].total_operations = ($dom.total_operations + 1) |
    .domains[$d].last_operated_at = $now |
    .domains[$d].consecutive_failures = (($dom.consecutive_failures // 0) + 1) |
    .domains[$d].pre_failure_score = $pfs |
    .domains[$d].is_recovering = $recovering |
    .global_operation_count = (.global_operation_count + 1) |
    .updated_at = $now
else
    error("Unknown action: \($action)")
end
