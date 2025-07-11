#!/usr/bin/env bash

# shellcheck disable=SC1090
source "$PROJECT_HOME/src/ensure.sh"
source "$PROJECT_HOME/src/github.sh"
source "$PROJECT_HOME/src/misc.sh"
source "$PROJECT_HOME/src/teamwork.sh"

main() {
  log::message "Running the process..."

  # Ensure env vars and args exist
  ensure::env_variable_exist "GITHUB_REPOSITORY"
  ensure::env_variable_exist "GITHUB_EVENT_PATH"

  export GITHUB_TOKEN="$1"
  export TEAMWORK_URI="$2"
  export TEAMWORK_API_TOKEN="$3"
  export AUTOMATIC_TAGGING="$4"
  export MAKE_COMMENTS_PRIVATE="$5"
  export BOARD_COLUMN_OPENED="$6"
  export BOARD_COLUMN_APPROVED="$7"
  export BOARD_COLUMN_CHANGES_REQUESTED="$8"
  export BOARD_COLUMN_MERGED="$9"
  export BOARD_COLUMN_CLOSED="${10}"
  export REASSIGN_TASKS="${11}"
  export USER_MAPPING="${12}"

  env::set_environment

  # Check if there is a task link in the PR
  local -r pr_body=$(github::get_pr_body)
  local -r task_ids_str=$(teamwork::get_task_id_from_body "$pr_body" )

  if [ "$task_ids_str" == "" ]; then
    log::message "Task not found"
    exit 0
  fi

  local -r event=$(github::get_event_name)
  local -r action=$(github::get_action)

  log::message "Event: $event - Action: $action"

  if [ $REASSIGN_TASKS == 'true' ]; then
    local tw_assignees=""
    local tw_reviewers=""

    while IFS= read -r assignee; do
      if [ "$assignee" != "" ]; then
        local assignee_login=$(echo "$assignee" | jq --raw-output '.login')
        local assignee_lookup=$(echo "$USER_MAPPING" | jq --raw-output --arg github_login "$assignee_login" '.[$github_login] // empty')

        if [ "$ENV" == "test" ]; then
          log::message "Assignee found: $assignee_lookup"
        fi

        local tw_user_id=$(teamwork::get_user_id "$assignee_lookup")
        if [ -z "$tw_user_id" ]; then
          local assignee_email=$(echo "$assignee" | jq --raw-output '.email // .name // .login')

          tw_user_id=$(teamwork::get_user_id "$assignee_email")
        fi

        if [ "$tw_assignees" != "" ]; then
          tw_assignees="$tw_assignees,"
        fi
        tw_assignees="$tw_assignees$tw_user_id"
      fi
    done <<< "$(github::get_pr_assignees)"

    while IFS= read -r reviewer; do
      if [ "$reviewer" != "" ]; then
        local reviewer_login=$(echo "$reviewer" | jq --raw-output '.login')
        local reviewer_lookup=$(echo "$USER_MAPPING" | jq --raw-output --arg github_login "$reviewer_login" '.[$github_login] // empty')

        if [ "$ENV" == "test" ]; then
          log::message "Reviewer found: $reviewer_lookup"
        fi

        local tw_user_id=$(teamwork::get_user_id "$reviewer_lookup")
        if [ -z "$tw_user_id" ]; then
          local reviewer_email=$(echo "$reviewer" | jq --raw-output '.email // .name // .login')

          tw_user_id=$(teamwork::get_user_id "$reviewer_email")
        fi

        if [ "$tw_reviewers" != "" ]; then
          tw_reviewers="$tw_reviewers,"
        fi
        tw_reviewers="$tw_reviewers$tw_user_id"
      fi
    done <<< "$(github::get_pr_reviewers)"

    export TEAMWORK_ASSIGNEES="$tw_assignees"
    echo $TEAMWORK_ASSIGNEES
    export TEAMWORK_REVIEWERS="$tw_reviewers"
    echo $TEAMWORK_REVIEWERS
  fi

  local sender_login="$(github::get_sender_login)"
  local sender_lookup=$(echo "$USER_MAPPING" | jq --raw-output --arg github_login "$sender_login" '.[$github_login] // empty')
  export SENDER_USER_ID=$(teamwork::get_user_id "$sender_lookup")

  local project_id
  IFS=',' read -r -a task_ids <<< "$task_ids_str"
  for task_id in "${task_ids[@]}"; do
    log::message "Task found with the id: $task_id"

    export TEAMWORK_TASK_ID=$task_id
    project_id="$(teamwork::get_project_id_from_task "$task_id")"
    export TEAMWORK_PROJECT_ID=$project_id

    ignored_project_ids=("${IGNORE_PROJECT_IDS:-}")
    if utils::in_array "$project_id" "${ignored_project_ids[*]}"
    then
        log::message "ignored due to IGNORE_PROJECT_IDS"
        exit 0
    fi

    if [ "$event" == "pull_request" ] && [ "$action" == "opened" ]; then
      teamwork::pull_request_opened
    elif [ "$event" == "pull_request" ] && [ "$action" == "edited" ]; then
      teamwork::pull_request_edited
    elif [ "$event" == "pull_request" ] && [ "$action" == "review_request_removed" ]; then
      teamwork::pull_request_review_request_removed
    elif [ "$event" == "pull_request" ] && [ "$action" == "review_requested" ]; then
      teamwork::pull_request_review_requested
    elif [ "$event" == "pull_request" ] && [ "$action" == "closed" ]; then
      teamwork::pull_request_closed
    elif [ "$event" == "pull_request_review" ] && [ "$action" == "submitted" ]; then
      teamwork::pull_request_review_submitted
    elif [ "$event" == "pull_request_review" ] && [ "$action" == "dismissed" ]; then
      teamwork::pull_request_review_dismissed
    elif [ "$ENV" == "test" ]; then # always run pull_request_opened at the very least when in test
      teamwork::pull_request_opened
    else
      log::message "Operation not allowed"
      exit 0
    fi
  done

  exit $?
}
