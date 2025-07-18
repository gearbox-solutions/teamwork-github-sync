#!/usr/bin/env bash

github::get_event_name() {
  echo "$GITHUB_EVENT_NAME"
}

github::get_action() {
  jq --raw-output .action "$GITHUB_EVENT_PATH"
}

github::get_pr_number() {
  jq --raw-output .pull_request.number "$GITHUB_EVENT_PATH"
}

github::get_pr_body() {
  jq --raw-output .pull_request.body "$GITHUB_EVENT_PATH" | sed -r 's/^#{1,3}\ /#### /g'
}

github::get_head_ref() {
  jq --raw-output .pull_request.head.ref "$GITHUB_EVENT_PATH"
}

github::get_base_ref() {
  jq --raw-output .pull_request.base.ref "$GITHUB_EVENT_PATH"
}

github::get_repository_full_name() {
  jq --raw-output .pull_request.head.repo.full_name "$GITHUB_EVENT_PATH"
}

github::get_pr_url() {
  jq --raw-output .pull_request.html_url "$GITHUB_EVENT_PATH"
}

github::get_pr_title() {
  jq --raw-output .pull_request.title "$GITHUB_EVENT_PATH"
}

github::get_pr_patch_stats() {
  jq --raw-output '.pull_request | "\(.commits) \(.changed_files) \(.additions) \(.deletions)"'  "$GITHUB_EVENT_PATH"
}

github::get_pr_merged() {
  jq --raw-output .pull_request.merged "$GITHUB_EVENT_PATH"
}

github::get_sender_login() {
  jq --raw-output '.sender.login' "$GITHUB_EVENT_PATH"
}

github::get_sender_user() {
  jq --raw-output '.sender.name // .sender.login' "$GITHUB_EVENT_PATH"
}

github::get_pr_assignees() {
  jq -c --raw-output .pull_request.assignees[] "$GITHUB_EVENT_PATH"
}

github::get_pr_reviewers() {
  jq -c --raw-output .pull_request.requested_reviewers[] "$GITHUB_EVENT_PATH"
}

github::get_review_state() {
  jq --raw-output .review.state "$GITHUB_EVENT_PATH"
}

github::get_review_comment() {
  jq --raw-output .review.body "$GITHUB_EVENT_PATH"
}

github::print_all_data() {
  cat "$GITHUB_EVENT_PATH"
}
