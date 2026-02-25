# oath-harness audit entry generator filter
# Usage:
#   jq -n -f audit-entry.jq \
#      --arg timestamp "..." \
#      --arg session_id "..." \
#      --arg tool_name "..." \
#      --argjson tool_input '{...}' \
#      --arg domain "..." \
#      --arg risk_category "..." \
#      --argjson trust_score_before 0.45 \
#      --argjson autonomy_score 0.82 \
#      --arg decision "auto_approved" \
#      --arg outcome "pending" \
#      --argjson trust_score_after null \
#      --arg recommended_model "sonnet" \
#      --arg phase "building" \
#      --argjson complexity 0.5

{
  timestamp:          $timestamp,
  session_id:         $session_id,
  tool_name:          $tool_name,
  tool_input:         $tool_input,
  domain:             $domain,
  risk_category:      $risk_category,
  trust_score_before: $trust_score_before,
  autonomy_score:     $autonomy_score,
  complexity:         $complexity,
  decision:           $decision,
  outcome:            $outcome,
  trust_score_after:  $trust_score_after,
  recommended_model:  $recommended_model,
  phase:              $phase
}
