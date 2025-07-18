#!/usr/bin/env bash

teamwork::get_task_id_from_body() {
  local body=$1
  local task_ids=()

  pat='tasks\/([0-9]{1,})'
  while [[ $body =~ $pat ]]; do
    task_ids+=( "${BASH_REMATCH[1]}" )
    body=${body#*"${BASH_REMATCH[0]}"}
  done

  local task_ids_str
  task_ids_str=$(printf ",%s" "${task_ids[@]}")
  task_ids_str=${task_ids_str:1} # remove initial comma
  echo "$task_ids_str"
}

teamwork::get_project_id_from_task() {
  local -r task_id=$1

  if [ "$ENV" == "test" ]; then
    echo "$task_id"
    return
  fi

  response=$(
    curl "$TEAMWORK_URI/projects/api/v1/tasks/$task_id.json" -u "$TEAMWORK_API_TOKEN"':' |\
      jq -r '.["todo-item"]["project-id"]'
  )
  echo "$response"
}

teamwork::get_matching_board_column_id() {
  local -r column_name=$1

  if [ -z "$column_name" ]; then
    return
  fi

  if [ "$ENV" == "test" ]; then
    echo "$TEAMWORK_PROJECT_ID"
    return
  fi

  response=$(
    curl "$TEAMWORK_URI/projects/$TEAMWORK_PROJECT_ID/boards/columns.json" -u "$TEAMWORK_API_TOKEN"':' |\
      jq -r --arg column_name "$column_name" '[.columns[] | select(.name | contains($column_name))] | map(.id)[0]'
  )

  if [ "$response" = "null" ]; then
    return
  fi

  echo "$response"
}

teamwork::get_user_id() {
  local -r user=$1

  if [ -z "$user" ]; then
    return
  fi

  if [ "$ENV" == "test" ]; then
#    log::message "Test - Simulate request. User Name: $user"
    echo "9999"
    return
  fi

  response=$(
    curl "$TEAMWORK_URI/projects/api/v3/people.json?onlyOwnerCompany=true&userType=account&searchTerm=$user" -u "$TEAMWORK_API_TOKEN"':' |\
      jq -r '.people[0] | .id'
  )

  if [ "$response" = "null" ]; then
    return
  fi

  echo "$response"
}

teamwork::assign_task_to_user() {
  local -r user_ids=$1

  if [ -z "$user_ids" ]; then
    log::message "No user ID provided"
    return
  fi

  if [ "$ENV" == "test" ]; then
    log::message "Test - Simulate request. Task ID: $TEAMWORK_TASK_ID - User ID: $user_id"
    return
  fi

  response=$(curl -X "PUT" "$TEAMWORK_URI/projects/api/v3/tasks/$TEAMWORK_TASK_ID.json" \
      -u "$TEAMWORK_API_TOKEN"':' \
      -H 'Content-Type: application/json; charset=utf-8' \
      -d "{ \"task\": { \"assignees\": { \"userIds\": [ $user_ids ] } } }" )

  log::message "$response"
}

teamwork::move_task_to_column() {
  local -r task_id=$TEAMWORK_TASK_ID
  local -r column_name=$1

  if [ -z "$column_name" ]; then
    log::message "No column name provided"
    return
  fi

  local -r column_id=$(teamwork::get_matching_board_column_id "$column_name")
  if [ -z "$column_id" ]; then
    log::message "Failed to find a matching board column for '$column_name'"
    return
  fi

  if [ "$ENV" == "test" ]; then
    log::message "Test - Simulate request. Task ID: $TEAMWORK_TASK_ID - Project ID: $TEAMWORK_PROJECT_ID - Column ID: $column_id"
    return
  fi

  response=$(curl -X "PUT" "$TEAMWORK_URI/tasks/$TEAMWORK_TASK_ID.json" \
      -u "$TEAMWORK_API_TOKEN"':' \
      -H 'Content-Type: application/json; charset=utf-8' \
      -d "{ \"todo-item\": { \"columnId\": $column_id } }" )

  log::message "$response"
}

teamwork::add_comment() {
  local -r body=$1

  if [ "$ENV" == "test" ]; then
    log::message "Test - Simulate request. Task ID: $TEAMWORK_TASK_ID - Comment: ${body//\"/} - Author ID: $SENDER_USER_ID"
    return
  fi

  response=$(curl -X "POST" "$TEAMWORK_URI/tasks/$TEAMWORK_TASK_ID/comments.json" \
       -u "$TEAMWORK_API_TOKEN"':' \
       -H 'Content-Type: application/json; charset=utf-8' \
       -d "{
                 \"comment\": {
                     \"author-id\": \"$SENDER_USER_ID\",
                     \"body\": \"${body//\"/}\",
                     \"notify\": true,
                     \"content-type\": \"text\",
                     \"isprivate\": $([ "$MAKE_COMMENTS_PRIVATE" == true ] && echo true || echo false)
                 }
             }"
        )
  log::message "$response"
}

teamwork::add_tag() {
  local -r tag_name=$1

  if [ "$ENV" == "test" ]; then
    log::message "Test - Simulate request. Task ID: $TEAMWORK_TASK_ID - Tag Added: ${tag_name//\"/}"
    return
  fi

  if [ "$AUTOMATIC_TAGGING" == true ]; then
    response=$(curl -X "PUT" "$TEAMWORK_URI/tasks/$TEAMWORK_TASK_ID/tags.json" \
       -u "$TEAMWORK_API_TOKEN"':' \
       -H 'Content-Type: application/json; charset=utf-8' \
       -d "{ \"tags\": { \"content\": \"${tag_name//\"/}\" } }" )

    log::message "$response"
  fi
}

teamwork::remove_tag() {
  local -r tag_name=$1

  if [ "$ENV" == "test" ]; then
    log::message "Test - Simulate request. Task ID: $TEAMWORK_TASK_ID - Tag Removed: ${tag_name//\"/}"
    return
  fi

  if [ "$AUTOMATIC_TAGGING" == true ]; then
    response=$(curl -X "PUT" "$TEAMWORK_URI/tasks/$TEAMWORK_TASK_ID/tags.json" \
         -u "$TEAMWORK_API_TOKEN"':' \
         -H 'Content-Type: application/json; charset=utf-8' \
         -d "{ \"tags\": { \"content\": \"${tag_name//\"/}\" },\"removeProvidedTags\":\"true\" }" )

    log::message "$response"
  fi
}

teamwork::pull_request_opened() {
  local -r pr_url=$(github::get_pr_url)
  local -r pr_title=$(github::get_pr_title)
  local -r head_ref=$(github::get_head_ref)
  local -r base_ref=$(github::get_base_ref)
  local -r user=$(github::get_sender_user)
  local -r pr_stats=$(github::get_pr_patch_stats)
  local -r pr_body=$(github::get_pr_body)
  IFS=" " read -r -a pr_stats_array <<< "$pr_stats"

  teamwork::add_comment "
**$user** opened a PR: **$pr_title**
[$pr_url]($pr_url)
\`$base_ref\` ⬅️ \`$head_ref\`

---

${pr_body}

---

🔢 ${pr_stats_array[0]} commits / 📝 ${pr_stats_array[1]} files updated / ➕ ${pr_stats_array[2]} additions / ➖ ${pr_stats_array[3]} deletions

  "

  teamwork::add_tag "PR Open"
  teamwork::move_task_to_column "$BOARD_COLUMN_OPENED"
  teamwork::assign_task_to_user "$TEAMWORK_REVIEWERS"
}

teamwork::pull_request_edited() {
  local -r pr_url=$(github::get_pr_url)
  local -r pr_title=$(github::get_pr_title)
  local -r head_ref=$(github::get_head_ref)
  local -r base_ref=$(github::get_base_ref)
  local -r user=$(github::get_sender_user)
  local -r pr_stats=$(github::get_pr_patch_stats)
  local -r pr_body=$(github::get_pr_body)
  IFS=" " read -r -a pr_stats_array <<< "$pr_stats"

  teamwork::add_comment "
**$user** edited a PR: **$pr_title**
[$pr_url]($pr_url)
\`$base_ref\` ⬅️ \`$head_ref\`

---

${pr_body}

---

🔢 ${pr_stats_array[0]} commits / 📝 ${pr_stats_array[1]} files updated / ➕ ${pr_stats_array[2]} additions / ➖ ${pr_stats_array[3]} deletions

  "

  teamwork::add_tag "PR Open"
  teamwork::move_task_to_column "$BOARD_COLUMN_OPENED"
  teamwork::assign_task_to_user "$TEAMWORK_REVIEWERS"
}

teamwork::reviewers_changed() {
  local -r pr_url=$(github::get_pr_url)
  local -r pr_title=$(github::get_pr_title)
  local -r head_ref=$(github::get_head_ref)
  local -r base_ref=$(github::get_base_ref)
  local -r user=$(github::get_sender_user)
  local -r pr_body=$(github::get_pr_body)
  local -r pr_reviewers=$(github::get_pr_reviewers | jq -r '.name // .login')

  log::message "$(github::get_pr_reviewers)"
  log::message "PR Reviewers: $pr_reviewers"
  log::message "TW PR Reviewers: $TEAMWORK_REVIEWERS"

  teamwork::add_comment "
**$user** changed who is reviewing the PR: **$pr_title**
[$pr_url]($pr_url)

---

${pr_reviewers}

---

  "

  teamwork::add_tag "PR Open"

  if [ -z "$TEAMWORK_REVIEWERS" ]; then
    log::message "No reviewers found, skipping PR reviewers change"
    return
  fi

  teamwork::assign_task_to_user "$TEAMWORK_REVIEWERS"
}

teamwork::pull_request_review_request_removed() {
  teamwork::reviewers_changed
}

teamwork::pull_request_review_requested() {
  teamwork::reviewers_changed
}

teamwork::pull_request_closed() {
  local -r user=$(github::get_sender_user)
  local -r pr_url=$(github::get_pr_url)
  local -r pr_title=$(github::get_pr_title)
  local -r pr_merged=$(github::get_pr_merged)

  if [ "$pr_merged" == "true" ]; then
    teamwork::add_comment "
**$user** merged a PR: **$pr_title**
[$pr_url]($pr_url)
"
  teamwork::add_tag "PR Merged"
  teamwork::remove_tag "PR Open"
  teamwork::remove_tag "PR Approved"
  teamwork::move_task_to_column "$BOARD_COLUMN_MERGED"
  else
    teamwork::add_comment "
**$user** closed a PR without merging: **$pr_title**
[$pr_url]($pr_url)
"
    teamwork::remove_tag "PR Open"
    teamwork::remove_tag "PR Approved"
    teamwork::move_task_to_column "$BOARD_COLUMN_CLOSED"
  fi
}

teamwork::pull_request_review_submitted() {
  local -r user=$(github::get_sender_user)
  local -r pr_url=$(github::get_pr_url)
  local -r pr_title=$(github::get_pr_title)
  local -r review_state=$(github::get_review_state)
  local -r comment=$(github::get_review_comment)

  # Only add a message if the PR has been approved
  if [ "$review_state" == "approved" ]; then
    teamwork::add_comment "
**$user** submitted a review to the PR: **$pr_title**
[$pr_url]($pr_url)

---

Review: **$review_state**
$comment
"
    teamwork::add_tag "PR Approved"
    teamwork::move_task_to_column "$BOARD_COLUMN_APPROVED"
    teamwork::assign_task_to_user "$TEAMWORK_ASSIGNEES"
  elif [ "$review_state" == "changes_requested" ]; then
    teamwork::add_comment "
**$user** requested changes to the PR: **$pr_title**
[$pr_url]($pr_url)

---

Review: **$review_state**
$comment
"
    teamwork::add_tag "PR Changes Requested"
    teamwork::move_task_to_column "$BOARD_COLUMN_CHANGES_REQUESTED"
    teamwork::assign_task_to_user "$TEAMWORK_ASSIGNEES"
  fi
}

teamwork::pull_request_review_dismissed() {
  local -r user=$(github::get_sender_user)
  teamwork::add_comment "Review dismissed by $user"
}
